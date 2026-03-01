# CXDB Graph UI Spec — Critique v19 (opus) Acknowledgement

Two of three issues were addressed in the v21 revision cycle; the third (gap recovery pagination limit) has been applied now. The `hasLifecycleResolution` merge semantics were fixed in v21, `determineActiveRuns` unreachable-instance handling was fixed in v21, and gap recovery now has a bounded page count.

## Issue #1: Merged `hasLifecycleResolution` flag suppresses error and stale heuristics for nodes active in parallel branches

**Status: Applied to specification (in v21 cycle)**

This was addressed during the v21 revision cycle (see v21-opus-acknowledgement.md, Issue #4). The `mergeStatusMaps` function was changed from OR to AND semantics for `hasLifecycleResolution`: the merged map now sets it to `true` only when ALL contexts that have processed turns for the node have lifecycle resolution. Contexts still at "pending" for the node are excluded from the AND.

Changes:
- `specification/cxdb-graph-ui-spec.md`: `hasLifecycleResolution` merge logic changed to AND semantics in Section 6.2 (applied in v21 cycle).

## Issue #2: Gap recovery pagination has no iteration limit — a long outage can block the poller indefinitely

**Status: Applied to specification**

Added a `MAX_GAP_PAGES = 10` constant to the gap recovery pseudocode in Section 6.1. The `WHILE` loop now includes a `pagesFetched < MAX_GAP_PAGES` guard. If the limit is hit before reaching `lastSeenTurnId`, the cursor is advanced to the oldest recovered turn (accepting that intermediate turns beyond the 1,000-turn window are lost). Added rationale explaining the tradeoff: bounded recovery time (at most 10 sequential HTTP requests per context) vs. potential loss of intermediate turns, which is safe because statuses are never demoted and the next poll's 100-turn window contains the most recent state.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added `MAX_GAP_PAGES` constant, `pagesFetched` counter, and cursor advancement logic to gap recovery pseudocode in Section 6.1.
- `specification/cxdb-graph-ui-spec.md`: Updated the explanatory paragraph after the pseudocode to describe the 10-page bound and tradeoff.

## Issue #3: `determineActiveRuns` fails when a previously-discovered context is absent from the current poll's context list

**Status: Applied to specification (in v21 cycle)**

This was addressed during the v21 revision cycle (see v21-opus-acknowledgement.md, Issue #3). Section 6.1 step 1 now caches context lists per instance on success (`cachedContextLists[i]`), and unreachable instances fall back to the cached context list for `lookupContext` calls. This preserves active-run determination and liveness signals through transient outages.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added `cachedContextLists` caching and fallback behavior in Section 6.1 step 1 (applied in v21 cycle).

## Not Addressed (Out of Scope)

- The suggestion to add a holdout scenario for the parallel branch error loop case was not added. Holdout scenarios are maintained separately and are outside the scope of spec revisions.
