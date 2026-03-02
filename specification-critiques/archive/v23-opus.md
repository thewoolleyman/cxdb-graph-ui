# CXDB Graph UI Spec — Critique v23 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v22 cycle had two critics (opus and codex). All 7 issues were applied: opus's 5 issues (bounded `fetchFirstTurn` pagination, context list ordering and truncation risk documented, context lineage optimization documented, `resetPipelineState` rationale corrected, holdout scenario scoping deferred). Codex's 2 issues (DOT regeneration refreshes cached metadata, server-side graph ID parsing matches browser algorithm). This critique is informed by reading the CXDB server source (`server/src/http/mod.rs`, `server/src/cql/`, `server/src/store.rs`, `server/src/events.rs`, `clients/go/`) to identify remaining gaps.

---

## Issue #1: CXDB has a CQL search endpoint with prefix matching (`^=`) that would solve the context discovery scalability problem — the spec does not mention it

### The problem

Section 5.2 documents that the `tag` query parameter on `GET /v1/contexts` uses exact match and notes this as a limitation: "a CXDB feature request for prefix-based `tag` filtering" would be needed. However, CXDB already has a CQL search endpoint at `GET /v1/contexts/search?q=...` (line 388 of `server/src/http/mod.rs`) that supports the `^=` (starts with) operator on the `tag` field:

```
GET /v1/contexts/search?q=tag ^= "kilroy/"
```

This returns only contexts whose `client_tag` starts with `"kilroy/"`, using secondary indexes for efficient server-side filtering (`server/src/cql/indexes.rs`). The search endpoint returns full context objects including `context_id`, `head_depth`, `head_turn_id`, `created_at_unix_ms`, `is_live`, and `client_tag` — all the fields the UI needs for discovery.

Using CQL search would eliminate two problems:
1. The `limit=10000` heuristic and its documented truncation risk (Section 5.2) — CQL returns all matching contexts regardless of total context count.
2. Client-side prefix filtering — the server handles it, reducing payload size and client complexity.

The spec already identifies the exact need ("prefix-based tag filtering") but treats it as a future feature request when it already exists.

### Suggestion

Replace the `GET /v1/contexts?limit=10000` approach in the discovery algorithm with `GET /v1/contexts/search?q=tag ^= "kilroy/"`. Update Section 5.2 to document the CQL search endpoint as the primary context discovery mechanism, falling back to the full context list only if the search endpoint is unavailable (404 — for older CXDB versions that lack CQL). Remove the "Truncation risk" paragraph (or downgrade it to a note about the fallback path). Update the `discoverPipelines` pseudocode in Section 5.5 to use the search endpoint, which eliminates Phase 1's client-side `client_tag` prefix filter since the server handles it. Note that the CQL search response has a slightly different shape (`total_count`, `elapsed_ms`, `query` fields alongside `contexts`) — document the relevant fields.

One caveat: the CQL search response (lines 417–449 of `server/src/http/mod.rs`) does not include `lineage` or `active_sessions` data. If the context lineage optimization (Section 5.5) is implemented in the future, the UI would need a separate context list request or individual context fetches for lineage data. Document this tradeoff.

---

## Issue #2: The spec's `fetchFirstTurn` backward pagination is unnecessary — CXDB's `ContextMetadataUpdated` SSE event and context metadata cache already extract and serve `client_tag` on the context list, and the `RunStarted` turn's data could be cached server-side

### The problem

The `fetchFirstTurn` pagination algorithm (Section 5.5) exists because the UI needs `graph_name` and `run_id` from the `RunStarted` turn. This is currently the most complex and expensive part of the discovery algorithm — up to 50 paginated requests per context.

However, examining the CXDB source reveals that the server already extracts and caches metadata from the first turn of every context (`store.rs`, lines 134–178, `load_context_metadata` and `get_context_metadata`). This metadata is extracted from the msgpack payload's key 30 (`context_metadata`), which includes `client_tag`, `title`, and `labels`. The `context_to_json` function (line 1305) serves this cached metadata on the context list response.

