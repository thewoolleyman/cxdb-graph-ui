# CXDB Graph UI Spec — Critique v11 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v10 critique raised 3 issues, all applied: (1) separate per-context and merge precedence maps to prevent complete→running regression; (2) scoped error heuristic per-context to avoid cross-instance turn_id comparison; (3) extracted error heuristic to a post-merge `applyErrorHeuristic` function, eliminating the missing `turnCache` parameter and per-context map contamination. The spec is now at a high level of maturity after 10 revision rounds.

---

## Issue #1: Detail panel sorts cross-instance turns by `turn_id` — the same bug fixed in the error heuristic

### The problem

The v10 critique correctly identified that `turn_id` comparison across CXDB instances is meaningless (CXDB instances have independent, monotonically-increasing turn ID counters with no temporal relationship). This was fixed for the error heuristic by scoping `getMostRecentTurnsForNodeInContext` to a single context.

However, the exact same problem persists in Section 7.2 (line 716):

> "When the selected node has matching turns across multiple contexts (e.g., parallel branches), turns from all matching contexts are combined and sorted newest-first by `turn_id` (using numeric comparison)."

When contexts span multiple CXDB instances, sorting the combined turns by `turn_id` produces arbitrary interleaving, not temporal ordering. The same scenario from v10 applies: CXDB-0 running for weeks (turn IDs in the 50,000s) and CXDB-1 freshly started (turn IDs in the 100s) would display all of CXDB-0's turns at the top of the detail panel as "most recent," regardless of when they actually occurred.

For parallel branches on the **same** CXDB instance, turn IDs from different contexts are also non-comparable (turn IDs are allocated from a global counter shared across all contexts on the instance). Context A might have turns 100, 150, 200 while context B has 120, 160, 210 — the temporal interleaving depends on when each context wrote, not on the ID magnitude.

### Suggestion

Group turns by context in the detail panel rather than interleaving them by `turn_id`. Two approaches:

**(a) Context-grouped display.** Show a collapsible section per context with turns sorted by `turn_id` within each section (safe because intra-context turn IDs are monotonic). Each section is labeled with the context ID and CXDB instance index. This makes the provenance clear and avoids cross-context ordering entirely.

**(b) Sort by `depth` within context, interleave by context `last_activity_at`.** For each context, use the `last_activity_at` field from the context list response (or `head_turn_id` as a proxy for recency) to determine which context contributed the most recent activity, and present that context's turns first. Within each context's turns, order by `turn_id` (which is safe intra-context).

Option (a) is simpler and avoids all ordering ambiguity. Update Section 7.2 to specify grouped display instead of combined+sorted.

## Issue #2: Gap recovery condition assumes consecutive `turn_id` within a context

### The problem

Section 6.1's gap recovery (line 515) uses this condition:

> "the oldest fetched turn has `turn_id > lastSeenTurnId + 1`, using numeric comparison"

This assumes turn IDs are consecutive within a context. They are not. CXDB allocates turn IDs from a global counter shared across all contexts on the instance. The spec's own example data confirms this: a context with `head_depth: 100` (100 turns) has `head_turn_id: "6064"` — if turn IDs were per-context consecutive, the head turn ID would be ~100, not 6064.

In a system with multiple active contexts writing concurrently, a single context's turn IDs will be sparse (e.g., 5964, 5970, 5978, 5985, ...). The gap between consecutive intra-context turns is proportional to the number of active contexts.

Concrete scenario: `lastSeenTurnId = 5964` (from previous poll). The new fetch returns 10 turns, oldest being turn_id 5970. The gap check fires: `5970 > 5964 + 1` → `5970 > 5965` → true. But there is no actual gap — turn IDs 5965–5969 simply belong to other contexts. The gap recovery then paginates backward from turn 5970, eventually finding turn 5964, and stops. The result is functionally correct but wasteful: **an extra paginated request on virtually every poll cycle for every context**, doubling request volume in steady state.

With many active pipelines and contexts, this adds up. At 3-second poll intervals with N active contexts across M CXDB instances, this means N×M unnecessary pagination requests every 3 seconds.

