# CXDB Graph UI Spec — Critique v38 (opus) Acknowledgement

All four issues from the v38 opus critique were evaluated and applied to the specification. Changes were verified against the Kilroy source code (`cxdb_events.go`, `kilroy_registry.go`, `runtime/status.go`).

## Issue #1: StageFinished detail panel rendering discards valuable `status` and `preferred_label` fields in favor of a fixed "Stage finished" label

**Status: Applied to specification**

The `StageFinished` row in the per-type rendering table (Section 7.2) was changed from a fixed "Stage finished" label to a dynamic rendering that includes `data.status`, `data.preferred_label` (when non-empty), and `data.failure_reason` (when non-empty). The Error column now highlights when `data.status` is `"fail"`. The summary paragraph at the end of the per-type rendering section was updated to explain why `StageFinished` now renders its data fields instead of a fixed label. Verified against Kilroy source: `cxdb_events.go` lines 80-89 confirms `StageFinished` emits `status`, `preferred_label`, `failure_reason`, `notes`, and `suggested_next_ids`.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated `StageFinished` row in Section 7.2 per-type rendering table
- `specification/cxdb-graph-ui-spec.md`: Updated summary paragraph at end of per-type rendering section

## Issue #2: Spec's Section 5.4 type table omits several fields that Kilroy actually emits for StageFinished and StageStarted

**Status: Applied to specification**

The Section 5.4 turn type table was updated to include the missing fields. `StageStarted` now lists `handler_type` (optional) and `attempt` (optional). `StageFinished` now lists `failure_reason` (optional), `notes` (optional), and `suggested_next_ids` (optional, array) in addition to the already-documented `status` and `preferred_label`. Verified against `kilroy_registry.go` lines 53-69.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated `StageStarted` and `StageFinished` rows in Section 5.4 type table

## Issue #3: The status derivation algorithm treats `StageFinished` as unconditionally "complete" regardless of the `status` field value

**Status: Applied to specification**

The `updateContextStatusMap` pseudocode in Section 6.2 was amended to check `turn.data.status` on `StageFinished` turns. When `status == "fail"`, the node is set to "error" (red) instead of "complete" (green). The `hasLifecycleResolution` flag is still set to `true` regardless of the status value. The "Lifecycle turn precedence" explanatory paragraph was updated to document the status check and the `StageStatus` enum values. Invariant #5 in Section 9 was updated to reflect that `StageFinished` with `status == "fail"` maps to "error".

Changes:
- `specification/cxdb-graph-ui-spec.md`: Amended `StageFinished` branch in `updateContextStatusMap` pseudocode (Section 6.2)
- `specification/cxdb-graph-ui-spec.md`: Updated "Lifecycle turn precedence" paragraph (Section 6.2)
- `specification/cxdb-graph-ui-spec.md`: Updated Invariant #5 (Section 9)

## Issue #4: No holdout scenario covers the `StageFinished` with `status: "fail"` case

**Status: Applied to holdout scenarios**

A proposed holdout scenario "Node finishes with failure status (StageFinished status: 'fail')" was written to `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`. The scenario tests that a node with `StageFinished { status: "fail" }` displays as red (error), not green (complete), and that the detail panel renders the failure details.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added proposed scenario for StageFinished with status "fail"

## Not Addressed (Out of Scope)

- None. All four issues were fully addressed.
