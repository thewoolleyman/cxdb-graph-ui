# CXDB Graph UI Spec — Critique v7 (opus) Acknowledgement

All 3 issues were valid and applied to the specification. Issue #1 was a correctness bug — string comparison on turn IDs breaks for IDs of different lengths. Issue #2 identified a missing data flow — raw turns were consumed by the status algorithm but never retained for the detail panel. Issue #3 resolved an ambiguity about whether inactive pipelines are polled.

## Issue #1: turn_id comparison uses string ordering, breaking deduplication

**Status: Applied to specification**

Added a "Turn ID comparison" paragraph to Section 6.2, immediately before the status derivation algorithm. The paragraph specifies that all turn ID comparisons must use `parseInt(turn.turn_id, 10)` for numeric ordering, and that the `<=` operator in the pseudocode denotes numeric comparison. Also updated Section 7.2's turn sorting description to reference numeric comparison.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 — added "Turn ID comparison" paragraph before "Status derivation algorithm"
- `specification/cxdb-graph-ui-spec.md`: Section 7.2 — added "(using numeric comparison — see Section 6.2)" to turn sorting description

## Issue #2: Raw turn data for the detail panel is never stored

**Status: Applied to specification**

Added an explicit "Cache raw turns" step (step 4) to the Section 6.1 polling algorithm. The step specifies a per-pipeline turn cache keyed by `(cxdb_index, context_id)`, replaced on each successful fetch, retained on failure. Updated Section 7.2 to reference this cache as the data source instead of the vague "most recent poll data" phrasing.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 — inserted step 4 "Cache raw turns" between turn fetching and status map update; renumbered subsequent steps
- `specification/cxdb-graph-ui-spec.md`: Section 7.2 — changed turn data source from "most recent poll data (the 100 turns fetched per context in Section 6.1)" to "per-pipeline turn cache (Section 6.1, step 4)"

## Issue #3: Per-pipeline status map caching on tab switch is ambiguous

**Status: Applied to specification**

Clarified that the poll cycle fetches turns for all pipelines (not just the active tab). Section 6.1 step 3 now reads "any loaded pipeline" instead of "the active pipeline" and includes an explanatory note. Step 5 clarifies that `mergeStatusMaps` runs for the active pipeline only, while per-context maps for inactive pipelines are still updated. Step 6 specifies CSS application is for the active pipeline. This resolves the ambiguity: all pipelines are polled, so cached status maps are always current on tab switch.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 step 3 — changed "active pipeline" to "any loaded pipeline"; added explanatory note
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 step 5 — clarified merge runs for active pipeline; inactive pipelines' per-context maps are updated but merge is deferred
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 step 6 — specified "for the active pipeline"