The key insight: CXDB's metadata extraction happens at the msgpack level, examining key 30 of the first turn's payload. If Kilroy were to include `graph_name` and `run_id` in the first turn's context metadata (key 30) — alongside the existing `client_tag` — CXDB would automatically extract and cache them, and they would appear in the context list response without any additional HTTP requests.

This is not a UI spec change per se, but the spec should document this as the recommended Kilroy integration pattern: embed `graph_name` and `run_id` in the context metadata (either as labels, title, or a future CXDB metadata field) to eliminate `fetchFirstTurn` entirely. Currently, the `RunStarted` turn carries `graph_name` and `run_id` in its type-specific payload fields, which are invisible to CXDB's metadata extraction layer.

### Suggestion

Add a note in Section 5.5 after the `fetchFirstTurn` algorithm documenting this potential optimization: if Kilroy embeds `graph_name` and `run_id` in the context metadata (key 30, e.g., as labels `["kilroy:graph=alpha_pipeline", "kilroy:run=01KJ7..."]`), the UI could read them directly from the context list response's `labels` field, eliminating all `fetchFirstTurn` pagination. This is a Kilroy-side change, not a CXDB change, but the spec should acknowledge it as the long-term path to simplifying discovery. Mark as "not required for initial implementation" — the pagination approach works correctly today.

---

## Issue #3: The spec does not account for CXDB's `ContextMetadataUpdated` event, which can change `client_tag` after context creation — potentially reclassifying a context mid-run

### The problem

Section 5.5 states: "The first turn of a context is immutable — once a context is successfully classified, it is never re-fetched." This is correct for the `RunStarted` turn data. However, the CXDB source (`events.rs`, lines 27–36) shows a `ContextMetadataUpdated` event that can update a context's `client_tag`, `title`, and `labels` after creation. The `maybe_cache_metadata` function (`store.rs`, line 161–178) only caches on the first append, but the metadata can also be updated via the `ContextMetadataUpdated` event path.

More importantly, the `context_to_json` function (`http/mod.rs`, line 1320–1324) resolves `client_tag` with a fallback chain: first from stored metadata (extracted from the first turn), then from the active session's tag. This means `client_tag` on a context list response can change depending on whether the session is active:

```rust
let client_tag = stored_metadata
    .as_ref()
    .and_then(|m| m.client_tag.clone())
    .or_else(|| session.as_ref().map(|s| s.client_tag.clone()))
    .filter(|t| !t.is_empty());
```

If a context is created by a session with tag `"kilroy/run-123"` but the first turn's payload has no context metadata (key 30 is absent — possible if the client does not embed it), the `client_tag` in the context list will be present only while the session is active (`is_live == true`). Once the session disconnects, `client_tag` becomes `null`. The UI's prefix filter (`client_tag.startsWith("kilroy/")`) would then fail to match, and the context would be classified as non-Kilroy and cached with `null` — permanently excluding it from discovery.

This is an edge case (Kilroy likely does embed context metadata), but the spec's claim that classification is permanent is based on the assumption that `client_tag` is stable. The spec should acknowledge this dependency.

### Suggestion

Add a note in Section 5.5's caching description that the `client_tag` prefix filter assumes `client_tag` is stable across polls — derived from the first turn's embedded context metadata rather than the session's tag. If `client_tag` comes from the session (because the first turn has no embedded metadata), it will disappear when the session disconnects. Document that Kilroy must embed `client_tag` in the first turn's context metadata (key 30) for reliable classification. This is likely already the case, but the spec should state the requirement explicitly rather than treating `client_tag` as an opaque stable field.

---

## Issue #4: The spec's `view=typed` default for turn fetches creates a hard dependency on the type registry — the CQL search endpoint and `view=raw` offer a more resilient discovery path

### The problem

