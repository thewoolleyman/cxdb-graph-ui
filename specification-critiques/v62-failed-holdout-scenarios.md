# CXDB Graph UI Spec — Critique v62 (failed-holdout-scenarios)

**Critic:** failed-holdout-scenarios (Claude Opus 4.6)
**Date:** 2026-03-02

## Prior Context

The v61 critique drove a comprehensive frontend architecture overhaul: the single-file SPA with CDN dependencies was replaced by a modern frontend stack aligned with cxdb conventions (Vite + React 18, TypeScript strict, Tailwind CSS v3, pnpm v9, ESLint, Playwright + Vitest). All 17 issues from v61 were applied in the v61 acknowledgement. This critique is based on **holdout scenario verification** of the built implementation, not a spec review. The implementation was produced by a Kilroy pipeline run and landed via squash-merge.

---

## Issue #1: Status engine does not process StageFinished turns — nodes never transition from running to complete

### The problem

The specification clearly defines in Section 6.2 (`updateContextStatusMap`) that `StageFinished` turns should promote nodes to "complete" (or "error" if `status == "fail"`). However, the implementation does not implement this logic. All nodes with any CXDB activity show as "running" (blue) regardless of whether `StageFinished` has been received.

**Evidence from holdout testing:**
- `pipeline_running` scenario (screenshot: `batch8-pipeline-running.png`): `implement` shows as blue (running) despite having a `StageFinished` turn with `status: "pass"`. Expected: green (complete).
- `pipeline_complete` scenario: All traversed nodes show as "stale" (orange) instead of "complete" (green), because without StageFinished processing, `hasLifecycleResolution` is never set to `true`, and the stale detection logic (`applyStaleDetection`) reclassifies all "running" nodes as "stale" when `is_live: false`.

This is the root cause of 6 of the 8 failures observed in holdout testing (pipeline_running, pipeline_complete, stage_finished_fail, run_failed, error_loop, second_run).

### Suggestion

This is an **implementation bug**, not a specification deficiency. The specification's `updateContextStatusMap` pseudocode (Section 6.2) correctly handles all lifecycle turn types:

```
IF typeId == "com.kilroy.attractor.StageFinished":
    existingMap[nodeId].hasLifecycleResolution = true
    IF turn.data.status == "fail":
        newStatus = "error"
    ELSE:
        newStatus = "complete"
```

The implementation must match this pseudocode. Specifically, the status derivation code in `frontend/src/lib/status.ts` must:

