# CXDB Graph UI Spec — Critique v35 (opus) Acknowledgement

All four issues from the v35 opus critique were evaluated. Issues #1, #2, and #3 were applied to the specification. Issue #4 was deferred as a proposed holdout scenario. Changes were informed by cross-referencing the Kilroy source code (`engine.go`, `cxdb_events.go`, `kilroy_registry.go`, `cli_stream_cxdb.go`) and the CXDB source code.

## Issue #1: `StageFailed` with `will_retry: true` causes premature "error" status that cannot be corrected until a lifecycle turn arrives

**Status: Applied to specification**

Updated the `StageFailed` branch in the `updateContextStatusMap` pseudocode (Section 6.2) to check `will_retry`. When `will_retry == true`, the turn sets status to "running" and does NOT set `hasLifecycleResolution`, allowing subsequent turns (StageRetrying, tool calls during retry) to continue updating the node's status. When `will_retry` is absent or false, the terminal behavior is unchanged: status is set to "error" with `hasLifecycleResolution = true`.

Also updated: the promotion block's lifecycle check to only treat `StageFailed` as a lifecycle override when `will_retry != true`; the `StageFailed` row in the Section 7.2 detail panel rendering table to append "(will retry)" and suppress error highlighting when `will_retry == true`; the `StageFailed` row in the Section 5.4 type table to include `will_retry (optional, boolean)` and `attempt (optional)` fields; Invariant #5 to document the `will_retry` distinction; and the Definition of Done checklist item.

Verified against Kilroy source: `engine.go` lines 1162-1213 confirm the retry flow (StageFailed with will_retry → StageRetrying → retry attempt → StageFinished or another StageFailed). `kilroy_registry.go` line 142 confirms `will_retry` is tag 5, boolean, optional. `cxdb_events.go` line 194 confirms `will_retry` is always passed.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated `StageFailed` branch in `updateContextStatusMap` pseudocode to check `will_retry`
- `specification/cxdb-graph-ui-spec.md`: Updated promotion block lifecycle check to exclude retriable `StageFailed`
- `specification/cxdb-graph-ui-spec.md`: Updated `StageFailed` row in Section 5.4 type table with `will_retry` and `attempt` fields
- `specification/cxdb-graph-ui-spec.md`: Updated `StageFailed` row in Section 7.2 detail panel rendering table
- `specification/cxdb-graph-ui-spec.md`: Updated Invariant #5 to document `will_retry` distinction
- `specification/cxdb-graph-ui-spec.md`: Updated Definition of Done checklist item

## Issue #2: Section 5.4 type table marks several `node_id` fields as unconditionally present when the registry marks them as optional

**Status: Applied to specification**

Updated the Section 5.4 type table: `ToolCall.node_id` and `ToolResult.node_id` now show "optional per registry, always populated in practice". `GitCheckpoint.node_id` changed from "(if present)" to required (matching the registry — tag 2 is NOT optional). Added a blanket note below the table explaining that optional annotations match the registry bundle definition, not the current emitting code, and that the `IF nodeId IS null` guard handles all cases.

Verified against Kilroy source: `kilroy_registry.go` confirms `ToolCall` tag 2 is `opt()`, `ToolResult` tag 2 is `opt()`, `GitCheckpoint` tag 2 is NOT optional. `cli_stream_cxdb.go` and `cxdb_events.go` confirm all three always populate `node_id` in current code.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated `ToolCall`, `ToolResult`, and `GitCheckpoint` `node_id` annotations in Section 5.4 type table
- `specification/cxdb-graph-ui-spec.md`: Added blanket note about registry vs. emitting code optionality

## Issue #3: `AssistantMessage` detail panel truncation and Kilroy-side 8,000-character truncation

**Status: Applied to specification**

Added a "Kilroy-side truncation" paragraph to Section 7.2, immediately before the existing "Truncation and expansion" paragraph. The note documents that Kilroy truncates `AssistantMessage.text`, `ToolCall.arguments_json`, and `ToolResult.output` to 8,000 characters at the source (in `cli_stream_cxdb.go`) before appending to CXDB. The UI's 500-character client-side truncation operates within this limit, and "Show more" expands to at most 8,000 characters, not the full original content.

Verified against Kilroy source: `cli_stream_cxdb.go` lines 46, 66, 87 confirm `truncate(text, 8_000)`, `truncate(call.InputJSON, 8_000)`, and `truncate(result.Content, 8_000)`.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "Kilroy-side truncation" paragraph to Section 7.2

## Issue #4: No holdout scenario covers the `StageFailed` → `StageRetrying` → retry success flow

**Status: Applied to holdout scenarios**

The proposed scenario has been written to `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` covering both the intermediate status during the retry window and the final "complete" status after successful retry. The scenario explicitly tests that `will_retry: true` prevents the node from being stuck in error state.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added proposed holdout scenario for StageFailed retry flow

## Not Addressed (Out of Scope)

- None. All four issues were addressed (three applied to spec, one deferred as proposed holdout scenario).
