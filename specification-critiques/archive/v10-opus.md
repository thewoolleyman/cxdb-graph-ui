# CXDB Graph UI Spec — Critique v10 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v9 critique raised 3 issues, all applied to the specification: (1) gap recovery's mixed-order batch broke `newLastSeenTurnId` cursor tracking — fixed with a pre-loop `max(turn_id)` computation and `CONTINUE` instead of `BREAK` for deduplication; (2) heuristic error status was permanent and blocked later `StageFinished` — fixed by adding `hasLifecycleResolution` so lifecycle turns unconditionally override status; (3) the error threshold was lifetime-total instead of recent-window — fixed by replacing `errorCount >= 3` with a `getMostRecentTurnsForNode` consecutive-error check.

---

## Issue #1: Per-context PRECEDENCE map contradicts prose and allows "complete" → "running" regression

### The problem

Section 6.2's prose states: "node statuses are **promoted** according to the precedence `pending < running < complete < error`. Statuses are never demoted."

This establishes a per-context promotion order where `complete` is higher than `running` — once a node is complete, it cannot regress to running within a single context.

But the PRECEDENCE map in `updateContextStatusMap` is:

```
PRECEDENCE = { "error": 3, "running": 2, "complete": 1, "pending": 0 }
```

Here `running (2) > complete (1)`, which is the **opposite** of the prose. The ELSE IF branch allows promotion when `PRECEDENCE[newStatus] > PRECEDENCE[existingMap[nodeId].status]`, so a "running" turn can override "complete."

This creates a concrete bug with the main-batch turn ordering. Turns arrive newest-first. Consider a node that completes normally:

1. `StageFinished` (turn_id 600, processed first): `hasLifecycleResolution = true`, status = "complete"
2. `StageStarted` (turn_id 500, processed second): not a lifecycle resolution type, falls to ELSE IF. `PRECEDENCE["running"] > PRECEDENCE["complete"]` → `2 > 1` → true. Status overridden to **"running"**.

The node reverts from "complete" to "running" because `StageStarted` has higher precedence than `StageFinished` in the code's map. The `hasLifecycleResolution` guard only protects against the heuristic — it does not prevent non-lifecycle turns from overriding lifecycle-resolved status via normal promotion.

Note: the `mergeStatusMaps` function correctly uses `running > complete` for cross-context merging (if any parallel branch is still running, the display should show running). But `updateContextStatusMap` applies per-context within a single execution flow where `complete` should be final.

### Suggestion

Use separate precedence maps for per-context promotion vs. cross-context merging:

```
-- Per-context: complete is higher than running (a node doesn't regress within one context)
CONTEXT_PRECEDENCE = { "error": 3, "complete": 2, "running": 1, "pending": 0 }

-- Cross-context merge: running is higher than complete (running branch takes visual priority)
MERGE_PRECEDENCE = { "error": 3, "running": 2, "complete": 1, "pending": 0 }
```

Additionally, guard the ELSE IF in `updateContextStatusMap` so that once `hasLifecycleResolution` is true, only lifecycle turns can modify the status:

```
ELSE IF NOT existingMap[nodeId].hasLifecycleResolution
    AND (newStatus == "error" OR CONTEXT_PRECEDENCE[newStatus] > CONTEXT_PRECEDENCE[existingMap[nodeId].status]):
        existingMap[nodeId].status = newStatus
```

This ensures that within a single context: (a) complete cannot regress to running, and (b) once a lifecycle turn has resolved the node, only another lifecycle turn can change it.

## Issue #2: `getMostRecentTurnsForNode` sorts by `turn_id` across CXDB instances with independent ID sequences

### The problem

Section 6.2's "Error loop detection heuristic" paragraph describes the `getMostRecentTurnsForNode` helper as: "scans the turn cache for turns matching the given `node_id`, collecting them newest-first across all contexts for the active pipeline."

