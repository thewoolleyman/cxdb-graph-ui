# CXDB Graph UI Spec -- Critique v38 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-25

## Prior Context

The v37 opus critique raised four issues, all applied: (1) `Prompt.text` not truncated by Kilroy -- spec now explicitly lists truncated and untruncated fields in Section 7.2; (2) `discoverPipelines` pseudocode missing a CQL-empty-results fallback -- spec now includes a supplemental context list fetch when CQL returns zero results; (3) missing error handling for `/dots/{name}` raw DOT endpoint -- spec now documents 500 response for file-read failures; (4) rationale for using `--dot` flags over `RunStarted.graph_dot` -- spec now includes non-goal #11 explaining the design choice.

This critique is informed by reading the **Kilroy source code** (`kilroy/internal/attractor/engine/cxdb_events.go`, `kilroy/internal/attractor/runtime/status.go`, `kilroy/internal/cxdb/kilroy_registry.go`) and the **CXDB server source code** (`cxdb/server/src/http/mod.rs`, `cxdb/server/src/store.rs`).

---

## Issue #1: StageFinished detail panel rendering discards valuable `status` and `preferred_label` fields in favor of a fixed "Stage finished" label

### The problem

Section 7.2's per-type rendering table maps `StageFinished` turns to:

| Turn Type | Output Column | Tool Column | Error Column |
|-----------|--------------|-------------|--------------|
| `StageFinished` | "Stage finished" (fixed label) | blank | blank |

However, `StageFinished` carries substantive data fields that the spec itself documents in Section 5.4: `status` (string) and `preferred_label` (optional string). The Kilroy source (`cxdb_events.go` lines 80-89) confirms that `StageFinished` is emitted with:

```go
"status":             string(out.Status),
"preferred_label":    out.PreferredLabel,
"failure_reason":     out.FailureReason,
"notes":              out.Notes,
"suggested_next_ids": out.SuggestedNextIDs,
```

The `status` field takes values from `runtime.StageStatus`: `"success"`, `"partial_success"`, `"retry"`, `"fail"`, `"skipped"` (from `runtime/status.go` lines 12-16). The `preferred_label` field contains the human-readable edge label chosen for the next hop (e.g., `"pass"`, `"fail"`, `"needs_revision"`). These are directly relevant to an operator's "mission control" view:

