# CXDB Graph UI Spec — Critique v28 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v27 cycle had two critics (opus and codex). All 7 issues were applied: opus's 4 issues (CQL vs context list `client_tag` resolution asymmetry, `bytes_render` query parameter documentation, `before_turn_id=0` sentinel behavior, CQL-to-fallback holdout scenario). Codex's 3 issues (graph ID extraction for `strict`/anonymous graphs, whitespace preservation with `white-space: pre-wrap`, deterministic truncation/expansion policy). This critique is informed by a detailed read of the CXDB server source (`server/src/http/mod.rs`, `server/src/store.rs`, `server/src/turn_store/mod.rs`, `server/src/cql/executor.rs`, `server/src/cql/indexes.rs`) to verify the spec's claims against actual implementation behavior.

---

## Issue #1: The `get_before` function does not scope turn traversal to the specified `context_id` — `before_turn_id` is resolved from the global turn table, and the parent chain walk can silently cross context boundaries even when the turns do not belong to the specified context

### The problem

Section 5.3 describes `before_turn_id` as a "pagination cursor" that returns "turns older than that ID (walking backward via `parent_turn_id`)." The spec implicitly assumes that the pagination is scoped to the specified context. However, the CXDB implementation (`turn_store/mod.rs` lines 524-556) reveals a subtle behavior:

1. The `context_id` parameter is used **only** to verify the context exists (head lookup at line 530-533) and to handle the `before_turn_id == 0` fallback (line 535-536).
2. The `before_turn_id` is resolved from the **global** `turns` HashMap (line 539-542: `self.turns.get(&before_turn_id)`), not from a per-context index.
3. The subsequent parent chain walk (`current = before.parent_turn_id`) follows `parent_turn_id` links without any context boundary check.

This means: if an implementer passes a `before_turn_id` that belongs to a different context (e.g., due to a bug where turn IDs from one context are accidentally used as cursors for another), CXDB will silently return turns from the wrong context. No error is raised.

For the UI's normal operation, this is not a problem — the UI uses `next_before_turn_id` from the previous response, which always belongs to the same context's parent chain. However:

