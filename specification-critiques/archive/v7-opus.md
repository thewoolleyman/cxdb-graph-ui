# CXDB Graph UI Spec — Critique v7 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v6 critique raised 4 issues, all applied to the specification: (1) turn deduplication via a `lastSeenTurnId` cursor prevents `turnCount`/`errorCount` inflation from re-processing overlapping turns; (2) `lastTurnId` assignment guarded by null check so it captures the newest turn per node; (3) `fetchFirstTurn` uses `min(headDepth + 1, 65535)` to fetch in a single request; (4) DOT attribute parsing rules enumerated (quoted/unquoted values, named nodes only, subgraph inclusion, escape sequences).

---

## Issue #1: turn_id comparison uses string ordering, breaking deduplication

### The problem

Section 6.2's deduplication check compares turn IDs with `<=`:

```
IF lastSeenTurnId IS NOT null AND turn.turn_id <= lastSeenTurnId:
    BREAK
```

Turn IDs are shown as string values throughout the spec (e.g., `"6066"`, `"6068"`). In JavaScript, the `<=` operator on strings uses lexicographic ordering, not numeric ordering. This breaks for IDs of different lengths:

- `"9" > "10000"` → `true` (lexicographic: "9" > "1")
- `"999" > "1000"` → `true`

If `lastSeenTurnId = "999"` and a new turn has `turn_id = "1000"`, the comparison `"1000" <= "999"` evaluates to `true`, causing the new turn to be incorrectly skipped as "already processed."

Similarly, the `newLastSeenTurnId` tracking (which records the newest turn ID) and the `lastTurnId` field on `NodeStatus` would be compared or used under the same assumption. The `fetchFirstTurn` algorithm's pagination loop isn't affected (it uses `next_before_turn_id` from the API response), but all client-side turn ID comparisons are broken.

### Suggestion

Specify that turn IDs must be compared numerically. Add a note to Section 6.2 before the algorithm:

> **Turn ID comparison.** CXDB turn IDs are numeric strings (e.g., `"6066"`). All turn ID comparisons in the UI must use numeric ordering: `parseInt(turn.turn_id, 10)`. The pseudocode `<=` operator on turn IDs denotes numeric comparison, not lexicographic string comparison.

Alternatively, convert turn IDs to integers on ingestion and store them as numbers throughout the client.

## Issue #2: Raw turn data for the detail panel is never stored

### The problem

Section 7.2 says the detail panel shows "recent CXDB turns for the selected node" sourced from "the most recent poll data (the 100 turns fetched per context in Section 6.1)." However, the polling algorithm in Section 6.1 describes fetching turns and passing them to `updateContextStatusMap`, which extracts status information and discards the raw turn objects. The spec never describes retaining the raw turn array.

An implementing agent following the spec would:

1. Fetch turns (Section 6.1, step 3)
2. Pass them to `updateContextStatusMap` (step 4), which iterates through turns to build status entries
3. Apply CSS classes (step 5)

After step 2, the raw turn data is no longer referenced. The detail panel (Section 7.2) needs the actual turn objects — `declared_type.type_id`, `data.tool_name`, `data.output`, `data.is_error` — but these are not stored anywhere by the polling algorithm. The `NodeStatus` type only stores aggregate data (`turnCount`, `errorCount`, `toolName`, `lastTurnId`), not the individual turns.

### Suggestion

Add an explicit data retention step to the polling algorithm. After Section 6.1 step 3, specify that the raw turns are cached per pipeline for detail panel use:

> **Turn cache for detail panel.** Each poll cycle, the raw turn arrays fetched in step 3 are stored in a per-pipeline turn cache, keyed by `(cxdb_index, context_id)`. This cache is replaced (not appended) on each successful fetch. The detail panel reads from this cache, filtering by `node_id`. When a CXDB instance is unreachable, its entries in the turn cache are retained from the previous successful fetch.

This makes the data flow explicit and tells the implementing agent exactly where the detail panel gets its data.

## Issue #3: Per-pipeline status map caching on tab switch is ambiguous

### The problem

Section 4.4 says: "If a cached status map exists for the newly selected pipeline (from a previous poll cycle), it is immediately reapplied to the new SVG." Section 6.1 says the poll cycle processes "each context matching the **active pipeline**" (emphasis mine). Section 6.2 describes per-context status maps that are persistent across polls.

The ambiguity: Does the poller fetch turns for all pipelines on every cycle, or only the active (displayed) pipeline?

If only the active pipeline is polled (Section 6.1 step 3 says "each context matching the active pipeline"), then switching to Pipeline B means Pipeline A stops receiving updates. When switching back to Pipeline A, the "cached status map" from Section 4.4 would be stale — reflecting the state when the user left that tab, not the current state.

If all pipelines are polled, then the phrase "matching the active pipeline" in Section 6.1 is misleading, and the poll cycle's cost scales with total contexts across all pipelines, not just the displayed one.

### Suggestion

Clarify the polling scope. The recommended approach (consistent with the "mission control" use case) is to poll all pipelines:

Add to Section 6.1: "The poll cycle processes all contexts that match any loaded pipeline, not just the active tab. Per-context status maps are maintained for all pipelines simultaneously. The `mergeStatusMaps` step produces a merged map for the active pipeline only (used for CSS updates), but per-context maps for inactive pipelines continue to accumulate, ensuring no data loss on tab switch."

Alternatively, if only the active pipeline should be polled (to minimize requests), state this explicitly and note that the "cached status map" on tab switch may be stale until the next poll cycle refreshes it.
