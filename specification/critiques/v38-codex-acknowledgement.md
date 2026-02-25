# CXDB Graph UI Spec — Critique v38 (codex) Acknowledgement

All three issues from the v38 codex critique were evaluated and applied to the specification. Changes address consistency gaps in the `cachedContextLists` population, node pruning on DOT regeneration, and alignment between the error heuristic window and the holdout scenarios.

## Issue #1: CQL-empty supplemental discovery is not reflected in the cached context list, causing false "stale" classification

**Status: Applied to specification**

Section 6.1 step 1 was rewritten to specify that `cachedContextLists[i]` is populated from the **discovery-effective context list** — the CQL results when non-empty, the supplemental context list when CQL returns zero results, or the full context list when using the fallback. This ensures that when the supplemental fetch discovers Kilroy contexts via session-tag resolution, those contexts (with their `is_live` field) are stored in `cachedContextLists[i]` so that `lookupContext` and `checkPipelineLiveness` can find them. The failure mode (empty `cachedContextLists` causing false stale detection) is now explicitly prevented. A proposed holdout scenario was also written to verify this behavior.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Rewrote Section 6.1 step 1 to specify discovery-effective context list population for `cachedContextLists[i]`
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added proposed scenario for CQL-empty supplemental context list populating cachedContextLists

## Issue #2: Spec requires dropping removed DOT nodes, but the status-map algorithms never define the removal step

**Status: Applied to specification**

An explicit pruning step was added to the `updateContextStatusMap` pseudocode in Section 6.2. Before initializing entries for new node IDs, the algorithm now iterates over existing map keys and deletes any that are not present in `dotNodeIds`. This satisfies Section 4.4's requirement that "removed nodes are dropped from the maps" and prevents unbounded growth of per-context status maps when DOT files are regenerated with different node sets. The `mergeStatusMaps` function already iterates only over `dotNodeIds`, so pruned nodes are excluded from the merged display map as well.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added node pruning step to `updateContextStatusMap` pseudocode (Section 6.2)

## Issue #3: Error loop heuristic does not preserve cross-poll consecutive errors, contradicting the holdout scenario about interleaving

**Status: Applied to specification (Option A — holdout scenario clarification)**

The holdout scenario "Agent stuck in error loop (per-context scoping)" was amended to explicitly state that the three error ToolResults must be within the current 100-turn poll window. This aligns the scenario with the documented "Error heuristic window limitation" paragraph in Section 6.2, which clearly states that the turn cache is replaced on each poll cycle and only errors visible in the current window are detected. Option B (persisting error history across polls) was not adopted because the current design targets rapid error loops within a single poll window, and slow cross-poll error loops are better addressed by lifecycle turns (`StageFailed`) or operator observation.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added "within the current 100-turn poll window" precondition to the error loop holdout scenario

## Not Addressed (Out of Scope)

- None. All three issues were fully addressed.
