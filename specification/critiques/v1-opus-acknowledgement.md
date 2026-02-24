# CXDB Graph UI Spec — Critique v1 (opus) Acknowledgement

All 10 issues were evaluated. 9 were applied to the specification with substantive changes. 1 was partially addressed. The status derivation algorithm was rewritten to use lifecycle turns and handle parallel contexts correctly. New server endpoints were added for DOT file listing and node attribute parsing. The initialization sequence and multiple-run handling were specified.

## Issue #1: Status derivation algorithm doesn't account for StageStarted/StageFinished/StageFailed turn types

**Status: Applied to specification**

Rewrote the `buildNodeStatusMap` algorithm (now `buildContextStatusMap`) in Section 6.2 to use lifecycle turns as primary status signals: `StageFinished` → complete, `StageFailed` → error, `StageStarted` → running. The heuristic fallback (non-lifecycle turns mark a node as "running" if pending) is retained for contexts that lack lifecycle events. The 3-error threshold is now a fallback that only applies when no `StageFailed` turn exists. Updated Invariant #5 to reference lifecycle turns.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 algorithm rewritten, Invariant #5 updated

## Issue #2: No specification for how turns are fetched for the status overlay

**Status: Applied to specification**

Added explicit query parameters (`limit=100, order=desc`) to Section 6.1 polling step 3. Added a "Turn fetch limit" paragraph explaining why 100 is sufficient (lifecycle turns at node boundaries) and what happens for very long-running nodes.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 steps and new paragraph after polling steps

## Issue #3: No specification for handling multiple active runs of the same pipeline

**Status: Applied to specification**

Added a "Multiple runs of the same pipeline" paragraph to Section 5.5. The UI uses only the most recent run, determined by `created_at_unix_ms` of the `RunStarted` contexts. Contexts from older runs are ignored. Added a holdout scenario for this case.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 5.5 new paragraph
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added "Second run of same pipeline" scenario

## Issue #4: Multi-context turn merging for parallel branches is under-specified

**Status: Applied to specification**

Rewrote Section 6.2 to process contexts independently via `buildContextStatusMap`, then merge with `mergeStatusMaps` using explicit precedence: error > running > complete > pending. Added full pseudocode for both functions. Updated the parallel branches holdout scenario to verify both branches show as running.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 complete rewrite with per-context algorithm and merge function
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Updated parallel branches scenario

## Issue #5: `run_id` field is present in turn data but never used

**Status: Applied to specification**

`run_id` is now used for run grouping (ties into Issue #3). The discovery algorithm records `run_id` from the `RunStarted` turn. Contexts sharing the same `run_id` are grouped as part of the same run. Cross-instance merging now explicitly references `run_id` matching. Added Definition of Done item.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 5.5 updated to reference `run_id` in discovery and cross-instance merging

## Issue #6: CDN dependency for @hpcc-js/wasm-graphviz has no fallback or version pin

**Status: Applied to specification**

Pinned the exact CDN URL to `@hpcc-js/wasm-graphviz@1.6.1` in Section 4.1. Documented the `Graphviz.load()` async factory API. Added CDN-unreachable behavior: error message in graph area, rest of UI still renders.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 4.1 rewritten with pinned URL and fallback behavior

## Issue #7: DOT attribute parsing for detail panel is unspecified

**Status: Applied to specification**

Added a new server endpoint `GET /dots/{name}/nodes` (Section 3.2) that parses DOT node attributes server-side and returns JSON. This avoids complex DOT parsing in browser JavaScript. Updated Section 7.1 to reference this endpoint. Added Definition of Done item.

Changes:
- `specification/cxdb-graph-ui-spec.md`: New route in Section 3.2, Section 7.1 updated

## Issue #8: Missing holdout scenario for the last node in a pipeline

**Status: Applied to specification**

Added a holdout scenario "Pipeline completed — last node marked complete via StageFinished" that verifies the final node is green, not blue. This is naturally solved by the lifecycle-turn-based algorithm from Issue #1: the `StageFinished` turn definitively marks the node as complete regardless of whether a subsequent node exists.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: New scenario added

## Issue #9: No specification for initial page load sequence

**Status: Applied to specification**

Added Section 4.5 "Initialization Sequence" describing the 5-step boot process: WASM loading (with loading indicator), DOT list fetch, CXDB instance fetch, first render, and polling start (first poll at t=0). Added `GET /api/dots` endpoint to Section 3.2 for listing available DOT files. Added Definition of Done item.

Changes:
- `specification/cxdb-graph-ui-spec.md`: New Section 4.5, new route in Section 3.2

## Issue #10: Holdout scenarios don't cover the goal_gate DOT attribute

**Status: Partially addressed**

Clarified in Section 7.1 that `goal_gate` is a boolean flag on conditional (`diamond` shape) nodes, displayed as a badge on the detail panel header. It does not have its own shape. Did not add a dedicated holdout scenario — the existing "Click a node to see details" scenario covers detail panel attribute display generically, and goal_gate is just one of several optional attributes shown when present.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 7.1 goal_gate description clarified

## Not Addressed (Out of Scope)

- None. All issues were addressed.
