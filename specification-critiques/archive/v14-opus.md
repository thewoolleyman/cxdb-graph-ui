# CXDB Graph UI Spec — Critique v14 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v13 critique raised 3 issues, all applied: (1) documented the `view=typed` type registry dependency and generalized per-context error handling beyond 502; (2) guarded the `fetchFirstTurn` `headDepth == 0` branch against empty contexts; (3) added explicit pseudocode for the gap recovery pagination loop and clarified the "at most once" statement. The spec is now on its 13th revision. This critique continues cross-referencing the spec against the CXDB server source.

---

## Issue #1: Error heuristic likely never fires — `getMostRecentTurnsForNodeInContext` returns ALL turn types, but only ToolResult turns have `is_error`

### The problem

The error loop heuristic in `applyErrorHeuristic` (Section 6.2) gets the 3 most recent turns for a node in a context and checks `ALL(turn.data.is_error == true FOR turn IN recentTurns)`. The helper `getMostRecentTurnsForNodeInContext` is described as scanning "turns matching the given `node_id`" — all turn types, not just ToolResult.

The problem is that during a typical error loop, Attractor generates interleaved turn types for the same node:

```
... → Prompt → ToolCall → ToolResult(is_error:true) → Prompt → ToolCall → ToolResult(is_error:true) → ...
```

The 3 most recent turns matching `node_id` for a node in an error loop would be something like:

```
1. ToolResult  (is_error: true)     ← most recent
2. ToolCall    (is_error: undefined)
3. Prompt      (is_error: undefined)
```

The `ALL(turn.data.is_error == true)` check fails because `ToolCall` and `Prompt` turns do not have an `is_error` field (it is specific to `ToolResult` — Section 5.4 only lists `is_error` for ToolResult). In JavaScript, `undefined == true` is `false`, so the heuristic evaluates to `false`.

