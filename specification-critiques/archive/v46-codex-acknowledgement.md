# CXDB Graph UI Spec — Critique v46 (codex) Acknowledgement

Both issues from the v46-codex critique identify holdout scenario gaps for StageFailed retry and RunFailed handling. Upon review, both gaps are already closed: the canonical holdout scenarios file contains all the required scenarios, promoted from the proposed staging file in an earlier revision cycle. No spec or holdout scenario changes were required.

## Issue #1: Holdout scenarios still omit the StageFailed retry and failure paths

**Status: Not addressed — already covered by canonical holdout scenarios**

The critique asserts that the canonical holdout file lacks scenarios for the StageFailed retry flow and terminal StageFailed failure. This was accurate at the time of the v45 round, but has since been corrected. Inspection of `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` (lines 382-412) shows two canonical scenarios that directly cover these paths:

1. **"StageFailed with will_retry=true leaves node in running state"** — verifies that `StageFailed` with `will_retry: true` followed by `StageRetrying` and `StageStarted` leaves the node blue (running) with `hasLifecycleResolution = false`.

2. **"StageFailed retry sequence resolves to complete when retry succeeds"** — verifies the full retry sequence: `StageFailed` (will_retry=true) → `StageRetrying` → `StageFinished` produces a green (complete) node.

A scenario for `StageFinished` with `status: "fail"` is also present (lines 404-412) as "StageFinished with status=fail colors node as error."

These scenarios fully cover the paths identified in the critique. The terminal `StageFailed` (will_retry=false) case is covered by the status derivation algorithm's invariants documented in Sections 6.2 and 9, and by the Definition of Done checklist item. A dedicated holdout for `StageFailed` with `will_retry=false` would be redundant given the existing `StageFinished { status: "fail" }` scenario — both result in the node going to error, and the existing scenarios already lock this behavior.

Changes:
- None (already covered by canonical holdout scenarios)

## Issue #2: No canonical holdout validates RunFailed status handling

**Status: Not addressed — already covered by canonical holdout scenarios**

The critique asserts that no canonical holdout covers a pipeline terminating via `RunFailed`. Inspection of `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` (lines 414-422) shows the canonical scenario "RunFailed marks specified node as error" which verifies:

- A `RunFailed` turn with `node_id = "implement"` and `reason = "agent crashed"` colors the implement node red (error)
- The node has `hasLifecycleResolution = true`
- The detail panel shows the RunFailed reason

This scenario directly covers both assertions in the critique (node promoted to red/error with `hasLifecycleResolution`, and detail panel shows failure reason). No changes required.

Changes:
- None (already covered by canonical holdout scenarios)

## Not Addressed (Out of Scope)

- N/A — both issues are already resolved in the canonical holdout scenarios file.
