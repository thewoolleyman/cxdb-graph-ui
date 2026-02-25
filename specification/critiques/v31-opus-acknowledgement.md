# CXDB Graph UI Spec — Critique v31 (opus) Acknowledgement

All four issues from v31-opus have been evaluated against the CXDB source code (`store.rs`, `turn_store/mod.rs`, `clients/go/types/conversation.go`). Three were applied directly to the specification. The fourth (forked-from-depth-0 holdout scenario) was deferred as a proposed holdout scenario.

## Issue #1: The spec's `decodeFirstTurn` pseudocode references a non-existent `useMaps` decoder option in `@msgpack/msgpack`

**Status: Applied to specification**

Removed the `{ useMaps: false }` option from the `msgpackDecode` call in `decodeFirstTurn`. Replaced the surrounding comments with an accurate description of the `@msgpack/msgpack` library's actual behavior: it always returns plain JavaScript objects for msgpack maps (never `Map` instances), integer keys are accepted by the default `mapKeyConverter` and coerced to string keys by JavaScript's object property semantics, and no special decoder configuration is needed. Retained the `|| fallback` for string-vs-integer keys as a defensive measure. Added a forward-looking note that if a different msgpack decoder is used in the future that returns `Map` objects, `Object.fromEntries` should be used. This aligns with the identical finding in v31-codex Issue #1.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated `decodeFirstTurn` pseudocode in Section 5.5 — removed `useMaps: false` option, replaced comments with accurate library behavior description

## Issue #2: The spec does not document the hot-path vs cold-path metadata extraction discrepancy for forked contexts

**Status: Applied to specification**

Added a "Metadata extraction asymmetry for forked contexts" paragraph in Section 5.5, immediately before the "Metadata labels optimization" paragraph. Documents the two CXDB code paths: (1) `maybe_cache_metadata` on append extracts from the first turn appended to the context (the child's first turn for forked contexts, at depth = base_depth + 1), and (2) `load_context_metadata` on cache miss walks the parent chain to depth=0, finding the parent's RunStarted turn for forked contexts. Confirmed against `store.rs` lines 151-178 and `conversation.go` line 165 ("By convention, only included in the first turn (depth=1) of a context"). Notes that both paths produce the same `client_tag` value since Kilroy uses the same `run_id` for parent and child contexts, but other metadata fields (`title`, `labels`) may differ.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "Metadata extraction asymmetry for forked contexts" paragraph in Section 5.5

## Issue #3: The spec does not document that `get_before` with a cross-context `before_turn_id` produces unpredictable results

**Status: Applied to specification**

Added a defensive programming note to the `before_turn_id` parameter description in Section 5.3. The note warns that because `before_turn_id` is resolved globally, callers must ensure the cursor originates from the same context's response chain. References the gap recovery pseudocode's per-`(cxdb_index, context_id)` `lastSeenTurnId` tracking as the correct pattern, and advises implementers to assert cursor-context correspondence.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added defensive note about cross-context `before_turn_id` hazard in Section 5.3

## Issue #4: The holdout scenarios do not cover the forked-from-depth-0 fast-path guard

**Status: Deferred — proposed holdout scenario written**

The suggested holdout scenario exercises the specific `fetchFirstTurn` fast-path edge case where a context forked from a depth-0 base turn has `headDepth == 0` but its newest turn is at depth > 0. This tests the depth guard added in v30 that prevents the fast-path from returning the wrong turn. Written to `holdout-scenarios/proposed-holdout-scenarios-to-review.md` for review before incorporation.

Changes:
- `holdout-scenarios/proposed-holdout-scenarios-to-review.md`: Added "Forked context with depth-0 base turn discovers RunStarted via pagination" proposed scenario

## Not Addressed (Out of Scope)

- None. All four issues were either applied or deferred with proposed holdout scenarios.
