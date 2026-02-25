# CXDB Graph UI Spec — Critique v48 (sonnet)

**Critic:** sonnet (claude-sonnet-4-6)
**Date:** 2026-02-25

## Prior Context

The v47 codex critique identified two issues that were both applied. Issue #1 fixed the permanent-blacklist bug in the fallback discovery algorithm for contexts with null `client_tag` (splitting the cache-negative path so only non-null, wrong-prefix tags are cached as null). Issue #2 added a holdout scenario requiring `view=raw` for `fetchFirstTurn` to survive an unpublished type registry. Three additional holdout scenarios were added to lock in the Issue #1 boundary conditions. No structural changes were made to the polling loop or detail panel rendering logic.

---

## Issue #1: `StageStarted.attempt` documented as an emitted field but never emitted by Kilroy

### The problem

Section 5.4 lists `StageStarted`'s key data fields as `node_id`, `handler_type (optional)`, `attempt (optional)`. The `attempt` field appears again in the per-type detail panel rendering table (Section 7.2):

```
| `StageStarted` | "Stage started" + (if `data.handler_type` is non-empty: ": {`data.handler_type`}") | blank | blank |
```

That row does not reference `attempt`, so the detail panel rendering itself is not the problem. The problem is that Section 5.4's turn type inventory explicitly lists `attempt` as a field for `StageStarted`.

Cross-referencing Kilroy's `cxdb_events.go` reveals that `cxdbStageStarted` emits exactly four fields:

```go
_, _, _ = e.CXDB.Append(ctx, "com.kilroy.attractor.StageStarted", 1, map[string]any{
    "run_id":       e.Options.RunID,
    "node_id":      node.ID,
    "timestamp_ms": nowMS(),
    "handler_type": resolvedHandlerType(node),
})
```

No `attempt` field is present. `attempt` is emitted by `cxdbStageFailed` and `cxdbStageRetrying`, but not by `cxdbStageStarted`. An implementing agent reading Section 5.4 could reasonably infer that `StageStarted` should display an attempt number — for example, on the second or later attempt, showing "Stage started: codergen (attempt 2)" — but this would be displaying a field that does not exist in real CXDB data.

The holdout scenario "StageFailed with will_retry=true leaves node in running state" mentions "the detail panel shows the StageFailed, StageRetrying, and StageStarted turns" but does not test for any `attempt` value in the `StageStarted` turn output, so there is no acceptance test enforcing the phantom field.

### Suggestion

Remove `attempt (optional)` from the `StageStarted` row in Section 5.4's key data fields table. The field does not exist in Kilroy's current implementation. The note should also confirm that `run_id` and `timestamp_ms` are emitted but not consumed by the UI (for completeness with other turn types in the table). If the `attempt` field is intended as a future addition to `StageStarted`, it should be noted explicitly as "not currently emitted by Kilroy."

---

## Issue #2: `AssistantMessage.text` truncation causes incorrect "Show more" UX promise

### The problem

Section 7.2 says Kilroy truncates `AssistantMessage.text`, `ToolCall.arguments_json`, and `ToolResult.output` at 8,000 characters in `cli_stream_cxdb.go`. The UI's client-side truncation at 500 characters/8 lines then applies on top of this. The spec notes:

> "Expanding a truncated turn row via 'Show more' shows at most 8,000 characters for these fields, not the full original content"

This is correctly documented for the named three fields. However, the spec also says:

> "`Prompt.text` is NOT truncated"

Looking at `cxdbPrompt` in `cxdb_events.go`:

```go
_, _, _ = e.CXDB.Append(ctx, "com.kilroy.attractor.Prompt", 1, map[string]any{
    "run_id":       e.Options.RunID,
    "node_id":      nodeID,
    "text":         text,
    "timestamp_ms": nowMS(),
})
```

Confirmed: `Prompt.text` is passed directly without truncation. The spec correctly notes this. The issue is that the spec does **not** state the practical implication for the "Show more" button: when the user expands a `Prompt` turn that the UI has client-side-truncated to 500 characters, the "Show more" button will reveal the full prompt — which the spec says can range from 5,000 to 50,000+ characters. This is dramatically different UX from expanding a `ToolResult` turn (which reveals at most 8,000 characters). An implementing agent has no guidance on whether to apply a secondary cap when expanding a `Prompt` turn, or what the DOM impact of injecting 50,000+ characters into a single expanded row should be.

