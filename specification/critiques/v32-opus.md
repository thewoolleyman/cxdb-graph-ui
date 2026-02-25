# CXDB Graph UI Spec — Critique v32 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-25

## Prior Context

The v31 cycle had two critics (opus and codex). Three of opus's four issues were applied: the `useMaps` decoder option was removed from `decodeFirstTurn`, the metadata extraction asymmetry for forked contexts was documented, and a defensive note about cross-context `before_turn_id` was added. Opus's fourth issue (forked-from-depth-0 holdout scenario) was deferred as a proposed holdout scenario. Codex's two issues were both applied: the `useMaps` option removal (duplicate finding) and the CQL support flag reset holdout scenario was promoted to the main document. This critique is informed by detailed reading of the CXDB source code (`turn_store/mod.rs`, `store.rs`, `http/mod.rs`), the Go client types (`conversation.go`, `builders.go`), and the CQL secondary indexes implementation (`cql/indexes.rs`).

---

## Issue #1: The proposed holdout scenario for "forked context with depth-0 base turn" contains a factually incorrect precondition

### The problem

The v31-opus Issue #4 proposed a holdout scenario (deferred to `holdout-scenarios/proposed-holdout-scenarios-to-review.md`) with this precondition:

> And the forked context has accumulated 50+ turns of its own (depths 1-50+)
> And the forked context's head_depth is 0 (inherited from the base turn)

This is incorrect. Reading `turn_store/mod.rs` lines 458-467, the `append_turn` method updates `head_depth` on every append:

```rust
let head = ContextHead {
    context_id,
    head_turn_id: turn_id,
    head_depth: depth,      // updated to the new turn's depth
    created_at_unix_ms: record.created_at_unix_ms,
    flags: 0,
};
self.write_head(&head)?;
self.heads.insert(context_id, head);
```

After a forked context (forked from depth 0) has 50 turns appended, `head_depth` is 50, not 0. The `head_depth` is only 0 at context creation time (between `fork_context` and the first `append_turn`). The proposed scenario describes an impossible state: a context cannot simultaneously have 50+ turns and `head_depth == 0`.

The correct scenario for the `headDepth == 0` fast-path guard is:

- **Scenario A (trivial):** A newly forked context from depth 0 with no turns yet appended. `head_depth == 0`, `head_turn_id` points to the parent's depth-0 turn. `get_last(limit=1)` returns the parent's RunStarted, depth check passes, discovery succeeds.
- **Scenario B (edge case for the guard):** Cannot actually occur given CXDB's `head_depth` update semantics — if the context has turns, `head_depth > 0`, and the `headDepth == 0` branch is not taken.

The depth guard in the fast-path (`IF response.turns[0].depth == 0`) is defensive but cannot actually fire as a fall-through, because a context with `head_depth == 0` either has no turns appended (in which case `get_last` returns the base turn at depth 0) or is a new non-forked context (in which case it has at most one turn at depth 0). The guard is harmless but not exercisable.

### Suggestion

Remove the proposed holdout scenario from `holdout-scenarios/proposed-holdout-scenarios-to-review.md` since the precondition is impossible. Add a brief comment in the spec's `fetchFirstTurn` fast-path explaining why the depth guard is defensive-only:

> **Note:** `head_depth` is updated on every `append_turn`. A context with `head_depth == 0` has either zero appended turns (just created/forked) or exactly one turn at depth 0. The `depth == 0` guard is a defensive check — in practice, `get_last(limit=1)` for a `head_depth == 0` context always returns either empty (no turns) or a depth-0 turn.

---

## Issue #2: The spec does not document that `ContextHead.created_at_unix_ms` is updated on each `append_turn`, potentially affecting `determineActiveRuns` ordering

### The problem

Section 6.1's `determineActiveRuns` algorithm selects the active run by finding "the highest `created_at_unix_ms` among the `RunStarted` contexts for that pipeline." The algorithm reads `created_at_unix_ms` from the context list response.

However, reading `turn_store/mod.rs` lines 458-464:

```rust
let head = ContextHead {
    context_id,
    head_turn_id: turn_id,
    head_depth: depth,
    created_at_unix_ms: record.created_at_unix_ms,  // updated to the TURN's created_at
    flags: 0,
};
```

The `created_at_unix_ms` on `ContextHead` is **overwritten on every `append_turn`** with the new turn's timestamp. This means `ContextHead.created_at_unix_ms` reflects the **most recent turn's timestamp**, not the context's original creation time.

This changes the semantics of `determineActiveRuns`: the algorithm's `max(c.createdAt FOR c IN contexts)` picks the run with the most recently **active** context (latest turn appended), not the most recently **created** context. For the active run selection, this is probably a better signal (the run with the most recent activity is most likely the "current" run), but it diverges from the spec's stated semantics: "The most recent run is determined by the highest `created_at_unix_ms` among the `RunStarted` contexts for that pipeline" (Section 5.5), which implies creation time.

The practical impact is minimal in most cases — newer runs typically also have newer activity. But consider this scenario:

