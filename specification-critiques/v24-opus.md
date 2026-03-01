# CXDB Graph UI Spec — Critique v24 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v23 cycle had two critics (opus and codex). All 7 issues were applied: opus's 5 issues (CQL search as primary discovery mechanism, metadata labels optimization documented, `client_tag` stability requirement, `view=raw` for `fetchFirstTurn`, error heuristic window limitation documented). Codex's 2 issues (`index.html` resolved via `go:embed`, DOT parse error handling for `/nodes` and `/edges`). This critique continues to be informed by reading the CXDB server source and compares it against the spec's documented behavior.

---

## Issue #1: The spec states CQL search context objects contain "the same fields as the context list response" — they do not, and the discrepancy affects the metadata labels optimization path

### The problem

Section 5.2 states: "Each context object in the `contexts` array contains the same fields as the context list response: `context_id`, `head_turn_id`, `head_depth`, `created_at_unix_ms`, `is_live`, and `client_tag` (from cached metadata)."

However, examining the CXDB source (`server/src/http/mod.rs` lines 415-449), the CQL search endpoint builds its own lightweight context objects rather than calling `context_to_json`. The CQL search response includes only: `context_id`, `head_turn_id`, `head_depth`, `created_at_unix_ms`, `is_live`, `client_tag`, and `title`. It does **not** include:

- `labels` — present in the context list response (via `context_to_json` line 1347-1349)
- `session_id` — present in the context list response (line 1337-1339)
- `last_activity_at` — present in the context list response (line 1340-1342)
- `lineage` — present in the context list response when `include_lineage=1` (lines 1366-1392)
- `provenance` — present in the context list response when `include_provenance=1` (lines 1352-1364)

The spec already notes that CQL search does not include `lineage` or `active_sessions`, but it fails to note the absence of `labels`. This matters because the "Metadata labels optimization" (Section 5.5) proposes that the UI could read `graph_name` and `run_id` from the context list response's `labels` field to eliminate `fetchFirstTurn`. If the UI uses CQL search as the primary discovery mechanism (which it does), `labels` are not available in the response. The optimization would require either: (a) switching to the context list fallback (losing the scalability benefits of CQL), (b) making separate per-context requests to `GET /v1/contexts/{id}` which does return `labels`, or (c) requesting a CXDB enhancement to include `labels` in the CQL search response.

### Suggestion

Fix the factual claim in Section 5.2 by enumerating the exact fields the CQL search response includes: `context_id`, `head_turn_id`, `head_depth`, `created_at_unix_ms`, `is_live`, `client_tag` (from cached metadata), and `title` (from cached metadata). Explicitly note the absence of `labels`, `session_id`, `last_activity_at`, `lineage`, and `provenance` — not just lineage. Update the "Metadata labels optimization" note in Section 5.5 to acknowledge that CQL search does not return `labels`, making the optimization incompatible with the CQL-first discovery path without per-context requests or a CXDB enhancement.

---

## Issue #2: The CQL search endpoint supports a `limit` parameter that the spec does not document — unbounded queries on CXDB instances with many Kilroy contexts could produce large response payloads

### The problem

The CXDB CQL search endpoint accepts an optional `limit` query parameter (`server/src/http/mod.rs` line 391: `let limit = params.get("limit").and_then(|v| v.parse::<u32>().ok());`). When present, it truncates results after sorting by `context_id` descending (`store.rs` lines 386-392). When absent, all matching contexts are returned.

The spec documents CQL search as returning "all matching contexts regardless of total context count" (Section 5.2), which is true when `limit` is omitted. However, it does not document the `limit` parameter's existence. This is not a problem for the initial implementation (fetching all Kilroy contexts is the intended behavior), but an implementer reading the spec might be unaware that the endpoint supports pagination-like behavior. More importantly, in environments with many Kilroy runs (long-lived shared servers), the CQL search could return thousands of contexts — each requiring a full context object to be assembled server-side. The spec does not discuss whether this poses a performance concern or whether `limit` should be used defensively.

### Suggestion

Add a brief note in Section 5.2's CQL search documentation that the endpoint supports an optional `limit` query parameter (matching contexts are sorted by `context_id` descending before truncation). State that the UI omits `limit` to retrieve all Kilroy contexts, since the discovery algorithm needs to see all contexts to determine the active run. Note that environments with hundreds of historical Kilroy runs will produce proportionally larger CQL search responses, but this is acceptable for the initial implementation — the alternative (paginating CQL results) would complicate discovery logic for a scenario that is not performance-critical at expected scale.

---

## Issue #3: CQL search sorts results by `context_id` descending, not by `created_at_unix_ms` — the spec's active run determination assumes creation-time ordering that aligns with this but does not document the actual sort key

### The problem

The spec's `determineActiveRuns` algorithm (Section 6.1 step 3) selects the active run by finding the `run_id` with the highest `created_at_unix_ms` among its contexts. This is correct regardless of response ordering — the algorithm iterates all candidates to find the maximum. However, Section 5.2's description of the context list fallback states that contexts are returned in "descending order by creation time" and Section 5.2 implies the same for CQL search by saying contexts contain "the same fields."

