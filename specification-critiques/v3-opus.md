# CXDB Graph UI Spec — Critique v3 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v2 critique raised 5 issues, all applied: polling now uses `setTimeout` to prevent overlapping cycles, per-context status maps are cached for CXDB failure resilience, `mergeStatusMaps` ties `lastTurnId` to the winning status context, tab switching reapplies cached status maps, and the discovery algorithm caches negative results.

---

## Issue #1: Turns endpoint uses `order=desc`/`order=asc` parameters that do not exist in CXDB

### The problem

The spec references `order` as a query parameter throughout:

- Section 5.1 endpoint table: `/v1/contexts/{id}/turns?limit={n}&order={dir}`
- Section 5.5 discovery algorithm: `fetchTurns(index, context.context_id, limit=1, order=asc)`
- Section 6.1 polling step 3: `GET /api/cxdb/{i}/v1/contexts/{id}/turns?limit=100&order=desc`

However, the actual CXDB HTTP API (`cxdb/server/src/http/mod.rs`, lines 743-801) does not support an `order` parameter. The turns endpoint accepts:
- `limit` (default: 64)
- `before_turn_id` (default: 0; when 0, returns the **newest** turns via `store.get_last()`)
- `view`, `type_hint_mode`, `include_unknown`, `bytes_render`, `u64_format`, `enum_render`, `time_render`

Turns are always returned newest-first. There is no way to request ascending order. An implementing agent following the spec would send `order=asc` or `order=desc` parameters that CXDB silently ignores, getting newest-first results in both cases.

This is critical for the discovery algorithm (Section 5.5), which needs the **first** turn of a context to check for `RunStarted`. With `limit=1` and no `order` support, the API returns the **most recent** turn, not the first — so the discovery check against `RunStarted` would almost always fail (the first turn is only the most recent turn when `head_depth` is 0).

### Suggestion

1. Remove all `order` parameter references from the spec.
2. For the discovery algorithm: use `before_turn_id` with cursor-based pagination to reach the first turn. The context list provides `head_depth` — if `head_depth` is 0, `limit=1` already returns the first turn. Otherwise, paginate backward using `next_before_turn_id` from the response until reaching depth 0. Alternatively, fetch `limit=<head_depth+1>` to get all turns in one request (the last element in the returned array is the oldest).
3. For the status polling (Section 6.1): `limit=100` with `before_turn_id=0` (or omitted) already returns the 100 most recent turns newest-first, which is the desired behavior. Just remove the `order=desc` parameter.

## Issue #2: Spec claims default turns limit is 20 but CXDB default is 64

### The problem

Section 5.3 shows the turns endpoint example as:
```
GET /v1/contexts/{context_id}/turns?limit=20&order=desc
```

The actual CXDB default for `limit` is 64 (line 747 in `mod.rs`). While the spec explicitly passes `limit=100` for status polling (Section 6.1), the example in Section 5.3 uses `limit=20` which misrepresents the API's default behavior. An implementing agent reading Section 5.3 as documentation of the CXDB API might assume 20 is the default.

### Suggestion

Update the Section 5.3 example to either use the actual default (omit `limit` entirely) or use `limit=100` to match the polling usage. Add a note that CXDB's default limit is 64 turns.

## Issue #3: Turns response includes `next_before_turn_id` for pagination but spec does not document it

### The problem

The CXDB turns response includes a `next_before_turn_id` field (line 927 in `mod.rs`) that is the cursor for fetching the next page of older turns. This field is critical for:
1. Implementing the discovery algorithm (paginating to the first turn)
2. Fetching more than `limit` turns for a context when needed
3. The detail panel, which might want to load older turns on demand

The spec's turn response example in Section 5.3 does not include this field. Without it, an implementing agent has no way to paginate and no way to reliably reach the `RunStarted` turn for discovery.

### Suggestion

Add `next_before_turn_id` to the Section 5.3 turn response example. Document that it is a string (turn ID) used as the `before_turn_id` query parameter to fetch the next page of older turns. Note that when it is `null`, there are no more turns to fetch.

## Issue #4: Turn response includes additional fields not shown in spec example

### The problem

The actual CXDB turn response includes several fields not shown in the spec's Section 5.3 example:
- `parent_turn_id` — the turn this was appended after
- `decoded_as` — the type after registry resolution (parallel to `declared_type`)
- `content_hash_b3` — content-addressed hash
- `encoding` and `compression` — storage format metadata
- `uncompressed_len` — payload size

While the UI may not use all of these, the `parent_turn_id` is relevant for understanding turn ordering, and `decoded_as` is what the UI should use for type identification (it reflects the registry's resolution of the declared type). An implementing agent seeing only `declared_type` in the example might not realize `decoded_as` exists and could miss type resolution differences.

### Suggestion

This is a minor documentation issue. At minimum, add `decoded_as` to the response example since the UI checks `declared_type.type_id` — clarify whether the UI should use `declared_type` or `decoded_as` for type matching. The other fields can be mentioned as "additional fields present but unused by the UI."

## Issue #5: Context list response includes fields the spec omits

### The problem

The actual CXDB context list response includes several per-context fields not shown in the spec's Section 5.2 example:
- `client_tag` — available directly on the context object (the spec only shows it in `active_sessions`)
- `session_id` — the session that last wrote to this context
- `title` — human-readable label
- `labels` — tags/categories

The `client_tag` on contexts is particularly relevant: the discovery algorithm could use it to filter for `kilroy/*` contexts before fetching turns, significantly reducing discovery requests. Instead of fetching the first turn of every context to check for `RunStarted`, the algorithm could first filter by `client_tag` prefix, skipping contexts created by other applications entirely.

Additionally, the contexts endpoint supports a `tag` query parameter for server-side filtering (`?tag=kilroy/...`), which would further reduce the number of contexts the UI needs to process.

### Suggestion

1. Update the Section 5.2 response example to include `client_tag` on context objects.
2. Document the `tag` query parameter on the contexts endpoint.
3. Consider optimizing the discovery algorithm to filter by `client_tag` prefix before fetching `RunStarted` turns — this would eliminate the need to fetch first turns for non-Kilroy contexts entirely (a stronger optimization than the current negative caching).
