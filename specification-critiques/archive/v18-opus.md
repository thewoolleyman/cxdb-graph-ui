# CXDB Graph UI Spec — Critique v18 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v17 cycle had two critics (opus and codex). All 5 issues were applied: opus's 3 issues fixed SVG status class accumulation (added `classList.remove` before `classList.add`), eliminated the unnecessary second HTTP request in `fetchFirstTurn` by replacing the pagination loop with a single fetch, and tightened the error loop holdout scenario to specify ToolResult turns with interleaving. Codex's 2 issues added a `GET /dots/{name}/edges` endpoint as the data source for human gate choices, and added a holdout scenario for the non-200 turn fetch error handling path.

---

## Issue #1: `fetchFirstTurn` has unreachable dead code — trailing `RETURN null` after unconditional return

### The problem

The v17 revision replaced the `fetchFirstTurn` pagination loop with a single fetch for the `headDepth > 0` case. However, the trailing `RETURN null` from the old loop structure was not removed. The pseudocode (Section 5.5, line 491) reads:

```
    response = fetchTurns(cxdbIndex, contextId, limit=headDepth + 1)
    IF response.turns IS EMPTY:
        RETURN null
    RETURN response.turns[0]  -- oldest turn (oldest-first ordering) = first turn
    RETURN null
```

The final `RETURN null` on line 491 is unreachable — every code path above it either returns a value or returns null. An implementer reading this pseudocode may wonder if the trailing return is intended to handle an implicit edge case they're missing, or may interpret it as a sign that the pseudocode is incomplete. At minimum it's confusing; at worst it signals to a careful implementer that something was accidentally omitted during the refactor.

### Suggestion

Delete the unreachable `RETURN null` on line 491. The function's control flow is already complete: the `headDepth == 0` branch returns early, and the `headDepth > 0` branch returns either `null` (empty response) or `response.turns[0]`.

---

## Issue #2: Gap recovery has no holdout scenario — an implementer can skip it entirely and pass all tests

### The problem

Section 6.1 defines a gap recovery mechanism: when a context's fetched turns don't reach back to `lastSeenTurnId`, the poller issues additional paginated requests to fetch the missing turns. This prevents lifecycle events (e.g., `StageFinished`) from being permanently lost when CXDB is temporarily unreachable or when a node generates more than 100 turns between poll cycles.

This is a significant resilience feature with detailed pseudocode (lines 601–618), a gap detection condition, and integration with the turn cache and status derivation pipeline. However, no holdout scenario exercises it. An implementer could skip gap recovery entirely — never issuing paginated requests, never prepending recovered turns — and still pass every holdout scenario.

The closest existing scenario ("CXDB becomes unreachable mid-session") tests that the last known status is preserved during an outage and resumes with fresh data when the instance recovers. But it doesn't test that turns generated during the outage are retroactively fetched and processed. Without gap recovery, a node that completed (via `StageFinished`) during the outage window would remain "running" indefinitely after reconnection — the `StageFinished` turn would fall outside the 100-turn window and never be seen.

### Suggestion

Add a holdout scenario under "CXDB Status Overlay" that exercises gap recovery:

```
### Scenario: Lifecycle turn missed during poll gap is recovered
Given a pipeline run is active with node implement in running state
  And the UI has polled successfully, recording lastSeenTurnId for the context
  And the agent completes implement (StageFinished) and starts the next node
  And more than 100 turns are appended after StageFinished
When the UI polls CXDB on the next cycle
Then the initial fetch (limit=100) does not contain the StageFinished turn
  And gap recovery issues paginated requests to fetch turns back to lastSeenTurnId
  And the StageFinished turn is recovered and processed
  And implement is colored green (complete), not blue (running)
```

---

## Issue #3: Detail panel context-section ordering compares `turn_id` across CXDB instances despite the spec warning this is meaningless

### The problem

Section 7.2 defines how context sections are ordered in the detail panel:

> "Sections are ordered by recency: for each context that has matching turns, compute the highest `turn_id` among its turns for the selected node. The context with the highest such `turn_id` appears first."

But two sentences later, the same paragraph warns:

> "When contexts span multiple CXDB instances, sections from different instances are not interleaved by `turn_id` — CXDB instances have independent turn ID counters with no temporal relationship, so cross-instance `turn_id` comparison would produce arbitrary ordering rather than temporal ordering."

The ordering algorithm and the warning contradict each other. The algorithm says "compute the highest `turn_id` ... The context with the highest such `turn_id` appears first" — this is a cross-context comparison that doesn't distinguish between same-instance and cross-instance contexts. When a node has activity in contexts on different CXDB instances (e.g., parallel branches written to separate servers), the algorithm compares turn IDs from independent counters, producing the exact "arbitrary ordering" the spec warns about.

The spec correctly identifies the problem but doesn't fix the algorithm. An implementer following the pseudocode literally will compare turn IDs across instances and get non-deterministic section ordering — contexts from an instance with a higher counter baseline will always appear first regardless of actual temporal recency.

### Suggestion

Define a two-level sort: first by CXDB instance index (lower index first), then by highest `turn_id` within that instance. This groups contexts by instance (where turn ID comparison is meaningful) and uses a stable, deterministic ordering across instances. Alternatively, use `last_activity_at` from the context list response (a Unix millisecond timestamp that IS comparable across instances) as the cross-instance ordering key, falling back to `turn_id` only for same-instance comparisons.

Update the prose to match whichever approach is chosen, and remove the contradictory warning (since the algorithm would no longer perform the comparison it warns against).
