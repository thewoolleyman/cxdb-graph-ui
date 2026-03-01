# CXDB Graph UI Spec — Critique v12 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v11 critique raised 3 issues, all applied: (1) context-grouped display in the detail panel to avoid cross-instance `turn_id` interleaving; (2) sparse-ID-safe gap recovery condition replacing the `+ 1` assumption; (3) `hasLifecycleResolution` propagation through `mergeStatusMaps`. The spec has undergone 11 revision rounds and is algorithmically mature. This critique cross-references the spec against the actual CXDB server source code (`/Users/cwoolley/workspace/cxdb/server/src/`) to validate API assumptions.

---

## Issue #1: CXDB returns turns in oldest-first order, not newest-first — all turn array indexing is reversed

### The problem

The spec states (Section 5.3, line 346):

> "Returns (turns are always ordered newest-first; CXDB does not support ascending order)"

This is incorrect. The CXDB server returns turns in **oldest-first** (ascending) order. Evidence from the source code:

**`turn_store/mod.rs` lines 503–522 (`get_last`):**
```rust
pub fn get_last(&self, context_id: u64, limit: u32) -> Result<Vec<TurnRecord>> {
    let mut results = Vec::new();
    let mut current = head.head_turn_id;
    while current != 0 && results.len() < limit as usize {
        let rec = self.turns.get(&current)?.clone();
        results.push(rec.clone());
        current = rec.parent_turn_id;
    }
    results.reverse();  // ← oldest-first after reverse
    Ok(results)
}
```

The walk traverses from head (newest) to root (oldest), collecting in newest-first order, then `results.reverse()` flips to **oldest-first**. The `get_before` method (lines 524–556) does the same reversal. The HTTP handler (`http/mod.rs` lines 806–913) iterates `turns` in this order and pushes to the JSON array, so the HTTP response is oldest-first.

**`http/mod.rs` line 916 (`next_before_turn_id`):**
```rust
let next_before = turns.first().map(|t| t.record.turn_id.to_string());
```

`turns.first()` is the **oldest** turn in the batch (index 0 of the oldest-first array). This is the correct value for backward pagination (fetching turns older than the current batch).

This reversal breaks three spec algorithms:

**(a) `fetchFirstTurn` returns the wrong turn.** The algorithm (Section 5.5) ends with:

```
RETURN lastTurns[lastTurns.length - 1]
```

With the spec's newest-first assumption, `lastTurns[length - 1]` would be the oldest (first) turn. But with actual oldest-first ordering, `lastTurns[length - 1]` is the **newest** (head) turn. Pipeline discovery would read the head turn instead of the `RunStarted` turn, failing to extract `graph_name` and `run_id`. For any context with more than one turn, pipeline discovery silently fails.

**(b) Gap recovery condition is inverted.** The gap detection (Section 6.1) uses:

```
oldestFetched = turns[turns.length - 1].turn_id   -- "oldest turn in the batch"
```

With actual oldest-first ordering, `turns[turns.length - 1]` is the **newest** turn. The condition `oldestFetched > lastSeenTurnId` becomes `newestFetched > lastSeenTurnId`, which is true whenever any new turns exist. Gap recovery fires on **every poll cycle for every context**, issuing extra paginated requests that discover no gap. This doubles request volume in steady state.

**(c) `lastTurnId` assignment comment is misleading.** Section 6.2 states: "Within a single poll batch, the first encounter per node captures the newest turn ID (since turns arrive newest-first)." With oldest-first ordering, the first encounter captures the **oldest** turn ID. The `lastTurnId` field is still updated correctly (the code uses max comparison, not first-encounter), but the explanatory comment would confuse an implementer.

### Suggestion

Replace all references to "newest-first" ordering with "oldest-first" (ascending by position in the parent chain). Specifically:

1. **Section 5.3** — Change "turns are always ordered newest-first" to "turns are always ordered oldest-first (ascending by depth within the context's parent chain)."

2. **Section 5.5 `fetchFirstTurn`** — Change `lastTurns[lastTurns.length - 1]` to `lastTurns[0]` (the first element is the oldest/first turn in an oldest-first array).

