# CXDB Graph UI Spec — Critique v19 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v18 cycle had two critics (opus and codex) but has not yet been acknowledged or revised. Opus raised 3 issues: unreachable dead code in `fetchFirstTurn`, missing gap recovery holdout scenario, and a contradiction in detail panel context-section ordering (cross-instance `turn_id` comparison). Codex raised 3 issues: `/api/dots` response format inconsistency (array vs object), undefined node ID loading for inactive pipelines during polling, and graph ID extraction failing for `graph` or quoted names. This critique raises new issues not covered by v18.

---

## Issue #1: Merged `hasLifecycleResolution` flag suppresses error and stale heuristics for nodes active in parallel branches

### The problem

Section 6.2's `mergeStatusMaps` propagates `hasLifecycleResolution` from ANY per-context map to the merged map:

```
IF contextStatus.hasLifecycleResolution:
    merged[nodeId].hasLifecycleResolution = true
```

Both `applyErrorHeuristic` and `applyStaleDetection` then guard on this merged flag:

```
IF mergedMap[nodeId].status == "running"
   AND NOT mergedMap[nodeId].hasLifecycleResolution:
```

This creates a bug when a node has completed in one context but is actively failing in another (parallel branches). Example: context A completed the node (`StageFinished` → `hasLifecycleResolution = true`, status = complete). Context B is running the same node and has 5 consecutive `ToolResult` errors (status = running, `hasLifecycleResolution = false`). After merging: status = "running" (correct — `running > complete` in merge precedence), but `hasLifecycleResolution = true` (propagated from context A). The error heuristic skips the node because the merged flag is true, even though context B — the one causing the "running" status — has no lifecycle resolution and is clearly stuck in an error loop.

The same problem affects stale detection: if the pipeline stalls and context B's running node has no lifecycle resolution, stale detection skips it because context A's lifecycle resolution was propagated. The node displays as "running" indefinitely with no visual indication of the problem.

### Suggestion

The root cause is that `hasLifecycleResolution` is meaningful per-context but loses its semantics when OR'd across contexts. Two options:

**Option A (minimal change):** Change the merge to propagate `hasLifecycleResolution` only when ALL per-context maps have it set for the node. This way the heuristics fire if any branch lacks lifecycle resolution.

**Option B (more correct):** Run the error and stale heuristics per-context (before merging) rather than post-merge. Each context's status map would independently promote "running" → "error" or "running" → "stale" based on its own data, and the merge would then correctly reflect per-branch error/stale states. This aligns with the error heuristic's existing design of examining "each context's cached turns independently" — the per-context scoping just needs to extend to the promotion decision, not just the turn examination.

Also add a holdout scenario exercising this case — e.g., a parallel branch completing a node while another branch is stuck in an error loop on the same node.

---

## Issue #2: Gap recovery pagination has no iteration limit — a long outage can block the poller indefinitely

### The problem

Section 6.1's gap recovery pseudocode loops until `lastSeenTurnId` is reached or `next_before_turn_id` is null:

```
WHILE cursor IS NOT null:
    gapResponse = fetchTurns(cxdbIndex, contextId, limit=100, before_turn_id=cursor)
    ...
```

There is no maximum iteration count. If a CXDB instance was unreachable for a long time while an active pipeline generated thousands of turns, gap recovery could issue dozens of paginated requests (one per 100 turns) in a single poll cycle. During this time, the `setTimeout`-based scheduling means no other poll cycles run — the entire UI shows stale data for all pipelines across all CXDB instances until recovery completes. A single context with a large gap blocks status updates globally.

The spec acknowledges "multiple paginated requests may be issued (one per 100 missed turns)" but doesn't bound this. For a context with 5,000 turns accumulated during an outage, that's 50 sequential HTTP requests before the poll cycle can continue.

### Suggestion

Add a maximum page count to the gap recovery loop (e.g., 10 pages = 1,000 turns). If the limit is hit, advance `lastSeenTurnId` to the oldest recovered turn (accepting that some intermediate turns are lost) and note the truncation. The persistent status map ensures that any status promotions from the lost turns are not critical — the next poll cycle's 100-turn window will contain the most recent state, and lifecycle events that were lost will not cause regression (statuses are never demoted). Add a brief rationale explaining the tradeoff: bounded recovery time vs. potential loss of intermediate turns.

---

## Issue #3: `determineActiveRuns` fails when a previously-discovered context is absent from the current poll's context list

### The problem

The `determineActiveRuns` function (Section 6.1, step 3) iterates over `knownMappings` — a persistent cache of all ever-discovered contexts — and calls `lookupContext(contextLists, index, contextId)` to access `created_at_unix_ms`. But `contextLists` comes from step 1 of the current poll cycle, which skips unreachable instances.

When a CXDB instance is unreachable, step 1 says "skip it and retain its per-context status maps." But `contextLists` contains no data for that instance. `determineActiveRuns` then iterates `knownMappings`, finds contexts mapped to the unreachable instance, and calls `lookupContext` — which has no entry for those contexts. The spec does not define what `lookupContext` returns in this case.

The consequences depend on the implementation: a null reference could crash the poll cycle, or silently excluding those contexts could change which `run_id` is considered "active." If a pipeline's contexts are split across two instances and one goes down, the remaining instance's contexts alone determine the active run. If those contexts happen to be from an older run (with a lower `created_at_unix_ms`), the active run appears to change, triggering `resetPipelineState` — which clears all cached status maps and cursors. This is exactly the opposite of the intended "retain cached status during outages" behavior. When the instance recovers, the status map has been wiped and must be rebuilt from scratch.

### Suggestion

Define the behavior of `determineActiveRuns` when `lookupContext` fails. The simplest fix: only iterate over contexts whose CXDB instance was successfully polled in step 1. Contexts from unreachable instances are excluded from active-run determination entirely, and the `previousActiveRunIds` map is not updated for pipelines that have any unreachable-instance contexts. This preserves the existing active run determination and prevents spurious run-change resets. Add a comment in the pseudocode:

```
-- Only consider contexts from reachable instances this cycle.
-- Unreachable instances retain their cached per-context status maps (step 1)
-- but do not participate in active-run determination to prevent
-- spurious run changes from incomplete data.
IF index NOT IN reachableInstances:
    CONTINUE
```