### Suggestion

Add a note to Section 7.2's truncation and expansion subsection clarifying that for `Prompt` turns, "Show more" expands to the full text (potentially 50,000+ characters with no secondary cap). Recommend that the implementation either: (a) apply the same 8,000-character secondary cap on expansion as for ToolResult/ToolCall/AssistantMessage (with a disclosure that the content is truncated), or (b) explicitly accept the unbounded expansion and document it as intentional for operators who need to inspect full prompts. Without this guidance, implementing agents will make an arbitrary choice with no acceptance test to verify it.

---

## Issue #3: `cqlSupported` flag reset semantics are underspecified for the reconnection case

### The problem

Section 5.5 states:

> "The `cqlSupported` flag is checked on subsequent polls to skip the CQL attempt — it is reset when the CXDB instance becomes unreachable and then reconnects (since the instance may have been upgraded)."

The holdout scenario "CQL support flag resets on CXDB instance reconnection" describes the upgrade path (old CXDB without CQL → upgraded → reconnects → UI retries CQL). This is clear.

However, the spec does not define what "becomes unreachable and then reconnects" means at the implementation level. Specifically:

1. How does the UI distinguish "unreachable" from "temporarily slow"? The proxy returns 502 when the CXDB instance is unreachable. Does a single 502 response count as "unreachable" for flag-reset purposes?

2. Section 6.1 step 1 says "If an instance is unreachable (502), skip it, retain its per-context status maps." This handles the unreachable case for discovery. But there is no corresponding pseudocode showing when and how the `cqlSupported` flag is reset.

3. Section 5.5's `discoverPipelines` pseudocode handles the 404 → set `cqlSupported = false` case and the `ELSE` (502 etc.) → `CONTINUE` case, but the reconnection reset is only described in prose, not in the pseudocode. An implementing agent following the pseudocode literally would never reset the flag.

### Suggestion

Add explicit pseudocode or a numbered step to the polling loop (Section 6.1) showing when `cqlSupported[index]` is reset to `undefined` (allowing a retry). The clearest semantics: when an instance that was previously unreachable (502) subsequently returns a non-502 response — whether from the context list, CQL search, or any proxied request — reset `cqlSupported[index]` so the next poll cycle retries CQL. The reset should happen at instance-reachability detection time, not inside the CQL path. Add a corresponding holdout scenario variant showing that the flag reset also occurs correctly when the instance was `cqlSupported = false` (not just the `true → upgrade` direction).

---

## Issue #4: No holdout scenario for the `StageFinished` detail panel rendering of `suggested_next_ids`

### The problem

Section 7.2's per-type rendering table shows that `StageFinished` includes:

```
... + (if `data.suggested_next_ids` is non-empty: "\nNext: {comma-joined `data.suggested_next_ids`}")
```

Cross-referencing `cxdb_events.go`, `cxdbStageFinished` always emits `suggested_next_ids` (line 88):

```go
"suggested_next_ids": out.SuggestedNextIDs,
```

This field is non-nil even for successful completions: `SuggestedNextIDs` is the list of downstream node IDs selected by the routing logic. For a typical pipeline node, this would be a single-element array like `["check_fmt"]`. For a conditional node with a matching edge, this would be `["done"]` or similar.

The holdout scenario "Conditional node with custom routing outcome shows as complete" tests `StageFinished { status: "process", preferred_label: "process" }` but does not test `suggested_next_ids`. An implementation that omits the `suggested_next_ids` line from the `StageFinished` rendering would pass all existing acceptance tests.

### Suggestion

Add a holdout scenario specifically for `StageFinished` rendering with non-empty `suggested_next_ids`. For example:

```
Given CXDB contains a StageFinished turn for a conditional node with:
  - status: "pass"
  - preferred_label: "pass"
  - suggested_next_ids: ["check_goal", "finalize"]
When the user clicks that node
Then the detail panel Output shows:
  "Stage finished: pass — pass\nNext: check_goal, finalize"
  And the "\nNext:" line uses a literal newline before "Next:"
```

This locks in the `suggested_next_ids` format and prevents regressions when the field is populated in real-world runs.

---

