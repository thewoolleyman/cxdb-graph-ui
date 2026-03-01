# CXDB Graph UI Spec — Critique v35 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-25

## Prior Context

The v34 cycle had two critics (opus and codex). Opus raised four issues: the `resetPipelineState` prose contradiction (applied), the missing `graph_dot (12)` field in the `decodeFirstTurn` inventory (applied), 11 undocumented turn types with `node_id` (applied -- Section 5.4 expanded to 23 types and Section 7.2 per-type rendering table expanded with 7 new entries), and a `client_tag` binary protocol mechanism clarification (applied). Codex raised two issues: the same `resetPipelineState` contradiction (applied, same fix as opus), and missing tab-switch error handling for `/nodes` and `/edges` (applied -- new "Tab-switch error handling" paragraph added to Section 4.4). All issues from both critics were addressed. This critique is informed by reading the Kilroy source code (`cxdb_events.go`, `kilroy_registry.go`, `engine.go`, `cxdb_sink.go`, `cxdb_bootstrap.go`, `cli_stream_cxdb.go`) and the CXDB source code (`http/mod.rs`, `store.rs`, `turn_store/mod.rs`).

---

## Issue #1: `StageFailed` with `will_retry: true` causes premature "error" status that cannot be corrected until a lifecycle turn arrives

### The problem

The status derivation pseudocode (Section 6.2, `updateContextStatusMap`) treats all `StageFailed` turns identically: they set `status = "error"` and `hasLifecycleResolution = true`. Once `hasLifecycleResolution` is true, only other lifecycle turns (`StageFinished`, `StageFailed`) can modify the node's status -- non-lifecycle turns like `StageRetrying`, `Prompt`, `ToolCall`, and `ToolResult` are ignored for that node.

Reading the actual Kilroy engine code (`engine.go` lines 1162-1228), the retry flow is:

1. `StageStarted` (once, before `executeWithRetry`)
2. ... turns during attempt 1 ...
3. `StageFailed` with `will_retry: true`, `attempt: 1`
4. `StageRetrying` with `attempt: 2`
5. ... turns during attempt 2 ...
6. Either another `StageFailed` or a `StageFinished` (from `cxdbStageFinished` after successful retry)

After step 3, the UI marks the node as red ("error") with `hasLifecycleResolution = true`. The `StageRetrying` turn at step 4 is a non-lifecycle turn, so it cannot override the error status. All subsequent tool activity during retry attempt 2 (step 5) is also ignored for status purposes. The node stays red until a `StageFinished` eventually overrides it at step 6 -- which could take minutes during a retry cycle.

This is misleading for the "mission control" use case. The operator sees a red node and may intervene (e.g., kill the pipeline), not realizing the node is actively retrying and may succeed. The `StageFailed.will_retry` field (registry tag 5, boolean, optional) exists precisely to distinguish retriable failures from terminal failures, but the spec ignores it.

The `StageFailed` registry bundle definition confirms the field (`kilroy_registry.go` line 142): `"5": field("will_retry", "bool", opt())`.

### Suggestion

Update the `StageFailed` branch in `updateContextStatusMap` to check `will_retry`:

```
ELSE IF typeId == "com.kilroy.attractor.StageFailed":
    IF turn.data.will_retry == true:
        newStatus = "running"
        -- Do NOT set hasLifecycleResolution. The node is retrying, not terminally
        -- failed. A subsequent StageFinished or StageFailed (will_retry=false)
        -- will provide the authoritative resolution.
    ELSE:
        newStatus = "error"
        existingMap[nodeId].hasLifecycleResolution = true
```

This preserves the "error" status for terminal failures while allowing retry-in-progress nodes to display as "running" (blue, pulsing). The `StageRetrying` turn that follows reinforces the "running" status via the non-lifecycle fallback.

---

## Issue #2: The Section 5.4 type table marks several `node_id` fields as unconditionally present when the registry bundle marks them as optional

### The problem

Cross-referencing the spec's Section 5.4 "Key Data Fields" column against the actual registry bundle definitions in `kilroy_registry.go`:

| Turn Type | Spec says | Registry says | Source code |
|-----------|-----------|---------------|-------------|
| `ToolCall` | `node_id` (no optional marker) | tag 2: `opt()` | `cli_stream_cxdb.go` always passes `nodeID` |
| `ToolResult` | `node_id` (no optional marker) | tag 2: `opt()` | `cli_stream_cxdb.go` always passes `nodeID` |
| `GitCheckpoint` | `node_id (if present)` | tag 2: NOT optional | `cxdb_events.go` always passes `nodeID` |
| `CheckpointSaved` | `node_id (optional)` | tag 6: `opt()` | `cxdb_events.go` does not always set it |

