# CXDB Graph UI Spec — Critique v45 (opus) Acknowledgement

All four issues from the v45 opus critique were evaluated. Issues #1, #2, and #3 were applied to the specification, verified against Kilroy source (`cxdb_events.go`, `engine.go`). Issue #4 was deferred as a proposed holdout scenario.

## Issue #1: `RunCompleted` lacks `node_id` but spec does not document this omission in the turn type table's key data fields

**Status: Applied to specification**

The Section 5.4 turn type table was updated to include the missing fields. `RunCompleted` now lists: `run_id`, `final_status`, `final_git_commit_sha`, `cxdb_context_id`, `cxdb_head_turn_id`. Verified against Kilroy's `cxdbRunCompleted` (`cxdb_events.go` lines 159-172: `final_git_commit_sha`, `cxdb_context_id`, `cxdb_head_turn_id`). Note that `final_status` is always hardcoded as `"success"` — `RunCompleted` is only emitted when the pipeline succeeds. `RunFailed` was also updated to add `git_commit_sha` (verified at `cxdb_events.go` line 324). The `run_id` and `timestamp_ms` meta-fields that appear on all turns are intentionally omitted from the "key data fields" column but noted in `RunCompleted` and `RunFailed` for completeness. The note in Section 5.4 already clarifies that none of these additional fields affect UI behavior since `RunCompleted` has no `node_id` and is filtered by the status derivation guard.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 5.4 `RunCompleted` row to add `final_git_commit_sha`, `cxdb_context_id`, `cxdb_head_turn_id`
- `specification/cxdb-graph-ui-spec.md`: Updated Section 5.4 `RunFailed` row to add `git_commit_sha`

## Issue #2: `StageFailed` field inventory missing `attempt` in the turn type table

**Status: Applied to specification**

The `StageFailed` rendering row in Section 7.2 was updated to include the attempt number. The rendering now appends " (will retry, attempt {`data.attempt`})" when `data.will_retry == true`, and " (attempt {`data.attempt`})" when `data.will_retry != true` and `data.attempt` is present and > 0. Verified against Kilroy's `cxdbStageFailed` (`cxdb_events.go` lines 185-197: `attempt` is always emitted). This gives operators consistent attempt visibility across both `StageFailed` (with and without retry) and `StageRetrying`.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 7.2 `StageFailed` rendering row to include attempt number

## Issue #3: Kilroy's `cxdbRunFailed` can be called with an empty `nodeID` string, but the spec assumes it always carries one

**Status: Applied to specification**

The language in Sections 6.2 and 7.2 was softened. Verified against `engine.go` (`persistFatalOutcome`, lines 1426-1448): `nodeID` is initialized to `""` and is only set if `e.Context != nil` and `current_node` is present — so an empty `node_id` is possible when the engine fails before entering any node. Section 6.2 now reads: "Kilroy's `cxdbRunFailed` always includes a `node_id` key, but the value may be an empty string if the run fails before entering any node (e.g., during graph initialization — see `persistFatalOutcome` in `engine.go`). An empty `node_id` passes the `IF nodeId IS null` guard but is filtered by the `IF nodeId NOT IN existingMap` guard, so it does not affect any node's status." Section 7.2 was updated similarly. The proposed holdout scenario for v39-opus (which also cited "always passes a `node_id`") was updated to match the corrected language.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 6.2 `RunFailed` `node_id` language in the Lifecycle turn precedence paragraph
- `specification/cxdb-graph-ui-spec.md`: Updated Section 7.2 pipeline-level turns paragraph for `RunFailed`
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Updated v39-opus expected behavior to match corrected language

## Issue #4: No holdout scenario tests gap recovery with lifecycle turns that arrive during the gap

**Status: Applied to holdout scenarios**

A proposed holdout scenario "Gap recovery bounded by MAX_GAP_PAGES advances cursor to oldest recovered turn" was written to `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`. The scenario verifies that when gap recovery exhausts `MAX_GAP_PAGES`, `lastSeenTurnId` is set to the oldest recovered turn's `turn_id` (not the newest), and that nodes outside the recovery window retain their previous status. The spec already documents this correctly in Section 6.1; the gap is in holdout scenario coverage.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added proposed scenario for MAX_GAP_PAGES cursor advancement

## Not Addressed (Out of Scope)

- Issue #4 is deferred to the holdout scenario review process. The spec already documents the correct cursor assignment; the gap is in holdout scenario coverage only.
