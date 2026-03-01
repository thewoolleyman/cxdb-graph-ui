# CXDB Graph UI Spec — Critique v13 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v12 critique raised 3 issues, all applied: (1) corrected turn ordering from newest-first to oldest-first across 6 spec sections, fixing index references in `fetchFirstTurn` and gap recovery; (2) added `limit=10000` to context list fetches to prevent pipeline discovery from missing Kilroy contexts; (3) qualified the CORS statement to distinguish REST endpoints (no CORS) from the SSE endpoint (`Access-Control-Allow-Origin: *`). The spec is now on its 12th revision. This critique continues cross-referencing the spec against the CXDB server source (`/Users/cwoolley/workspace/cxdb/server/src/http/mod.rs`).

---

## Issue #1: `view=typed` turn fetch fails entirely if any turn's type is unregistered — spec has no error handling for this failure mode

### The problem

The spec's turn fetch (Section 5.3) uses the default `view=typed` response format. The CXDB typed view requires every turn's declared type to exist in the type registry. If **any single turn** in a context has a type that is not registered, the **entire turn fetch request fails**.

Evidence from CXDB source (`http/mod.rs` lines 847–850):

```rust
if view == "typed" || view == "both" {
    let desc = registry
        .get_type_version(&decoded_type_id, decoded_type_version)
        .ok_or_else(|| StoreError::NotFound("type descriptor".into()))?;
```

The `?` operator on line 850 propagates the error immediately, aborting the per-turn loop (line 806: `for item in turns.iter()`) and returning an error HTTP response for the entire request. There is no fallback that skips the offending turn — it is a hard failure.

This matters for three reasons:

**(a) The spec's polling error handling only covers 502 (instance unreachable).** Section 6.1 step 1 says: "If an instance is unreachable (502), skip it and retain its per-context status maps from the last successful poll." A type registry failure returns 404 or 500, not 502. The spec does not specify behavior for non-502 turn fetch errors. An implementing agent would likely treat them as unhandled exceptions, potentially crashing the poll cycle or silently losing status for that context.

**(b) The failure is per-context but affects the entire context.** If context 33 has 100 turns and turn #47 references an unregistered type, fetching turns for context 33 fails entirely — not just turn #47. The status overlay for that context goes dark until the type registry is fixed.

**(c) Practical scenarios where this occurs:**
- **Development:** An implementer testing the UI before Kilroy's type registry bundle is published. All turn fetches fail, but the error message ("type descriptor not found") gives no hint that the registry is the problem.
- **Version mismatch:** A newer Attractor version writes a new type (e.g., `com.kilroy.attractor.AgentHandoff`) that isn't in the registry bundle the CXDB instance was initialized with.
- **Forked contexts:** If a Kilroy context was forked from a non-Kilroy context (inheriting parent turns with different types), the parent-chain turns would have unregistered types.

### Suggestion

Two changes:

1. **Document the type registry dependency.** Add a note to Section 5.3 or 5.4 explaining that the `view=typed` format requires the Kilroy type registry bundle (`kilroy-attractor-v1`) to be published to CXDB before the UI can fetch turns. Reference the bundle ID shown in the example response's `meta.registry_bundle_id` field.

2. **Generalize turn fetch error handling in the polling algorithm.** In Section 6.1 step 4, specify that per-context turn fetch failures (any non-200 response) are handled the same as instance-level failures: retain the context's cached turns and per-context status map from the last successful fetch, log a warning, and continue polling. This is a one-line addition to the polling step but prevents a single context's type registry issue from affecting the entire poll cycle.

---

## Issue #2: `fetchFirstTurn` crashes on empty contexts when `headDepth == 0`

### The problem

The `fetchFirstTurn` algorithm (Section 5.5) has a special case for `headDepth == 0`:

```
IF headDepth == 0:
    -- Context has exactly one turn; limit=1 returns it
    RETURN fetchTurns(cxdbIndex, contextId, limit=1).turns[0]
```

The comment says "exactly one turn," but `headDepth == 0` is ambiguous. A context that has just been created but has no turns yet also has `head_depth: 0` and `head_turn_id: "0"` (CXDB uses turn ID 0 as the sentinel for "no head"). The `fetchTurns` call for an empty context returns an empty `turns` array, and `turns[0]` is an out-of-bounds access.

This race condition is narrow but real: between the moment Kilroy creates a context (with `client_tag: "kilroy/{run_id}"`) and appends the `RunStarted` turn, the context appears in the context list with `head_depth: 0`. If a poll cycle runs during this window, discovery calls `fetchFirstTurn`, hits the `headDepth == 0` branch, and crashes.

The general-case code path (the pagination loop) handles empty results correctly — it checks `IF response.turns IS EMPTY: BREAK` and returns `null` when `lastTurns IS null`. The `headDepth == 0` special case bypasses this safety.

### Suggestion

Guard the `headDepth == 0` branch against empty results:

```
IF headDepth == 0:
    response = fetchTurns(cxdbIndex, contextId, limit=1)
    IF response.turns IS EMPTY:
        RETURN null
    RETURN response.turns[0]
```

Alternatively, remove the special case entirely and let all contexts go through the general pagination loop, which already handles empty results. The special case is a micro-optimization (avoids setting up a loop variable and cursor) but the general case with `limit=1` and an empty context would execute identically: one request, empty response, break, return null.

---

## Issue #3: Gap recovery pagination is described in prose but lacks pseudocode

### The problem

Section 6.1 describes gap recovery in prose:

> "the poller issues additional paginated requests using `before_turn_id` to fetch the missing turns until `lastSeenTurnId` is reached or `next_before_turn_id` is null."

And later:

> "Gap recovery runs at most once per context per poll cycle and is bounded by the number of turns missed (typically one additional request per 100 missed turns)."

But no pseudocode is provided for the gap recovery pagination loop. Every other algorithm in the spec (pipeline discovery, `fetchFirstTurn`, `updateContextStatusMap`, `mergeStatusMaps`, `applyErrorHeuristic`) has explicit pseudocode. Gap recovery is the only algorithm described solely in prose, despite having non-trivial logic:

- It must paginate backward from `next_before_turn_id` until reaching `lastSeenTurnId`
- Recovered turns must be prepended to the main batch in oldest-first order
- The loop must terminate when `next_before_turn_id` is null (beginning of context)
- Each page uses `limit=100` (matching the main fetch) or some other value

An implementing agent would need to infer these details from the prose description and the gap detection condition pseudocode. The phrase "runs at most once per context per poll cycle" could be misread as "makes at most one additional request" (it means the gap recovery **procedure** runs once, but the procedure itself loops).

### Suggestion

Add pseudocode for the gap recovery loop, parallel to the existing gap detection condition:

```
-- Gap recovery: fetch turns between lastSeenTurnId and the main batch
recoveredTurns = []
cursor = response.next_before_turn_id
WHILE cursor IS NOT null:
    gapResponse = fetchTurns(cxdbIndex, contextId, limit=100, before_turn_id=cursor)
    IF gapResponse.turns IS EMPTY:
        BREAK
    recoveredTurns = gapResponse.turns + recoveredTurns  -- prepend (maintain oldest-first)
    -- Check if we've reached lastSeenTurnId
    oldestInGap = gapResponse.turns[0].turn_id
    IF oldestInGap <= lastSeenTurnId:
        BREAK
    cursor = gapResponse.next_before_turn_id

-- Prepend recovered turns to the main batch
turns = recoveredTurns + turns
```

Also clarify the "at most once" statement: "The gap recovery procedure runs at most once per context per poll cycle. Within the procedure, multiple paginated requests may be issued (one per 100 missed turns)."
