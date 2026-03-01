# CXDB Graph UI Spec — Critique v28 (opus) Acknowledgement

All four issues from v28-opus have been applied to the specification. The changes document the `before_turn_id` context scoping behavior, clarify the CQL `total_count` pre-limit semantics, document the context list `tag` filter post-limit ordering, and add a blob-level failure scope note to Section 5.3. Each issue was verified against the CXDB server source (`server/src/turn_store/mod.rs`, `server/src/store.rs`, `server/src/http/mod.rs`).

## Issue #1: `get_before` does not scope `before_turn_id` traversal to the specified `context_id`

**Status: Applied to specification**

Added a "Context scoping note" to the `before_turn_id` parameter description in Section 5.3. The note documents that `context_id` only verifies context existence, that `before_turn_id` is resolved from the global turn table (line 539-542), and that parent chain walks cross context boundaries without checks. Ties this to `fetchFirstTurn`'s correct cross-context discovery for forked contexts and notes the UI's pagination is safe because it uses `next_before_turn_id` from the same response chain.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Expanded `before_turn_id` parameter description in Section 5.3 query parameter table with context scoping note.

## Issue #2: `total_count` in CQL search is pre-limit, not post-limit

**Status: Applied to specification**

Amended the CQL `limit` parameter description in Section 5.2 to clarify that `total_count` reflects matching contexts before truncation. References the specific CXDB source lines (`store.rs` lines 389-392). Notes that since the UI omits `limit`, `total_count == contexts.length` in normal operation.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Expanded CQL `limit` parameter description in Section 5.2 to clarify `total_count` semantics.

## Issue #3: Context list `tag` filter applies AFTER `limit` truncation

**Status: Applied to specification**

Added a caution note after the existing `tag` parameter mention in Section 5.2. Documents that `list_recent_contexts(limit)` runs first (line 221), then `tag_filter` is applied to the truncated result (lines 236-241). Explains the failure mode (matching contexts in the discarded tail are silently lost) and ties this to the existing rationale for preferring CQL search and client-side prefix filtering.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added post-limit `tag` filter caution note in Section 5.2 after the `tag` parameter description.

## Issue #4: Blob-level failure scope causes entire context turn fetch to fail

**Status: Applied to specification**

Added a "Blob-level failure scope" paragraph in Section 5.3 after the type registry dependency note. Documents that `blob_store.get(&record.payload_hash)?` uses error propagation with no per-turn skip (`store.rs` lines 268-274 for `get_last`, lines 295-301 for `get_before`). Explains that a single corrupted blob blocks the entire 100-turn window, the failure persists until the blob falls outside the window, and the per-context error handling mitigates this. Distinguishes this from the type registry miss failure mode.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "Blob-level failure scope" paragraph in Section 5.3 after the type registry dependency paragraph.

## Not Addressed (Out of Scope)

- None. All four issues were applied.