Section 5.3 documents that `view=typed` (the default) requires every turn's `declared_type` to be registered in CXDB's type registry, and that a missing type causes the entire turn fetch to fail. The spec correctly handles this as a per-context error in Section 6.1 step 4. However, `fetchFirstTurn` (Section 5.5) also uses the default `view=typed` format, meaning pipeline discovery itself fails when the type registry is not yet published.

This creates a bootstrap ordering problem: the UI cannot discover pipelines until the registry bundle is published, but the registry bundle is typically published by the Kilroy runner at the start of the pipeline run. During the window between context creation and registry publication (which could be seconds or longer if the runner starts slowly), all `fetchFirstTurn` calls fail, and contexts are retried on subsequent polls. This is handled correctly (transient errors are not cached), but it means the UI shows no pipeline activity for potentially several poll cycles after a run starts.

The CXDB source reveals that `fetchFirstTurn` only needs `declared_type.type_id` and `data.graph_name`/`data.run_id` from the first turn. The `declared_type` field is available in both `view=typed` and `view=raw` responses (it comes from the turn metadata, not the registry). For the `data` fields, `view=raw` returns the raw msgpack payload (base64-encoded in `bytes_b64`), which the UI could decode client-side to extract `graph_name` and `run_id` without needing the type registry.

### Suggestion

Update the `fetchFirstTurn` algorithm to use `view=raw` instead of the default `view=typed`. This eliminates the type registry dependency for pipeline discovery. The UI would:
1. Check `declared_type.type_id` directly (present in both raw and typed responses).
2. If it matches `com.kilroy.attractor.RunStarted`, decode the `bytes_b64` field (base64-encoded msgpack) client-side to extract `graph_name` and `run_id`.

The msgpack decoding is straightforward: `RunStarted` has known field tags (documented in the Kilroy registry bundle). This avoids the bootstrap ordering problem and makes discovery more resilient. The regular turn polling (Section 6.1 step 4) should continue using `view=typed` for the status overlay, since those fields are more complex and benefit from server-side projection.

Alternatively, if client-side msgpack decoding is deemed too complex for the initial implementation, document the bootstrap ordering issue and the expected delay (1-3 poll cycles, 3-9 seconds) as a known behavior. Currently, the spec does not mention this delay.

---

## Issue #5: The `getMostRecentToolResultsForNodeInContext` helper scans cached turns, but the turn cache is replaced (not appended) on each poll — error loop detection can miss errors from previous poll cycles

### The problem

Section 6.1 step 5 states: "This cache is replaced (not appended) on each successful fetch." The `applyErrorHeuristic` (Section 6.2) calls `getMostRecentToolResultsForNodeInContext` which "scans a single context's cached turns" to find the 3 most recent `ToolResult` turns with `is_error: true`.

If the 3 error ToolResults span across two poll cycles — for example, 2 errors in the previous poll's 100-turn window and 1 error in the current poll's window — the replace-on-fetch cache means only the current window's turns are available. The heuristic would see only 1 error ToolResult and would not fire.

This is especially likely for nodes that generate errors slowly (one error every few minutes), where the 100-turn window advances past the older errors between polls. The error loop heuristic is designed to detect "agent stuck in error loop" scenarios, but a slow error loop (3 errors over several minutes) would not be caught because the turn cache window moves forward.

### Suggestion

The fix depends on the intended behavior:

1. **If the error heuristic should detect slow error loops:** Maintain a separate per-node, per-context error ToolResult buffer that accumulates across polls (up to the last N ToolResults, e.g., 10). This buffer is updated from the turn cache on each poll but is not cleared. The heuristic reads from this buffer instead of the raw turn cache.

2. **If the error heuristic is only intended for rapid error loops within a single 100-turn window:** Document this limitation explicitly. Add a note in Section 6.2 that the heuristic only detects errors visible in the current 100-turn fetch window, and that error loops where errors are spaced more than ~100 turns apart (across all turn types in the context) will not trigger the heuristic.

Option 2 is likely sufficient for the initial implementation — rapid error loops (where the agent retries the same failing command in quick succession) produce many ToolResult turns per poll window. But the limitation should be documented so implementers understand the detection scope.
