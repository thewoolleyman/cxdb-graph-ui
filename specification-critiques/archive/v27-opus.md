# CXDB Graph UI Spec — Critique v27 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v26 cycle had two critics (opus and codex). All 6 issues were applied: opus's 4 issues (concrete RunStarted tag numbers from the verified registry bundle, removal of phantom `graph_dot` field, null/empty `graph_name` guard in discovery, cross-context parent chain traversal documentation). Codex's 2 issues (per-type rendering mapping table for the detail panel, numeric `turn_id` comparison requirement for detail panel ordering). This critique is informed by reading the CXDB server source (`server/src/http/mod.rs`, `server/src/store.rs`, `server/src/turn_store/mod.rs`, `server/src/cql/`) to verify the spec's claims against actual implementation.

---

## Issue #1: The CQL search response includes `session_id` in the spec's field list, but the CXDB source does NOT include `session_id` in CQL search results — only `context_to_json` (used by the context list endpoint) adds it

### The problem

Section 5.2 documents the CQL search response fields as: `context_id`, `head_turn_id`, `head_depth`, `created_at_unix_ms`, `is_live`, `client_tag` (from cached metadata), and `title` (from cached metadata). It then says:

> The CQL search response does **not** include `labels`, `session_id`, `last_activity_at`, `lineage`, `provenance`, `active_sessions`, or `active_tags`

This exclusion list is correct — the CXDB source at `server/src/http/mod.rs` lines 425-447 confirms that the CQL search endpoint builds context objects with only `context_id`, `head_turn_id`, `head_depth`, `created_at_unix_ms`, `is_live`, and optionally `client_tag` and `title` from the metadata cache. It does NOT include `session_id` or `last_activity_at`.

However, the spec's context list response example (Section 5.2, under the fallback endpoint) includes `session_id` in each context object, while the CQL search response description does not show `session_id`. This is correct but asymmetric — the reader could miss that `session_id` is available in the fallback path but NOT in the CQL path. More importantly, the spec does not document that the full context list endpoint's `context_to_json` function (`http/mod.rs` line 1305) has a **session-tag fallback** for `client_tag` (line 1323: it falls back to the active session's `client_tag` when stored metadata has no tag), while the CQL search endpoint (`http/mod.rs` line 439) only reads from the metadata cache. This difference is mentioned in the "CQL search bootstrap lag" note but is not explicitly tied to the `client_tag` resolution asymmetry — an implementer testing with the context list fallback might observe `client_tag` appearing for live contexts, then be confused when switching to CQL and finding it missing for the same context during the brief metadata extraction window.

### Suggestion

Add a brief note after the CQL search response field list clarifying the `client_tag` resolution difference:

- **CQL search**: `client_tag` comes from cached metadata only (extracted from the first turn's key 30). If metadata extraction has not yet occurred (context just created), `client_tag` is absent.
- **Context list fallback**: `client_tag` comes from cached metadata first, then falls back to the active session's tag (`context_to_json`'s session-tag fallback). This means `client_tag` is available for live contexts even before metadata extraction.

This makes the bootstrap lag note in Section 5.2 more actionable by tying it to the specific API field behavior.

---

## Issue #2: The spec does not document the `bytes_render` query parameter for turn fetch requests — the CXDB source supports `base64` (default), `hex`, and `len_only` render modes, and the UI's `fetchFirstTurn` relies on the default `base64` mode without specifying it explicitly

### The problem

Section 5.5's `fetchFirstTurn` pseudocode fetches turns with `view=raw` and then accesses `rawTurn.bytes_b64` to get the base64-encoded msgpack payload. The CXDB server's turn endpoint (`http/mod.rs` lines 758-761) supports a `bytes_render` query parameter:

```rust
let bytes_render = match params.get("bytes_render").map(|v| v.as_str()) {
    Some("hex") => BytesRender::Hex,
    Some("len_only") => BytesRender::LenOnly,
    _ => BytesRender::Base64,
};
```

When `bytes_render=hex`, the response uses `bytes_hex` instead of `bytes_b64`. When `bytes_render=len_only`, only `bytes_len` is returned (no payload data at all).

The UI relies on the default behavior (`bytes_b64`), which is correct. But the spec does not document this parameter or the existence of alternative render modes in Section 5.3's query parameter table. If a proxy, middleware, or debugging tool adds `bytes_render=hex` to the request (or if CXDB's default changes in a future version), the UI's `rawTurn.bytes_b64` access would silently return `undefined`, and `base64Decode(undefined)` would fail.

### Suggestion

Add `bytes_render` to Section 5.3's query parameter table:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `bytes_render` | `base64` | Raw payload encoding when `view=raw` or `view=both`: `base64` (field: `bytes_b64`), `hex` (field: `bytes_hex`), or `len_only` (field: `bytes_len`, no payload data). The UI uses the default (`base64`) and accesses `bytes_b64`. |

