# CXDB Graph UI Spec — Critique v9 (opus) Acknowledgement

All 3 issues were valid and applied to the specification. Issue #1 fixed a cursor-tracking bug where gap recovery's mixed-order batch caused `newLastSeenTurnId` to advance to the oldest gap turn instead of the newest turn. Issue #2 added lifecycle authority so `StageFinished` can override heuristic error status. Issue #3 replaced the lifetime error counter with a consecutive-recent-errors check matching the holdout scenario's semantics.

## Issue #1: Gap recovery prepend breaks `newLastSeenTurnId` cursor tracking

**Status: Applied to specification**

Replaced the first-iteration trick for capturing `newLastSeenTurnId` with an explicit pre-loop pass that computes `max(turn_id)` across the entire batch. This handles any batch ordering, including the mixed-order batches produced by gap recovery (oldest-first gap turns prepended before newest-first main-batch turns). Changed the deduplication `BREAK` to `CONTINUE` since the combined batch is no longer guaranteed to be sorted newest-first — older turns may appear after newer ones. Updated the "Turn deduplication" explanatory paragraph to describe the new behavior.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 pseudocode — replaced in-loop `newLastSeenTurnId` capture with pre-loop `max(turn_id)` computation; changed `BREAK` to `CONTINUE` for deduplication
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 "Turn deduplication" paragraph — rewritten to explain mixed-order batch handling and pre-loop cursor computation

## Issue #2: Heuristic error status is permanent and blocks later StageFinished

**Status: Applied to specification**

Added a `hasLifecycleResolution` boolean to `NodeStatus`, set to `true` when `StageFinished` or `StageFailed` is processed. Lifecycle turns now unconditionally set the node's status (overriding any previous value, including heuristic "error"). Non-lifecycle turns still follow the promotion-only rule. The error loop heuristic now only fires for nodes where `hasLifecycleResolution == false`, preventing it from overriding a definitive lifecycle outcome. Rewrote the "Lifecycle turn precedence" paragraph to explain this behavior. This was implemented using the simpler `hasLifecycleResolution` approach (the critique's second suggestion) rather than the `errorSource` field approach, as it cleanly separates "has the pipeline framework resolved this node?" from "what status does the heuristic infer?".

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 `NodeStatus` type — added `hasLifecycleResolution: Boolean` field
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 pseudocode — `StageFinished` and `StageFailed` now set `hasLifecycleResolution = true` and unconditionally override status; heuristic guarded by `NOT hasLifecycleResolution`
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 "Lifecycle turn precedence" paragraph — rewritten to explain lifecycle authority over heuristic errors
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 `mergeStatusMaps` — updated `NodeStatus` initialization to include `hasLifecycleResolution: false`

## Issue #3: Error heuristic threshold is lifetime-total, not recent-window

**Status: Applied to specification**

Replaced the `errorCount >= 3` lifetime threshold with a check against the most recent 3 turns for the node from the per-pipeline turn cache. The heuristic now calls `getMostRecentTurnsForNode(turnCache, nodeId, count=3)` and only promotes to "error" if all 3 recent turns have `is_error == true`. This matches the holdout scenario's semantics ("the most recent 3+ turns on a node have `is_error: true`") — detecting an active error loop rather than lifetime error accumulation. Added a new "Error loop detection heuristic" paragraph describing the `getMostRecentTurnsForNode` helper and the semantic distinction. The `errorCount` field remains on `NodeStatus` as a display-only lifetime counter for the detail panel.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 pseudocode — replaced `errorCount >= 3` heuristic with `getMostRecentTurnsForNode` recent-window check
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 — added "Error loop detection heuristic" paragraph explaining the helper and semantics

## Not Addressed (Out of Scope)

- None — all issues were addressed.
