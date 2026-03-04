# Unimplemented Specifications

Source: holdout scenario verification during landing of run 01KJRF75H261FMFY4YR1A3HCNY
Date: 2026-03-02

## Unimplemented: Status engine does not process StageFinished turns — nodes never transition from running to complete

**Specification reference:** `specification/intent/status-overlay.md`, Section 6.2 — `updateContextStatusMap` pseudocode (lines 188–285)
**What the spec requires:** `StageFinished` turns set `hasLifecycleResolution = true` and promote nodes to "complete" (or "error" if `status == "fail"`). `StageFailed` (terminal) and `RunFailed` also set `hasLifecycleResolution = true`. Lifecycle turns unconditionally override current status. The type ID check uses `turn.declared_type.type_id` against full strings like `com.kilroy.attractor.StageFinished`.
**What the implementation does:** All nodes with any CXDB activity (StageStarted or later) show as "running" (blue) regardless of whether StageFinished has been received. The status engine does not process lifecycle turns to promote nodes beyond "running".
**Holdout scenarios affected:** pipeline_running, pipeline_complete, stage_finished_fail, run_failed, error_loop, second_run (6 of 8 failures)
**Evidence:** `specification-critiques/v62-failed-holdout-scenarios-artifacts/batch8-pipeline-running.png` — implement node shows blue (running) instead of green (complete)

**Implementation fix required in:** `frontend/src/lib/status.ts` — implement the `updateContextStatusMap` algorithm as specified:
1. Check `turn.declared_type.type_id` (not `turn.declared_type` directly) against full type ID strings
2. Set `hasLifecycleResolution = true` for StageFinished, terminal StageFailed, and RunFailed
3. Apply lifecycle turn precedence (unconditional override) vs non-lifecycle turn precedence (promotion-only)
4. Handle `StageFinished.data.status == "fail"` as "error", not "complete"

## Unimplemented: Detail panel crashes on declared_type field access — TypeError on CXDB turn rendering

**Specification reference:** `specification/intent/status-overlay.md`, Section 6.2 — `turn.declared_type.type_id` access pattern; `specification/contracts/cxdb-upstream.md` — Turn Response structure showing `declared_type` as an object with `type_id` field
**What the spec requires:** Turn type is accessed via `turn.declared_type.type_id` (an object property). The detail panel (Section 7.2) renders per-type turn rows using the Type column sourced from `declared_type.type_id`.
**What the implementation does:** The detail panel's turn rendering code calls `.split()` on an undefined property, crashing with `TypeError: Cannot read properties of undefined (reading 'split')`. This suggests it treats `declared_type` as a string or accesses a non-existent sub-property.
**Holdout scenarios affected:** detail panel crash (1 failure)
**Evidence:** `specification-critiques/v62-failed-holdout-scenarios-artifacts/batch9-detail-panel-crash.png` — white screen after clicking a node with CXDB turns

**Implementation fix required in:** `frontend/src/components/DetailPanel.tsx` (or `TurnRow.tsx` / per-type rendering logic):
1. Fix type access to use `turn.declared_type.type_id` consistently
2. Add a React error boundary around the CXDB Activity section so turn rendering failures show an error message in the panel, not a white screen

## Unimplemented: Error loop detection heuristic not triggering

**Specification reference:** `specification/intent/status-overlay.md`, Section 6.2 — `applyErrorHeuristic` pseudocode and "Error loop detection heuristic" paragraph (line 287)
**What the spec requires:** Post-merge, for nodes that are "running" with `hasLifecycleResolution == false`, examine each context's cached turns — if any single context has 3 consecutive recent `ToolResult` errors (`is_error == true`) for the node, promote to "error".
**What the implementation does:** fix_fmt shows as "running" (blue) despite 3 consecutive ToolResult errors in the error_loop mock scenario. The heuristic either is not implemented or is not firing.
**Holdout scenarios affected:** error_loop (1 failure, also blocked by Issue #1 since hasLifecycleResolution is never set)
**Evidence:** error_loop scenario: fix_fmt expected red (error), actual blue (running)

**Implementation fix required in:** `frontend/src/lib/status.ts` — implement or fix `applyErrorHeuristic` per the spec pseudocode

## Unimplemented: Pipeline state not cleared when active run disappears (no_pipeline scenario)

**Specification reference:** `specification/intent/status-overlay.md`, Section 6.1 step 3 — `determineActiveRuns` and `resetPipelineState`
**What the spec requires:** When `candidates IS EMPTY` for a pipeline that previously had an active run, reset pipeline state (clear per-context status maps, cursors, and turn cache). Section 6.1 step 3 specifies `resetPipelineState` for run changes but does not explicitly cover the transition from "having an active run" to "having no active run".
**What the implementation does:** When switching to no_pipeline (CXDB returns empty contexts), nodes retain their previous stale/running status and the "Pipeline stalled" banner persists.
**Holdout scenarios affected:** no_pipeline retains stale state (1 failure)
**Evidence:** After switching to no_pipeline, nodes retain `node-stale` class and "Pipeline stalled" banner persists

**Implementation fix required in:** `frontend/src/lib/status.ts` or the polling hook — handle the transition from non-null `activeRunId` to null (empty candidate list) by calling `resetPipelineState`

**Note:** This issue also has a minor spec gap — the critique (v62) suggests adding explicit language to `determineActiveRuns` for the empty-candidates case. See `specification-critiques/v62-failed-holdout-scenarios.md` Issue #4 for the suggested spec addition.
