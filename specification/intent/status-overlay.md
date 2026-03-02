## 6. Status Overlay

### 6.1 Polling

The UI polls all configured CXDB instances every 3 seconds. Each poll cycle:

1. For each CXDB instance, fetch Kilroy contexts using the CQL search endpoint or fallback (see the CXDB upstream contract (`specification/contracts/cxdb-upstream.md`) and Section 5.2's `discoverPipelines` for the CQL/fallback selection logic). On success, store the **discovery-effective context list** in `cachedContextLists[i]` (replacing any previous cached value). The discovery-effective list is: the merged list of CQL results plus any supplemental kilroy-prefixed contexts not already in CQL (deduplicated by `context_id`, per the `discoverPipelines` pseudocode in Section 5.2) when CQL is in use, or the full context list when using the fallback. This ensures that `cachedContextLists[i]` always reflects the same `contexts` array used for Phase 2 discovery in the current poll cycle — including supplemental contexts regardless of whether CQL returned results. In particular: when CQL returns empty results, the supplemental context list may discover active Kilroy contexts via session-tag resolution, and those contexts (with their `is_live` field) must be in `cachedContextLists[i]` for `lookupContext` and `checkPipelineLiveness` to find them; when CQL returns some results but misses others (mixed deployment — see Section 5.2, case (b)), the supplemental contexts merged into `contexts` must also be present in `cachedContextLists[i]`, otherwise `checkPipelineLiveness` will not find their `is_live` field and will misclassify active runs as stale. Without storing the full merged list, CQL-only polls would produce an incomplete `cachedContextLists[i]`, causing `applyStaleDetection` to flip running nodes to "stale" even though agents are actively working. If an instance is unreachable (502), skip it, retain its per-context status maps from the last successful poll, and use `cachedContextLists[i]` as the context list for that instance in subsequent steps. This ensures that `lookupContext`, `determineActiveRuns`, and `checkPipelineLiveness` continue to function using the last known context data during transient outages — preserving active-run determination and liveness signals rather than losing them.

   **`cqlSupported` flag reset on reconnection.** The UI tracks a per-instance `instanceReachable[i]` flag. On each poll step 1, before issuing any discovery request: if `instanceReachable[i]` was `false` in the previous cycle (the instance was unreachable), and the current attempt succeeds with a non-502 response, set `instanceReachable[i] = true` and reset `cqlSupported[i] = undefined` (allowing the next poll cycle to retry CQL). This reset is applied regardless of whether the instance was previously `cqlSupported[i] = false` (no CQL) or `cqlSupported[i] = true` (CQL worked but could be affected by an upgrade). The reset happens at reachability detection time — not inside the CQL path itself — so it applies whether the non-502 response comes from a CQL search, context list, or any other proxied request. If the current attempt returns 502, set `instanceReachable[i] = false` and skip the instance as before. In pseudocode:

   ```
   -- At the top of each poll cycle for instance[i]:
   currentlyReachable = (fetchContextsOrCql(i) does NOT return 502)
   IF NOT currentlyReachable:
       instanceReachable[i] = false
       SKIP instance i this cycle
   ELSE:
       IF instanceReachable[i] == false:
           -- Instance just reconnected after being unreachable.
           -- Reset cqlSupported so the next poll retries CQL
           -- (the instance may have been upgraded while down).
           cqlSupported[i] = undefined
       instanceReachable[i] = true
       -- proceed with discovery
   ```

   This ensures that an instance upgraded from non-CQL to CQL while unreachable will have CQL re-probed on the next poll after it comes back, rather than permanently skipping CQL based on a pre-outage 404.
2. Run pipeline discovery for any new `(index, context_id)` pairs (Section 5.2)
3. **Determine active run per pipeline.** For each loaded pipeline, group discovered contexts by `run_id`. The active run is the one with the lexicographically greatest `run_id` value — since `run_id` is a ULID with a 48-bit millisecond timestamp prefix, lexicographic max is equivalent to "most recently started run" and is safe across multiple CXDB instances (see Section 5.2 for the full explanation including why `context_id` cannot be used cross-instance and why `created_at_unix_ms` is also unsuitable). Contexts from non-active runs are excluded from steps 4–7. When the active `run_id` changes for a pipeline (a new run has started), reset all per-context status maps and `lastSeenTurnId` cursors for that pipeline's old-run contexts, and clear the per-pipeline turn cache (step 5) for that pipeline. This implements the "most recent run" rule described in Section 5.2. The algorithm also maintains a `previousActiveRunIds` map (keyed by pipeline graph ID) across poll cycles to detect run changes.

   **Active run determination pseudocode:**

   ```
   FUNCTION determineActiveRuns(pipelines, knownMappings, contextLists, previousActiveRunIds):
       activeContextsByPipeline = {}

       FOR EACH pipeline IN pipelines:
           -- Collect discovered contexts for this pipeline with their run_id and created_at.
           -- knownMappings is keyed by (cxdb_index, context_id) from step 2.
           -- contextLists is the raw context list data retained from step 1.
           candidates = []
           FOR EACH ((index, contextId), mapping) IN knownMappings:
               IF mapping IS NOT null AND mapping.graphName == pipeline.graphId:
                   candidates.append({ index, contextId, runId: mapping.runId })

           IF candidates IS EMPTY:
               activeContextsByPipeline[pipeline.graphId] = []
               CONTINUE

           -- Group by run_id, pick the run with the lexicographically greatest
           -- run_id. run_id is a ULID (Universally Unique Lexicographically Sortable
           -- Identifier) generated at run start time with a 48-bit millisecond
           -- timestamp prefix (ulid.New(ulid.Timestamp(t), entropy) in
           -- internal/attractor/engine/runid.go). Lexicographic max of run_id is
           -- therefore equivalent to "most recently started run". This comparison
           -- is safe across CXDB instances because run_id is generated by Kilroy
           -- at launch time (not by CXDB), so it does not depend on any per-instance
           -- counter. In contrast, context_id is a per-instance monotonic counter
           -- that resets independently on each CXDB server — comparing context_id
           -- values across instances can incorrectly favour an old run on a
           -- high-counter instance over a newer run on a low-counter instance.
           runGroups = groupBy(candidates, "runId")
           activeRunId = null
           FOR EACH (runId, contexts) IN runGroups:
               IF activeRunId IS null OR runId > activeRunId:
                   -- ULID lexicographic comparison: larger string = later creation time
                   activeRunId = runId

           -- Detect run change and reset stale state
           IF previousActiveRunIds[pipeline.graphId] IS NOT null
              AND previousActiveRunIds[pipeline.graphId] != activeRunId:
               resetPipelineState(pipeline.graphId)  -- clear per-context status maps, cursors, turn cache for old run
               -- IMPORTANT: resetPipelineState does NOT remove old-run entries from
               -- knownMappings. Old-run contexts remain cached (with their graphName
               -- and runId) so that discoverPipelines skips them on future polls.
               -- Removing them would force expensive re-discovery (fetchFirstTurn)
               -- for every old-run context on every poll cycle. Since context IDs
               -- are monotonic and never recycled, retaining these mappings is safe.
               -- The determineActiveRuns algorithm naturally ignores old-run contexts
               -- because their runId will not match the new activeRunId.

           previousActiveRunIds[pipeline.graphId] = activeRunId
           activeContextsByPipeline[pipeline.graphId] = runGroups[activeRunId]

       RETURN activeContextsByPipeline
   ```

   The `lookupContext` helper finds the context object (from step 1's context list responses) by `(cxdb_index, context_id)` to access fields like `is_live`. The `resetPipelineState` helper clears the per-context status maps, `lastSeenTurnId` cursors, and per-pipeline turn cache for all contexts that belonged to the old run. It does **not** remove `knownMappings` entries for the old run — doing so would force expensive `fetchFirstTurn` re-discovery for every old-run context on every subsequent poll cycle. Old-run entries are harmless: the `determineActiveRuns` algorithm naturally ignores them because their `runId` does not match the current active run (which is selected by ULID lex max, not by `context_id`). CXDB context IDs are monotonically increasing integers allocated from a per-instance counter and are never reused within an instance, so old-run entries do not cause collisions within the `knownMappings` key space (which is always `(cxdb_index, context_id)`). Over time, old-run entries accumulate in `knownMappings` — this is acceptable because the number of entries is bounded by the total number of Kilroy contexts across all CXDB instances, which grows slowly. Entries with `null` mappings (negative caches for non-Kilroy contexts) are also retained.

   **Pipeline liveness check.** After determining active runs, check whether each pipeline's active-run contexts have any live sessions. A pipeline is "live" if at least one of its active-run contexts has `is_live == true` in the context list response. This signal is used in step 6 for stale node detection.

   ```
   FUNCTION checkPipelineLiveness(activeContexts, contextLists):
       -- A pipeline is "live" if ANY of its active-run contexts has is_live == true
       FOR EACH ctx IN activeContexts:
           contextInfo = lookupContext(contextLists, ctx.index, ctx.contextId)
           IF contextInfo.is_live == true:
               RETURN true
       RETURN false
   ```

4. For each context in the **active run** of **any loaded pipeline** (across all instances), fetch recent turns: `GET /api/cxdb/{i}/v1/contexts/{id}/turns?limit=100` (returns oldest-first). If a per-context turn fetch returns a non-200 response (e.g., 404/500 from a type registry miss, or any other server error), skip that context for this poll cycle: retain its cached turns and per-context status map from the last successful fetch, and continue polling. This prevents a single context's failure (such as an unregistered type in `view=typed` — see see `specification/contracts/cxdb-upstream.md`) from affecting other contexts or crashing the poll cycle. Turns are fetched for all pipelines, not just the active tab — this ensures per-context status maps stay current for inactive pipelines, preventing stale data on tab switch.
5. **Cache raw turns** — Store the raw turn arrays from step 4 in a per-pipeline turn cache, keyed by `(cxdb_index, context_id)`. This cache is replaced (not appended) on each successful fetch. When a CXDB instance is unreachable, its entries in the turn cache are retained from the previous successful fetch. The detail panel (Section 7.2) reads from this cache.
6. Run `updateContextStatusMap` per context (updating persistent per-context maps and advancing each context's `lastSeenTurnId` cursor), then `mergeStatusMaps` across **active-run** contexts for **each loaded pipeline** (both active and inactive), then `applyErrorHeuristic` on each pipeline's merged map using the per-context turn caches, then `applyStaleDetection` using the pipeline liveness result from step 3 (Section 6.2). The merged map for each pipeline is cached as the pipeline's current display map. This ensures that when the user switches to an inactive tab, the cached merged map can be immediately applied to the SVG without recomputation, satisfying the "no gray flash" requirement (Section 4.4 and the "Switch between pipeline tabs" holdout scenario). Per-context status maps from unreachable instances are included in the merge using their cached values.
7. Apply CSS classes to SVG nodes for the active pipeline (Section 6.3)

**Poll scheduling.** The poller uses `setTimeout` (not `setInterval`). After a poll cycle completes, the next poll is scheduled 3 seconds later. This prevents overlapping poll cycles when CXDB instances respond slowly — at most one poll cycle is in flight at any time. The effective interval is 3 seconds plus poll execution time.

The polling interval is constant. It does not adapt to pipeline activity or CXDB load. Requests to different CXDB instances within a single poll cycle are issued in parallel.

**Status caching on failure.** The UI retains per-context status maps from the last successful poll. When a CXDB instance is unreachable, its contexts' status maps are not discarded — they participate in the merge using cached values. This ensures that status is preserved (not reverted to "pending") when a CXDB instance goes down temporarily. Cached status maps are only replaced when fresh data is successfully fetched for that context.

**Turn fetch limit.** Each context poll fetches at most 100 recent turns (`limit=100`; CXDB returns turns oldest-first). This window may not contain lifecycle turns for nodes that completed early in a long-running pipeline. The persistent status map (Section 6.2) ensures completed nodes retain their status even when their lifecycle turns fall outside this window.

**Gap recovery.** After step 4, if any context's fetched turns do not reach back to `lastSeenTurnId`, the poller issues additional paginated requests using `before_turn_id` to fetch the missing turns until `lastSeenTurnId` is reached or `next_before_turn_id` is null. The gap detection condition is:

```
oldestFetched = turns[0].turn_id   -- oldest turn in the batch (oldest-first ordering)
IF lastSeenTurnId IS NOT null
   AND numericTurnId(oldestFetched) > numericTurnId(lastSeenTurnId)  -- batch doesn't reach our cursor
   AND response.next_before_turn_id IS NOT null:   -- response was non-empty (more turns may exist to paginate)
    -- Run gap recovery.
```

The condition uses `oldestFetched > lastSeenTurnId` (without `+ 1`) because CXDB allocates turn IDs from a global counter shared across all contexts on an instance. Within a single context's parent chain, turn IDs are monotonically increasing but **not consecutive** — gaps between intra-context turn IDs are normal and proportional to the number of concurrently active contexts. The `next_before_turn_id IS NOT null` guard prevents gap recovery when the response was empty (which indicates no turns exist before the cursor). Note that a non-null `next_before_turn_id` means the response contained at least one turn, not that older turns definitely exist — but in the gap recovery context, this is sufficient because if the batch contains any turns and doesn't reach `lastSeenTurnId`, there are older turns to fetch. Together, these conditions detect real gaps (the 100-turn fetch window doesn't include `lastSeenTurnId` and there are older turns to paginate) without false positives from sparse turn IDs.

**Gap recovery pseudocode:**

```
-- Gap recovery: fetch turns between lastSeenTurnId and the main batch
-- Bounded to MAX_GAP_PAGES (10) to prevent a long outage from blocking the poller.
MAX_GAP_PAGES = 10
recoveredTurns = []
cursor = response.next_before_turn_id
pagesFetched = 0
WHILE cursor IS NOT null AND pagesFetched < MAX_GAP_PAGES:
    gapResponse = fetchTurns(cxdbIndex, contextId, limit=100, before_turn_id=cursor)
    pagesFetched = pagesFetched + 1
    IF gapResponse.turns IS EMPTY:
        BREAK
    recoveredTurns = gapResponse.turns + recoveredTurns  -- prepend to maintain oldest-first
    -- Check if we've reached lastSeenTurnId
    oldestInGap = gapResponse.turns[0].turn_id  -- oldest turn in page (oldest-first ordering)
    IF numericTurnId(oldestInGap) <= numericTurnId(lastSeenTurnId):
        BREAK
    cursor = gapResponse.next_before_turn_id

-- If the page limit was hit before reaching lastSeenTurnId, advance the cursor
-- to the oldest recovered turn. Some intermediate turns are lost, but the persistent
-- status map ensures statuses are never demoted, and the next poll's 100-turn window
-- will contain the most recent state.
IF pagesFetched >= MAX_GAP_PAGES AND cursor IS NOT null:
    lastSeenTurnId = recoveredTurns[0].turn_id  -- oldest recovered turn becomes new cursor

-- Prepend recovered turns to the main batch
turns = recoveredTurns + turns
```

This ensures lifecycle events (e.g., `StageFinished`) that occurred during a CXDB outage are not permanently lost. The gap recovery procedure runs at most once per context per poll cycle. Within the procedure, up to `MAX_GAP_PAGES` (10) paginated requests are issued (one per 100 turns, covering up to 1,000 missed turns). This bounds recovery time: a context with thousands of accumulated turns during a long outage will recover the most recent 1,000 turns and advance the cursor, rather than blocking the entire poll cycle with dozens of sequential HTTP requests. The tradeoff is that intermediate turns beyond the 1,000-turn window are lost — but because statuses are never demoted (Section 6.2), any promotions from lost turns are not critical. The next poll cycle's 100-turn window contains the most recent state. The recovered turns are prepended (in oldest-first order) to the context's turn batch before step 5 caches them and step 6 processes them for status derivation.

### 6.2 Node Status Map

The status map associates each DOT node ID with an execution status. The status map is **persistent** — it accumulates across poll cycles rather than being recomputed from scratch. This prevents completed nodes from reverting to "pending" when their lifecycle turns fall outside the 100-turn fetch window.

```
TYPE NodeStatus:
    status                : "pending" | "running" | "complete" | "error" | "stale"
    lastTurnId            : String | null
    toolName              : String | null
    turnCount             : Integer
    errorCount            : Integer
    hasLifecycleResolution: Boolean
```

**Status map lifecycle:**

1. A new status map is initialized (all nodes "pending") when a pipeline is first displayed.
2. On each poll cycle, fetched turns are processed and node statuses are **promoted** within each context according to the per-context precedence `pending < running < complete < error`. Statuses are never demoted within a context. (Cross-context merging uses a different precedence where `running > complete` — see Section 6.2.)
3. The status map is **reset** (all nodes back to "pending") only when the active `run_id` changes — i.e., a new run of the same pipeline is detected (Section 5.2).

**Turn ID comparison.** CXDB turn IDs are numeric strings (e.g., `"6066"`). All turn ID comparisons in the UI — including the deduplication check, `lastSeenTurnId` tracking, `lastTurnId` on `NodeStatus`, gap recovery detection, and error heuristic sorting — must use numeric ordering: `parseInt(turn_id, 10)`. Lexicographic comparison breaks for IDs of different lengths (e.g., `"999" > "1000"` lexicographically). All pseudocode in this specification uses the `numericTurnId(id)` helper (equivalent to `parseInt(id, 10)`) to make numeric comparison explicit at every comparison site. This applies to gap recovery (Section 6.1), `updateContextStatusMap`, `mergeStatusMaps`, `applyErrorHeuristic`, and the detail panel's within-context sorting (Section 7.2).

**Status derivation algorithm (per context):**

The algorithm processes turns from a single CXDB context and promotes statuses in an existing per-context status map. When multiple contexts match the active pipeline (e.g., parallel branches), the algorithm runs independently per context and the results are merged (see below).

```
FUNCTION updateContextStatusMap(existingMap, dotNodeIds, turns, lastSeenTurnId):
    -- Prune entries for node IDs no longer in dotNodeIds (handles DOT file regeneration
    -- where nodes are removed). This prevents unbounded growth of per-context status maps
    -- and satisfies the Section 4.4 requirement that "removed nodes are dropped from the maps."
    FOR EACH nodeId IN keys(existingMap):
        IF nodeId NOT IN dotNodeIds:
            DELETE existingMap[nodeId]

    -- Initialize entries for any new node IDs not yet in the map
    FOR EACH nodeId IN dotNodeIds:
        IF nodeId NOT IN existingMap:
            existingMap[nodeId] = NodeStatus { status: "pending", turnCount: 0, errorCount: 0, hasLifecycleResolution: false }

    -- Per-context precedence: complete outranks running because within a single
    -- execution flow, a completed node must not regress to running. (The cross-context
    -- merge uses a different precedence where running outranks complete — see mergeStatusMaps.)
    CONTEXT_PRECEDENCE = { "error": 3, "complete": 2, "running": 1, "pending": 0 }

    -- Compute the newest turn ID across the entire batch (handles any ordering,
    -- including mixed-order batches produced by gap recovery prepending)
    newLastSeenTurnId = lastSeenTurnId
    FOR EACH turn IN turns:
        IF newLastSeenTurnId IS null OR numericTurnId(turn.turn_id) > numericTurnId(newLastSeenTurnId):
            newLastSeenTurnId = turn.turn_id

    -- turns are oldest-first from the API; gap recovery may prepend older turns
    FOR EACH turn IN turns:
        -- Skip turns already processed in a previous poll cycle
        IF lastSeenTurnId IS NOT null AND numericTurnId(turn.turn_id) <= numericTurnId(lastSeenTurnId):
            CONTINUE  -- skip this turn; batch may not be sorted, so don't break

        nodeId = turn.data.node_id
        typeId = turn.declared_type.type_id
        IF nodeId IS null OR nodeId NOT IN existingMap:
            CONTINUE

        -- Determine the status this turn implies
        newStatus = null
        IF typeId == "com.kilroy.attractor.StageFinished":
            existingMap[nodeId].hasLifecycleResolution = true
            IF turn.data.status == "fail":
                newStatus = "error"
            ELSE:
                newStatus = "complete"
        ELSE IF typeId == "com.kilroy.attractor.StageFailed":
            IF turn.data.will_retry == true:
                newStatus = "running"
                -- Do NOT set hasLifecycleResolution. The node is retrying, not terminally
                -- failed. A subsequent StageFinished or StageFailed (will_retry=false)
                -- will provide the authoritative resolution.
            ELSE:
                newStatus = "error"
                existingMap[nodeId].hasLifecycleResolution = true
        ELSE IF typeId == "com.kilroy.attractor.RunFailed":
            newStatus = "error"
            existingMap[nodeId].hasLifecycleResolution = true
        ELSE IF typeId == "com.kilroy.attractor.StageStarted":
            newStatus = "running"
        ELSE:
            -- Non-lifecycle turns: infer running
            newStatus = "running"

        -- Promote status. Lifecycle resolutions (StageFinished, terminal StageFailed)
        -- are authoritative and unconditionally override status. Once a node has
        -- lifecycle resolution, only other lifecycle turns can modify its status.
        -- Non-lifecycle turns follow promotion-only (never demote).
        -- StageFailed with will_retry=true is NOT a lifecycle resolution — it sets
        -- "running" status and follows the non-lifecycle promotion path, allowing
        -- the retry to proceed visually as a running node.
        IF typeId == "com.kilroy.attractor.StageFinished"
           OR (typeId == "com.kilroy.attractor.StageFailed" AND turn.data.will_retry != true)
           OR typeId == "com.kilroy.attractor.RunFailed":
            -- Lifecycle turns are authoritative: override any previous status
            existingMap[nodeId].status = newStatus
        ELSE IF NOT existingMap[nodeId].hasLifecycleResolution
           AND (newStatus == "error" OR CONTEXT_PRECEDENCE[newStatus] > CONTEXT_PRECEDENCE[existingMap[nodeId].status]):
            existingMap[nodeId].status = newStatus

        IF turn.data.is_error == true:
            existingMap[nodeId].errorCount++

        existingMap[nodeId].turnCount++
        IF existingMap[nodeId].toolName IS null:
            existingMap[nodeId].toolName = turn.data.tool_name

        -- Update lastTurnId to the most recent turn for this node (numeric comparison)
        IF existingMap[nodeId].lastTurnId IS null
           OR numericTurnId(turn.turn_id) > numericTurnId(existingMap[nodeId].lastTurnId):
            existingMap[nodeId].lastTurnId = turn.turn_id

    RETURN (existingMap, newLastSeenTurnId)
```

**Turn deduplication.** Each per-context status map tracks a `lastSeenTurnId` — the newest `turn_id` processed in the previous poll cycle. On each poll, the algorithm skips turns with `turn_id <= lastSeenTurnId`, processing only newly appended turns. Because gap recovery prepends older turns before the main batch (both segments are oldest-first but the combined batch has a discontinuity at the join point), the algorithm uses `CONTINUE` instead of `BREAK` to skip already-seen turns — it cannot assume strictly ascending order across the join. The `newLastSeenTurnId` cursor is computed as the maximum `turn_id` across the entire batch before the processing loop begins, ensuring it always advances to the newest turn regardless of batch ordering. This prevents `turnCount` and `errorCount` from being inflated by re-processing overlapping turns across poll cycles. The cursor is initialized to `null` (process all turns) when a context is first discovered, and resets to `null` when the active `run_id` changes.

**lastTurnId assignment.** The `lastTurnId` field on `NodeStatus` records the most recent turn for that node. It is updated whenever a turn's `turn_id` exceeds the stored value (using numeric comparison). Since turns arrive oldest-first, later encounters per node in the batch have higher turn IDs, and the max-comparison ensures `lastTurnId` always holds the newest turn ID. Across poll cycles, new turns always have higher IDs than previously stored values (due to deduplication), so `lastTurnId` correctly advances to reflect the latest activity for each node.

**Lifecycle turn precedence.** `StageFinished`, `StageFailed`, and `RunFailed` are authoritative lifecycle signals. When processed, they set `hasLifecycleResolution = true` on the node and unconditionally override the current status — including any previous status. `RunFailed` is a pipeline-level failure event that carries an optional `node_id` — when present and non-empty, it marks the node as "error" (red). Kilroy's `cxdbRunFailed` always includes a `node_id` key, but the value may be an empty string if the run fails before entering any node (e.g., during graph initialization — see `persistFatalOutcome` in `engine.go`). An empty `node_id` passes the `IF nodeId IS null` guard but is filtered by the `IF nodeId NOT IN existingMap` guard, so it does not affect any node's status. `StageFinished` checks the `data.status` field: if `status == "fail"`, the node is set to "error" (red); otherwise it is set to "complete" (green). This ensures that a node which finished with a terminal failure (e.g., `StageFinished { status: "fail" }` followed by `RunFailed`) displays as red, not green. The `status` field has five canonical values (`"success"`, `"partial_success"`, `"retry"`, `"fail"`, `"skipped"` — from Kilroy's `StageStatus` enum in `runtime/status.go`) and may also contain custom routing values (e.g., `"process"`, `"done"`, `"port"`, `"needs_dod"`) used for multi-way conditional branching (see `ParseStageStatus` in `runtime/status.go` lines 31-39, and `custom_outcome_routing_test.go`). All values are treated as "complete" except `"fail"`. The UI must not assume a closed set of status values — the `status == "fail"` check is the only branch that matters. This handles three cases: (a) an agent encounters 3+ tool errors but then recovers and completes the node successfully, (b) gap recovery prepends older turns before the main batch, where a `StageStarted` turn might appear after a `StageFinished` for the same node in the combined batch, and (c) a node terminates with `StageFinished { status: "fail" }` and should display as error, not complete. Once a node has `hasLifecycleResolution = true`, only other lifecycle turns (`StageFinished`, `StageFailed`, `RunFailed`) can modify its status — non-lifecycle turns are ignored for that node. This prevents a `StageStarted` turn (processed after `StageFinished` due to batch ordering) from regressing a completed node back to running. The error loop heuristic (which runs post-merge) also skips nodes with `hasLifecycleResolution = true`.

**Error loop detection heuristic.** The heuristic runs as a post-merge step (see `applyErrorHeuristic` above), after `updateContextStatusMap` and `mergeStatusMaps` have produced the merged display map. It fires only for nodes that are "running" and have no lifecycle resolution (`hasLifecycleResolution == false`). For each such node, it examines each context's cached turns independently — if any single context has 3 consecutive recent errors for the node, the node is promoted to "error" in the merged map. This per-context scoping avoids cross-instance `turn_id` comparison: CXDB instances have independent turn ID counters with no temporal relationship, so sorting turns by `turn_id` across instances would produce arbitrary interleaving rather than temporal ordering. Within a single context, `turn_id` is monotonically increasing and safe to use for ordering. The `errorCount` field on `NodeStatus` is an internal-only lifetime counter used for diagnostics (e.g., logging, debugging) but is **not displayed** in the detail panel UI. The same applies to `turnCount` and `toolName` on `NodeStatus` — these are internal bookkeeping fields used by the status derivation and merge algorithms, not rendered in the detail panel. The detail panel's CXDB Activity section (Section 7.2) shows individual turn rows sourced from the turn cache, not aggregated counters from `NodeStatus`.

**Multi-context merging.** When multiple CXDB contexts match the active pipeline (e.g., parallel branches), the algorithm runs independently per context, producing one per-context status map. The per-context maps are then merged into a single display map using **merge precedence** (highest wins):

```
error > running > complete > pending
```

Note: the merge precedence intentionally differs from the per-context precedence (`error > complete > running > pending`). Within a single context, a completed node should never regress to running. But across contexts, `running > complete` because if one parallel branch is still running a node while another has completed it, the display should show "running" to indicate ongoing activity.

```
FUNCTION mergeStatusMaps(dotNodeIds, perContextMaps):
    MERGE_PRECEDENCE = { "error": 3, "running": 2, "complete": 1, "pending": 0 }
    merged = {}
    FOR EACH nodeId IN dotNodeIds:
        merged[nodeId] = NodeStatus { status: "pending", turnCount: 0, errorCount: 0, hasLifecycleResolution: false }
        -- Track lifecycle resolution across all contexts using AND semantics
        allContextsHaveLifecycleResolution = true
        anyContextHasNode = false
        FOR EACH contextMap IN perContextMaps:
            contextStatus = contextMap[nodeId]
            IF MERGE_PRECEDENCE[contextStatus.status] > MERGE_PRECEDENCE[merged[nodeId].status]:
                merged[nodeId].status = contextStatus.status
                merged[nodeId].toolName = contextStatus.toolName
                merged[nodeId].lastTurnId = contextStatus.lastTurnId
            merged[nodeId].turnCount += contextStatus.turnCount
            merged[nodeId].errorCount += contextStatus.errorCount
            -- Only consider contexts that have actually processed turns for this node
            IF contextStatus.status != "pending":
                anyContextHasNode = true
                IF NOT contextStatus.hasLifecycleResolution:
                    allContextsHaveLifecycleResolution = false
        -- hasLifecycleResolution is true only when ALL contexts that have processed
        -- turns for this node have lifecycle resolution. This prevents a completed
        -- branch from suppressing error/stale heuristics in a branch that is still
        -- actively failing.
        merged[nodeId].hasLifecycleResolution = anyContextHasNode AND allContextsHaveLifecycleResolution
    RETURN merged
```

This ensures that parallel branches each contribute their own "running" node, and a node that is "running" in one context but "complete" in another shows as "running." The `hasLifecycleResolution` flag uses AND semantics across contexts: the merged map sets `hasLifecycleResolution = true` only when ALL contexts that have processed turns for the node have lifecycle resolution. This prevents a branch that has completed a node from suppressing the error and stale heuristics for the same node in a different branch that is actively failing. Only contexts that have progressed beyond "pending" for the node participate in the AND — contexts that have not yet encountered the node do not prevent lifecycle resolution from being set. The per-context maps are persistent (accumulated across polls); the merged map is recomputed each poll cycle from the current per-context maps.

**Error loop heuristic (post-merge).** After merging per-context maps, the error loop heuristic runs once per pipeline per poll cycle against the merged map and the per-context turn caches. This architecture avoids two problems: (a) scoping the heuristic per-context prevents cross-instance `turn_id` comparison (CXDB instances have independent, monotonically-increasing turn ID counters with no temporal relationship), and (b) per-context maps are no longer contaminated with decisions based on other contexts' data.

```
FUNCTION applyErrorHeuristic(mergedMap, dotNodeIds, perContextCaches):
    -- For each running node without lifecycle resolution, check each context's
    -- cached turns independently. If ANY context shows 3 consecutive recent
    -- ToolResult errors for the node, flag it as "error" in the merged map.
    FOR EACH nodeId IN dotNodeIds:
        IF mergedMap[nodeId].status == "running"
           AND NOT mergedMap[nodeId].hasLifecycleResolution:
            FOR EACH contextTurns IN perContextCaches:
                recentTurns = getMostRecentToolResultsForNodeInContext(contextTurns, nodeId, count=3)
                IF recentTurns.length >= 3 AND ALL(turn.data.is_error == true FOR turn IN recentTurns):
                    mergedMap[nodeId].status = "error"
                    BREAK  -- one context with an error loop is sufficient
    RETURN mergedMap
```

The `getMostRecentToolResultsForNodeInContext` helper scans a single context's cached turns for `ToolResult` turns (i.e., turns whose `declared_type.type_id` is `com.kilroy.attractor.ToolResult`) matching the given `node_id`, collecting them sorted by `numericTurnId(turn_id)` descending (newest-first, which is safe for intra-context ordering since turn IDs are monotonically increasing within a single context), and returns the first `count` matches. Only `ToolResult` turns carry the `is_error` field (see see `specification/contracts/cxdb-upstream.md`); other turn types (Prompt, ToolCall, etc.) do not have this field, so including them would dilute the error detection window and prevent the heuristic from firing during typical error loops where turn types interleave as Prompt → ToolCall → ToolResult. This avoids the cross-instance `turn_id` ordering problem: turn IDs are only compared within the same CXDB instance and context, where they have a meaningful temporal relationship.

**Error heuristic window limitation.** The turn cache is replaced (not appended) on each successful fetch (Section 6.1, step 5). The error heuristic therefore only detects errors visible in the current 100-turn fetch window. If 3 error ToolResults span across two poll cycles — for example, 2 errors in the previous poll's window and 1 in the current window — only the current window's turns are available, and the heuristic would not fire. This means slow error loops (where errors are spaced more than ~100 turns apart across all turn types in the context) will not trigger the heuristic. This is acceptable for the initial implementation: the heuristic targets rapid error loops where the agent retries the same failing command in quick succession, producing many ToolResult turns per poll window. Slow error loops (one error every few minutes with hundreds of intervening turns) are an atypical pattern that is better addressed by lifecycle turns (`StageFailed`) or operator observation.

**Stale pipeline detection (post-merge).** After the error heuristic, the stale detection step runs if the pipeline has no live sessions. When all contexts for a pipeline's active run have `is_live == false` (no agent is writing to any of them), any node still showing as "running" without lifecycle resolution is reclassified as "stale." This detects the case where an agent process crashes mid-node — no `StageFinished` or `StageFailed` is written, and the node would otherwise display as "running" indefinitely.

```
FUNCTION applyStaleDetection(mergedMap, dotNodeIds, pipelineIsLive):
    IF pipelineIsLive:
        RETURN mergedMap  -- at least one session is active; no stale detection needed
    FOR EACH nodeId IN dotNodeIds:
        IF mergedMap[nodeId].status == "running"
           AND NOT mergedMap[nodeId].hasLifecycleResolution:
            mergedMap[nodeId].status = "stale"
    RETURN mergedMap
```

The `pipelineIsLive` flag is computed by `checkPipelineLiveness` in Section 6.1 step 3. Nodes with `hasLifecycleResolution == true` are not affected — their status is authoritative from lifecycle turns.

### 6.3 CSS Status Classes

After building the status map, the UI walks SVG `<g class="node">` elements and applies CSS classes:

| Status | CSS Class | Visual |
|--------|-----------|--------|
| `pending` | `node-pending` | Gray fill |
| `running` | `node-running` | Blue fill, pulsing animation |
| `complete` | `node-complete` | Green fill |
| `error` | `node-error` | Red fill |
| `stale` | `node-stale` | Orange/amber fill, no animation |

These CSS rules are defined in `frontend/src/app/globals.css` using Tailwind's `@layer` directive, since the SVG elements are generated at runtime by Graphviz WASM (not authored in JSX) and cannot use Tailwind utility classes directly:

```css
@layer components {
  .node-pending polygon, .node-pending ellipse, .node-pending path   { fill: #e0e0e0; }
  .node-running polygon, .node-running ellipse, .node-running path   { fill: #90caf9; animation: pulse 1.5s infinite; }
  .node-complete polygon, .node-complete ellipse, .node-complete path  { fill: #a5d6a7; }
  .node-error polygon, .node-error ellipse, .node-error path        { fill: #ef9a9a; }
  .node-stale polygon, .node-stale ellipse, .node-stale path        { fill: #ffcc80; }
}

@keyframes pulse {
    0%, 100% { opacity: 1; }
    50%      { opacity: 0.6; }
}
```

The status colors may also be defined as custom colors in `frontend/tailwind.config.ts` for use in non-SVG UI elements (e.g., status badges in the detail panel). The pulsing animation for "running" nodes is a Tailwind custom animation matching cxdb's `breathe` and `glow-pulse` animation patterns. A `cn()` utility in `frontend/src/lib/utils.ts` (matching cxdb's pattern) handles conditional class merging for React components.

**SVG element coverage.** The CSS selectors (`polygon`, `ellipse`, `path`) cover all ten node shapes in the Kilroy shape vocabulary (Section 7.3). Most shapes (`Mdiamond`, `Msquare`, `box`, `diamond`, `parallelogram`, `hexagon`, `component`, `tripleoctagon`, `house`) render as `<polygon>`. `circle` renders as `<ellipse>`. `doublecircle` renders as two nested `<ellipse>` elements — the CSS selectors match both, coloring the entire node correctly. No shapes render as elements outside the `polygon`/`ellipse`/`path` set.

Status classes are reapplied on every poll cycle. The SVG itself is not re-rendered — only `data-status` attributes and CSS classes are updated.