1. Run A starts at t=100, creates context A1.
2. Run B starts at t=200, creates context B1.
3. Run A's context A1 receives a late turn at t=300 (e.g., a delayed parallel branch completing).
4. Now A1.`created_at_unix_ms` = 300, B1.`created_at_unix_ms` = 200 (or whatever B1's latest turn timestamp is).
5. `determineActiveRuns` selects Run A as the active run, even though Run B started more recently.

This is a correctness issue: the spec says "most recent run" but the implementation would select the run with the most recent **activity**.

### Suggestion

Either:

(a) **Document the actual CXDB behavior** and state that `created_at_unix_ms` from the context list reflects the timestamp of the most recent turn, not the context creation time. Adjust the `determineActiveRuns` description accordingly — the algorithm selects the run with the most recent activity, which is typically the desired behavior.

Or:

(b) **Use a different field for run ordering.** The CQL search response includes `head_turn_id`, and the context list response includes `context_id`. Since both `context_id` and `turn_id` are allocated from monotonically increasing global counters (`turn_store/mod.rs` lines 347-348 for `context_id`, line 408 for `turn_id`), `context_id` is a reliable proxy for creation order. The `determineActiveRuns` tiebreaker already uses `context_id` — promoting it to the primary sort key would make active-run selection independent of the `created_at_unix_ms` semantics.

---

## Issue #3: The CQL search response does not include `labels` but also does not include `head_depth` — which `fetchFirstTurn` uses as input

### The problem

Section 5.5's `fetchFirstTurn` takes `context.head_depth` as a parameter and uses it for the `headDepth == 0` fast path. The spec documents (Section 5.2) that the CQL search response includes `head_depth`:

```json
{
  "context_id": "33",
  "head_turn_id": "6064",
  "head_depth": 100,
  "created_at_unix_ms": 1771929214262,
  "is_live": false
}
```

Verifying against the CXDB source (`http/mod.rs` lines 421-431):

```rust
let head = store.turn_store.get_head(context_id).ok()?;
let mut obj = json!({
    "context_id": context_id.to_string(),
    "head_turn_id": head.head_turn_id.to_string(),
    "head_depth": head.head_depth,
    "created_at_unix_ms": head.created_at_unix_ms,
    "is_live": is_live,
});
```

This confirms `head_depth` is present in the CQL search response. No issue here — I verified the spec's claim is accurate.

However, the spec's Section 5.2 says the CQL search response "does not include `labels`, `session_id`, `last_activity_at`, `lineage`, `provenance`, `active_sessions`, or `active_tags`." Looking at lines 438-445:

```rust
if let Some(ref tag) = metadata.client_tag {
    obj["client_tag"] = JsonValue::String(tag.clone());
}
if let Some(ref title) = metadata.title {
    obj["title"] = JsonValue::String(title.clone());
}
```

The CQL search response currently does **not** include `labels` (confirmed — lines 438-445 only add `client_tag` and `title` from metadata, skipping `labels`). This is accurately documented. However, the spec says "the optimization cannot read `graph_name`/`run_id` from labels without per-context requests or a CXDB enhancement to include `labels` in CQL results."

Looking more closely at the CQL search handler, I notice that `head_depth` is present but the response does NOT include `head_turn_id` as a string-formatted value. Wait — re-reading line 427: `"head_turn_id": head.head_turn_id.to_string()` — it IS present. This is correct.

**The actual issue:** The spec's Section 5.2 lists the CQL response fields but does not mention `title` as an included field. The CQL search handler (line 443-444) does include `title` when present in cached metadata. The spec says the response includes `context_id`, `head_turn_id`, `head_depth`, `created_at_unix_ms`, `is_live`, and `client_tag`, but omits `title` from the field list.

### Suggestion

Add `title` to the CQL search response field list in Section 5.2:

> Each context object in the `contexts` array contains: `context_id`, `head_turn_id`, `head_depth`, `created_at_unix_ms`, `is_live`, `client_tag` (from cached metadata), and `title` (from cached metadata).

This is a documentation accuracy fix. The UI does not use `title`, but an implementer reading the spec should know the complete response shape when debugging or extending the UI.

---

## Issue #4: The spec's `list_recent_contexts` line reference in Section 5.2 is incorrect — `context_to_json` does not have a line 1323 session-tag fallback at the stated location

### The problem

Section 5.2 states:

> **Context list fallback**: `client_tag` comes from cached metadata first, then falls back to the active session's tag (`context_to_json`'s session-tag fallback at `http/mod.rs` line 1323: `.or_else(|| session.as_ref().map(|s| s.client_tag.clone()))`).

The actual `context_to_json` function starts at line 1305 in the current CXDB source. The `client_tag` resolution chain is at lines 1320-1324:

```rust
let client_tag = stored_metadata
    .as_ref()
    .and_then(|m| m.client_tag.clone())
    .or_else(|| session.as_ref().map(|s| s.client_tag.clone()))
    .filter(|t| !t.is_empty());
```

The session-tag fallback is at line 1323 (`.or_else(...)`) and the empty-string filter is at line 1324 (`.filter(...)`). The spec's line reference happens to be correct for the current version of the source, but line numbers are inherently fragile — they change with any edit to the file.

### Suggestion

This is a minor observation, not a required change. The line references are accurate as of the current CXDB source but will drift as the code evolves. The spec's descriptions of the behavior are accurate regardless of line numbers, so no change is strictly needed. If the spec is ever revised for other reasons, consider removing specific line numbers in favor of function name references (e.g., "`context_to_json`'s `.or_else` fallback to the active session's `client_tag`").

---

If these are addressed, I do not see other major spec gaps. The spec is thorough and well-aligned with the CXDB source code. The most significant finding is Issue #2 (the `created_at_unix_ms` update semantics), which could affect active-run determination in edge cases.
