# CXDB Graph UI Spec — Critique v46 (sonnet) Acknowledgement

All five issues from the v46-sonnet critique were evaluated. Issues #1, #2, and #3 identified undocumented fields in the Section 5.4 turn type table; all three were verified against Kilroy source (`cxdb_events.go`, `handlers.go`, `codergen_router.go`, `cli_stream_cxdb.go`) and applied to the specification. Issues #4 and #5 identified holdout scenario gaps that are already covered by canonical scenarios in the holdout file.

## Issue #1: `GitCheckpoint` turn has an undocumented `status` field in Section 5.4

**Status: Applied to specification**

Verified against Kilroy's `cxdbCheckpointSaved` (`cxdb_events.go` lines 134-156): the function takes a `status runtime.StageStatus` parameter and emits it as `"status": string(status)` alongside `node_id` and `git_commit_sha`. The Section 5.4 `GitCheckpoint` table row was updated to add `status` to the key data fields list. A field note was added to the "Field notes for specific turn types" paragraph explaining that `GitCheckpoint.status` uses the same `StageStatus` value set as `StageFinished.status` and records the stage status at checkpoint time. This field does not affect UI rendering (GitCheckpoint falls through to "Other/unknown" in the detail panel), but the table is now accurate for operators inspecting raw CXDB turn data.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 5.4 `GitCheckpoint` row from `node_id`, `git_commit_sha` to `node_id`, `git_commit_sha`, `status`
- `specification/cxdb-graph-ui-spec.md`: Added `GitCheckpoint.status` explanation to new "Field notes for specific turn types" paragraph

## Issue #2: `ToolCall` and `ToolResult` turns have an undocumented `call_id` field in Section 5.4

**Status: Applied to specification**

Verified against all three Kilroy emit paths:
- CLI stream path (`cli_stream_cxdb.go` lines 61-68): emits `"call_id": call.ID` (Anthropic tool_use ID) for `ToolCall`, and `"call_id": result.ToolUseID` for `ToolResult`
- Tool gate path (`handlers.go` lines 541-659): emits `"call_id": callID` (ULID) for both `ToolCall` and `ToolResult`
- Codergen router path (`codergen_router.go` lines 1814-1839): emits `"call_id": callID` (ULID) for both

The Section 5.4 `ToolCall` row was updated to add `call_id` to the key data fields. The `ToolResult` row was updated similarly. A field note was added to the "Field notes for specific turn types" paragraph explaining that `call_id` correlates a `ToolCall` with its corresponding `ToolResult`, with the value being an Anthropic tool_use ID for LLM-driven calls and a ULID for tool gate and Codergen-routed calls. The note clarifies that `call_id` is not rendered by the detail panel but is present in all real-world turns.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 5.4 `ToolCall` row to add `call_id`
- `specification/cxdb-graph-ui-spec.md`: Updated Section 5.4 `ToolResult` row to add `call_id`
- `specification/cxdb-graph-ui-spec.md`: Added `ToolCall.call_id`/`ToolResult.call_id` explanation to new "Field notes for specific turn types" paragraph

## Issue #3: `ParallelStarted` turn has undocumented `join_policy` and `error_policy` fields in Section 5.4

**Status: Applied to specification**

Verified against Kilroy's `cxdbParallelStarted` (`cxdb_events.go` lines 213-226): the function takes `joinPolicy string` and `errorPolicy string` parameters and emits them as `"join_policy": joinPolicy` and `"error_policy": errorPolicy`. The Section 5.4 `ParallelStarted` row was updated to add `join_policy` and `error_policy` to the key data fields. A field note was added to the "Field notes for specific turn types" paragraph explaining that these are string values from Kilroy's parallel handler configuration describing how the fan-out is coordinated. These fields do not affect UI rendering (ParallelStarted falls through to "Other/unknown" in the detail panel) but are operationally significant for operators debugging failing parallel nodes.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 5.4 `ParallelStarted` row from `node_id`, `branch_count` to `node_id`, `branch_count`, `join_policy`, `error_policy`
- `specification/cxdb-graph-ui-spec.md`: Added `ParallelStarted.join_policy`/`error_policy` explanation to new "Field notes for specific turn types" paragraph

## Issue #4: No holdout scenario covers the human gate `InterviewStarted`/`InterviewCompleted`/`InterviewTimeout` turn sequence

**Status: Not addressed — already covered by canonical holdout scenarios**

Inspection of `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` (lines 638-663) shows two canonical scenarios that directly cover the requested rendering:

1. **"Human gate interview turns render in detail panel CXDB Activity section"** — verifies `InterviewStarted` renders `"Approve the implementation? [SingleSelect]"` and `InterviewCompleted` renders `"YES (waited 45s)"` for a 45000ms duration.

2. **"InterviewTimeout turn renders with error highlight in detail panel"** — verifies `InterviewTimeout` renders the `question_text` in Output and the Error column is highlighted with "timeout".

These scenarios fully cover all rendering behaviors identified in the critique. No changes required.

Changes:
- None (already covered by canonical holdout scenarios)

## Issue #5: `StageStarted` handler type rendering is not covered by any holdout scenario

**Status: Not addressed — already covered by canonical holdout scenarios**

Inspection of `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` (lines 665-679) shows a canonical scenario "StageStarted turn renders handler_type in detail panel" that covers all three handler_type variations: `"codergen"` (renders "Stage started: codergen"), `"tool"` (renders "Stage started: tool"), and empty string (renders "Stage started" with no colon suffix). This matches the scenario suggested in the critique. No changes required.

Changes:
- None (already covered by canonical holdout scenarios)

## Not Addressed (Out of Scope)

- Issues #4 and #5 are fully resolved — the canonical holdout scenarios file already contains the scenarios the critique requested. These were likely added in a prior revision cycle after the critique was generated.
