# CXDB Graph UI Spec — Critique v4 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v3 critique raised 5 issues against the CXDB API surface: non-existent `order` parameter, incorrect default limit, missing `next_before_turn_id` pagination field, undocumented `decoded_as` turn field, and undocumented context-level `client_tag`/`tag` query parameter. No acknowledgement file exists for v3 yet, so those issues are presumed unaddressed. This v4 critique raises **new** issues discovered by examining the CXDB source code directly — none of the issues below duplicate v3.

---

## Issue #1: `created_at_unix_ms` field name and format do not match CXDB API

### The problem

Section 5.2 shows the context list response with:

```json
{
  "contexts": [
    {
      "context_id": "33",
      "created_at_unix_ms": 1771929214262,
      ...
    }
  ]
}
```

The actual CXDB context structure uses `created_at` (not `created_at_unix_ms`) and returns an ISO-8601 timestamp string by default (e.g., `"2026-02-24T10:00:14.262Z"`). The format is controlled by the `time_render` query parameter on the contexts endpoint (`iso` by default, `unix_ms` available).

This matters for the discovery algorithm in Section 5.5, which determines the "most recent run" by comparing `created_at_unix_ms` values across RunStarted contexts. An implementing agent would:
1. Try to read a field named `created_at_unix_ms` that doesn't exist (getting `undefined`)
2. Even if they guessed `created_at`, get an ISO string instead of a numeric value, breaking numeric comparison

### Suggestion

1. Update Section 5.2 to use the correct field name `created_at` with an ISO-8601 string value.
2. Either: (a) add `?time_render=unix_ms` to the contexts fetch URL so the response uses numeric timestamps, making comparison trivial; or (b) document that `created_at` is an ISO-8601 string and the comparison in Section 5.5 uses string or Date comparison.
3. Update Section 5.5's "most recent run" logic to reference the correct field name and format.

## Issue #2: `is_live` field in context response does not exist in CXDB

### The problem

Section 5.2's example response includes `"is_live": false` as a field on each context object. The actual CXDB context structure does not include an `is_live` field. Context liveness in CXDB is determined externally — a context is "live" if its `context_id` appears in any entry in the `active_sessions` array (or equivalently, its `client_tag` appears in `active_tags`).

An implementing agent would look for `is_live` on each context object and find it absent, creating confusion about how to determine whether a context is actively being written to.

While the spec does not currently use `is_live` in any algorithm (status is derived from turns, not liveness), its presence in the example response is misleading. An implementer might build logic around it.

### Suggestion

Remove `is_live` from the Section 5.2 example response. If liveness information is useful for the UI (e.g., showing which pipelines are actively running vs. completed), document how to derive it from `active_sessions` or `active_tags` instead.

## Issue #3: SSE events endpoint exists but spec does not acknowledge it

### The problem

CXDB exposes a `/v1/events` Server-Sent Events (SSE) endpoint that broadcasts real-time events including:
- `TurnAppended { context_id, turn_id, depth, declared_type_id }`
- `ContextCreated { context_id, session_id, client_tag }`
- `ClientConnected` / `ClientDisconnected`

The spec's polling architecture (3-second `setTimeout` loop) is a valid design choice, but it means status updates are delayed by up to 3 seconds plus poll execution time. The SSE endpoint would enable near-instant status updates — a `TurnAppended` event with a `StageStarted` type could immediately trigger a node color change.

The spec doesn't mention SSE at all. This creates two problems:
1. An implementing agent discovering `/v1/events` might wonder if they should use it instead of polling, creating ambiguity.
2. The Non-Goals section (Section 10) doesn't address real-time event streaming, so it's unclear whether this was a deliberate omission.

### Suggestion

This is a minor documentation/clarity issue. Add a brief note to Section 5.1 or Section 10 acknowledging that CXDB supports SSE via `/v1/events` but the UI uses polling for simplicity (no persistent connection management, simpler error handling, sufficient latency for the use case). This prevents implementing agents from second-guessing the polling design.

## Issue #4: `active_sessions` response structure has undocumented fields

### The problem

Section 5.2 shows `active_sessions` entries with only three fields:

```json
{
  "client_tag": "kilroy/01KJ7JPB3C2AHNP9AYX7D19BWK",
  "session_id": "54",
  "last_activity_at": 1771929214261
}
```

The actual CXDB response includes additional fields:
- `connected_at` — when the session connected
- `context_count` — number of contexts the session is writing to
- `peer_addr` — network address of the client (optional)

More importantly, `last_activity_at` is shown as a numeric unix-ms value (`1771929214261`), but like `created_at`, its format depends on the `time_render` query parameter and defaults to ISO-8601.

### Suggestion

This is minor — the UI likely doesn't use `active_sessions` directly. At minimum, fix the `last_activity_at` format to match the actual default (ISO-8601 string), consistent with the `created_at` fix in Issue #1. Optionally note that `connected_at`, `context_count`, and `peer_addr` are also present but unused.

## Issue #5: Discovery algorithm should use `before_turn_id` pagination to reach RunStarted turn

### The problem

The v3 critique (Issue #1) identified that the `order=asc` parameter doesn't exist, meaning `limit=1` returns the newest turn, not the first. However, v3's suggestion for resolving this was somewhat vague ("paginate backward using `next_before_turn_id`" or "fetch `limit=<head_depth+1>`").

The second approach (`limit=head_depth+1`) is problematic for contexts with many turns — a context with `head_depth: 10000` would require fetching 10,001 turns just to check the first one. This is wasteful and could cause timeouts.

A concrete, efficient algorithm is needed. The CXDB API returns turns newest-first with `next_before_turn_id` for pagination. To reach the first turn:

```
FUNCTION fetchFirstTurn(cxdbIndex, contextId, headDepth):
    IF headDepth == 0:
        -- Only one turn exists; limit=1 returns it
        RETURN fetchTurns(cxdbIndex, contextId, limit=1)

    -- Binary search using before_turn_id is not possible (turn IDs are opaque).
    -- Instead, paginate from newest to oldest in chunks.
    -- But this is O(headDepth/chunkSize) requests — still expensive.

    -- Best approach: fetch a single page from the tail.
    -- Turn IDs are monotonically increasing in CXDB.
    -- The first turn has the lowest turn_id.
    -- Heuristic: fetch limit=1 with before_turn_id=2 (turn ID just above the minimum).
    -- If CXDB's turn IDs start at 1, this returns the first turn.
```

Actually, the most reliable approach depends on CXDB's turn ID allocation scheme, which the spec doesn't document. This needs a concrete algorithm that works regardless.

### Suggestion

Replace the discovery algorithm's first-turn fetch with one of these concrete approaches:

**Option A (recommended): Use `client_tag` filtering.** As v3 Issue #5 suggested, fetch contexts with `?tag=kilroy/` to filter for Attractor contexts only. Then for matched contexts, the `RunStarted` data (`graph_name`, `run_id`) could be extracted from the `client_tag` itself if Kilroy embeds it there. Check the actual Kilroy client_tag format to see if this is viable.

**Option B: Paginate to first turn.** Fetch chunks of turns using `next_before_turn_id` until `next_before_turn_id` is null (no more older turns), then take the last turn in the final chunk. This is O(depth/limit) requests per context but only runs once per context (cached).

**Option C: Use context provenance.** CXDB has a `/v1/contexts/{id}/provenance` endpoint that may contain metadata about the context. If Kilroy stores pipeline metadata in provenance, this avoids turn pagination entirely.

The spec should pick one approach and specify it concretely so an implementing agent doesn't have to solve this puzzle.
