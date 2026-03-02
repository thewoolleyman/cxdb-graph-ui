# CXDB Graph UI Spec — Critique v25 (opus) Acknowledgement

All four issues from v25-opus have been applied to the specification. The changes document integer-tag-based msgpack field access for `decodeFirstTurn`, add a browser dependencies section with a pinned msgpack CDN URL, clarify the CQL search bootstrap lag, and connect the server-side SSE option to the metadata labels optimization as a fourth workaround.

## Issue #1: `decodeFirstTurn` pseudocode assumes named field access on raw msgpack payload — integer tags not documented

**Status: Applied to specification**

Updated the `decodeFirstTurn` pseudocode in Section 5.5 to use tag-based field access (`payload[TAG_GRAPH_NAME]`, `payload[TAG_RUN_ID]`) instead of named field access (`payload.graph_name`). Added detailed comments explaining: (a) raw msgpack payloads use integer tags as map keys, not field names, (b) Go's msgpack encoder produces string-encoded integer keys (e.g., `"1"` instead of `1`), (c) the browser-side decoder must handle both forms, and (d) the exact tag numbers are defined in the `kilroy-attractor-v1` registry bundle and must be verified by the implementer against the published bundle. The tag numbers are not hardcoded in the spec because they are owned by the Kilroy project and may vary across bundle versions.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Rewrote the `decodeFirstTurn` pseudocode's msgpack decoding section with tag-based access and explanatory comments.

## Issue #2: Msgpack CDN dependency not specified — conflicts with "no build toolchain" constraint

**Status: Applied to specification**

Added a new Section 4.1.1 "Browser Dependencies" that documents both CDN dependencies: `@hpcc-js/wasm-graphviz` (already documented, cross-referenced) and `@msgpack/msgpack` at a pinned CDN URL (`https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/mod.min.mjs`). Included usage context (only used by `decodeFirstTurn`, not during regular polling), the base64 decoding approach using browser-built-in `atob()` with a code example, and a note that no other CDN dependencies are required.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added Section 4.1.1 "Browser Dependencies" after Section 4.1 with pinned msgpack CDN URL, usage notes, and base64 decoding approach.

## Issue #3: CQL search may lag behind context list fallback during context bootstrap

**Status: Applied to specification**

Added a "CQL search bootstrap lag" note to Section 5.2, explaining that CQL secondary indexes are built from cached metadata (extracted from the first turn), so a newly created context may not appear in CQL results until its first turn is appended. The context list fallback resolves `client_tag` from the active session as well, so it discovers contexts earlier. Noted that the race window is typically sub-second and does not affect UI behavior.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "CQL search bootstrap lag" paragraph to Section 5.2 before the CQL advantages paragraph.

## Issue #4: SSE `ContextMetadataUpdated` event carries `labels` — connects to metadata labels optimization

**Status: Applied to specification**

Updated the "Metadata labels optimization" paragraph in Section 5.5 to add a fourth workaround option (d): the Go proxy server could subscribe to CXDB's SSE endpoint and collect `labels` from `ContextMetadataUpdated` events, serving them without per-context HTTP requests. Referenced the CXDB source (`events.rs`, `http/mod.rs`) as confirmation. Noted that this is the most efficient workaround but requires the server-side SSE infrastructure from non-goal #11.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated the metadata labels optimization paragraph in Section 5.5 to include the SSE-based workaround as option (d).

## Not Addressed (Out of Scope)

- None. All four issues were applied.
