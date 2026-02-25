# CXDB Graph UI Spec — Critique v21 (opus) Acknowledgement

All five issues from v21-opus have been applied to the specification. These were re-raises from unacknowledged v18/v19 critiques that remain valid. The unreachable dead code in `fetchFirstTurn` has been removed, the `/api/dots` response format contradiction resolved, context list caching added for unreachable CXDB instances, `hasLifecycleResolution` merge semantics changed from OR to AND, and a node-ID prefetch step added to initialization.

## Issue #1: `fetchFirstTurn` still has unreachable dead code — trailing `RETURN null` after unconditional return

**Status: Applied to specification**

Removed the unreachable `RETURN null` on what was line 503 of the spec. The function's control flow was already complete without it — every code path returns before reaching the trailing line.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Deleted trailing `RETURN null` from the `fetchFirstTurn` pseudocode in Section 5.5.

## Issue #2: `/api/dots` response format is still contradictory — prose says "array" but example shows an object

**Status: Applied to specification**

Changed the prose description from "Returns a JSON array of available DOT filenames" to "Returns a JSON object with a `dots` array containing the available DOT filenames." The example response (an object with a `dots` field) is the intended format and is now consistent with the prose. Also updated the initialization sequence step 2 to reference the object-with-`dots`-array format.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated the `GET /api/dots` description in Section 3.2.
- `specification/cxdb-graph-ui-spec.md`: Updated initialization step 2 in Section 4.5 to note the response format.

## Issue #3: `determineActiveRuns` and `checkPipelineLiveness` are undefined when a CXDB instance is unreachable

**Status: Applied to specification**

Updated Section 6.1 step 1 to specify that context lists are cached per instance on success (`cachedContextLists[i]`). When an instance is unreachable, the cached context list is used as the fallback for `lookupContext` calls in `determineActiveRuns` and `checkPipelineLiveness`. This preserves active-run determination and liveness signals through transient outages, preventing both false run-change resets and false stale detection.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Extended Section 6.1 step 1 to describe `cachedContextLists` caching and fallback behavior for unreachable instances.

## Issue #4: Merged `hasLifecycleResolution` flag suppresses error and stale heuristics in parallel branches

**Status: Applied to specification**

Changed the `mergeStatusMaps` function to use AND semantics for `hasLifecycleResolution` instead of OR. The merged map now sets `hasLifecycleResolution = true` only when ALL contexts that have processed turns for a node (i.e., have progressed beyond "pending") have lifecycle resolution. Contexts still at "pending" for the node are excluded from the AND to avoid false negatives when a node has not yet been encountered in all branches. Updated the prose description to explain the new semantics and rationale.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Rewrote the `hasLifecycleResolution` propagation logic in `mergeStatusMaps` pseudocode in Section 6.2.
- `specification/cxdb-graph-ui-spec.md`: Updated the explanatory paragraph after `mergeStatusMaps` to describe AND semantics.

## Issue #5: Poller updates inactive pipelines but the spec never requires loading their node IDs

**Status: Applied to specification**

Added a new initialization step 4 ("Prefetch node IDs for all pipelines") that fetches `GET /dots/{name}/nodes` for every pipeline listed by `/api/dots` before polling starts. This ensures `dotNodeIds` is available for all pipelines from the first poll cycle, enabling `updateContextStatusMap` to compute per-context status maps for inactive pipelines. Renumbered subsequent steps and updated the dependency description.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added step 4 to the initialization sequence in Section 4.5 and renumbered steps 5–6.
- `specification/cxdb-graph-ui-spec.md`: Updated the step dependency description.

## Not Addressed (Out of Scope)

- None. All five issues were applied.
