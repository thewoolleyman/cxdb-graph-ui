# CXDB Graph UI Spec — Critique v16 (opus) Acknowledgement

All 3 issues were valid and applied to the specification. Issue #1 removed a stale 65535 cap reference left over from the v15 revision. Issue #2 removed the vestigial `turnCache` parameter from `applyErrorHeuristic` and updated the surrounding prose. Issue #3 replaced the ambiguous `head_turn_id` ordering with node-specific `turn_id` ordering for detail panel context sections.

## Issue #1: Section 5.5 prose still references "capped at the CXDB maximum of 65,535"

**Status: Applied to specification**

The prose paragraph before the `fetchFirstTurn` pseudocode was a leftover from the pre-v15 text. Updated to match the corrected pseudocode: "the algorithm requests `headDepth + 1` turns to fetch the entire context in a single request."

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 5.5 — replaced "requests up to `headDepth + 1` turns (capped at the CXDB maximum of 65,535) to fetch the entire context in as few requests as possible" with "requests `headDepth + 1` turns to fetch the entire context in a single request"

## Issue #2: `applyErrorHeuristic` function signature includes unused `turnCache` parameter

**Status: Applied to specification**

Removed the vestigial `turnCache` parameter from the function signature. Updated the prose paragraph to remove the explanation of the old parameter (reason (a) in the three-problem list), reducing it to a two-problem list. Updated the step 6 call description from "using the per-pipeline turn cache" to "using the per-context turn caches for the active pipeline" to match the actual parameter name `perContextCaches`.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 — removed `turnCache` from `applyErrorHeuristic` signature, updated prose from three-problem to two-problem explanation
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 step 6 — updated call description to reference "per-context turn caches"

## Issue #3: Detail panel context-section ordering criterion is ambiguous

**Status: Applied to specification**

Replaced the ambiguous sentence conflating context-level `head_turn_id` with node-level filtering. The new text specifies node-specific recency: compute the highest `turn_id` among each context's turns for the selected node, and order context sections by that value. Added explicit note that this uses intra-context `turn_id` ordering (safe within a single context's parent chain). The existing text already states that cross-instance sections are not interleaved by `turn_id`, which remains unchanged.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 7.2 — replaced `head_turn_id` ordering sentence with node-specific `turn_id` ordering

## Not Addressed (Out of Scope)

- None. All issues were addressed.