### Suggestion

Replace the `turn_id > lastSeenTurnId + 1` heuristic with a condition that doesn't assume consecutive IDs. Two options:

**(a) Use `head_turn_id` from the context list.** The context list response includes `head_turn_id` for each context. Compare this against the `lastSeenTurnId` cursor. If `head_turn_id > lastSeenTurnId` (there are new turns) AND the fetched batch doesn't contain `lastSeenTurnId` (check if any turn has `turn_id == lastSeenTurnId` or the oldest fetched turn has `turn_id > lastSeenTurnId`), then there's a real gap:

```
headTurnId = context.head_turn_id  -- from step 1's context list
oldestFetched = turns[turns.length - 1].turn_id
IF lastSeenTurnId IS NOT null
   AND oldestFetched > lastSeenTurnId
   AND response.next_before_turn_id IS NOT null:
    -- Turns exist between lastSeenTurnId and oldestFetched that weren't fetched.
    -- Run gap recovery.
```

The key difference: this checks whether `next_before_turn_id` is non-null (meaning there are older turns we haven't fetched) AND the oldest fetched turn is beyond our cursor. When turn IDs are merely sparse but no turns were missed, the `limit=100` fetch will contain `lastSeenTurnId` itself (since 100 turns back is more than enough for a 3-second window), and the condition won't fire.

**(b) Use `head_depth` delta.** Track the previous `head_depth` per context. If the delta (new_depth - old_depth) exceeds the fetch limit, a gap exists. This avoids turn_id comparison entirely but requires tracking an additional value per context.

Option (a) is more precise and requires no additional tracked state beyond what already exists.

## Issue #3: `hasLifecycleResolution` not propagated through `mergeStatusMaps` — dead condition in `applyErrorHeuristic`

### The problem

The `mergeStatusMaps` function (lines 631–645) initializes each node's `hasLifecycleResolution` to `false` and never updates it from per-context maps:

```
merged[nodeId] = NodeStatus { status: "pending", ..., hasLifecycleResolution: false }
FOR EACH contextMap IN perContextMaps:
    -- hasLifecycleResolution is never read or propagated
```

This means `mergedMap[nodeId].hasLifecycleResolution` is **always false** for every node.

The `applyErrorHeuristic` then checks:

```
IF mergedMap[nodeId].status == "running"
   AND NOT mergedMap[nodeId].hasLifecycleResolution:
```

The `NOT mergedMap[nodeId].hasLifecycleResolution` condition is dead code — it always evaluates to `NOT false` = `true`. The guard provides no protection.

This happens to produce correct behavior because a node can only be "running" in the merged map if at least one per-context map has it as "running," and within a per-context map, "running" implies no lifecycle resolution (since `StageFinished`/`StageFailed` would have set status to "complete"/"error" respectively). So the dead condition is accidentally correct — but it's misleading for an implementing agent who might:

1. Read the condition and assume it provides meaningful gating, then be confused when debugging why it never triggers.
2. Attempt to "optimize" by removing the seemingly-redundant check, then later break behavior if the merge logic changes.
3. Attempt to "fix" the propagation, potentially introducing unintended interactions.

### Suggestion

Either propagate `hasLifecycleResolution` through the merge (set to `true` if ANY per-context map has it true for that node), or remove the check from `applyErrorHeuristic` and add a comment explaining why it's unnecessary. The propagation approach is cleaner:

In `mergeStatusMaps`, after the inner loop for each node:

```
FOR EACH contextMap IN perContextMaps:
    IF contextMap[nodeId].hasLifecycleResolution:
        merged[nodeId].hasLifecycleResolution = true
```

This makes the guard in `applyErrorHeuristic` meaningful: if all contexts have lifecycle resolution for a node (all show complete or error), the heuristic correctly skips it. In the current code, this case doesn't arise (all-resolved nodes merge to "complete" or "error", not "running"), but propagating the field is defensive against future changes and makes the pseudocode self-documenting.