- During integration testing, using a turn ID from context A as a cursor for context B would produce confusing results with no error signal.
- The `fetchFirstTurn` pagination for forked contexts intentionally traverses across context boundaries (documented in Section 5.5's "Cross-context traversal" note). This works correctly because forked contexts' parent chains extend into the parent context by design. But the spec should explicitly note that CXDB's turn API does **not** enforce context-scoped pagination — the context_id parameter is a soft guard, not a filter.

### Suggestion

Add a brief note to Section 5.3 after the `before_turn_id` parameter description:

> **Context scoping note.** The `context_id` parameter verifies the context exists but does not scope the `before_turn_id` traversal. CXDB resolves `before_turn_id` from a global turn table and walks `parent_turn_id` links without context boundary checks. This is why `fetchFirstTurn` (Section 5.5) correctly discovers the parent context's `RunStarted` turn for forked contexts — the parent chain naturally crosses context boundaries. The UI's pagination is safe because it uses `next_before_turn_id` from the same context's response chain.

---

## Issue #2: The `total_count` field in CQL search responses is the pre-limit count (total matching contexts), not the post-limit count (truncated contexts returned) — the spec does not clarify this distinction

### The problem

Section 5.2 documents the CQL search response as:

```json
{
  "contexts": [ ... ],
  "total_count": 5,
  "elapsed_ms": 2,
  "query": "tag ^= \"kilroy/\""
}
```

The spec states: "When present, matching contexts are sorted by `context_id` descending and truncated to the specified count." But it does not clarify that `total_count` reflects the number of matching contexts **before** the `limit` is applied. In the CXDB source (`store.rs` lines 386-392):

```rust
let total_count = sorted_ids.len();  // pre-limit
if let Some(limit) = limit {
    sorted_ids.truncate(limit as usize);  // post-limit
}
```

So when `limit=5` and 20 contexts match, the response has `contexts.length == 5` but `total_count == 20`.

The UI omits the `limit` parameter, so `total_count` always equals `contexts.length` in practice. However, the spec explicitly documents the `limit` parameter's behavior and its interaction with `total_count` should be precise. An implementer who uses `total_count` for loop bounds (instead of `contexts.length`) would iterate correctly in the no-limit case but could over-index in the limited case.

### Suggestion

Amend the CQL search `limit` description to clarify:

> When present, matching contexts are sorted by `context_id` descending and truncated to the specified count. The response's `total_count` field reflects the number of matching contexts **before** truncation — it may be larger than `contexts.length` when a `limit` is applied. The UI omits `limit` to retrieve all Kilroy contexts, so `total_count == contexts.length` in normal operation.

---

## Issue #3: The context list fallback endpoint applies the `limit` parameter BEFORE the `tag` query parameter filter — the spec does not document this ordering, which means `tag` filtering can return fewer results than `limit` even when more matching contexts exist

### The problem

Section 5.2 mentions the context list endpoint's `tag` parameter for server-side filtering: "The UI does not use server-side tag filtering because the `run_id` portion of the Kilroy tag varies." The spec also mentions `limit=10000` for the fallback path.

However, the CXDB source (`http/mod.rs` lines 220-245) reveals that `list_recent_contexts(limit)` is called first (truncating to `limit` contexts), and THEN the `tag_filter` is applied to the truncated result:

```rust
let contexts = store.list_recent_contexts(limit);  // limit applied here
let contexts_json: Vec<JsonValue> = contexts
    .iter()
    .filter_map(|c| {
        // tag_filter applied here, AFTER truncation
        if let Some(ref filter) = tag_filter {
            if tag != filter { return None; }
        }
        Some(obj)
    })
    .collect();
```

This means if an instance has 15,000 contexts and a `limit=10000` is passed with `tag=kilroy/some-run-id`, the response could return 0 results even though matching contexts exist — they were truncated out before filtering. Contexts are ordered newest-first, so oldest matching contexts are most likely to be lost.

The UI does not use `tag` filtering, so this is not a correctness issue for the current implementation. But the spec documents the `tag` parameter's existence and should note this ordering limitation. An implementer reading the spec might consider using `tag` filtering as an optimization without realizing it's fundamentally broken for the "find all matching contexts" use case.

### Suggestion

Add a note after the `tag` parameter mention in Section 5.2:

> **Caution:** The `tag` query parameter filters AFTER the `limit` truncation. If 15,000 contexts exist and `limit=10000`, the oldest 5,000 are discarded before `tag` filtering runs. Matching contexts in the discarded tail are silently lost. This is why the UI uses client-side prefix filtering rather than server-side `tag` filtering — and why the CQL `^=` operator (which filters before response construction) is the preferred discovery path.

---

## Issue #4: A single corrupted or missing blob in the turn store causes the entire context's turn fetch to fail — the spec documents per-context error handling but does not explain this blast radius from CXDB's all-or-nothing payload loading

### The problem

Section 6.1 step 4 says: "If a per-context turn fetch returns a non-200 response... skip that context for this poll cycle: retain its cached turns and per-context status map from the last successful fetch." This is correct and sufficient for the UI's resilience. However, the spec does not document the underlying CXDB behavior that makes per-context failures likely in a specific scenario.

The CXDB HTTP handler (`http/mod.rs` line 797-801) calls `store.get_last(context_id, limit, true)` or `store.get_before(context_id, before_turn_id, limit, true)` with `include_payload=true`. The Store wrapper (`store.rs` line 272-274) loads every turn's payload from the blob store:

```rust
let payload = if include_payload {
    Some(self.blob_store.get(&record.payload_hash)?)  // ? propagates errors
};
```

If ANY single payload blob in the 100-turn window is corrupted or missing, the entire request fails. The error propagates through `?` to the HTTP handler, which returns a 500 (via `StoreError::Io` or `StoreError::NotFound`). This means:

1. A corrupted blob at depth 900 prevents fetching turns at depths 901-1000 (the most recent activity).
2. The failure persists across poll cycles — the same corrupted blob blocks the same context every time.
3. The 100-turn window slides with new turns, so the failure eventually resolves when the corrupted blob falls outside the window. But for slow-moving contexts, this could take hours.

The UI handles this correctly (per-context skip with cached status), but an implementer debugging "context X stopped updating" should understand that the root cause might be a single corrupted blob, not an API-level issue. The spec's type registry miss scenario ("e.g., 404/500 from a type registry miss") is the only failure example given; blob corruption is a distinct and less obvious failure mode.

### Suggestion

Add a note in Section 5.3 or Section 6.1 step 4:

> **Blob-level failure scope.** CXDB loads payload blobs for all turns in the response window. If any single payload is corrupted or missing (disk error, incomplete write), the entire request fails with 500 — even if the most recent turns are intact. This is because CXDB's `store.get_before` uses error propagation (`?`) with no per-turn skip. The failure persists until the corrupted blob falls outside the 100-turn fetch window. The per-context error handling (skip and retain cache) mitigates this by preserving last-known status, but the context will not update until the blob is no longer in the window.
