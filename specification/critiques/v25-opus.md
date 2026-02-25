# CXDB Graph UI Spec — Critique v25 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v24 cycle had two critics (opus and codex). All 8 issues were applied: opus's 5 issues (CQL search response field enumeration with explicit absence list, CQL `limit` parameter documentation, CQL sort key documentation, CQL error response shape, narrowed SSE non-goal to browser-side). Codex's 3 issues (node ID normalization rules for `/nodes` and `/edges`, deterministic `/api/dots` ordering, DOT edge parsing scope definition). The spec is now very mature at 24 rounds. This critique focuses on remaining implementability gaps discovered by reading the CXDB source code, particularly around the `view=raw` msgpack decoding path and the CDN dependency chain.

---

## Issue #1: The `decodeFirstTurn` pseudocode assumes named field access (`payload.graph_name`, `payload.run_id`) on the raw msgpack payload, but `view=raw` returns integer-tagged msgpack maps — the spec does not document the `RunStarted` field tags needed for decoding

### The problem

Section 5.5's `decodeFirstTurn` function includes:

```
bytes = base64Decode(rawTurn.bytes_b64)
payload = msgpackDecode(bytes)
RETURN { ..., data: { graph_name: payload.graph_name, run_id: payload.run_id } }
```

This pseudocode uses named field access (`payload.graph_name`), but `view=raw` returns the raw msgpack payload with no projection through the type registry. CXDB type payloads use integer tags as map keys (see the `kilroy-attractor-v1` registry bundle format, where each field has a `tag` integer — e.g., `{"tag": 1, "name": "graph_name", "type": "string"}`). The CXDB projection module (`server/src/projection/mod.rs`) converts these integer tags to named fields when `view=typed`, but that conversion does not happen for `view=raw`.

Furthermore, Kilroy is written in Go, and Go's msgpack encoder produces **string-encoded integer keys** (e.g., the string `"1"` instead of the integer `1`). CXDB's `key_to_tag` function (`store.rs` line 747) handles both forms, but a browser-side msgpack decoder would see string keys like `"1"`, `"2"`, etc. — not `"graph_name"` or `"run_id"`.

An implementer following the pseudocode would decode the msgpack and attempt `payload.graph_name`, which would be `undefined`. They need to know:
1. The tag number for `graph_name` in the `RunStarted` type
2. The tag number for `run_id` in the `RunStarted` type
3. That Go-generated msgpack uses string-encoded integer keys (so they should look for key `"1"` or integer `1`, not `"graph_name"`)

### Suggestion

Add a note to Section 5.5's `decodeFirstTurn` explaining that the raw msgpack payload uses integer tags (not field names) as map keys, and that Go's msgpack encoder may produce string-encoded integers (e.g., `"1"` instead of `1`). Document the specific tag numbers for `RunStarted` fields needed by the UI: `graph_name` (tag N) and `run_id` (tag M). Update the pseudocode to use tag-based access:

```
payload = msgpackDecode(bytes)
RETURN { ..., data: { graph_name: payload[TAG_GRAPH_NAME], run_id: payload[TAG_RUN_ID] } }
```

If the tag numbers are not stable or depend on the registry bundle version, document this as a coupling risk and note that the implementer must verify against the published `kilroy-attractor-v1` bundle.

---

## Issue #2: The spec requires browser-side msgpack decoding for `view=raw` but does not specify a msgpack CDN dependency — this conflicts with the "no build toolchain" constraint and leaves an implementability gap

### The problem

Section 5.5 requires the browser to decode msgpack payloads from `view=raw` responses: "base64-decode to bytes, then msgpack-decode to extract the known `RunStarted` fields." Section 4.1 specifies the Graphviz WASM CDN dependency with a pinned URL. However, no corresponding CDN dependency is specified for msgpack decoding.

The spec's design principle (Section 1.2) states: "External dependencies are loaded from CDN." The Graphviz WASM library is the only CDN dependency explicitly documented (Section 4.1). A browser-side msgpack decoder is a second required CDN dependency that is not documented anywhere.

An implementer would need to:
1. Choose a msgpack library (e.g., `@msgpack/msgpack`, `msgpack-lite`)
2. Find a CDN URL that exposes it as an ES module (for use in `<script type="module">`)
3. Pin a version
4. Handle the base64-to-Uint8Array conversion (which requires either `atob` + manual byte array construction, or a base64 library)

