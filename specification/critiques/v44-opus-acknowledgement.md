# CXDB Graph UI Spec — Critique v44 (opus) Acknowledgement

All four issues from the v44 opus critique were evaluated. Issues #1, #2, and #4 were applied to the specification, verified against Kilroy source (`cxdb_events.go`). Issue #3 was deferred as a proposed holdout scenario.

## Issue #1: `InterviewStarted` rendering drops `question_type`, losing the gate mode distinction operators need

**Status: Applied to specification**

The `InterviewStarted` row in Section 7.2's per-type rendering table was updated to include `question_type`. The rendering now appends " [{`data.question_type`}]" when `data.question_type` is non-empty, showing the gate mode (e.g., "multiple_choice", "free_text", "yes_no") alongside the question text. The `InterviewCompleted` row was also updated to include `duration_ms`, appending " (waited {formatted_duration})" when `data.duration_ms` is present and greater than 0, showing how long the pipeline was blocked waiting for human input. Both use the new `formatMilliseconds` helper (see Issue #4). The explanatory paragraph was updated to note the new fields. Verified against Kilroy's `cxdbInterviewStarted` (`cxdb_events.go` line 283: `question_type`) and `cxdbInterviewCompleted` (`cxdb_events.go` line 296: `duration_ms`).

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 7.2 `InterviewStarted` rendering row to include `question_type`
- `specification/cxdb-graph-ui-spec.md`: Updated Section 7.2 `InterviewCompleted` rendering row to include `duration_ms`
- `specification/cxdb-graph-ui-spec.md`: Updated Section 7.2 explanatory paragraph to describe the new Interview fields

## Issue #2: Section 5.4's `ParallelBranchCompleted` field list is incomplete relative to Kilroy source

**Status: Applied to specification**

The Section 5.4 turn type table was updated to include the missing fields. `ParallelBranchCompleted` now lists: `node_id`, `branch_key`, `branch_index`, `status`, `duration_ms`. `ParallelCompleted` now lists: `node_id`, `success_count`, `failure_count`, `duration_ms`. These additions are documentation-only — both types fall through to the "Other/unknown" rendering row and their UI behavior is unchanged. Verified against Kilroy's `cxdbParallelBranchCompleted` (`cxdb_events.go` lines 247-255: `branch_index`, `duration_ms`) and `cxdbParallelCompleted` (`cxdb_events.go` lines 259-270: `duration_ms`). The `run_id` and `timestamp_ms` meta-fields were intentionally omitted from the table as they appear on all turn types and are not UI-relevant.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 5.4 `ParallelBranchCompleted` row to add `branch_index` and `duration_ms`
- `specification/cxdb-graph-ui-spec.md`: Updated Section 5.4 `ParallelCompleted` row to add `duration_ms`

## Issue #3: No holdout scenario verifies that `StageFinished` with `status: "fail"` produces a red (error) node, not green (complete)

**Status: Deferred — proposed holdout scenario written**

A proposed holdout scenario "StageFinished with status=fail shows as error, not complete" was written to `holdout-scenarios/proposed-holdout-scenarios-to-review.md`. The scenario verifies that a `StageFinished` turn with `status: "fail"` colors the node red (error), sets `hasLifecycleResolution = true`, and renders the failure reason in the detail panel. This supersedes the similar v38-opus proposed scenario by being more concise and focused on the status field check. The spec already documents this behavior in Section 6.2 (`updateContextStatusMap` pseudocode) and the Definition of Done; the gap is in holdout scenario coverage.

Changes:
- `holdout-scenarios/proposed-holdout-scenarios-to-review.md`: Added proposed scenario for StageFinished status=fail

## Issue #4: `formatted_delay` conversion for `StageRetrying` is underspecified for sub-second and large values

**Status: Applied to specification**

A `formatMilliseconds` helper definition was added to Section 7.2, specifying the conversion rules: if `ms >= 1000`, display as `{ms / 1000}s` (one decimal place if not a whole number, e.g., 1500 -> "1.5s", 2000 -> "2s", 60000 -> "60s"); if `ms < 1000`, display as `{ms}ms` (e.g., 250 -> "250ms", 1 -> "1ms"). Values of 0 are excluded by the guard (`> 0`). The `StageRetrying` row now references this helper, and the new `InterviewCompleted` rendering (Issue #1) also uses it. This eliminates ambiguity for sub-second values and ensures consistent formatting across all millisecond-to-human-readable conversions. Kilroy's retry backoff (`engine.go`) uses delays ranging from hundreds of milliseconds to tens of seconds, all of which now have deterministic display formats.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added `formatMilliseconds` helper definition to Section 7.2
- `specification/cxdb-graph-ui-spec.md`: Updated `StageRetrying` rendering row to reference the helper

## Not Addressed (Out of Scope)

- Issue #3 is deferred to the holdout scenario review process. The spec already documents the `StageFinished` status="fail" behavior; the gap is in holdout scenario coverage only.
