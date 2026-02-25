# CXDB Graph UI Spec — Critique v30 (opus) Acknowledgement

All four issues from v30-opus have been evaluated against the CXDB source code (`turn_store/mod.rs`, `http/mod.rs`, `store.rs`). Three were applied directly to the specification. The fourth (CQL support flag reset holdout scenario) was deferred as a proposed holdout scenario.

## Issue #1: The `fetchFirstTurn` algorithm assumes `headDepth == 0` implies a non-forked context with at most one turn, but forked contexts created from a depth-0 base turn also have `headDepth == 0`

**Status: Applied to specification**

Updated the `fetchFirstTurn` fast-path in Section 5.5 to add a depth verification guard. The fast-path now checks whether the returned turn has `depth == 0` after fetching with `limit=1`. If the turn's depth is not 0 (which happens when a context was forked from a depth-0 base turn and has accumulated its own turns), the algorithm falls through to the general pagination loop instead of returning the wrong turn. Updated the comment to explain the forked-from-depth-0 scenario, referencing `turn_store/mod.rs` line 336-344 where `head_depth` is set to the base turn's depth. This was confirmed against the CXDB source: `create_context(base_turn_id)` with a turn at depth 0 produces a context with `head_depth == 0` that can later have turns at depth 1+.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated `fetchFirstTurn` fast-path in Section 5.5 to add `depth == 0` guard and fall-through to pagination loop

## Issue #2: The spec does not document that `context_to_json` filters out empty `client_tag` strings, which affects the context list fallback path's prefix filter

**Status: Applied to specification**

Added documentation in Section 5.2 after the `client_tag` field description. Notes that `context_to_json` filters empty-string `client_tag` values via `.filter(|t| !t.is_empty())` (line 1324), converting them to `None`/absent. Documents the asymmetry with the CQL search endpoint, which reads directly from cached metadata (line 439) without the empty-string filter. Notes that `extract_context_metadata` (line 634) stores whatever the msgpack payload contains, so an empty-string `client_tag` could theoretically appear in CQL results. Clarifies that in practice Kilroy always sets a non-empty `client_tag`, so the asymmetry has no functional impact, and the UI's prefix filter need not check for empty strings.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Extended `client_tag` field description in Section 5.2 with empty-string filtering documentation and endpoint asymmetry note

## Issue #3: The spec's `determineActiveRuns` algorithm uses `created_at_unix_ms` to pick the active run, but does not document the edge case where two runs of the same pipeline start in the same millisecond

**Status: Applied to specification**

Updated the `determineActiveRuns` pseudocode in Section 6.1 to add a tie-breaking clause using `context_id`. When two runs have the same `maxCreatedAt`, the run whose contexts include the highest `context_id` (parsed as integer) is selected. Context IDs are allocated monotonically from a global counter (`turn_store/mod.rs` line 347-348: `context_id = self.next_context_id; self.next_context_id += 1`), so a higher context ID is guaranteed to be newer. Added a `highestContextId` tracking variable and a compound comparison condition. This makes active run selection fully deterministic even if two runs start in the same millisecond.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated `determineActiveRuns` pseudocode in Section 6.1 with `context_id` tie-breaking

## Issue #4: The holdout scenarios do not cover the `cqlSupported` flag reset on reconnection

**Status: Applied to holdout scenarios**

The suggested holdout scenario exercises a specific flag lifecycle (unreachable -> reconnect -> CQL retry) that is documented in the spec (Section 5.5) but not covered by existing holdout scenarios. The proposed scenario has been written to `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` for review before incorporation. This complements the existing v27-opus proposed scenario (CQL-supported to unsupported transition) by covering the opposite direction (non-CQL to CQL upgrade).

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added "CQL support flag resets on CXDB instance reconnection" proposed scenario

## Not Addressed (Out of Scope)

- None. All four issues were either applied or deferred with proposed holdout scenarios.