The CXDB source reveals that CQL search sorts by `context_id` descending (`store.rs` line 387: `sorted_ids.sort_by(|a, b| b.cmp(a))`), while the context list sorts by `created_at_unix_ms` descending (`turn_store` `list_recent_contexts`). Since `context_id` is a monotonically increasing counter allocated at context creation, the two orderings are effectively equivalent in practice — a higher `context_id` always implies a later `created_at_unix_ms`. But they are technically different sort keys, and the spec should document this for accuracy. An implementer who relies on response ordering for optimization (e.g., "the first context in the CQL response is the newest") should know the actual sort key.

### Suggestion

Add a note in Section 5.2's CQL search description that CQL results are sorted by `context_id` descending (most recent first), which is effectively equivalent to creation-time ordering since CXDB allocates context IDs monotonically. Note that the context list fallback sorts by `created_at_unix_ms` descending. State that the `determineActiveRuns` algorithm does not depend on response ordering — it scans all candidates to find the maximum `created_at_unix_ms` — so this difference has no functional impact.

---

## Issue #4: The spec does not document the CQL search error response shape, making it unclear how the UI should handle malformed CQL queries

### The problem

Section 5.2 documents the CQL success response shape (`total_count`, `elapsed_ms`, `query`, `contexts`) and mentions falling back to the context list when CQL returns 404. However, it does not document the CQL error response (400 status) that CXDB returns for malformed queries.

The CXDB source (`server/src/http/mod.rs` lines 474-497) returns a 400 with a JSON error body:

```json
{
  "error": "Parse error: unexpected token at position 5",
  "error_type": "ParseError",
  "position": 5,
  "field": null
}
```

The spec's `discoverPipelines` pseudocode (Section 5.5) catches `httpError` from CQL search and checks for status 404 to trigger fallback. But a 400 (malformed query) is a different failure mode than 404 (endpoint not found). A 400 means CQL is supported but the query was rejected — the UI should not fall back to the context list (since CQL works) and should not retry (the query is deterministic). The current pseudocode would hit the `ELSE: CONTINUE` branch, treating a malformed query the same as an unreachable instance, which silently skips discovery for that instance.

This is unlikely in practice since the query `tag ^= "kilroy/"` is hardcoded and correct, but an implementer testing against a different CQL version or a misconfigured proxy could encounter this. The spec should document the expected behavior.

### Suggestion

Add a note in Section 5.2 documenting the CQL error response shape (400 with `error`, `error_type`, `position`, `field` fields). In the `discoverPipelines` pseudocode, add explicit handling for 400 responses: log the error (for debugging) and skip the instance for this poll cycle, but do not set `cqlSupported[index] = false` (CQL is supported, the query just failed). This distinguishes "CQL not available" (404 -> fallback) from "CQL query error" (400 -> log and skip) from "instance unreachable" (network error -> skip and retain cache).

---

## Issue #5: The SSE event stream at `/v1/events` is dismissed as a non-goal but could solve the discovery bootstrap delay without the complexity the non-goal implies

### The problem

Section 10 (Non-Goals, item 11) states: "No SSE event streaming. CXDB exposes a `/v1/events` Server-Sent Events endpoint for real-time push notifications (e.g., `TurnAppended`, `ContextCreated`). The UI uses polling instead for simplicity — no persistent connection management, simpler error recovery, and 3-second latency is sufficient for the 'mission control' use case."

This is a reasonable design decision for the main turn-polling loop. However, reading the CXDB source reveals that the SSE endpoint (`server/src/http/mod.rs` lines 1209-1287) emits a `ContextCreated` event (with `context_id`, `session_id`, `client_tag`) immediately when a new context is created, and a `ContextMetadataUpdated` event (with `context_id`, `client_tag`, `title`, `labels`) when the first turn's metadata is extracted. The Go client (`clients/go/subscribe.go`) provides a ready-to-use `SubscribeEvents` function with automatic reconnection.

The Go server (the UI's proxy server) could subscribe to SSE from each CXDB instance and maintain a local set of known Kilroy context IDs. When a `ContextCreated` event with a `kilroy/`-prefixed `client_tag` arrives, the server could immediately trigger discovery for that context — or at minimum, include the new context ID in the next proxy response. This would eliminate the discovery bootstrap delay (1-3 poll cycles / 3-9 seconds) that the spec acknowledges in Section 5.5 without requiring the browser to manage SSE connections. The server-side SSE subscription is invisible to the browser — polling continues unchanged.

This is not a critique of the non-goal itself (browser-side SSE is correctly deferred), but the non-goal is written broadly enough that it might discourage server-side SSE usage, which is a different design point with lower complexity.

### Suggestion

Narrow the non-goal to specify "No browser-side SSE event streaming" rather than "No SSE event streaming." Add an optional note that the Go proxy server could subscribe to CXDB's SSE endpoint server-side to reduce discovery latency, without changing the browser's polling architecture. This is not required for the initial implementation but keeps the door open without misleading implementers into thinking SSE is categorically excluded.
