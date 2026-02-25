# CXDB Graph UI Spec — Critique v27 (opus) Acknowledgement

All four issues from v27-opus have been applied to the specification. The changes document the `client_tag` resolution asymmetry between CQL search and context list endpoints, add the `bytes_render` query parameter to Section 5.3, clarify the `before_turn_id=0` sentinel behavior with CXDB source references, and propose a holdout scenario for the CQL-to-fallback transition.

## Issue #1: CQL vs context list `client_tag` resolution asymmetry

**Status: Applied to specification**

Added a "`client_tag` resolution asymmetry" paragraph after the CQL search response field list in Section 5.2. The note explicitly documents that CQL search resolves `client_tag` from cached metadata only (`context_metadata_cache`), while the context list fallback has a session-tag fallback (`context_to_json` line 1323). References the specific CXDB source location. Ties the asymmetry to the existing bootstrap lag note so implementers understand when and why `client_tag` may be absent in CQL results for newly created contexts.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added `client_tag` resolution asymmetry paragraph in Section 5.2 after the CQL search response field list.

## Issue #2: `bytes_render` query parameter undocumented

**Status: Applied to specification**

Added `bytes_render` to Section 5.3's query parameter table with its three modes (`base64`/`hex`/`len_only`), the corresponding response field names (`bytes_b64`/`bytes_hex`/`bytes_len`), and a note that the UI uses the default. Also added a comment in the `decodeFirstTurn` pseudocode explaining that `bytes_b64` is present only because `bytes_render` is omitted (defaulting to `base64`).

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added `bytes_render` row to Section 5.3 query parameter table; added comment in `decodeFirstTurn` pseudocode.

## Issue #3: `before_turn_id=0` sentinel behavior undocumented

**Status: Applied to specification**

Expanded the `before_turn_id` row in Section 5.3's query parameter table to document that `0` and omitting the parameter are equivalent — both delegate to CXDB's `get_last(context_id, limit)` internally. Referenced the specific CXDB source location (`turn_store/mod.rs` line 535-536). Noted that both code paths produce the same oldest-first ordering via `results.reverse()`. Tied this to the `fetchFirstTurn` pseudocode's `cursor = 0` sentinel convention.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Expanded `before_turn_id` description in Section 5.3 query parameter table.

## Issue #4: CQL-to-fallback transition holdout scenario

**Status: Deferred — proposed holdout scenario written**

The critique correctly identifies that the CQL-to-fallback transition during continuous operation (instance remains reachable but loses CQL support after a fast restart) is not covered by existing holdout scenarios. The code path is already fully specified in the `discoverPipelines` pseudocode. A proposed holdout scenario has been written to `holdout-scenarios/proposed-holdout-scenarios-to-review.md` for review before incorporation.

Changes:
- `holdout-scenarios/proposed-holdout-scenarios-to-review.md`: Added proposed scenario for CXDB CQL-to-fallback transition.

## Not Addressed (Out of Scope)

- None. All four issues were addressed (three applied to spec, one deferred as proposed holdout scenario).
