# CXDB Graph UI Spec — Critique v30 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-25

## Prior Context

The v29 cycle had two critics (opus and codex). All 6 issues were applied or deferred: opus's 4 issues (`view=raw` subsystem dependencies note, `is_live` resolution mechanism, `ContextMetadataUpdated` SSE event documentation, and a proposed holdout scenario for forked context discovery) and codex's 2 issues (HTML escaping for DOT attributes, explicit per-node `shape` guarantee for Kilroy DOT files). This critique is informed by detailed reading of the CXDB source (`server/src/http/mod.rs`, `server/src/store.rs`, `server/src/turn_store/mod.rs`, `server/src/cql/indexes.rs`, `server/src/events.rs`) and the Go client (`clients/go/events.go`), focusing on correctness of the UI's interaction with CXDB's turn store traversal and CQL search semantics.

---

## Issue #1: The `fetchFirstTurn` algorithm assumes `headDepth == 0` implies a non-forked context with at most one turn, but forked contexts created from a depth-0 base turn also have `headDepth == 0`

### The problem

Section 5.5's `fetchFirstTurn` has a fast-path for `headDepth == 0`:

```
IF headDepth == 0:
    response = fetchTurns(cxdbIndex, contextId, limit=1, view="raw")
    IF response.turns IS EMPTY:
        RETURN null
    RETURN decodeFirstTurn(response.turns[0])
```

The comment says "Context has at most one turn." However, examining `turn_store/mod.rs` line 336-344 (`create_context`), a forked context's `head_depth` is set to the base turn's depth:

```rust
let (head_turn_id, head_depth) = if base_turn_id == 0 {
    (0, 0)
} else {
    let turn = self.turns.get(&base_turn_id)...;
    (turn.turn_id, turn.depth)
};
```

