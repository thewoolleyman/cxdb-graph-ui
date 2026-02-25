# CXDB Graph UI Spec — Critique v10 (opus) Acknowledgement

All 3 issues were valid and applied to the specification. Issue #1 introduced separate per-context and merge precedence maps to prevent complete→running regression within a single context. Issues #2 and #3 were addressed together by extracting the error loop heuristic from `updateContextStatusMap` into a new post-merge `applyErrorHeuristic` function that examines each context's turns independently, eliminating cross-instance turn ID comparison, the missing `turnCache` parameter, and per-context map contamination.

## Issue #1: Per-context PRECEDENCE map contradicts prose and allows "complete" → "running" regression

**Status: Applied to specification**

Introduced two distinct precedence maps: `CONTEXT_PRECEDENCE` (used in `updateContextStatusMap`) where `complete (2) > running (1)`, and `MERGE_PRECEDENCE` (used in `mergeStatusMaps`) where `running (2) > complete (1)`. Within a single execution flow, a completed node must not regress to running — this prevents the concrete bug where a `StageStarted` turn processed after `StageFinished` (due to newest-first batch ordering) would override the completed status. Across contexts, `running > complete` is correct because a running parallel branch should take visual priority over a completed one. Additionally, strengthened the lifecycle guard so that once `hasLifecycleResolution` is true, only lifecycle turns (`StageFinished`, `StageFailed`) can modify the node's status — non-lifecycle turns are now gated by `NOT existingMap[nodeId].hasLifecycleResolution`, providing a second layer of protection against regression.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 pseudocode — replaced single `PRECEDENCE` with `CONTEXT_PRECEDENCE` in `updateContextStatusMap` and `MERGE_PRECEDENCE` in `mergeStatusMaps`
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 pseudocode — restructured promotion guard so lifecycle turns are checked first (unconditional override), and non-lifecycle turns are gated by `NOT hasLifecycleResolution`
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 "Status map lifecycle" — updated prose to note per-context vs cross-context precedence difference
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 "Lifecycle turn precedence" paragraph — rewritten to explain both regression scenarios (error recovery and batch ordering)
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 "Multi-context merging" — added explanatory paragraph about why merge precedence intentionally differs from per-context precedence

## Issue #2: `getMostRecentTurnsForNode` sorts by `turn_id` across CXDB instances with independent ID sequences

**Status: Applied to specification**

Confirmed via CXDB source that turn IDs are per-context sequential counters with no cross-instance temporal relationship. Scoped the error heuristic per-context by moving it to a post-merge step (see Issue #3) where it examines each context's cached turns independently using `getMostRecentTurnsForNodeInContext`. The renamed helper explicitly scans a single context's turns, ordering by `turn_id` only within that context (where monotonic ordering is guaranteed). An error loop in any single context is sufficient to flag the node. This avoids the cross-instance interleaving problem described in the critique (e.g., CXDB-0 with high turn IDs from weeks of operation masking CXDB-1's recent error loop with low turn IDs).

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 — replaced `getMostRecentTurnsForNode` (cross-context) with `getMostRecentTurnsForNodeInContext` (single-context) in the new `applyErrorHeuristic` function
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 "Error loop detection heuristic" paragraph — rewritten to explain per-context scoping and why cross-instance turn ID comparison is invalid

## Issue #3: `turnCache` referenced in `updateContextStatusMap` but not in function signature

**Status: Applied to specification**

Adopted the critique's option (b): extracted the error heuristic entirely from `updateContextStatusMap` into a new `applyErrorHeuristic(mergedMap, dotNodeIds, turnCache, perContextCaches)` function that runs as a post-merge step. This resolves the missing parameter, eliminates per-context map contamination (the heuristic no longer writes into per-context maps based on other contexts' data), and naturally pairs with Issue #2's per-context scoping. Updated Section 6.1 step 6 to describe the three-phase pipeline: `updateContextStatusMap` → `mergeStatusMaps` → `applyErrorHeuristic`. Added a new "Error loop heuristic (post-merge)" paragraph with pseudocode and architectural rationale.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 pseudocode — removed heuristic loop from `updateContextStatusMap`
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 — added new `applyErrorHeuristic` function with per-context turn examination
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 — added "Error loop heuristic (post-merge)" explanatory paragraph
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 step 6 — updated to reference three-phase pipeline including `applyErrorHeuristic`

## Not Addressed (Out of Scope)

- None — all issues were addressed.
