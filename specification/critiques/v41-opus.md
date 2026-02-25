# CXDB Graph UI Spec — Critique v41 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-25

## Prior Context

The v40 round addressed all issues from both critics. DOT comment handling was added to the server's parsing rules (verified against Kilroy's `stripComments`). The `RunCompleted` unreachability in the detail panel was explicitly documented. The Definition of Done shape list was updated to all ten shapes plus a Section 7.3 reference. A proposed holdout scenario for DOT comment handling was written. The codex issues about holdout shape coverage and RunFailed holdout promotion were deferred to the holdout scenario review process (proposed scenarios already exist).

---

## Issue #1: StageFinished.data.status can contain custom routing values beyond the five canonical statuses, but the spec only lists five

### The problem

Section 6.2's status derivation algorithm checks `StageFinished.data.status == "fail"` to decide between "error" and "complete", and the lifecycle precedence narrative (also Section 6.2) lists the `status` field values as `"success"`, `"partial_success"`, `"retry"`, `"fail"`, `"skipped"` from Kilroy's `StageStatus` enum.

However, Kilroy's `ParseStageStatus` function (`runtime/status.go` lines 31-39) accepts **arbitrary custom routing values** as valid stage statuses. The comment reads: "Custom outcome values (e.g. 'process', 'done', 'port') are used in reference dotfiles (semport.dot, consensus_task.dot) for multi-way conditional routing. Pass them through as-is." The `IsCanonical()` method explicitly distinguishes the five canonical values from these custom routing values. The `custom_outcome_routing_test.go` confirms this is an active, tested feature: box nodes return custom values like `"needs_dod"`, `"has_dod"`, `"process"`, `"done"`, `"port"`, `"skip"`.

When a conditional node uses custom routing, `StageFinished` is emitted with `data.status` set to the custom value (e.g., `"process"`, `"done"`). These values will reach the spec's `StageFinished` handling code. The current logic happens to handle them correctly — since `"process" != "fail"`, the node gets status "complete" — but an implementer reading the spec would believe only five values are possible and might write a switch/case on those five values that falls through to an error or default case for unrecognized values.

### Suggestion

Amend the parenthetical in Section 6.2's lifecycle turn precedence paragraph that currently reads:

> The `status` field values (`"success"`, `"partial_success"`, `"retry"`, `"fail"`, `"skipped"` — from Kilroy's `StageStatus` enum in `runtime/status.go`) are all treated as "complete" except `"fail"`.

to something like:

> The `status` field has five canonical values (`"success"`, `"partial_success"`, `"retry"`, `"fail"`, `"skipped"` — from Kilroy's `StageStatus` enum in `runtime/status.go`) and may also contain custom routing values (e.g., `"process"`, `"done"`, `"port"`) used for multi-way conditional branching. All values are treated as "complete" except `"fail"`. The UI must not assume a closed set of status values — the `status == "fail"` check is the only branch that matters.

## Issue #2: The `StageFinished` detail panel rendering does not account for custom routing status values in the Error column

### The problem

Section 7.2's per-type rendering table specifies that `StageFinished` highlights the Error column when `data.status` is `"fail"`. This is correct. However, the `preferred_label` field (which shows the edge the pipeline chose at a conditional node) is particularly important for custom routing outcomes — it tells the operator which branch was taken (e.g., `"process"` or `"done"`).

Looking at Kilroy's `cxdbStageFinished` (`cxdb_events.go` line 85), `preferred_label` is always set from `out.PreferredLabel`, which is populated for conditional nodes that produce custom routing outcomes. The spec's rendering rule for `StageFinished` already includes `preferred_label`:

> "Stage finished: {data.status}" + (if data.preferred_label is non-empty: " — {data.preferred_label}")

This actually renders correctly for custom routing values. For example, a conditional node with `status: "process"` and `preferred_label: "process"` would display as: "Stage finished: process — process". This is somewhat redundant when status and preferred_label are the same value. An implementer might wonder whether to deduplicate, but the spec should be explicit that this is the intended rendering and no deduplication is needed.

### Suggestion

Add a brief note after the `StageFinished` rendering rule or in the narrative below the per-type rendering table:

> For conditional nodes using custom routing outcomes, `data.status` and `data.preferred_label` may contain the same value (e.g., both `"process"`). The rendering displays both as-is — no deduplication is applied.

This is a minor documentation clarification, not a functional issue.

## Issue #3: The spec does not document the `view` query parameter for the turns endpoint, yet `fetchFirstTurn` implicitly relies on `view=raw`

### The problem

Section 5.3 documents the turns endpoint query parameters (`limit` and `before_turn_id`) but does not mention the `view` parameter. The `fetchFirstTurn` pseudocode in Section 5.5 accesses `rawTurn.bytes_b64` to decode the msgpack payload — this field is only present when `view=raw` is used (which returns the raw msgpack payload as base64). The default `view=typed` returns decoded JSON in `rawTurn.data` instead.

The spec's narrative around `decodeFirstTurn` mentions "bytes_b64 is present because fetchFirstTurn omits the bytes_render parameter, defaulting to base64" but doesn't explain that `view=raw` must be used to get `bytes_b64` in the first place. Looking at the CXDB HTTP handler (`http/mod.rs` lines 758-761), `bytes_render` only applies to raw view responses. The typed view (`view=typed`) returns decoded data in the `data` field and does not include `bytes_b64`.

An implementer reading Section 5.3 alone would not know to use `view=raw` for the discovery pagination. The `fetchFirstTurn` pseudocode works correctly (it produces the right HTTP request), but the turns endpoint documentation in Section 5.3 should list `view` as a query parameter.

### Suggestion

Add `view` to the query parameters table in Section 5.3:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `view` | `typed` | Response format. `typed` returns turns with decoded `data` fields (JSON objects with named keys). `raw` returns turns with `bytes_b64` containing the base64-encoded msgpack payload. The UI uses `typed` for regular polling and `raw` for discovery pagination (`fetchFirstTurn`) where direct msgpack decoding is needed to extract `graph_name` and `run_id` from the `RunStarted` payload. |

Also add `bytes_render` as a parameter used with `view=raw` to control base64 vs hex encoding.

## Issue #4: Holdout scenarios do not test custom routing outcomes in StageFinished

### The problem

Given Issue #1 (custom routing values in `StageFinished.data.status`), there is no holdout scenario verifying that a `StageFinished` turn with a custom status value (e.g., `"process"`, `"done"`) correctly results in a "complete" (green) node rather than an error or unexpected behavior. This is a real scenario that occurs in production pipelines using multi-way conditional routing (consensus_task.dot, semport.dot).

An implementation that hardcodes a switch on the five canonical status values and falls through to an error/default case for unrecognized values would pass all current holdout scenarios.

### Suggestion

Add a holdout scenario:

```
### Scenario: Conditional node with custom routing outcome shows as complete
Given a pipeline run has a conditional node using custom routing
  And CXDB contains a StageFinished turn for that node with data.status = "process" (a custom routing value)
  And data.preferred_label = "process"
When the UI polls CXDB
Then the node is colored green (complete), not red (error)
  And the detail panel shows "Stage finished: process — process"
```
