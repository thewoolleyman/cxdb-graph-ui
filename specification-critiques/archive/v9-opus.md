# CXDB Graph UI Spec — Critique v9 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v8 critique raised 3 issues, all applied to the specification: (1) an explicit "Determine active run per pipeline" step was added to Section 6.1 (step 3) to filter contexts by `run_id`, implementing the "most recent run" rule; (2) a "Gap recovery" mechanism was added to Section 6.1 to fill missed turns after CXDB outages via backward pagination; (3) the `lastTurnId` null guard in `updateContextStatusMap` was replaced with a numeric comparison so it advances correctly across poll cycles.

---

## Issue #1: Gap recovery prepend breaks `newLastSeenTurnId` cursor tracking

### The problem

Section 6.1's gap recovery specifies: "The recovered turns are prepended (in oldest-first order) to the context's turn batch before step 5 caches them and step 6 processes them for status derivation."

This produces a combined batch ordered: `[gap_oldest, ..., gap_newest, main_newest, ..., main_oldest]`.

Section 6.2's `updateContextStatusMap` sets `newLastSeenTurnId` on the first iteration of the loop (the comment explains "first iteration only, since turns are newest-first"). But with gap recovery turns prepended in oldest-first order, the first turn in the combined batch is the **oldest** gap turn — not the newest main-batch turn.

Concrete example:

1. Poll N: processes turns up to `lastSeenTurnId = 1000`.
2. CXDB outage; pipeline generates turns 1001–1300.
3. Poll N+K: main batch fetches turns 1201–1300 (newest-first). Gap recovery fetches turns 1001–1200.
4. Combined batch: `[1001, 1002, ..., 1200, 1300, 1299, ..., 1201]`.
5. `updateContextStatusMap` iterates: first turn is 1001. `newLastSeenTurnId` is set to `1001`.
6. All turns are processed (none ≤ `lastSeenTurnId` of 1000). Returns `newLastSeenTurnId = 1001`.
7. Poll N+K+1: `lastSeenTurnId = 1001`. Fetches turns 1301+, but also re-processes turns 1002–1300 from the next batch because the cursor is set too low.

The cursor should advance to 1300 (the newest turn), but it advances to 1001 (the oldest gap turn). Every subsequent poll re-processes hundreds of already-seen turns until the cursor gradually catches up, inflating `turnCount` and `errorCount` on `NodeStatus` entries.

### Suggestion

Either (a) process the combined batch in a specific order that respects the cursor logic, or (b) compute `newLastSeenTurnId` independently of iteration order. The simplest fix is to compute `newLastSeenTurnId` before the loop:

```
-- Compute the newest turn ID in the combined batch (handles any ordering)
newLastSeenTurnId = lastSeenTurnId
FOR EACH turn IN turns:
    IF lastSeenTurnId IS null OR turn.turn_id > lastSeenTurnId:
        IF newLastSeenTurnId == lastSeenTurnId OR turn.turn_id > newLastSeenTurnId:
            newLastSeenTurnId = turn.turn_id
```

Or more simply: `newLastSeenTurnId = max(turn.turn_id for turn in turns)` when the batch is non-empty, computed before the main processing loop. The deduplication `BREAK` should also be changed to `CONTINUE` (since the combined batch is no longer sorted newest-first, older turns may appear after newer ones).

## Issue #2: Heuristic error status is permanent and blocks later StageFinished

### The problem

Section 6.2's heuristic fires at the end of each `updateContextStatusMap` call:

```
FOR EACH nodeId IN dotNodeIds:
    IF existingMap[nodeId].status == "running" AND existingMap[nodeId].errorCount >= 3:
        existingMap[nodeId].status = "error"
```

Once this fires, the node is "error". On the next poll cycle, if a `StageFinished` turn arrives for that node, it produces `newStatus = "complete"`. But the promotion rule `PRECEDENCE[newStatus] > PRECEDENCE[existingMap[nodeId].status]` evaluates `complete (1) > error (3)` → false. The status stays "error."

This scenario is realistic: an agent encounters 3+ tool errors on a node (e.g., compilation failures while iterating on code), then fixes the issue and the node completes successfully. If the errors and the `StageFinished` land in different poll batches (3 seconds apart), the heuristic fires between them, permanently trapping the node at "error" status. The operator sees a red node for a stage that actually succeeded.

The definitive lifecycle signal (`StageFinished`) should always be authoritative over the heuristic, but the promotion-only rule with `error > complete` prevents this.

### Suggestion

Make `StageFinished` authoritative by allowing it to override heuristic error status. One approach: add a flag to `NodeStatus` that distinguishes heuristic errors from lifecycle errors:

```
TYPE NodeStatus:
    ...
    errorSource: "lifecycle" | "heuristic" | null
```

When processing a `StageFailed` turn, set `errorSource = "lifecycle"`. When the heuristic fires, set `errorSource = "heuristic"`. Then modify the promotion rule so that `StageFinished` can override heuristic errors but not lifecycle errors:

```
IF typeId == "com.kilroy.attractor.StageFinished":
    IF existingMap[nodeId].status != "error"
       OR existingMap[nodeId].errorSource == "heuristic":
        existingMap[nodeId].status = "complete"
        existingMap[nodeId].errorSource = null
```

Alternatively, a simpler approach: skip the heuristic for nodes that already have a `StageFinished` turn recorded. Track this with a `hasLifecycleResolution` boolean on `NodeStatus`, set to `true` when `StageFinished` or `StageFailed` is processed. The heuristic only fires for nodes where `hasLifecycleResolution` is false.

## Issue #3: Error heuristic threshold is lifetime-total, not recent-window

### The problem

The holdout scenario "Agent stuck in error loop" specifies: "the most recent 3+ turns on a node have `is_error: true`" — describing a window of consecutive recent errors indicating the agent is stuck.

The spec's implementation accumulates `errorCount` across all poll cycles (it is never reset except on run change) and checks `errorCount >= 3`. This fires when a running node has 3 total errors over its entire lifetime, regardless of how many successful turns occurred between them. A node with 100 successful tool calls and 3 errors spread across them would trigger the heuristic, even though the agent is clearly making progress.

This is a semantic mismatch. The holdout scenario describes detecting an active error loop (consecutive recent failures). The spec implements a lifetime error counter that becomes increasingly likely to fire as a node runs longer, even when the agent is functioning normally.

### Suggestion

Replace the lifetime `errorCount >= 3` threshold with a check against recent consecutive errors. Since the detail panel turn cache (Section 6.1, step 5) stores raw turns from the most recent fetch, the heuristic can examine recent turns directly:

> **Heuristic fallback (error loop detection).** After status derivation, for each node with status "running" and no lifecycle resolution (`StageFinished` or `StageFailed`): examine the most recent 3 turns for that node (from the per-pipeline turn cache). If all 3 have `is_error == true`, promote the node to "error" status. This detects an active error loop without false-positiving on nodes with occasional errors over a long execution.

This also removes the need for the `errorCount` field on `NodeStatus` (or repurposes it as a display-only counter).
