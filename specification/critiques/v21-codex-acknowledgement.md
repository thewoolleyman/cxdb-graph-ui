# CXDB Graph UI Spec — Critique v21 (codex) Acknowledgement

All three issues from v21-codex have been applied to the specification. Empty contexts are no longer permanently classified as non-Kilroy, node ID prefetching ensures status caching works for inactive pipelines, and the `/api/dots` response format inconsistency has been resolved.

## Issue #1: Empty contexts are permanently classified as non-Kilroy

**Status: Applied to specification**

Modified the discovery algorithm pseudocode in Section 5.5 to treat `firstTurn == null` (empty context) as an unknown state. When `fetchFirstTurn` returns `null`, the context is left unmapped (not cached as `null`) via `CONTINUE`, so discovery retries on subsequent polls until a turn appears or a non-RunStarted first turn is confirmed. Updated the caching paragraph and Invariant 10 to document that empty contexts are retried alongside transient errors.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added `ELSE IF firstTurn IS null` branch with `CONTINUE` in the `discoverPipelines` pseudocode in Section 5.5.
- `specification/cxdb-graph-ui-spec.md`: Updated the "Caching" paragraph in Section 5.5 to list empty contexts as a second unmapped/retried case.
- `specification/cxdb-graph-ui-spec.md`: Updated Invariant 10 to mention empty context retry behavior.

## Issue #2: Status caching for inactive pipelines lacks a defined node list source

**Status: Applied to specification**

Added a new initialization step 4 ("Prefetch node IDs for all pipelines") to Section 4.5 that fetches `GET /dots/{name}/nodes` for every pipeline listed by `/api/dots` before the poller starts. This ensures `dotNodeIds` is available for all pipelines from the first poll cycle, enabling `updateContextStatusMap` to run for inactive pipelines and satisfying the holdout scenario that expects cached status on tab switch with no gray flash.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added step 4 to the initialization sequence in Section 4.5 and renumbered subsequent steps.

## Issue #3: `/api/dots` response format is internally inconsistent

**Status: Applied to specification**

Resolved the contradiction by updating the prose to match the example. The description now reads "Returns a JSON object with a `dots` array containing the available DOT filenames" instead of "Returns a JSON array." The example response (an object with a `dots` field) was already the intended format.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated the `GET /api/dots` description in Section 3.2.

## Not Addressed (Out of Scope)

- None. All three issues were applied.