For the heuristic to fire as currently specified, 3 consecutive recent turns for a node would ALL need `is_error: true`. Given the Prompt → ToolCall → ToolResult turn cycle, this requires that Prompt and ToolCall turns also carry `is_error: true`, which contradicts the type definitions in Section 5.4 (those types don't have an `is_error` field).

The holdout scenario "Agent stuck in error loop" expects: "the most recent 3+ turns on a node have `is_error: true`" → node colored red. This scenario is unreachable under the current heuristic specification because non-ToolResult turns dilute the "most recent 3" window.

### Suggestion

Change `getMostRecentTurnsForNodeInContext` to filter by turn type in addition to `node_id`. Only consider turns whose `declared_type.type_id` is `com.kilroy.attractor.ToolResult` (the only type with `is_error`). Then "3 most recent ToolResult turns all have `is_error: true`" correctly detects an error loop.

Updated pseudocode:

```
recentTurns = getMostRecentToolResultsForNodeInContext(contextTurns, nodeId, count=3)
IF recentTurns.length >= 3 AND ALL(turn.data.is_error == true FOR turn IN recentTurns):
    mergedMap[nodeId].status = "error"
    BREAK
```

And update the helper description: "scans a single context's cached turns for `ToolResult` turns matching the given `node_id`, collecting them sorted by `turn_id` descending, and returns the first `count` matches."

Also update the holdout scenario to be more precise: "the most recent 3+ **ToolResult** turns on a node have `is_error: true`."

---

## Issue #2: `next_before_turn_id` semantics are mischaracterized — it is null only when the response is empty, not when no more pages exist

### The problem

Section 5.3 describes `next_before_turn_id` as: "null when there are no more turns." The CXDB source (`http/mod.rs:916-927`) shows the actual implementation:

```rust
let next_before = turns.first().map(|t| t.record.turn_id.to_string());
```

This sets `next_before_turn_id` to the oldest turn's ID in the response. It is `null` **only** when the response turns array is empty — not when the response reaches the beginning of the context. If a response contains the context's very first turn (depth 0), `next_before_turn_id` is still non-null (set to that first turn's ID).

This has two concrete impacts:

**(a) The `fetchFirstTurn` algorithm (Section 5.5) has a dead code path.** The pagination loop checks:

```
IF response.next_before_turn_id IS null:
    BREAK  -- reached the oldest page
```

This condition never fires when the response contains turns. The loop always terminates through the other break: `IF response.turns IS EMPTY: BREAK`. This means one extra HTTP request per context discovery — after fetching all turns in the first request, the loop sets `cursor = next_before_turn_id` (the first turn's ID), makes a second request with `before_turn_id=first_turn_id`, gets an empty response, and breaks. For the typical single-request case (≤65535 turns), discovery makes 2 requests instead of 1 per context.

**(b) The gap detection comment is misleading.** The condition has:

```
AND response.next_before_turn_id IS NOT null:   -- older turns exist to paginate
```

The comment says "older turns exist to paginate," but `next_before_turn_id IS NOT null` only means "the response contained at least one turn." Older turns may or may not exist. The condition works correctly in practice (if the response reaches the beginning of the context, there's no gap to recover), but the comment could mislead an implementer.

### Suggestion

Three changes:

1. **Section 5.3** — Correct the `next_before_turn_id` description to: "`null` when the response contains no turns. Otherwise, set to the oldest turn's ID in the response (use as `before_turn_id` for the next page)."

2. **Section 5.5 `fetchFirstTurn`** — Add an early-exit after the first fetch to avoid the extra request:

```
response = fetchTurns(cxdbIndex, contextId, limit=fetchLimit, before_turn_id=cursor)
IF response.turns IS EMPTY:
    BREAK
lastTurns = response.turns
IF response.turns.length < fetchLimit:
    BREAK  -- all turns fit in one request; no older turns exist
IF response.next_before_turn_id IS null:
    BREAK
cursor = response.next_before_turn_id
```

The `response.turns.length < fetchLimit` check is the definitive "no more pages" signal: if the server returned fewer turns than requested, there are no more to paginate. This eliminates the extra HTTP request for all contexts with ≤65535 turns (virtually all Kilroy pipelines).

3. **Section 6.1 gap detection** — Update the comment from "older turns exist to paginate" to "response was non-empty (more turns may exist to paginate)."

---

## Issue #3: "Determine active run per pipeline" (polling step 3) is the only multi-step algorithm in the polling cycle without pseudocode

### The problem

Section 6.1 step 3 describes the active run determination in prose:

> "For each loaded pipeline, group discovered contexts by `run_id`. The active run is the one whose contexts have the highest `created_at_unix_ms` value. Contexts from non-active runs are excluded from steps 4–7. When the active `run_id` changes for a pipeline (a new run has started), reset all per-context status maps and `lastSeenTurnId` cursors for that pipeline's old-run contexts, and clear the per-pipeline turn cache (step 5) for that pipeline."

This involves several non-trivial operations:

1. **Data joining** — The discovery mapping (from step 2) stores `{ graphName, runId }` keyed by `(cxdb_index, context_id)`. The `created_at_unix_ms` field is on the context objects from the context list (step 1). Step 3 must join these two data sources, but the spec doesn't specify how the context list data is retained from step 1 to step 3.

2. **Grouping and comparison** — For each pipeline, contexts are grouped by `run_id`, then the group with the highest `created_at_unix_ms` is selected. "Highest `created_at_unix_ms`" is ambiguous: is it the maximum `created_at_unix_ms` among all contexts in the group, or some other aggregation?

3. **State reset** — When the active run changes, per-context maps, `lastSeenTurnId` cursors, and the turn cache must be reset. The scope of the reset ("old-run contexts") requires identifying which cached state belongs to the old run.

4. **Active run tracking** — The algorithm must track the previous active `run_id` per pipeline to detect changes. This state is not mentioned in the data model.

Every other algorithm in the spec — `discoverPipelines`, `fetchFirstTurn`, `updateContextStatusMap`, `mergeStatusMaps`, `applyErrorHeuristic`, gap detection, gap recovery — has explicit pseudocode. Step 3 is the sole exception despite having comparable complexity.

### Suggestion

Add pseudocode for the active run determination. Example:

```
FUNCTION determineActiveRuns(pipelines, knownMappings, contextLists, previousActiveRunIds):
    activeContextsByPipeline = {}

    FOR EACH pipeline IN pipelines:
        -- Collect discovered contexts for this pipeline with their run_id and created_at
        candidates = []
        FOR EACH ((index, contextId), mapping) IN knownMappings:
            IF mapping IS NOT null AND mapping.graphName == pipeline.graphId:
                contextInfo = lookupContext(contextLists, index, contextId)
                candidates.append({ index, contextId, runId: mapping.runId,
                                    createdAt: contextInfo.created_at_unix_ms })

        IF candidates IS EMPTY:
            activeContextsByPipeline[pipeline.graphId] = []
            CONTINUE

        -- Group by run_id, pick the run with the highest created_at among its contexts
        runGroups = groupBy(candidates, "runId")
        activeRunId = null
        highestCreatedAt = 0
        FOR EACH (runId, contexts) IN runGroups:
            maxCreatedAt = max(c.createdAt FOR c IN contexts)
            IF maxCreatedAt > highestCreatedAt:
                highestCreatedAt = maxCreatedAt
                activeRunId = runId

        -- Detect run change and reset stale state
        IF previousActiveRunIds[pipeline.graphId] IS NOT null
           AND previousActiveRunIds[pipeline.graphId] != activeRunId:
            resetPipelineState(pipeline.graphId)  -- clear per-context maps, cursors, turn cache

        previousActiveRunIds[pipeline.graphId] = activeRunId
        activeContextsByPipeline[pipeline.graphId] = runGroups[activeRunId]

    RETURN activeContextsByPipeline
```

Also add a note that the context list data from step 1 must be retained (e.g., in a local variable) for use in step 3, since the discovery mapping does not store `created_at_unix_ms`.
