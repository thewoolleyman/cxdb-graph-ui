# CXDB Graph UI Spec — Critique v31 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-25

## Prior Context

The v30 cycle had two critics (opus and codex). All 6 issues were applied or deferred: opus's 4 issues (fetchFirstTurn depth-0 fork guard, empty client_tag filtering documentation, determineActiveRuns tie-breaking, and cqlSupported flag reset holdout scenario) and codex's 2 issues (HTML escaping for tab labels and CXDB indicator, and msgpack decoder Map handling). This critique is informed by detailed reading of the CXDB source code (`server/src/store.rs`, `server/src/turn_store/mod.rs`, `server/src/http/mod.rs`) and the Go client types (`clients/go/types/conversation.go`, `clients/go/types/builders.go`), as well as the `@msgpack/msgpack` JavaScript library's actual API surface for the pinned version (3.0.0-beta2).

---

## Issue #1: The spec's `decodeFirstTurn` pseudocode references a non-existent `useMaps` decoder option in `@msgpack/msgpack`

### The problem

Section 5.5's `decodeFirstTurn` pseudocode passes `{ useMaps: false }` to `msgpackDecode`:

```
payload = msgpackDecode(bytes, { useMaps: false })
```

And the surrounding comments explain: "With useMaps=false (or the equivalent option for the pinned version), integer keys are coerced to string keys in the resulting object."

However, the `@msgpack/msgpack` library (at the pinned version 3.0.0-beta2 and in the current main branch) does **not** have a `useMaps` option. Examining the library's `Decoder.ts` source, the decoder options are: `extensionCodec`, `context`, `useBigInt64`, `rawStrings`, `maxStrLength`, `maxBinLength`, `maxArrayLength`, `maxMapLength`, `maxExtLength`, and `mapKeyConverter`. There is no `useMaps`, `useMap`, or equivalent toggle.

The library always returns plain JavaScript objects for msgpack maps, never `Map` instances. Integer keys are accepted (the default `mapKeyConverter` allows `string | number` types) and are coerced to strings automatically by JavaScript's object key semantics. This means `payload[8]` and `payload["8"]` both work correctly without any special configuration — JavaScript converts the number `8` to the string `"8"` when used as an object property access.

An implementer following the spec literally would pass an unrecognized option (`useMaps: false`) to the `decode` function. The `@msgpack/msgpack` library silently ignores unknown options (they are not validated), so this would not cause a runtime error — but it is misleading. More critically, the spec's fallback guidance ("If the decoder does not support useMaps=false, wrap the result: if payload is a Map, convert it to an object via Object.fromEntries(payload.entries())") implies a failure mode that cannot actually occur with this library, wasting implementer time on dead-code defensive handling.

### Suggestion

Remove the `{ useMaps: false }` option from the `msgpackDecode` call in `decodeFirstTurn`. Replace the surrounding comments with an accurate description of the library's behavior:

> The `@msgpack/msgpack` library always returns plain JavaScript objects for msgpack maps (never `Map` instances). Integer keys in the msgpack payload are accepted by the default `mapKeyConverter` and are automatically coerced to string keys by JavaScript's object property semantics. No special decoder configuration is needed. The `|| fallback` (`payload["8"] || payload[8]`) is retained as a defensive measure but both forms resolve identically since integer property access on a plain object is equivalent to string access.

Update the pseudocode to:
```
payload = msgpackDecode(bytes)
```

---

## Issue #2: The spec describes `maybe_cache_metadata` as extracting metadata from "the first turn" but does not document the hot-path vs cold-path discrepancy for forked contexts

### The problem

Section 5.5 states that CXDB extracts and caches metadata from "the first turn's msgpack payload key 30." The spec's description of `client_tag` resolution in Section 5.2 mentions "stored metadata (extracted from the first turn's msgpack payload key 30, stored in context_metadata_cache)."

However, examining the CXDB source (`store.rs` lines 158-178), there are two distinct code paths for populating the `context_metadata_cache`:

1. **Hot path (`maybe_cache_metadata`):** Called on `append_turn`. For a **new context** (depth=0), this extracts metadata from the RunStarted turn's payload — which has key 30 (context_metadata) with `client_tag = "kilroy/{run_id}"`. For a **forked context**, this extracts metadata from the **first appended turn to the child context** (depth = base_depth + 1), which is a Kilroy application turn (e.g., `StageStarted`, `Prompt`). The Go client types confirm this convention: `conversation.go` line 165 says "By convention, only included in the first turn (depth=1) of a context."

2. **Cold path (`load_context_metadata`):** Called on cache miss (e.g., after CXDB restart). This calls `get_first_turn(context_id)`, which walks the parent chain to depth=0 — crossing context boundaries for forked contexts. For a forked context, this finds the **parent's RunStarted turn**, not the child's first appended turn.

The two paths may extract metadata from **different turns** with **different payloads** for the same forked context. If Kilroy embeds context metadata (key 30) in the child's first appended turn (as the convention suggests), both paths would find metadata — but potentially with different `client_tag`, `title`, or `labels` values. If Kilroy does NOT embed key 30 in the child's first turn (relying only on the RunStarted turn), then `maybe_cache_metadata` returns `None` for the forked context, and the metadata cache stores `None` — but after a CXDB restart, `load_context_metadata` would find the parent's RunStarted metadata, producing a different cache state.

