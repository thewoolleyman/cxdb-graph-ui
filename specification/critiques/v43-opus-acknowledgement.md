# CXDB Graph UI Spec — Critique v43 (opus) Acknowledgement

All four issues from the v43 opus critique were evaluated. Issues #1, #2, and #4 were applied to the specification, verified against Kilroy source (`cxdb_events.go`). Issue #3 was deferred as a proposed holdout scenario.

## Issue #1: `StageFinished` rendering omits `notes` and `suggested_next_ids` fields that Kilroy emits

**Status: Applied to specification**

The `StageFinished` row in Section 7.2's per-type rendering table was updated to include `notes` and `suggested_next_ids`. The rendering now appends `notes` (if non-empty) as a newline-separated block after `failure_reason`, and `suggested_next_ids` (if non-empty) as a comma-joined list prefixed with "Next:". The explanatory paragraph later in Section 7.2 was also updated to describe both fields and their source in Kilroy's `cxdbStageFinished` (`cxdb_events.go` lines 87-88). Option (a) from the critique was chosen because `notes` provides the only concise narrative summary of what happened during a stage, beyond the raw turn stream.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 7.2 `StageFinished` rendering row and explanatory paragraph to include `notes` and `suggested_next_ids`

## Issue #2: `StageRetrying` rendering omits `delay_ms`, losing useful temporal context for operators

**Status: Applied to specification**

The `StageRetrying` row in Section 7.2's per-type rendering table was updated to include `delay_ms`. The rendering now appends ", delay {formatted_delay}" (where `formatted_delay` converts milliseconds to human-readable duration, e.g., 1500 to "1.5s", 60000 to "60s") when `data.delay_ms` is present and greater than 0. The explanatory paragraph was also updated to note that `StageRetrying` renders `delay_ms` alongside `attempt`. Verified against Kilroy's `cxdbStageRetrying` (`cxdb_events.go` line 209) which always emits `delay_ms`.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 7.2 `StageRetrying` rendering row and explanatory paragraph to include `delay_ms`

## Issue #3: No holdout scenario covers the interaction between `StageFailed` with `will_retry=true` and subsequent `StageRetrying` turn ordering in the status map

**Status: Deferred — proposed holdout scenario written**

A proposed holdout scenario "Node retrying after StageFailed with will_retry=true shows as running" was written to `holdout-scenarios/proposed-holdout-scenarios-to-review.md`. The scenario isolates the intermediate retry state (`StageFailed(will_retry=true)` then `StageRetrying` then `StageStarted`) and verifies that `hasLifecycleResolution` remains `false` throughout, distinguishing it from the existing v35-opus proposed scenario which tests the full retry-to-completion flow.

Changes:
- `holdout-scenarios/proposed-holdout-scenarios-to-review.md`: Added proposed scenario for StageFailed retry sequence intermediate state

## Issue #4: The spec does not document what happens when the Go server receives a request to a non-existent route

**Status: Applied to specification**

A new bullet point was added to Section 3.3 (Server Properties) stating that requests to paths not matching any registered route return 404 with a plain-text body, and that the server does not serve directory listings, automatic redirects, or HTML error pages for unmatched routes. This covers browser `/favicon.ico` requests and monitoring tool probes.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added unmatched-route behavior to Section 3.3

## Not Addressed (Out of Scope)

- Issue #3 is deferred to the holdout scenario review process. The spec already documents the `StageFailed` `will_retry` behavior in the status derivation pseudocode; the gap is in holdout scenario coverage for the specific retry turn sequence.
