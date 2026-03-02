# CXDB Graph UI Spec — Critique v8 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v7 critique raised 3 issues, all applied to the specification: (1) turn ID comparisons now require `parseInt(turn.turn_id, 10)` for numeric ordering; (2) a per-pipeline turn cache (Section 6.1, step 4) stores raw turns for the detail panel; (3) the poller now fetches turns for all pipelines (not just the active tab), keeping per-context status maps current for inactive pipelines and preventing stale data on tab switch.

---

## Issue #1: Run ID filtering is missing from the polling algorithm

### The problem

Section 5.5 states: "When CXDB contains contexts from multiple runs of the same pipeline (same `graph_name`, different `run_id`), the UI uses only the most recent run." However, the polling algorithm in Section 6.1 never filters contexts by `run_id`.

Step 3 fetches turns "for each context matching any loaded pipeline" — matching is by `graph_name` only (via the discovery mapping). Step 5 runs `updateContextStatusMap` per context and then `mergeStatusMaps` across contexts "for the active pipeline." Neither step filters out contexts from older runs.

An implementing agent following the polling algorithm literally would:

1. Discover that contexts A1, A2 (run_id "ABC", completed last week) and B1 (run_id "DEF", started today) all map to `alpha_pipeline`
2. Fetch turns for A1, A2, and B1
3. Update per-context status maps for all three
4. Merge all three per-context maps into the display map

The result: nodes completed in run ABC would show as "complete" even though run DEF hasn't reached them yet — directly contradicting the holdout scenario "Second run of same pipeline while first run data exists."

The discovery algorithm records `run_id` per context, and Section 5.5 describes how to pick the most recent run, but there is no step in the polling algorithm (Section 6.1) or the merge function (Section 6.2) that uses this information to exclude old-run contexts.

### Suggestion

Add an explicit run filtering step to Section 6.1 between steps 2 and 3. After discovery, determine the active `run_id` for each pipeline:

> **Step 2b: Determine active run per pipeline.** For each loaded pipeline, group discovered contexts by `run_id`. The active run is the one with the highest `created_at_unix_ms` among its contexts. Contexts from non-active runs are excluded from steps 3–6. When the active `run_id` changes for a pipeline (a new run has started), reset all per-context status maps and `lastSeenTurnId` cursors for that pipeline's contexts.

Also update the `mergeStatusMaps` call in step 5 to clarify it only receives per-context maps from the active run.

## Issue #2: Extended CXDB outage creates an unrecoverable turn gap

### The problem

The polling algorithm fetches at most 100 turns per context per poll cycle, and the deduplication cursor (`lastSeenTurnId`) advances to the newest turn processed. Consider this sequence:

1. Poll N: Fetches turns 901–1000. `lastSeenTurnId` = 1000.
2. CXDB instance goes unreachable for several minutes. The pipeline continues executing, generating turns 1001–1300.
3. Poll N+K: CXDB comes back. Fetch `limit=100` returns turns 1201–1300 (newest-first).
4. The algorithm processes turns 1300 down to 1201 — all have `turn_id > lastSeenTurnId (1000)`, so all are processed.
5. `lastSeenTurnId` advances to 1300. Turns 1001–1200 are never processed.

If a `StageFinished` event for a node occurred in the 1001–1200 range, that node would remain stuck at "running" status forever. The persistent map never demotes statuses, and the lifecycle turn will never re-enter the 100-turn window.

This is not purely theoretical — CXDB instances going unreachable is explicitly handled by the spec (Section 6.1 step 1, Section 8.2), and pipeline nodes can generate hundreds of turns during active execution (e.g., a long `implement` node with many tool calls).

### Suggestion

Add a gap detection mechanism to Section 6.1. When the deduplication cursor detects a gap (the oldest turn in the fetched batch has `turn_id` much greater than `lastSeenTurnId`), the algorithm should fetch backward to fill the gap:

> **Gap recovery.** After step 3, if any context's fetched turns do not reach back to `lastSeenTurnId` (i.e., the oldest fetched turn has `turn_id > lastSeenTurnId + 1`), issue additional paginated requests using `before_turn_id` to fetch the missing turns until `lastSeenTurnId` is reached or `next_before_turn_id` is null. This ensures lifecycle events that occurred during a CXDB outage are not lost. Gap recovery runs at most once per context per poll cycle and is bounded by the number of turns missed (typically one additional request per 100 missed turns).

Alternatively, if the added complexity is undesirable, document this as a known limitation and suggest that operators restart the UI after extended CXDB outages to reset all cursors.

## Issue #3: NodeStatus.lastTurnId never updates after initial assignment

### The problem

Section 6.2's algorithm sets `lastTurnId` on `NodeStatus` with an `IS null` guard:

```
IF existingMap[nodeId].lastTurnId IS null:
    existingMap[nodeId].lastTurnId = turn.turn_id
```

Within a single poll batch this is correct — turns arrive newest-first, so the first encounter for a node captures the most recent turn ID.

But across poll cycles with deduplication, the guard prevents updates. On poll 1, `lastTurnId` for node "implement" is set to "998" (the newest turn for that node at the time). On poll 2, new turns 999–1050 are processed; turn 1045 is for "implement." Since `lastTurnId` is already "998" (not null), it is not updated to "1045."

The `lastTurnId` field is therefore frozen at the value from the first poll that ever processed activity for a given node. This also propagates through `mergeStatusMaps`, which copies `lastTurnId` from the winning context.

### Suggestion

Replace the null guard with a numeric comparison:

```
IF existingMap[nodeId].lastTurnId IS null
   OR turn.turn_id > existingMap[nodeId].lastTurnId:  -- numeric comparison
    existingMap[nodeId].lastTurnId = turn.turn_id
```

Since deduplication ensures only new turns (with higher turn IDs) are processed, and turns arrive newest-first, the first new turn for a node will always have a higher turn_id than the stored value. This makes `lastTurnId` always reflect the most recent turn for the node across all polls.