This discrepancy is invisible during normal operation (CXDB doesn't restart often), but an implementer testing against a freshly-restarted CXDB might observe different CQL search results than against a long-running instance where metadata was populated via the hot path.

The spec's `client_tag` stability requirement paragraph (Section 5.5) says "Kilroy must embed client_tag in the first turn's context metadata (key 30)" — but it does not clarify whether this means the depth-0 RunStarted turn or the first appended turn to each forked context. Kilroy needs to do both for consistency across CXDB restarts.

### Suggestion

Add a note in Section 5.5 (near the `client_tag` stability requirement) documenting the dual extraction paths in CXDB:

> **Metadata extraction asymmetry for forked contexts.** CXDB populates the `context_metadata_cache` via two paths: (1) on append, metadata is extracted from the first turn appended to the context (`maybe_cache_metadata` in `store.rs`), and (2) on cache miss (e.g., after CXDB restart), metadata is extracted from the depth-0 turn found by walking the parent chain (`load_context_metadata` → `get_first_turn`). For forked contexts, these paths read different turns — the child's first appended turn (path 1) vs the parent's RunStarted turn (path 2). Kilroy should embed `client_tag` in the context metadata (key 30) of the first turn appended to each forked context to ensure consistent metadata across both paths.

---

## Issue #3: The spec does not document that `get_before` with a `before_turn_id` referencing a turn from a **different** context produces unpredictable results

### The problem

Section 5.3 correctly documents: "The context_id parameter verifies the context exists but does not scope the before_turn_id traversal. CXDB resolves before_turn_id from a global turn table and walks parent_turn_id links without context boundary checks."

The spec uses this behavior intentionally in `fetchFirstTurn` for forked contexts (Section 5.5), where the parent chain crosses context boundaries to reach the parent's RunStarted turn. This is correct and safe when `before_turn_id` comes from the same context's response chain (the `next_before_turn_id` is derived from turns in the same parent chain).

However, the spec does not document what happens if an implementer accidentally passes a `before_turn_id` obtained from a **different** context (e.g., due to a bug where cursors from different contexts are mixed up). In CXDB's `get_before` (`turn_store/mod.rs` line 539-542), it resolves `before_turn_id` from the global `self.turns` map and starts walking from `before.parent_turn_id`. If the `before_turn_id` belongs to a different context entirely, the walk follows that unrelated context's parent chain, returning turns from the wrong context. The `context_id` parameter only verifies that the context exists — it does not filter or validate the returned turns.

This is a correctness hazard for the gap recovery pseudocode (Section 6.1), which tracks `lastSeenTurnId` per context. If an implementation bug causes context A's `lastSeenTurnId` to be used as `before_turn_id` when fetching context B's turns, the response would contain context A's turns — silently producing incorrect status data.

### Suggestion

Add a defensive programming note to Section 5.3 after the "Context scoping note":

> **Defensive note.** Because `before_turn_id` is resolved globally, callers must ensure that the cursor passed as `before_turn_id` originates from the same context's response chain. Mixing cursors across contexts produces silently incorrect results — the returned turns belong to the wrong context's parent chain. The gap recovery pseudocode (Section 6.1) maintains `lastSeenTurnId` per `(cxdb_index, context_id)` pair to prevent this. Implementers should assert that the cursor and context_id are from the same mapping.

---

## Issue #4: The holdout scenarios do not cover the forked-from-depth-0 fast-path guard added in v30

### The problem

The v30 acknowledgement notes that the `fetchFirstTurn` fast-path was updated to add a `depth == 0` guard for contexts forked from a depth-0 base turn. This guard is a specific edge-case handler:

```
IF headDepth == 0:
    response = fetchTurns(cxdbIndex, contextId, limit=1, view="raw")
    IF response.turns IS EMPTY:
        RETURN null
    IF response.turns[0].depth == 0:
        RETURN decodeFirstTurn(response.turns[0])
    -- Fall through to pagination
```

However, there is no holdout scenario testing this specific code path. The existing "Context matched to pipeline via RunStarted turn" scenario tests basic discovery but does not test the `headDepth == 0` fast-path, and no scenario exercises a forked context whose base turn is at depth 0. Without a scenario covering this, an implementer might omit the depth guard (returning whatever `limit=1` fetches without checking `depth == 0`) and no test would catch it.

### Suggestion

Add a holdout scenario:

```
### Scenario: Forked context with depth-0 base turn discovers RunStarted via pagination
Given a context was forked from the parent's RunStarted turn (base depth = 0)
  And the forked context has accumulated 50+ turns of its own (depths 1-50+)
  And the forked context's head_depth is 0 (inherited from the base turn)
When the UI runs fetchFirstTurn for this context
Then the fast-path fetches 1 turn (limit=1) and gets the newest turn (depth 50+)
  And the depth != 0 guard triggers a fall-through to the pagination loop
  And the pagination loop walks backward to find the depth-0 RunStarted turn
  And the context is correctly mapped to the parent's pipeline
```
