# CXDB Graph UI Spec — Critique v2 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v1 critique raised 10 issues. All were addressed: the status derivation algorithm was rewritten to use lifecycle turns (`StageStarted`/`StageFinished`/`StageFailed`) as primary signals with heuristic fallback. Multi-context merging was specified with explicit precedence. `run_id` is now used for run grouping. A `GET /dots/{name}/nodes` endpoint was added for server-side DOT attribute parsing. The initialization sequence was specified. A `GET /api/dots` endpoint was added. Multiple runs of the same pipeline now use only the most recent `run_id`.

---

## Issue #1: Status preservation on CXDB failure contradicts the polling algorithm

### The problem

Section 8.2 states: "When a CXDB instance is unreachable, the graph remains visible with the last known status from that instance." The holdout scenario "CXDB becomes unreachable mid-session" specifies: "the last known node status is preserved (not cleared)."

However, the polling algorithm in Section 6.1 rebuilds the status map from scratch every cycle. Steps 1–4 fetch contexts, fetch turns, build per-context maps, and merge — producing a new status map each cycle. If a CXDB instance returns 502, its contexts are not fetched, so nodes whose status derived solely from that instance's contexts would revert to "pending" in the newly built map.

The spec promises status preservation but the algorithm doesn't implement it. An implementing agent would either follow the algorithm (losing status on failure) or follow the holdout scenario (caching status), but cannot follow both without additional specification.

### Suggestion

Add explicit caching behavior to the polling algorithm. For example: "If fetching contexts or turns from a CXDB instance fails, retain the per-context status maps from the last successful poll for that instance. Only replace a per-context map when fresh data is successfully fetched." This aligns the algorithm with the stated UI behavior and holdout scenario.

## Issue #2: No guard against overlapping poll cycles

### The problem

Section 6.1 uses `setInterval` with a 3-second interval. If a CXDB instance responds slowly (>3 seconds), the next interval fires while the previous poll is still in flight. This creates concurrent polls that can:

1. Issue duplicate HTTP requests to the same CXDB instances
2. Race to update the status map, potentially applying stale data over fresh data
3. Overwhelm a slow CXDB instance with compounding requests

The spec doesn't address this. An implementing agent might use `setInterval` naively and encounter these issues.

### Suggestion

Specify one of:
1. **Skip-if-busy:** "If a poll cycle is still in progress when the next interval fires, skip that cycle." (simplest)
2. **Delay-after-completion:** Use `setTimeout` after each poll completes rather than `setInterval`. "The next poll starts 3 seconds after the previous poll completes."
3. **Cancel-and-restart:** Cancel the in-flight poll and start fresh.

Option 1 or 2 would be simplest and prevent request pile-up.

## Issue #3: `lastTurnId` in `mergeStatusMaps` is non-deterministic

### The problem

In the `mergeStatusMaps` function (Section 6.2), `lastTurnId` is set to whatever non-null value is encountered last during iteration over `perContextMaps`:

```
IF contextStatus.lastTurnId IS NOT null:
    merged[nodeId].lastTurnId = contextStatus.lastTurnId
```

This means the merged `lastTurnId` depends on the iteration order of context maps, which is not specified. For nodes that appear in multiple contexts (e.g., shared nodes before a parallel fork), the merged `lastTurnId` could arbitrarily come from any context.

Meanwhile, `toolName` is only updated when a higher-precedence status is found, so `lastTurnId` and `toolName` can come from different contexts, making the merged `NodeStatus` semantically incoherent.

### Suggestion

Either:
1. Track `lastTurnId` alongside status precedence (use the `lastTurnId` from whichever context provided the winning status).
2. Use the numerically highest `turn_id` across contexts (if turn IDs are comparable).
3. Document that `lastTurnId` in the merged map is not meaningful and should not be relied on. If it's only used for display in the detail panel, clarify that the detail panel shows per-context turns separately rather than using the merged `lastTurnId`.

## Issue #4: Tab switch clears status overlay unnecessarily

### The problem

Section 4.4 states: "Switching tabs fetches the DOT file fresh, re-renders the SVG, and clears the CXDB status overlay. The status overlay rebuilds on the next poll cycle."

This means switching to a tab and back creates a 0–3 second window where all nodes appear gray (pending), even when CXDB data for that pipeline was successfully polled moments ago. For an operator monitoring multiple pipelines, this flickering would be jarring and could momentarily hide an error state.

### Suggestion

On tab switch, immediately reapply the last known status map for the newly selected pipeline instead of clearing to pending. The status map should be retained per pipeline (keyed by DOT filename or graph ID). The next poll cycle will refresh it, but the user sees continuity rather than a gray flash.

## Issue #5: Discovery algorithm fetches first turn for every non-RunStarted context on every discovery pass

### The problem

Section 5.5's discovery algorithm caches the mapping for contexts whose first turn is `RunStarted`. But for contexts that are NOT Attractor pipeline contexts (e.g., plain CXDB contexts from other applications sharing the same instance), the algorithm fetches `limit=1, order=asc` on every discovery pass because:

```
IF key IN knownMappings:
    CONTINUE  -- already discovered
```

Only contexts that successfully match as `RunStarted` are added to `knownMappings`. Non-RunStarted contexts are never cached, so they're re-fetched every 3 seconds indefinitely.

If a CXDB instance has many non-Attractor contexts (hundreds or thousands), this creates significant unnecessary load — fetching the first turn of every unrelated context every poll cycle.

### Suggestion

Cache negative results too. When a context's first turn is not `RunStarted`, record it in `knownMappings` with a sentinel value (e.g., `null` or `"unknown"`). Skip these contexts on subsequent discovery passes. This is safe because the first turn of a context is immutable.
