# CXDB Graph UI Spec — Critique v2 (opus) Acknowledgement

All 5 issues were evaluated and applied to the specification. The polling algorithm now caches per-context status maps for CXDB failure resilience, uses `setTimeout` to prevent overlapping polls, and the `mergeStatusMaps` function ties `lastTurnId` to the winning status context. Tab switching reapplies cached status maps. The discovery algorithm caches negative results.

## Issue #1: Status preservation on CXDB failure contradicts the polling algorithm

**Status: Applied to specification**

Added explicit status caching behavior to Section 6.1. When a CXDB instance is unreachable, its per-context status maps from the last successful poll are retained and included in the merge. Added a "Status caching on failure" paragraph explaining the behavior. Updated polling step 1 to specify that unreachable instances are skipped with cached maps retained, and step 4 to include cached maps in the merge.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 polling steps 1 and 4 updated, new "Status caching on failure" paragraph added

## Issue #2: No guard against overlapping poll cycles

**Status: Applied to specification**

Changed from `setInterval` to `setTimeout` throughout. Added a "Poll scheduling" paragraph to Section 6.1 specifying that the next poll is scheduled 3 seconds after the previous poll completes, ensuring at most one poll cycle is in flight at any time. Updated Section 4.5 initialization sequence to reference `setTimeout`. Updated Invariant #7 to reflect the `setTimeout` semantics.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 new "Poll scheduling" paragraph, Section 4.5 step 5 updated, Invariant #7 updated

## Issue #3: `lastTurnId` in `mergeStatusMaps` is non-deterministic

**Status: Applied to specification**

Changed `mergeStatusMaps` to update `lastTurnId` alongside `status` and `toolName` when a higher-precedence status is found. The merged `lastTurnId` now always comes from the same context that provided the winning status, making the merged `NodeStatus` semantically coherent.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 `mergeStatusMaps` pseudocode updated — `lastTurnId` moved inside the precedence check block

## Issue #4: Tab switch clears status overlay unnecessarily

**Status: Applied to specification**

Changed Section 4.4 tab switch behavior: instead of clearing the CXDB status overlay, the UI immediately reapplies any cached status map for the newly selected pipeline. Nodes only start as pending if no cached status exists (first time viewing that tab). Updated the holdout scenario to verify no gray flash between tab switch and next poll.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 4.4 tab switch behavior rewritten
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: "Switch between pipeline tabs" scenario updated

## Issue #5: Discovery algorithm fetches first turn for every non-RunStarted context on every discovery pass

**Status: Applied to specification**

Updated the discovery algorithm pseudocode in Section 5.5 to cache negative results. When a context's first turn is not `RunStarted`, it is stored as `null` in `knownMappings`. The `CONTINUE` comment was updated to clarify it covers both positive and negative cached results. Updated the caching description paragraph to explain negative caching and its purpose.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 5.5 discovery algorithm pseudocode updated with `ELSE` branch for negative caching, caching paragraph expanded

## Not Addressed (Out of Scope)

- None. All issues were addressed.