- **`status`** tells the operator whether the node succeeded, partially succeeded, was skipped, or failed. This is distinct from the binary complete/error CSS coloring -- a node can have `StageFinished` with `status: "fail"` (which the spec's status derivation treats as "complete" because `StageFinished` is an authoritative lifecycle resolution, regardless of the `status` value).
- **`preferred_label`** tells the operator which edge the pipeline took at a conditional node. For conditional nodes (diamond shape), this is the most important field in the entire turn -- it answers "which path did the pipeline choose?"

Rendering `StageFinished` as a fixed "Stage finished" string discards both of these. An operator clicking a conditional node to understand why the pipeline took a particular path would see "Stage finished" instead of `"status: fail, label: needs_revision"`.

Additionally, the registry (`kilroy_registry.go` lines 60-69) includes `failure_reason` (tag 6, optional) and `notes` (tag 7, optional) on `StageFinished`. Kilroy emits these when a node finishes with a non-success status. Discarding `failure_reason` on `StageFinished` is especially confusing because `StageFailed` renders `data.failure_reason` -- but `StageFinished` with `status: "fail"` also carries `failure_reason` and gets a fixed label instead.

### Suggestion

Change the `StageFinished` row in the per-type rendering table to render the `status` and `preferred_label` fields:

| Turn Type | Output Column | Tool Column | Error Column |
|-----------|--------------|-------------|--------------|
| `StageFinished` | "Stage finished: {`data.status`}" + (if `data.preferred_label` is non-empty: " — {`data.preferred_label`}") + (if `data.failure_reason` is non-empty: "\n{`data.failure_reason`}") | blank | highlighted if `data.status` is `"fail"` |

This gives the operator: `"Stage finished: success — pass"` for a passing conditional, `"Stage finished: fail — needs_revision\nTest suite failed with 3 errors"` for a failing conditional, and `"Stage finished: success"` for a node without a preferred label.

---

## Issue #2: Spec's Section 5.4 type table omits several fields that Kilroy actually emits for StageFinished and StageStarted

### The problem

Section 5.4 documents turn type IDs and their "Key Data Fields." The table lists:

| Type ID | Key Data Fields |
|---------|-----------------|
| `StageStarted` | `node_id` |
| `StageFinished` | `node_id`, `status`, `preferred_label` (optional) |

But the Kilroy registry (`kilroy_registry.go`) and the actual emission code (`cxdb_events.go`) show these types carry additional fields:

**`StageStarted`** (registry lines 53-59):
- `run_id` (1), `node_id` (2), `timestamp_ms` (3), **`handler_type`** (4, optional), **`attempt`** (5, optional)

Kilroy emits `handler_type` on every `StageStarted` (`cxdb_events.go` line 73: `"handler_type": resolvedHandlerType(node)`), which resolves to the node's type override or its shape-derived type label (e.g., `"llm_task"`, `"tool_gate"`, `"human_gate"`).

**`StageFinished`** (registry lines 60-69):
- `run_id` (1), `node_id` (2), `timestamp_ms` (3), `status` (4), `preferred_label` (5, optional), **`failure_reason`** (6, optional), **`notes`** (7, optional), **`suggested_next_ids`** (8, optional array)

The spec acknowledges that fields should be "verified against the bundle if field-level details are needed beyond what is documented here" (paragraph after the table). But for an implementer building the detail panel's per-type rendering, these omitted fields represent missed display opportunities. More critically, the `failure_reason` field on `StageFinished` is absent from the spec despite being functionally identical to the `failure_reason` field on `StageFailed` (which IS documented). An implementer would not know to render it.

### Suggestion

Add the missing fields to the Section 5.4 table:

| Type ID | Key Data Fields |
|---------|-----------------|
| `StageStarted` | `node_id`, `handler_type` (optional), `attempt` (optional) |
| `StageFinished` | `node_id`, `status`, `preferred_label` (optional), `failure_reason` (optional), `notes` (optional), `suggested_next_ids` (optional, array) |

This does not require any behavioral change -- the status derivation algorithm does not use these fields -- but it provides the implementer with the full field inventory needed for a complete detail panel.

---

## Issue #3: The status derivation algorithm treats `StageFinished` as unconditionally "complete" regardless of the `status` field value

### The problem

Section 6.2's `updateContextStatusMap` pseudocode maps `StageFinished` to the "complete" CSS status:

```
IF typeId == "com.kilroy.attractor.StageFinished":
    newStatus = "complete"
    existingMap[nodeId].hasLifecycleResolution = true
```

But Kilroy's `StageFinished` can carry `status: "fail"` -- the Kilroy engine emits `StageFinished` for all terminal node outcomes, including failures that are not retried. The `StageStatus` enum (`runtime/status.go` lines 12-16) includes `"success"`, `"partial_success"`, `"retry"`, `"fail"`, and `"skipped"`.

This means a node that terminates with `StageFinished { status: "fail" }` is displayed as green (complete) in the overlay, not red (error). The distinction matters: `StageFailed` with `will_retry: false` sets status to "error" (red), but `StageFinished` with `status: "fail"` sets status to "complete" (green). These represent different Kilroy code paths but similar semantic outcomes.

Looking at the Kilroy source more carefully: `cxdbStageFinished` is called in `engine.go` (lines 520 and 559) after a node's handler returns an `Outcome`. The engine then calls `cxdbStageFailed` separately (line 709 area) only when the overall run fails due to the node failure. So the sequence for a failing node that causes a run failure is:

1. `StageStarted` (running)
2. `StageFinished { status: "fail" }` (the node itself finished with a failure)
3. `RunFailed` (the run terminated because of the failure)

And for a failing node with retry:
1. `StageStarted` (running)
2. `StageFailed { will_retry: true }` (emitted by the retry logic)
3. `StageRetrying` (retry begins)
4. ...
5. `StageFinished { status: "success" }` (eventually succeeds)

The key distinction: `StageFailed` is emitted by the retry/failure handling logic, while `StageFinished` is emitted for every terminal node outcome regardless of success/failure. A `StageFinished` with `status: "fail"` followed by a `RunFailed` means the node failed terminally.

This means the current spec correctly reflects the CSS status for the *node* (it finished, so "complete" in the lifecycle sense), but the green coloring is misleading for an operator who sees a green node followed by a red "Pipeline stalled" banner. The node-level status should reflect the node's outcome, not just its lifecycle completion.

### Suggestion

Amend the `updateContextStatusMap` to check `StageFinished.data.status`:

```
IF typeId == "com.kilroy.attractor.StageFinished":
    existingMap[nodeId].hasLifecycleResolution = true
    IF turn.data.status == "fail":
        newStatus = "error"
    ELSE:
        newStatus = "complete"
```

This ensures that a node which finished with a failure status is displayed as red (error), matching the operator's expectation. Nodes with `status: "success"`, `"partial_success"`, or `"skipped"` remain green (complete). The `hasLifecycleResolution = true` flag still prevents non-lifecycle turns from overriding the status.

---

## Issue #4: No holdout scenario covers the `StageFinished` with `status: "fail"` case

### The problem

The holdout scenarios test `StageFinished` in the "Pipeline completed -- last node marked complete via StageFinished" scenario, which assumes all nodes finished successfully. There is no scenario covering the case where a node emits `StageFinished` with `status: "fail"` -- a common occurrence when a node fails terminally (no retries configured or max retries exceeded) and the run subsequently fails.

The existing "Agent stuck in error loop" scenario tests the error heuristic (3 consecutive `ToolResult` errors), and the "Pipeline stalled after agent crash" scenario tests stale detection. Neither covers the `StageFinished { status: "fail" }` path where the node's lifecycle turn itself indicates failure.

### Suggestion

Add a holdout scenario:

```
### Scenario: Node finishes with failure status
Given a pipeline run is active
  And a node emits StageFinished with status: "fail"
  And the run subsequently emits RunFailed
When the UI polls CXDB
Then the failed node is colored red (error), not green (complete)
  And the detail panel shows the failure status and failure_reason
```

This scenario directly tests the boundary between "complete" and "error" at the lifecycle level, which is currently untested.