For `ToolCall` and `ToolResult`, the spec implies `node_id` is always present, but the registry declares it optional. In current Kilroy code, it is always populated, but the registry allows future callers to omit it. An implementer relying on the spec's implication of guaranteed presence would not add null guards.

For `GitCheckpoint`, the reverse: the spec says `node_id (if present)` suggesting it is optional, but the registry marks it as required (not optional). The source code always passes it.

These mismatches between the spec and the registry are minor since the null guard (`IF nodeId IS null`) already handles absent `node_id` gracefully. But they could confuse an implementer cross-referencing the spec against the registry bundle.

### Suggestion

Update Section 5.4's "Key Data Fields" column to match the registry:

- `ToolCall`: change `node_id` to `node_id (optional per registry, always populated in practice)`
- `ToolResult`: same treatment
- `GitCheckpoint`: change `node_id (if present)` to `node_id` (required per registry)
- Keep `CheckpointSaved` as-is (`node_id (optional)` matches the registry)

Alternatively, add a blanket note below the table: "The `optional` annotations match the `kilroy-attractor-v1` registry bundle definition, not the current Kilroy emitting code. Fields marked optional in the registry may be absent from turns emitted by future Kilroy versions or third-party Attractor implementations. The `IF nodeId IS null` guard in the status derivation algorithm handles all cases."

---

## Issue #3: The `AssistantMessage` detail panel rendering truncates `data.text` but does not specify a truncation threshold, and `data.text` from `cli_stream_cxdb.go` is already truncated to 8,000 characters

### The problem

Section 7.2's per-type rendering table shows `AssistantMessage` with Output column `data.text`. Section 7.2's truncation rule says: "The Output column truncates content to the first 500 characters or 8 lines, whichever limit is reached first."

Reading `cli_stream_cxdb.go` line 46, the `text` field is already truncated server-side by Kilroy:

```go
"text": truncate(text, 8_000),
```

Similarly, `ToolCall.arguments_json` is truncated to 8,000 characters (line 66), and `ToolResult.output` is truncated to 8,000 characters (line 87).

The spec's 500-character client-side truncation is applied on top of Kilroy's 8,000-character truncation. This is functionally correct -- the client always sees at most 8,000 characters and then truncates to 500 for initial display. But the "Show more" toggle would expand to at most 8,000 characters (not the full original text), which could surprise an operator expecting the complete LLM response. For `AssistantMessage` in particular, the full response text is often >8,000 characters, and the truncated text may cut off mid-sentence.

This is a documentation gap, not a code change. The spec does not mention that Kilroy-side truncation exists, and an implementer might invest effort in handling very long `data.text` values when in reality they are capped at 8,000 characters.

### Suggestion

Add a note to Section 7.2 (near the truncation rule) or Section 5.4: "Kilroy truncates large text fields at the source: `AssistantMessage.text`, `ToolCall.arguments_json`, and `ToolResult.output` are each capped at 8,000 characters by the Kilroy engine before appending to CXDB. The UI's client-side truncation (500 characters / 8 lines for initial display) operates within this limit. Expanding a truncated turn row shows at most 8,000 characters, not the full original content."

---

## Issue #4: No holdout scenario covers the `StageFailed` → `StageRetrying` → retry success flow

### The problem

The holdout scenarios cover the "agent stuck in error loop" case (3 consecutive `ToolResult` errors) and the "pipeline completed" case (all `StageFinished`), but there is no scenario for the retry flow:

1. Node enters running state
2. `StageFailed` with `will_retry: true` is emitted
3. `StageRetrying` is emitted
4. The retry succeeds (`StageFinished`)
5. The node should eventually show "complete" (green)

If Issue #1 is addressed (checking `will_retry`), then during step 2-3 the node should remain "running" (blue, pulsing). If Issue #1 is not addressed, the node goes red during steps 2-4 and then flips to green at step 5. Either way, the final state should be "complete" -- but neither intermediate behavior is tested by the holdout scenarios.

This is relevant because the `StageFailed` → lifecycle resolution interaction is one of the most complex status derivation paths and the retry flow is common in real Kilroy pipelines (tool gate nodes frequently fail on first attempt).

### Suggestion

Add a holdout scenario:

```
### Scenario: Node retries after StageFailed with will_retry
Given a pipeline run is active with node check_fmt in running state
  And CXDB contains a StageFailed turn for check_fmt with will_retry: true
  And CXDB contains a StageRetrying turn after the StageFailed
  And the retry succeeds with a StageFinished turn
When the UI polls CXDB
Then check_fmt is colored green (complete)
  And check_fmt is NOT permanently stuck in error state
```

---

The most significant finding is Issue #1 (`StageFailed` with `will_retry: true` causing premature error status). This directly affects operator experience during the retry window -- common in real Kilroy pipelines where tool gates fail and retry. The fix requires checking a single field that already exists in the turn data.