3. **Section 6.1 gap recovery** — Change `turns[turns.length - 1]` to `turns[0]` for `oldestFetched`. In an oldest-first array, the oldest turn is at index 0.

4. **Section 6.2** — Update the `lastTurnId` assignment comment to reflect oldest-first ordering. The max-comparison logic is already correct and needs no change.

5. **Section 6.2 `newLastSeenTurnId`** — The pre-loop max computation is correct regardless of ordering. No change needed.

6. **Section 7.2** — "Within each section, turns are sorted newest-first by `turn_id`" needs updating. The raw API response is oldest-first; the UI should reverse for display (newest-first is better UX for the detail panel) or the spec should note that the UI reverses the API order for display.

---

## Issue #2: Context list default limit of 20 — pipeline discovery may miss Kilroy contexts

### The problem

The CXDB context list endpoint (`GET /v1/contexts`) has a `limit` query parameter that defaults to 20 (`http/mod.rs` line 207):

```rust
let limit = params.get("limit").and_then(|v| v.parse::<u32>().ok()).unwrap_or(20);
```

The spec's pipeline discovery algorithm (Section 5.5) says:

```
contexts = fetchContexts(index)
```

It does not specify a `limit` parameter for this request. An implementing agent following the spec would use the CXDB default of 20. If a CXDB instance has more than 20 contexts (common in development — Claude Code sessions, test runs, and other tools all create contexts), only the 20 most recent are returned. Kilroy pipeline contexts created before the 20 most recent contexts are silently missed.

Concrete scenario: A developer has been using Claude Code (which creates CXDB contexts) and has accumulated 30 contexts on the instance. They start a Kilroy pipeline run that creates context #15 (by creation time). The UI's context list fetch returns contexts #11–#30 (the 20 most recent). Context #15 is within this window and is discovered. But if they later create 16 more Claude Code contexts (#31–#46), context #15 falls outside the top 20 window. On the next fresh discovery (e.g., page reload), the Kilroy context is missed and the pipeline shows no status.

This is especially problematic because the spec's caching design (Section 5.5) means contexts are only discovered once — if a context is missed on the first fetch, it's never retried (there's no mechanism to page through the full context list).

### Suggestion

Add `limit=65535` (the CXDB maximum for turn limits; verify the context list also accepts this) to the `fetchContexts` call in Section 5.5 and document it in Section 5.2. Alternatively, note that the `client_tag` prefix filter in Phase 1 already runs client-side, so fetching all contexts is necessary for correct discovery:

```
contexts = fetchContexts(index, limit=10000)
```

If CXDB instances may accumulate very large numbers of contexts, consider using the CQL search endpoint (`GET /v1/contexts/search?q=tag:kilroy/*`) which the CXDB source exposes (`http/mod.rs` lines 388–497) — this would return only matching contexts without a hard limit. However, this depends on whether the CQL `tag:` operator supports prefix/glob matching, which should be verified against the CQL implementation.

---

## Issue #3: SSE endpoint sets CORS headers — spec's CORS claim is overly broad

### The problem

The spec states (Section 2, line 83):

> "CXDB's HTTP API (port 9010) does not set CORS headers."

This is used to justify the reverse proxy architecture. However, the SSE endpoint (`/v1/events`) **does** set CORS headers (`http/mod.rs` lines 1217, 1237):

```rust
Header::from_bytes(&b"Access-Control-Allow-Origin"[..], &b"*"[..]).unwrap(),
```

While regular REST endpoints (contexts, turns) do not set CORS headers, the SSE endpoint sets `Access-Control-Allow-Origin: *`. This means a future version of the UI could potentially consume SSE events directly from CXDB without the proxy — but only for the SSE endpoint, not for the REST endpoints the UI currently uses.

This is a minor accuracy issue. The proxy is still necessary for the REST endpoints, so the architectural decision is sound. But the blanket statement "does not set CORS headers" is technically incorrect and could mislead an implementer who considers using SSE in the future.

### Suggestion

Qualify the statement: "CXDB's REST endpoints (contexts, turns) do not set CORS headers. The SSE endpoint (`/v1/events`) does set `Access-Control-Allow-Origin: *`, but the UI uses polling, not SSE (Section 10)."