And add a note in the `decodeFirstTurn` pseudocode that the `bytes_b64` field is only present when `bytes_render` is omitted or set to `base64`.

---

## Issue #3: The `fetchFirstTurn` pseudocode does not account for the fact that `get_before` with `before_turn_id=0` in CXDB delegates to `get_last` (returns newest turns from head), not an empty response — the spec's cursor initialization semantics are correct but the underlying CXDB behavior is undocumented and the pseudocode conflates two different API behaviors

### The problem

The `fetchFirstTurn` pseudocode initializes `cursor = 0` and uses this special value to mean "start from head (no before_turn_id)." On the first iteration:

```
IF cursor == 0:
    response = fetchTurns(cxdbIndex, contextId, limit=PAGE_SIZE, view="raw")
```

This omits the `before_turn_id` parameter entirely, which is correct — the CXDB server treats a missing `before_turn_id` the same as `before_turn_id=0`, and both fall through to `get_last(context_id, limit)` (`turn_store/mod.rs` line 535-536):

```rust
if before_turn_id == 0 || head.head_turn_id == 0 {
    return self.get_last(context_id, limit);
}
```

The pseudocode works correctly because it distinguishes `cursor == 0` (first request, omit parameter) from subsequent requests where `cursor` is a real turn ID. However, the spec does not document this CXDB behavior: `before_turn_id=0` and omitting `before_turn_id` are functionally identical — both return the most recent turns from the head. Section 5.3 says "When `0` (default), returns the most recent turns" which is accurate but could be clearer that 0 is the sentinel value for "no cursor."

More importantly, the `get_last` function walks backward from the head via `parent_turn_id` links and returns results in **oldest-first** order (line 520: `results.reverse()`). This is the same ordering as `get_before`. The spec states "returns oldest-first" for turn responses generally, which is correct. But an implementer might wonder whether the first request (no cursor) and subsequent requests (with cursor) return turns in the same order — they do, because both paths reverse the parent chain walk.

### Suggestion

This is a minor documentation gap. Add a note to Section 5.3 clarifying that `before_turn_id=0` (the default) and omitting the parameter are equivalent — both return the most recent `limit` turns from the context head, in oldest-first order. This makes the `fetchFirstTurn` pseudocode's `cursor = 0` sentinel clearer to implementers who might check the CXDB source.

---

## Issue #4: The holdout scenarios do not cover the CQL-to-fallback transition — there is no scenario for a CXDB instance that initially supports CQL but then returns 404 on CQL after a downgrade or reconfiguration, which would leave the `cqlSupported` flag in a stale `true` state

### The problem

Section 5.5's `discoverPipelines` pseudocode sets `cqlSupported[index] = true` on the first successful CQL search and `cqlSupported[index] = false` on a 404. The spec states:

> The `cqlSupported` flag is reset when the CXDB instance becomes unreachable and then reconnects (since the instance may have been upgraded).

This means the flag is reset on reconnection after an outage. But consider this scenario:

1. CXDB instance supports CQL. UI sets `cqlSupported[0] = true`.
2. CXDB is restarted with an older version that lacks CQL support (downgrade).
3. The restart is fast enough that the UI never sees an unreachable state (no 502 between polls).
4. On the next poll, the UI attempts CQL search (because `cqlSupported[0]` is still `true`).
5. CXDB returns 404 for `/v1/contexts/search`.

In the current pseudocode, step 5 correctly sets `cqlSupported[0] = false` and falls back to the context list. So the behavior is correct. However, the holdout scenarios do not cover this transition. They also do not cover the reverse (upgrading from non-CQL to CQL-capable while the UI is running), which would be handled by the reconnection reset.

The existing holdout scenarios cover CXDB unreachable/reconnect (connection handling section) and the basic CQL discovery flow (pipeline discovery section), but the CQL-to-fallback transition during continuous operation is a gap.

### Suggestion

Add a holdout scenario:

```
### Scenario: CXDB downgrades and CQL becomes unavailable mid-session
Given the UI has been polling CXDB-0 successfully using CQL search
  And cqlSupported[0] is true
When CXDB-0 is restarted with a version that lacks CQL support
  And the restart is fast enough that no poll cycle sees a 502
Then the next CQL search attempt returns 404
  And the UI sets cqlSupported[0] to false
  And falls back to the context list endpoint for that poll cycle
  And subsequent polls use the context list fallback without retrying CQL
  And pipeline discovery continues uninterrupted
```

This is a minor gap — the code path is already specified in the pseudocode — but adding the scenario makes the fallback transition explicitly testable.
