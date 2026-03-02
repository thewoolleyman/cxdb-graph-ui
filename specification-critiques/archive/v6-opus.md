# CXDB Graph UI Spec — Critique v6 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v5 critique raised 4 issues, all valid. Three were applied to the specification: (1) a persistent status map with promotion-only semantics replaced the per-cycle rebuild, fixing the 100-turn window revert-to-pending bug; (2) the detail panel turn source was made explicit (filtered by `node_id`, multi-context turns combined, "No recent CXDB activity" message when turns fall outside the window); (3) graph ID parsing was specified with a regex, timing, and fallback. Issue #4 (holdout scenario gaps) was deferred as out of scope for spec revision.

---

## Issue #1: turnCount and errorCount double-count across poll cycles

### The problem

Section 6.2's `updateContextStatusMap` increments `turnCount` and `errorCount` for every turn processed:

```
existingMap[nodeId].turnCount++
IF turn.data.is_error == true:
    existingMap[nodeId].errorCount++
```

The status map is now persistent across poll cycles (per the v5 fix). Each poll fetches the 100 most recent turns. Since the polling interval is 3 seconds and an active node typically generates 0–5 turns per interval, approximately 95–100 of the fetched turns overlap with the previous poll's fetch window. These overlapping turns are re-processed and re-counted.

After N poll cycles with a mostly-stable turn window, `turnCount` is inflated by roughly N×. A node with 50 actual turns would show `turnCount ≈ 50 × N` after N polls.

More critically, `errorCount` suffers the same inflation. The error heuristic (promote running → error when `errorCount >= 3`) uses this inflated count. A node with a single `is_error: true` turn would reach `errorCount >= 3` after just 3 poll cycles, incorrectly triggering the error heuristic — even though only one error actually occurred.

### Suggestion

Track which turns have already been processed, either by:

1. **Recording the last-seen `turn_id` per context** and only processing turns newer than that cursor on subsequent polls. Since turns are ordered newest-first, stop processing when a turn's `turn_id` is ≤ the recorded cursor.
2. **Maintaining a `Set` of seen turn IDs** per context (bounded by the window size).

Option 1 is simpler and more memory-efficient. Update the pseudocode to accept and return a `lastSeenTurnId` per context, and add an early-exit condition:

```
IF turn.turn_id <= lastSeenTurnId:
    BREAK  -- already processed in a previous cycle
```

## Issue #2: lastTurnId ends up pointing to the oldest turn in the batch

### The problem

In `updateContextStatusMap`, `lastTurnId` is set unconditionally for every turn:

```
existingMap[nodeId].lastTurnId = turn.turn_id
```

Since turns are processed newest-first, the first assignment is the newest turn's ID, but subsequent assignments overwrite it with progressively older turn IDs. After the loop completes, `lastTurnId` holds the oldest turn's ID from the batch — the opposite of what the field name suggests.

This field is also copied during `mergeStatusMaps`, so the merged map inherits the incorrect value. While `lastTurnId` is not currently used for any logic beyond storage in `NodeStatus`, it would be a trap for any future use (e.g., pagination, change detection) and is misleading in the data model.

### Suggestion

Only set `lastTurnId` on the first encounter for each node (when the value is still null or when the new turn is more recent):

```
IF existingMap[nodeId].lastTurnId IS null:
    existingMap[nodeId].lastTurnId = turn.turn_id
```

Since turns are processed newest-first, the first assignment per node captures the most recent turn. Alternatively, remove `lastTurnId` from `NodeStatus` if it has no consumer.

## Issue #3: fetchFirstTurn uses limit=64 requiring many round trips

### The problem

Section 5.5's `fetchFirstTurn` paginates backward through the entire context history using `limit=64` chunks. For a context with 10,000 turns, this requires ~156 HTTP requests. The spec acknowledges this ("at most `ceil(headDepth / 64)` requests") and says it "completes in under 200 requests" for typical contexts.

However, CXDB's `limit` parameter accepts values up to 65,535 (Section 5.3: "1–65535"). A single request with `limit=65535` would fetch the entire context in one round trip for any context under 65,535 turns, reducing 156 requests to 1. For the rare context exceeding 65,535 turns, a second request suffices.

The discovery algorithm runs once per context, but with many contexts (e.g., 20+ parallel branches across multiple CXDB instances), the cumulative request count at `limit=64` becomes significant — potentially thousands of requests on first load.

### Suggestion

Use `limit=65535` (or at minimum `limit=10000`) in `fetchFirstTurn` instead of `limit=64`. This is a one-line change to the pseudocode that eliminates virtually all pagination in discovery. The tradeoff is larger response payloads per request, but since the response data is only used to extract the last element (the first turn), the excess data is discarded immediately.

Alternatively, since `head_depth` is available from the context list response, calculate the optimal limit: `limit = min(headDepth + 1, 65535)` to fetch exactly enough turns in one request.

## Issue #4: DOT attribute parsing scope is unspecified

### The problem

Section 3.2 says the server parses "node attribute blocks matching `nodeId [key="value", ...]` syntax" but does not specify:

1. **Unquoted attribute values** — DOT allows `shape=box` without quotes. The spec's description implies quoted values only (`key="value"`).
2. **Default/global attribute blocks** — DOT supports `node [shape=box]` to set defaults. The server must distinguish node definitions (`implement [shape=box, prompt="..."]`) from default blocks (`node [shape=box]`).
3. **Subgraph scope** — Nodes defined inside `subgraph` blocks need to be captured too.
4. **Attribute value escaping** — DOT uses `\"` and `\n` escapes within quoted strings. The spec mentions unescaping but doesn't specify which escape sequences are supported.

Since Attractor pipeline DOT files are compiler-generated with a consistent format, a full DOT parser is unnecessary. But the spec should state the expected format constraints so the implementing agent knows which subset to handle.

### Suggestion

Add a brief note to Section 3.2 stating:

1. The parser handles both quoted (`key="value"`) and unquoted (`key=value`) attribute values.
2. Global default blocks (`node [...]`, `edge [...]`, `graph [...]`) are excluded — only named node definitions are parsed.
3. Nodes inside subgraphs are included.
4. Supported escape sequences in quoted values: `\"` → `"`, `\n` → newline, `\\` → `\`. Other escapes are passed through verbatim.