"Newest-first" implies sorting by `turn_id`. But CXDB instances have independent, monotonically-increasing turn ID counters. Turn ID 500 on CXDB-0 and turn ID 5000 on CXDB-1 have no temporal relationship — the lower ID on instance 0 could be the more recent event.

When parallel branches of the same pipeline run across multiple CXDB instances (the spec's cross-instance merging scenario), `getMostRecentTurnsForNode` collects turns from all contexts across all instances. Sorting these by `turn_id` produces an arbitrary interleaving, not a temporal ordering. The "most recent 3 turns" could actually be the 3 turns with the highest IDs from whichever instance happens to have the largest counter, regardless of when they occurred.

Concrete example: CXDB-0 has been running for weeks (turn IDs in the 50,000s). CXDB-1 was just started (turn IDs in the 100s). A parallel branch on CXDB-1 hits 3 consecutive errors on node X (turn IDs 101, 102, 103). Meanwhile, CXDB-0 has successful turns for node X (turn IDs 50,001–50,010). The helper returns CXDB-0's turns as "most recent" (higher IDs), missing the error loop entirely.

### Suggestion

The CXDB HTTP turn response does not include a `created_at_unix_ms` timestamp on individual turns (only on contexts). Since temporal ordering across instances isn't available from the current API, the simplest correct approach is to scope the error loop heuristic per-context rather than cross-context:

> The `getMostRecentTurnsForNode` helper examines turns from **a single context's** cached turn batch. The error loop heuristic fires independently per context: if any context has 3 consecutive recent errors for a node, the node is flagged as "error" in that context's per-context status map (which then propagates through the merge).

This avoids cross-instance ordering entirely. A stuck error loop in any single context is sufficient to flag the node. Alternatively, if cross-context aggregation is desired, use each context's `head_turn_id` or `last_activity_at` from the context list as a proxy for recency, and interleave turns by context recency rather than by turn ID.

## Issue #3: `turnCache` referenced in `updateContextStatusMap` but not in function signature

### The problem

The `updateContextStatusMap` function signature is:

```
FUNCTION updateContextStatusMap(existingMap, dotNodeIds, turns, lastSeenTurnId):
```

But the error loop heuristic within the function body calls:

```
recentTurns = getMostRecentTurnsForNode(turnCache, nodeId, count=3)
```

`turnCache` is not a parameter. It refers to the per-pipeline turn cache from Section 6.1 step 5, but the pseudocode doesn't pass it in. An implementing agent would need to either add `turnCache` as a parameter or restructure the code to access it as module-level state.

Beyond the missing parameter, there is an architectural inconsistency: `updateContextStatusMap` runs per-context (producing per-context status maps), but the heuristic reads from `turnCache` which contains turns from **all** contexts for the pipeline. This means the heuristic fires once per context invocation but examines the same cross-context data each time. If the heuristic determines a node should be "error" based on turns from context B, it will set that status in context A's per-context map — even if context A has no errors for that node. After the merge, the status is correct (error wins), but the per-context maps are contaminated with decisions based on other contexts' data.

### Suggestion

Either:

**(a)** Add `turnCache` to the function signature and document that the heuristic intentionally reads cross-context data:

```
FUNCTION updateContextStatusMap(existingMap, dotNodeIds, turns, lastSeenTurnId, turnCache):
```

**(b)** Move the heuristic out of `updateContextStatusMap` and into a post-merge step in Section 6.1. Run it once per pipeline per poll cycle against the merged status map, after step 6's merge. This avoids the per-context contamination and makes the data flow explicit:

```
6a. Run updateContextStatusMap per context (no heuristic)
6b. mergeStatusMaps across active-run contexts
6c. Run error loop heuristic against merged map + turnCache
```

Option (b) is cleaner architecturally and naturally pairs with Issue #2's suggestion to scope the heuristic per-context — if moved to a post-merge step, it can examine each context's turns independently and flag the merged node if any context shows an error loop.