None of this is specified, and different library choices produce different APIs (`msgpack.decode()` vs `decode()` import, etc.).

### Suggestion

Add a "Browser Dependencies" subsection (or expand Section 4.1 to cover all CDN dependencies) that lists:
1. `@hpcc-js/wasm-graphviz` at the pinned version (already documented)
2. A msgpack decoding library at a pinned CDN URL (e.g., `https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/mod.min.mjs` or `https://cdn.jsdelivr.net/npm/msgpack-lite@0.1.26/dist/msgpack.min.js`)

Include a brief note on the base64 decoding approach (the browser's built-in `atob()` + `Uint8Array` conversion is sufficient, no additional library needed).

---

## Issue #3: The CQL search endpoint resolves `client_tag` only from cached metadata, not from the active session — newly created contexts may appear in CQL results without a `client_tag` field during the window between context creation and first-turn metadata extraction

### The problem

The CXDB context list endpoint (`context_to_json`, `http/mod.rs` line 1320-1324) resolves `client_tag` with a fallback chain: first from stored metadata (extracted from the first turn's payload), then from the active session's tag. This means a context always has `client_tag` if its session is active, even before metadata is extracted.

The CQL search endpoint (`http/mod.rs` lines 433-445) resolves `client_tag` **only** from the cached metadata — there is no session-tag fallback. Additionally, the CQL secondary indexes (`cql/indexes.rs` lines 109-114) are built from `ContextMetadata.client_tag`, which is only populated after the first turn's payload is extracted. This creates a race condition:

1. Kilroy creates a context and opens a session with `client_tag = "kilroy/RUN_ID"`
2. The context exists (has a `context_id`) but no turns have been appended yet
3. CQL search `tag ^= "kilroy/"` will NOT match this context because the index entry doesn't exist yet
4. The context list fallback WOULD match (via the session-tag fallback), but CQL is the primary path

This race window is typically very short (milliseconds between context creation and first turn), so it may not matter in practice. However, it means CQL search and the context list fallback have subtly different discovery semantics during context bootstrap. The spec describes them as equivalent discovery mechanisms that differ only in efficiency.

### Suggestion

Add a note in Section 5.5 (or Section 5.2's CQL search description) acknowledging that CQL search may lag behind the context list fallback during context bootstrap. Specifically: CQL indexes are built from cached metadata (extracted from the first turn), so a newly created context may not appear in CQL results until its first turn is appended and metadata is extracted. The context list fallback resolves `client_tag` from the active session as well, so it can discover contexts earlier. This race window is typically sub-second and does not affect the UI's behavior (the context would be discovered on the next poll cycle after metadata extraction). No code change is needed — this is a documentation clarification.

---

## Issue #4: The `ContextMetadataUpdated` SSE event carries `labels` — the server-side SSE optimization note in non-goal #11 could leverage this to solve the metadata labels optimization gap described in Section 5.5 without per-context HTTP requests

### The problem

Non-goal #11 notes that the Go proxy server could optionally subscribe to CXDB's SSE endpoint to reduce discovery latency. Section 5.5's "Metadata labels optimization" paragraph notes that CQL search does not return `labels`, making the optimization "incompatible with the CQL-first discovery path without per-context requests or a CXDB enhancement."

However, reading the CXDB source (`events.rs` lines 27-36), the `ContextMetadataUpdated` SSE event carries `labels: Option<Vec<String>>`. If the Go server subscribes to SSE, it would receive `labels` for every context immediately after metadata extraction — without any per-context HTTP requests. The Go server could maintain an in-memory labels cache and expose it via a new endpoint (e.g., `GET /api/labels/{context_id}`) or augment the proxied context list response with cached labels.

This means the server-side SSE option documented in non-goal #11 is actually the fourth workaround for the metadata labels optimization gap — and it's the most elegant one because it avoids both the CQL limitation and per-context HTTP overhead. The current spec lists only three workarounds (context list fallback, per-context requests, CXDB enhancement) and doesn't connect the SSE note to the labels optimization.

### Suggestion

Update the "Metadata labels optimization" paragraph in Section 5.5 to add a fourth workaround option: if the Go server subscribes to CXDB's SSE endpoint (as described in non-goal #11), it can collect `labels` from `ContextMetadataUpdated` events and serve them without per-context HTTP requests. This connects two independently documented features and gives implementers a clearer picture of how they fit together. Still mark as not required for the initial implementation.