1. Check `turn.declared_type.type_id` (not `turn.declared_type` directly — see Issue #2) against the full type ID strings (`com.kilroy.attractor.StageFinished`, `com.kilroy.attractor.StageFailed`, `com.kilroy.attractor.RunFailed`, `com.kilroy.attractor.StageStarted`).
2. Set `hasLifecycleResolution = true` for `StageFinished`, terminal `StageFailed`, and `RunFailed`.
3. Apply lifecycle turn precedence (unconditional override) vs. non-lifecycle turn precedence (promotion-only).
4. Correctly handle `StageFinished.data.status == "fail"` as "error", not "complete".

**No spec change needed.** The factory's next run should be directed to implement the `updateContextStatusMap` algorithm as specified, with particular attention to the lifecycle turn precedence rules.

---

## Issue #2: Detail panel crashes (React white screen) when rendering CXDB turn data — TypeError on `declared_type` field access

### The problem

Clicking any node with CXDB activity causes a React crash (white screen). The error is:

```
TypeError: Cannot read properties of undefined (reading 'split')
    at Ki (index-Bmp4OIjF.js:43:55)
```

**Evidence:** Screenshot `batch9-detail-panel-crash.png` shows a completely white page after clicking a node with CXDB turns present.

**Root cause:** The detail panel's turn rendering code (likely in `TurnRow.tsx` or the per-type rendering logic) accesses `declared_type` incorrectly. The CXDB turn response (as documented in `specification/contracts/cxdb-upstream.md`) returns `declared_type` as an **object** with a `type_id` field:

```json
{
  "declared_type": {
    "type_id": "com.kilroy.attractor.ToolResult",
    "type_version": 1
  }
}
```

The implementation appears to call `.split()` on a property that is undefined, suggesting it may be treating `declared_type` as a string, or accessing a non-existent sub-property. The correct access pattern is `turn.declared_type.type_id`.

### Suggestion

This is an **implementation bug**. The specification clearly documents the turn response structure in `specification/contracts/cxdb-upstream.md` (Turn Response section) and references `declared_type.type_id` throughout Section 6.2 and Section 7.2.

Two implementation fixes are needed:

1. **Fix the type access pattern.** The code must use `turn.declared_type.type_id` to extract the type string. The per-type rendering table in Section 7.2 uses the Type column sourced from `declared_type.type_id`.

2. **Add an error boundary around the detail panel.** The specification states in Section 1.2 (Graceful degradation) that CXDB is an overlay — a crash in the CXDB Activity section should not kill the entire React component tree. The detail panel should wrap the CXDB Activity section in a React error boundary so that a rendering failure in turn data shows an error message in the panel, not a white screen.

**Suggested spec addition:** Add to Section 7.2 (CXDB Activity) a defensive rendering note:

> **Error boundary.** The CXDB Activity section of the detail panel must be wrapped in a React error boundary. If any turn's data structure does not match the expected shape (e.g., missing `declared_type.type_id`, missing `data` fields), the error boundary catches the rendering failure and displays "Error rendering CXDB turns" in place of the turn list. The rest of the detail panel (DOT attributes, node ID, type) remains functional. This prevents malformed or unexpected turn data from crashing the entire UI.

---

## Issue #3: Pipeline completion detection treats `is_live: false` + finished nodes as "stalled" instead of "completed"

### The problem

When all active-run contexts have `is_live: false` and all traversed nodes have `StageFinished` turns, the specification's `applyStaleDetection` correctly handles this case — it only reclassifies nodes that are "running" AND lack `hasLifecycleResolution`. If `StageFinished` is processed correctly (Issue #1), nodes would be "complete" with `hasLifecycleResolution = true`, and `applyStaleDetection` would leave them alone.

However, because Issue #1 prevents `hasLifecycleResolution` from being set, `applyStaleDetection` reclassifies all nodes as "stale" and the UI shows the "Pipeline stalled — no active sessions" banner.

**Evidence:** `pipeline_complete` scenario shows all traversed nodes as orange (stale) with the stall banner, when they should be green (complete).

### Suggestion

This is a **cascading effect of Issue #1**, not a separate spec issue. Once `StageFinished` processing is implemented correctly:
- Nodes with `StageFinished` will have `status: "complete"` and `hasLifecycleResolution: true`
- `applyStaleDetection` will skip them (they are not "running")
- The stall banner should only appear when there are nodes in "running" state that get reclassified to "stale"

**No spec change needed.** The spec's algorithm is correct. The implementation must match it.

However, the specification could be clearer about the **stall banner display condition**. Currently, the stall banner logic is not explicitly specified — it is implied by the stale detection. Consider adding to Section 6.2 or the UI layout specification:

> **Stall banner.** The "Pipeline stalled — no active sessions" banner is displayed when `applyStaleDetection` reclassifies at least one node from "running" to "stale." If all nodes are "complete" or "pending" and `is_live: false`, no banner is shown — this represents a successfully completed pipeline, not a stalled one.

---

## Issue #4: State not cleared between mock scenario switches (no_pipeline retains stale state)

### The problem

When switching from a scenario with CXDB data to the `no_pipeline` scenario (which returns empty context lists), nodes retain their previous status (stale/running) instead of resetting to gray (pending).

**Evidence:** After switching to `no_pipeline`, nodes retain `node-stale` class and the "Pipeline stalled" banner persists.

### Suggestion

This is partly an **implementation bug** and partly a **spec gap**. The specification addresses run changes in Section 6.1 step 3:

> When the active `run_id` changes for a pipeline, reset all per-context status maps and `lastSeenTurnId` cursors for that pipeline's old-run contexts, and clear the per-pipeline turn cache.

But it does not explicitly address the transition from "having an active run" to "having no active run" (i.e., when `determineActiveRuns` returns an empty context list for a pipeline that previously had contexts). In the `no_pipeline` scenario, CXDB returns no contexts at all — `determineActiveRuns` finds no candidates, so `activeRunId` would be `null`.

**Suggested spec addition to Section 6.1 step 3 (`determineActiveRuns`):**

> When `candidates IS EMPTY` for a pipeline that previously had an active run (i.e., `previousActiveRunIds[pipeline.graphId]` is non-null), call `resetPipelineState(pipeline.graphId)` and set `previousActiveRunIds[pipeline.graphId] = null`. This handles the case where all contexts for a pipeline are removed (e.g., CXDB data cleared) or when switching from a live pipeline to no pipeline activity. Without this reset, the per-context status maps from the previous run persist indefinitely with no data to update them.

---

## Issue #5: Second run shows stale instead of run B progress

### The problem

The `second_run` scenario tests that when a new run B starts while run A data exists, the UI shows run B's progress. Instead, all traversed nodes show as "stale" with the stall banner.

**Evidence:** `second_run` scenario: Expected `implement=green, fix_fmt=blue` (from run B). Actual: all traversed nodes=stale.

### Suggestion

This is a **cascading effect of Issues #1 and #3**. The `second_run` mock scenario includes run B data with `StageFinished` for `implement` and `StageStarted` for `fix_fmt`. If `StageFinished` processing worked (Issue #1), `implement` would be "complete" and `fix_fmt` would be "running". Then `applyStaleDetection` would only reclassify `fix_fmt` to "stale" if `is_live: false` — but the `second_run` scenario should have `is_live: true` for run B's contexts.

**No spec change needed.** Fixing Issue #1 resolves this.

---

## Summary

The 8 holdout failures stem from **2 root implementation bugs** and **1 minor spec gap**:

| Root Cause | Affected Failures | Fix Type |
|---|---|---|
| Status engine ignores lifecycle turns (StageFinished, StageFailed, RunFailed) | 6 failures: pipeline_running, pipeline_complete, stage_finished_fail, run_failed, error_loop, second_run | Implementation fix — match spec pseudocode |
| Detail panel crashes on `declared_type` field access | 1 failure: detail panel crash | Implementation fix + spec addition (error boundary) |
| State not cleared when pipeline has no active run | 1 failure: no_pipeline retains stale state | Minor spec addition to `determineActiveRuns` |

The specification's algorithms are sound. The implementation does not follow them. The next Kilroy pipeline run should prioritize:

1. Implementing `updateContextStatusMap` lifecycle turn processing exactly as specified in Section 6.2
2. Fixing `declared_type.type_id` access in the detail panel turn rendering
3. Adding an error boundary around the CXDB Activity section
4. Handling the "no active run" → reset transition in `determineActiveRuns`