If Kilroy forks a context from a turn at depth 0 (the RunStarted turn itself), the child context has `head_depth == 0` even though it will later accumulate its own turns at depths 1, 2, 3, etc. The `fetchFirstTurn` fast-path would fetch only 1 turn (`limit=1`), which would be the most recent turn (CXDB's `get_last` returns the most recent `limit` turns from the head). For a forked context with hundreds of turns whose `head_depth` started at 0, this would return the newest turn, not the depth-0 turn.

In practice, this edge case is unlikely to be triggered — Kilroy typically forks at a depth well above 0 (the fork happens after the pipeline has been running for some time). But the spec's comment "Context has at most one turn" is incorrect, and an adversarial or unusual scenario (forking directly from the RunStarted turn) could cause `fetchFirstTurn` to return the wrong turn.

The fast-path still works correctly in the common case because:
1. Non-forked contexts with `headDepth == 0` truly have at most one turn (the RunStarted itself), and `limit=1` fetches it.
2. Forked contexts from depth-0 would return their newest turn, but `get_last` walks the parent chain, and for a forked context, the depth-0 turn IS the parent's RunStarted. Wait — actually, `get_last(context_id, 1)` walks backward from `head_turn_id`. If the context has appended turns beyond the fork point, `head_turn_id` points to the newest turn, and `limit=1` returns only that one. The depth-0 turn would not be returned.

So the correctness concern is real: a forked-from-depth-0 context with its own turns would NOT correctly discover the RunStarted via the fast-path.

### Suggestion

Update the `headDepth == 0` fast-path comment and logic:

1. Change the comment to: "If headDepth == 0, the first turn is either at the head or one hop away. Fetch limit=1 and check if depth == 0."
2. If the returned turn has `depth != 0` (which could happen for forked-from-depth-0 contexts with many appended turns), fall through to the normal pagination path rather than returning it directly.

Alternatively, remove the fast-path entirely — the general pagination loop already handles `headDepth == 0` correctly (it would fetch up to 100 turns and find depth-0 in the first page).

---

## Issue #2: The spec does not document that `context_to_json` filters out empty `client_tag` strings, which affects the context list fallback path's prefix filter

### The problem

Section 5.2 documents the context list fallback response and states that `client_tag` is an "optional string." The spec's `discoverPipelines` pseudocode (Section 5.5) checks:

```
IF context.client_tag IS null OR NOT context.client_tag.startsWith("kilroy/"):
```

However, examining `context_to_json` in `http/mod.rs` line 1320-1324:

```rust
let client_tag = stored_metadata
    .as_ref()
    .and_then(|m| m.client_tag.clone())
    .or_else(|| session.as_ref().map(|s| s.client_tag.clone()))
    .filter(|t| !t.is_empty());
```

The `.filter(|t| !t.is_empty())` call means empty-string `client_tag` values are converted to `None` (and thus omitted from the JSON). This is a defensive measure in CXDB — binary protocol clients that connect with an empty `client_tag` string will have their tag filtered to null in the response.

The spec's pseudocode handles this correctly (it checks for null), but an implementer reading the spec might not realize that `client_tag` can never be an empty string `""` in the response — it's always either a non-empty string or absent. If an implementer adds a defensive `client_tag == ""` check, it's harmless but dead code. More importantly, the spec's description of `client_tag` as "optional string" is technically correct but incomplete — it should note that CXDB never returns empty-string tags in either endpoint.

This is a minor documentation gap, not a correctness issue.

### Suggestion

Add a brief note after the `client_tag` field description in Section 5.2:

> CXDB filters out empty-string `client_tag` values — both the context list endpoint (`context_to_json`'s `.filter(|t| !t.is_empty())`) and the CQL search endpoint omit `client_tag` when it is empty. The field is either a non-empty string or absent (null). The UI's prefix filter need not check for empty strings.

---

## Issue #3: The spec's `determineActiveRuns` algorithm uses `created_at_unix_ms` to pick the active run, but does not document the edge case where two runs of the same pipeline start in the same millisecond

### The problem

Section 6.1 step 3's `determineActiveRuns` pseudocode determines the active run by finding the highest `created_at_unix_ms` across contexts for each pipeline:

```
FOR EACH (runId, contexts) IN runGroups:
    maxCreatedAt = max(c.createdAt FOR c IN contexts)
    IF maxCreatedAt > highestCreatedAt:
        highestCreatedAt = maxCreatedAt
        activeRunId = runId
```

The `>` comparison means ties are broken by iteration order of `runGroups`, which is non-deterministic (it depends on the hash map implementation). If two runs of the same pipeline start in the same millisecond (e.g., automated CI triggering two runs nearly simultaneously), the active run selection is unpredictable and could flip between poll cycles if the hash map's iteration order changes.

In practice, `created_at_unix_ms` has millisecond granularity and two distinct pipeline runs starting in the same millisecond is extremely unlikely. Additionally, CXDB context IDs are monotonically increasing, so a tie-breaker using the highest `context_id` across each run's contexts would deterministically select the truly newest run. But the pseudocode does not implement this.

This is an edge case that is unlikely to affect real usage, but the spec should acknowledge it or specify a tie-breaking strategy.

### Suggestion

Add a tie-breaking clause to the `determineActiveRuns` pseudocode: when two runs have the same `maxCreatedAt`, break the tie by selecting the run whose contexts include the highest `context_id` (as a numeric value). Context IDs are allocated monotonically from a global counter (`turn_store/mod.rs` line 347-348: `context_id = self.next_context_id; self.next_context_id += 1`), so a higher context ID is guaranteed to be newer. This makes the active run selection fully deterministic.

Alternatively, add a documentation note that ties are non-deterministic but operationally irrelevant, since two runs starting in the same millisecond is not a supported scenario.

---

## Issue #4: The holdout scenarios do not cover the `cqlSupported` flag reset on reconnection — a CXDB instance upgraded from non-CQL to CQL-supporting version during a UI session

### The problem

Section 5.5 states: "The `cqlSupported` flag is checked on subsequent polls to skip the CQL attempt — it is reset when the CXDB instance becomes unreachable and then reconnects (since the instance may have been upgraded)."

This is a deliberate design decision that allows the UI to discover CQL support on a CXDB instance that was initially running an older version without CQL but was upgraded while the UI was running. The flag transitions are:

1. Initial state: `cqlSupported[i]` is unset (neither true nor false)
2. CQL search returns 404 → `cqlSupported[i] = false`
3. Instance becomes unreachable → flag is reset to unset
4. Instance reconnects → CQL search is retried

However, there is no holdout scenario testing this lifecycle. The existing scenarios test:
- "One of multiple CXDB instances unreachable" — tests partial connectivity, not CQL flag behavior
- CQL search is covered implicitly but the flag reset on reconnection is not

If an implementer forgets to reset the `cqlSupported` flag on reconnection, the UI will permanently use the slower fallback path for that instance, even if CXDB was upgraded. This is a silent performance regression, not a functional bug, but it violates the spec's stated behavior.

### Suggestion

Add a holdout scenario:

```
### Scenario: CQL support flag resets on CXDB instance reconnection
Given a CXDB instance initially runs an older version without CQL support
  And the UI's CQL search to that instance returned 404
  And the UI is using the context list fallback for that instance
When the CXDB instance becomes unreachable
  And then reconnects after being upgraded to a CQL-supporting version
Then the UI retries CQL search on the next poll cycle
  And discovers CQL is now supported
  And subsequent polls use CQL search instead of the fallback
```
