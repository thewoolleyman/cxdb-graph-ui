# CXDB Graph UI Spec — Critique v26 (opus) Acknowledgement

All four issues from v26-opus have been applied to the specification. The changes hardcode concrete RunStarted tag numbers from the verified registry bundle, remove the phantom `graph_dot` field from the turn type table, add a null/empty `graph_name` guard in the discovery pseudocode, and document the cross-context parent chain traversal behavior of `fetchFirstTurn`.

## Issue #1: Document exact RunStarted tag numbers instead of "MUST verify" hedge

**Status: Applied to specification**

Replaced the "MUST verify" block in the `decodeFirstTurn` pseudocode with concrete tag numbers verified against the published `kilroy-attractor-v1` bundle (`bundle_kilroy-attractor-v1_004673dd423a.json`): tag 1 = `run_id`, tag 8 = `graph_name`. Added a note that these tags are stable within bundle version 1 per CXDB's type registry versioning model (existing tags are never reassigned). Listed the full RunStarted v1 field inventory (tags 1-11) for reference, noting only tags 1 and 8 are used by the UI. Updated the return statement to use concrete `payload["8"] || payload[8]` and `payload["1"] || payload[1]` syntax with the `||` fallback for string-vs-integer key handling.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Rewrote the `decodeFirstTurn` tag comment block and return statement in Section 5.5 with concrete tag numbers and full field inventory.

## Issue #2: Remove phantom `graph_dot` from RunStarted key data fields

**Status: Applied to specification**

Removed `graph_dot` from the `RunStarted` row in Section 5.4's turn type table. The field is not in the `kilroy-attractor-v1` registry bundle and is silently dropped during msgpack encoding by Kilroy's `EncodeTurnPayload`, so it never reaches CXDB. The key data fields for `RunStarted` are now `graph_name`, `run_id` — matching the two fields actually present in turn data and used by the UI.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 5.4 `RunStarted` row to remove `graph_dot`.

## Issue #3: Guard against null or empty `graph_name` in discovery

**Status: Applied to specification**

Added a guard in the `discoverPipelines` pseudocode after extracting `graphName` from the `RunStarted` turn. If `graphName` is null or empty string, the context is cached as a null mapping (same as a non-Kilroy context) rather than being cached with a non-matchable graph name. This follows the critique's option (a) recommendation since the first turn is immutable — retrying would not help. Added a comment explaining the rationale (registry marks `graph_name` as optional).

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added null/empty `graph_name` guard with comment in the `discoverPipelines` pseudocode in Section 5.5.

## Issue #4: Document cross-context traversal behavior of `fetchFirstTurn`

**Status: Applied to specification**

Added a "Cross-context traversal for forked contexts" paragraph after the `fetchFirstTurn` pseudocode and before the "Pagination cost" paragraph. The note explains: (1) `get_before` walks `parent_turn_id` links without context boundary checks (confirmed in CXDB's `turn_store/mod.rs`), (2) for forked contexts the depth-0 turn discovered is from the parent context, (3) this is correct because Kilroy's parallel branch contexts share the parent's `RunStarted` via the linked parent chain, and (4) future Kilroy versions emitting per-child `RunStarted` would still work correctly.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "Cross-context traversal for forked contexts" paragraph in Section 5.5 after the `fetchFirstTurn` pseudocode block.

## Not Addressed (Out of Scope)

- None. All four issues were applied.
