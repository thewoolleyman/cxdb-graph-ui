## 5. CXDB Integration

The UI consumes four CXDB HTTP API endpoints: CQL context search (primary discovery), context list (fallback discovery), turn fetch (with pagination), and the server-generated instance list. The turn response includes typed/raw view modes, pagination cursors, and 24 Kilroy turn type IDs used for status derivation.

**For complete endpoint definitions, request/response schemas, turn type ID table, and CXDB internals documentation, see [`specification/contracts/cxdb-upstream.md`](../contracts/cxdb-upstream.md).**

### 5.2 Pipeline Discovery

CXDB is a generic context store with no first-class pipeline concept. The UI discovers which contexts belong to which pipeline by reading the `RunStarted` turn. When multiple CXDB instances are configured, the UI queries all of them and builds a unified mapping.

**Discovery algorithm:**

The algorithm has two phases: (1) identify Kilroy contexts using `client_tag`, and (2) fetch the `RunStarted` turn to extract `graph_name` and `run_id`.

Kilroy contexts are identified by their `client_tag`, which follows the format `kilroy/{run_id}`. The UI uses the CQL search endpoint (see `specification/contracts/cxdb-upstream.md`) as the primary discovery mechanism, with a fallback to the full context list for older CXDB versions. On each discovery call, the UI first attempts `GET /v1/contexts/search?q=tag ^= "kilroy/"`. If the endpoint returns 404, the UI sets a per-instance `cqlSupported` flag to `false` and falls back to `GET /v1/contexts?limit=10000` with client-side prefix filtering. The `cqlSupported` flag is checked on subsequent polls to skip the CQL attempt — it is reset when the CXDB instance becomes unreachable and then reconnects (since the instance may have been upgraded). When using CQL search, the server returns only `kilroy/`-prefixed contexts, eliminating the need for client-side prefix filtering and the 10,000-context limit heuristic. When using the fallback, the context list request must include `limit=10000` to override the CXDB default of 20 — without this, instances with many non-Kilroy contexts (e.g., Claude Code sessions) may push Kilroy contexts outside the default 20-context window.

**CQL discovery limitation (until Kilroy implements key 30).** As documented in the "`client_tag` stability requirement" section below, Kilroy does not currently embed context metadata at key 30 in turn payloads. CQL search relies on this metadata for `client_tag` indexing. Until Kilroy implements key 30, CQL search returns zero Kilroy contexts even though they exist — the CQL endpoint returns a valid 200 response with an empty `contexts` array, so the `cqlSupported` flag remains `true`. To handle this, the `discoverPipelines` pseudocode includes a **supplemental context list fetch** that runs on every poll cycle when CQL is supported, regardless of whether CQL returned contexts. The supplemental fetch serves three roles: (1) when CQL returns empty results, it provides `kilroy/`-prefixed contexts via session-tag resolution for active sessions; (2) when CQL returns some contexts but misses others (mixed deployment — new runs have key 30 and appear in CQL, but legacy active runs or runs whose metadata extraction has not yet completed appear only in the supplemental list with a non-null session-resolved `client_tag`), it provides the missing kilroy-prefixed contexts; (3) regardless of CQL result count, it collects null-tag contexts (completed runs whose `client_tag` is permanently null after session disconnect) into the null-tag backlog for `fetchFirstTurn` processing. The third role is essential during mixed deployments — once Kilroy begins emitting key 30, new runs appear in CQL results while older legacy runs (key 30 absent, session disconnected) are invisible to CQL. Without running the supplemental fetch even when CQL returns data, those legacy contexts are never queued for the null-tag backlog and become permanently inaccessible. `kilroy/`-prefixed contexts from the supplemental list are **always** merged into `contexts` using a dedup set built from `context_id` values already present in the CQL results — this prevents duplicates whether CQL returned zero results or many. Null-tag contexts are always collected. See the "`client_tag` stability requirement" section for the underlying limitation and the required Kilroy-side change.

```
FUNCTION discoverPipelines(cxdbInstances, knownMappings, cqlSupported):
    FOR EACH (index, instance) IN cxdbInstances:
        -- Phase 1: Fetch Kilroy contexts (CQL search or fallback)
        -- supplementalNullTagCandidates collects null-tag contexts encountered during
        -- the supplemental context list fetch (runs on every CQL-supported poll cycle,
        -- not only when CQL is empty). These are merged into nullTagCandidates below
        -- for backlog processing so legacy completed runs are found in mixed deployments.
        supplementalNullTagCandidates = []
        IF cqlSupported[index] != false:
            TRY:
                searchResponse = fetchCqlSearch(index, 'tag ^= "kilroy/"')
                contexts = searchResponse.contexts
                cqlSupported[index] = true
                -- Always fetch the full context list as a supplemental pass, regardless
                -- of whether CQL returned contexts. This is necessary for three cases:
                -- (a) CQL returned zero contexts: Kilroy contexts may exist but lack key 30
                --     metadata (current default), so session-tag-resolved client_tags are
                --     the only way to find active runs. Merge them into `contexts`.
                -- (b) CQL returned some contexts (mixed deployment): new runs with key 30
                --     appear in CQL, but legacy active runs or runs whose metadata extraction
                --     has not yet completed appear only in the supplemental list with a
                --     non-null client_tag (session-tag resolution). Without this merge, those
                --     contexts are silently dropped — their client_tag is non-null so they
                --     are never queued for the null-tag backlog, making them permanently
                --     undiscovered even though the agent is actively running.
                -- (c) Any deployment: completed runs whose sessions disconnected (client_tag
                --     permanently null due to absent key 30) are invisible to CQL and cannot
                --     be matched by prefix; collecting them here feeds the null-tag backlog.
                -- Kilroy-prefixed contexts from supplemental are merged by dedup on
                -- context_id to avoid adding entries already present from CQL. Null-tag
                -- contexts are always collected for the null-tag backlog regardless.
                supplemental = fetchContexts(index, limit=10000)
                -- Build a set of context_ids already returned by CQL so we can
                -- deduplicate when merging supplemental kilroy-prefixed contexts.
                -- CQL and the full context list can overlap: new runs that have
                -- key 30 metadata appear in both. Legacy runs or partially-upgraded
                -- runs may appear only in the supplemental list (e.g., active sessions
                -- on Kilroy instances not yet emitting key 30, or contexts that CQL
                -- missed due to metadata extraction lag). Deduplication by context_id
                -- ensures these contexts are merged without doubling existing ones.
                cqlContextIds = SET(ctx.context_id FOR ctx IN contexts)
                FOR EACH ctx IN supplemental:
                    IF ctx.client_tag IS NOT null AND ctx.client_tag.startsWith("kilroy/"):
                        -- Append kilroy-prefixed contexts from the supplemental list
                        -- that are absent from CQL results. This covers:
                        -- (a) CQL returned empty (current default, no key 30): all
                        --     active Kilroy contexts come from supplemental via session-tag.
                        -- (b) CQL returned some contexts (mixed deployment): new runs with
                        --     key 30 appear in CQL; legacy active runs that lack key 30
                        --     (or whose metadata lag behind) appear only in supplemental.
                        --     Without this merge, those active runs remain undiscovered
                        --     even though their client_tag is visible via session resolution.
                        IF ctx.context_id NOT IN cqlContextIds:
                            contexts.append(ctx)
                            cqlContextIds.add(ctx.context_id)  -- prevent double-append
                    ELSE IF ctx.client_tag IS null:
                        -- Null-tag context from the supplemental fetch. This context
                        -- may be a completed Kilroy run whose session has disconnected
                        -- (client_tag permanently null because key 30 is absent and the
                        -- session fallback in context_to_json is no longer available).
                        -- We cannot filter by prefix here, so collect it for the
                        -- null-tag backlog. The (index, ctx.context_id) key will be
                        -- checked against knownMappings in the backlog processing block.
                        supplementalNullTagCandidates.append(ctx)
            CATCH httpError:
                IF httpError.status == 404:
                    cqlSupported[index] = false
                    contexts = fetchContexts(index, limit=10000)  -- fallback
                ELSE IF httpError.status == 400:
                    -- CQL is supported but the query was rejected. Log the error
                    -- for debugging. Do NOT set cqlSupported[index] = false (CQL works,
                    -- the query just failed). Skip this instance for this poll cycle.
                    logWarning("CQL query error on instance " + index + ": " + httpError.body.error)
                    CONTINUE
                ELSE:
                    CONTINUE  -- instance unreachable, skip
        ELSE:
            contexts = fetchContexts(index, limit=10000)

        -- Null-tag backlog: contexts whose client_tag is null from either discovery path.
        -- These may be completed Kilroy runs whose session disconnected (making
        -- client_tag permanently null because key 30 is absent and context_to_json's
        -- session fallback no longer resolves the tag). Two sources feed this backlog:
        -- (1) the supplemental context list fetch (runs every CQL-supported poll cycle,
        --     not only when CQL is empty), collected above into supplementalNullTagCandidates.
        --     Running supplemental even when CQL has results is essential for mixed
        --     deployments: CQL finds new runs with key 30 metadata, but older legacy
        --     runs (no key 30, session disconnected) are invisible to CQL and would
        --     be permanently stranded without the supplemental pass.
        -- (2) the full context list fallback (CQL not supported), collected in the
        --     main context loop below into nullTagCandidates directly.
        -- We attempt fetchFirstTurn for up to NULL_TAG_BATCH_SIZE of the newest such
        -- contexts per poll cycle, prioritised by descending context_id (newest first).
        -- Contexts that are confirmed Kilroy are cached normally; confirmed
        -- non-Kilroy or transient errors are handled by the logic below.
        -- knownMappings is checked again in the batch processing block to handle
        -- supplementalNullTagCandidates that were not filtered against knownMappings
        -- in the supplemental fetch loop above.
        NULL_TAG_BATCH_SIZE = 5
        nullTagCandidates = supplementalNullTagCandidates  -- seed from supplemental path

        FOR EACH context IN contexts:
            key = (index, context.context_id)
            IF key IN knownMappings:
                CONTINUE  -- already discovered (positive or negative)

            -- When using fallback (no CQL), apply client-side prefix filter.
            -- IMPORTANT: Only cache a null mapping when client_tag is PRESENT but
            -- does NOT start with "kilroy/". If client_tag is null (absent), the
            -- context is a candidate for the null-tag backlog (see below).
            -- Rationale: on older CXDB versions (precisely those that use this fallback
            -- path), client_tag is resolved from the active session via context_to_json's
            -- .or_else fallback. This means client_tag can be legitimately null in two
            -- situations: (1) immediately after context creation before the session
            -- registers the context in context_to_session (brief startup window), and
            -- (2) after the run finishes and the session disconnects (SessionTracker.
            -- unregister removes the context-to-session mapping). For historical runs
            -- on legacy CXDB (completed + session gone), client_tag is PERMANENTLY
            -- null — so simply doing CONTINUE here would prevent those runs from ever
            -- being discovered. Instead, we enqueue them into the null-tag backlog.
            IF cqlSupported[index] == false:
                IF context.client_tag IS NOT null AND NOT context.client_tag.startsWith("kilroy/"):
                    knownMappings[key] = null  -- confirmed non-Kilroy context (tag present but wrong prefix)
                    CONTINUE
                ELSE IF context.client_tag IS null:
                    nullTagCandidates.append(context)
                    CONTINUE  -- will be processed in the null-tag batch below

            -- Phase 2: Fetch RunStarted turn (first turn of the context)
            -- fetchFirstTurn may fail due to transient errors (non-200 response,
            -- instance temporarily unreachable, msgpack decode failure). Distinguish
            -- between "confirmed non-RunStarted" and "unknown due to error."
            TRY:
                firstTurn = fetchFirstTurn(index, context.context_id, context.head_depth)
            CATCH fetchError:
                -- Transient failure: do NOT cache a null mapping.
                -- Leave the context unmapped so it is retried on the next poll cycle.
                CONTINUE

            IF firstTurn IS NOT null AND firstTurn.declared_type.type_id == "com.kilroy.attractor.RunStarted":
                graphName = firstTurn.data.graph_name
                runId = firstTurn.data.run_id
                -- Guard against null or empty graph_name. The registry bundle
                -- marks graph_name as optional, so a valid RunStarted can have
                -- graph_name absent or empty. Such a context can never match
                -- any pipeline. Cache it as null (same as non-Kilroy) since
                -- the first turn is immutable — retrying would not help.
                IF graphName IS null OR graphName == "":
                    knownMappings[key] = null
                    CONTINUE
                knownMappings[key] = { graphName, runId }
            ELSE IF firstTurn IS null:
                -- Empty context (no turns yet). This can happen during early pipeline
                -- startup or transient CXDB lag. Do NOT cache a null mapping — leave
                -- unmapped so discovery retries on the next poll cycle until a turn appears.
                CONTINUE
            ELSE:
                knownMappings[key] = null  -- has kilroy tag but confirmed non-RunStarted first turn

        -- Null-tag batch: attempt fetchFirstTurn for the newest N null-tag contexts.
        -- Sort descending by context_id (newest first — monotonic proxy for recency).
        -- This enables discovery of completed Kilroy runs on both CQL-enabled CXDB
        -- (supplemental path, post-disconnect) and legacy CXDB (fallback path).
        -- Note: contexts from the supplemental path (supplementalNullTagCandidates) were
        -- not filtered against knownMappings before being added; check here to avoid
        -- redundant fetchFirstTurn calls for already-cached contexts.
        -- IMPORTANT: iterate the full sorted list and use a counter (not a slice) to
        -- enforce the batch limit. Slicing to [0..NULL_TAG_BATCH_SIZE] before iteration
        -- causes starvation: once the first N contexts are cached in knownMappings they
        -- permanently occupy the top of the sorted list and the CONTINUE skips each of
        -- them, so contexts past index N-1 are never examined regardless of how many
        -- poll cycles pass.
        nullTagCandidates.sortByDescending(c => parseInt(c.context_id, 10))
        nullTagProcessed = 0
        FOR EACH context IN nullTagCandidates:
            IF nullTagProcessed >= NULL_TAG_BATCH_SIZE:
                BREAK
            key = (index, context.context_id)
            IF key IN knownMappings:
                CONTINUE  -- already cached (positive or negative); skip (does NOT count toward batch limit)
            TRY:
                firstTurn = fetchFirstTurn(index, context.context_id, context.head_depth)
                nullTagProcessed++  -- count against batch limit only when fetchFirstTurn is invoked
            CATCH fetchError:
                -- Transient failure: do NOT cache, retry next poll.
                -- Still counts against the batch limit (the fetch was attempted).
                nullTagProcessed++
                CONTINUE

            IF firstTurn IS NOT null AND firstTurn.declared_type.type_id == "com.kilroy.attractor.RunStarted":
                graphName = firstTurn.data.graph_name
                runId = firstTurn.data.run_id
                IF graphName IS null OR graphName == "":
                    knownMappings[key] = null  -- RunStarted but no graph_name; immutable, cache negative
                    CONTINUE
                knownMappings[key] = { graphName, runId }
            ELSE IF firstTurn IS null:
                -- Empty context. Leave unmapped, retry next poll.
                CONTINUE
            ELSE:
                -- First turn is not RunStarted → confirmed non-Kilroy.
                -- Cache null to avoid re-fetching.
                knownMappings[key] = null

    RETURN knownMappings
```

**Fetching the first turn.** CXDB returns turns oldest-first (ascending by position in the parent chain). The `before_turn_id` parameter paginates backward from a given turn ID. To reach the first turn of a context, the algorithm paginates backward from the head in bounded pages rather than fetching the entire context in a single request. This avoids O(headDepth) memory and latency costs — CXDB's `get_last` walks the parent chain sequentially, serializes every turn including decoded payloads, and transfers the entire response over HTTP. For deep contexts (headDepth in the tens of thousands), a single unbounded request could produce hundreds of megabytes of JSON, all of which would be discarded except the first turn.

**Using `view=raw` for discovery.** The `fetchFirstTurn` algorithm uses `view=raw` instead of the default `view=typed`. This eliminates the type registry dependency for pipeline discovery. The `declared_type` field (containing `type_id` and `type_version`) is present in both `view=raw` and `view=typed` responses — it comes from the turn metadata, not the type registry. For the `RunStarted` data fields (`graph_name`, `run_id`), `view=raw` returns the raw msgpack payload as base64-encoded bytes in the `bytes_b64` field. The UI decodes this client-side: base64-decode to bytes, then msgpack-decode to extract the known `RunStarted` fields. This avoids the bootstrap ordering problem where the type registry bundle has not yet been published when the UI first discovers a pipeline (the registry is typically published by the Kilroy runner at the start of the run). Without `view=raw`, `fetchFirstTurn` would fail for all contexts during the window between context creation and registry publication, delaying pipeline discovery by 1-3 poll cycles (3-9 seconds). The regular turn polling (Section 6.1 step 4) continues using the default `view=typed` for the status overlay, since those fields are more complex and benefit from server-side projection.

```
FUNCTION fetchFirstTurn(cxdbIndex, contextId, headDepth):
    IF headDepth == 0:
        -- If headDepth == 0, the first turn is either at the head or one hop
        -- away. For non-forked contexts, headDepth 0 means at most one turn.
        -- For forked contexts created from a depth-0 base turn (e.g., forking
        -- directly from RunStarted), headDepth starts at 0 but the context
        -- may later accumulate turns at depths 1, 2, ... — in that case,
        -- limit=1 returns the newest turn (via get_last), not depth-0.
        -- Guard: verify the returned turn has depth == 0. If not, fall through
        -- to the general pagination loop which handles arbitrary depths.
        --
        -- Note: head_depth is updated on every append_turn (turn_store/mod.rs).
        -- A context with head_depth == 0 has either zero appended turns (just
        -- created/forked) or exactly one turn at depth 0. The depth == 0 guard
        -- is defensive — in practice, get_last(limit=1) for a head_depth == 0
        -- context always returns either empty (no turns) or a depth-0 turn.
        -- Use view=raw to avoid type registry dependency.
        response = fetchTurns(cxdbIndex, contextId, limit=1, view="raw")
        IF response.turns IS EMPTY:
            RETURN null
        IF response.turns[0].depth == 0:
            RETURN decodeFirstTurn(response.turns[0])
        -- Fall through to pagination: the context was forked from depth-0
        -- but has accumulated its own turns, so depth-0 is not at the head.

    -- Paginate backward from the head in bounded pages.
    -- Each page fetches up to PAGE_SIZE turns (100). Check whether the page
    -- contains a turn with depth == 0 (the first turn). If not, continue
    -- paginating using before_turn_id. Cap at MAX_PAGES (50) to prevent
    -- runaway pagination for extremely deep contexts.
    -- Use view=raw to avoid type registry dependency.
    PAGE_SIZE = 100
    MAX_PAGES = 50
    cursor = 0  -- 0 means "start from head" (no before_turn_id)

    FOR page = 1 TO MAX_PAGES:
        IF cursor == 0:
            response = fetchTurns(cxdbIndex, contextId, limit=PAGE_SIZE, view="raw")
        ELSE:
            response = fetchTurns(cxdbIndex, contextId, limit=PAGE_SIZE, before_turn_id=cursor, view="raw")

        IF response.turns IS EMPTY:
            RETURN null

        -- Turns are oldest-first. Check if depth=0 is in this page.
        IF response.turns[0].depth == 0:
            RETURN decodeFirstTurn(response.turns[0])

        -- The oldest turn in this page is not depth=0. Continue paginating.
        cursor = response.turns[0].turn_id  -- oldest turn's ID becomes the next before_turn_id
        -- CXDB's get_before walks backward from before_turn_id's parent,
        -- so the next page will contain turns older than this one.

    -- Exceeded MAX_PAGES without finding depth=0.
    -- This context is too deep for first-turn discovery. Return null so it
    -- is retried on subsequent polls (not cached as a negative result).
    -- Implementations SHOULD log a warning here (e.g., "discovery deferred:
    -- context {contextId} exceeds MAX_PAGES pagination cap") so that operators
    -- can recognise when a context is consistently skipped due to unusual depth.
    RETURN null

FUNCTION decodeFirstTurn(rawTurn):
    -- Extract declared_type (available in both raw and typed views)
    typeId = rawTurn.declared_type.type_id
    IF typeId != "com.kilroy.attractor.RunStarted":
        RETURN { declared_type: rawTurn.declared_type, data: null }

    -- Decode the raw msgpack payload to extract graph_name and run_id.
    -- The raw payload uses integer tags as map keys (not field names).
    -- Go's msgpack encoder produces string-encoded integer keys (e.g., the
    -- string "1" instead of the integer 1). CXDB's key_to_tag function
    -- (store.rs, projection/mod.rs) handles both forms. The browser-side
    -- decoder must do the same: for each map key, try parseInt if it is a
    -- string, or use the integer directly.
    --
    -- RunStarted field tags (from kilroy-attractor-v1 bundle, version 1):
    --   Tag 1: run_id (string)
    --   Tag 8: graph_name (string, optional)
    -- These tags are stable within bundle version 1. CXDB's type registry
    -- versioning model ensures existing tags are never reassigned — new
    -- bundle versions add fields with new tags. The full RunStarted v1
    -- field inventory is: run_id (1), timestamp_ms (2), repo_path (3),
    -- base_sha (4), run_branch (5), logs_root (6), worktree_dir (7),
    -- graph_name (8), goal (9), modeldb_catalog_sha256 (10),
    -- modeldb_catalog_source (11), graph_dot (12). The graph_dot field
    -- (optional string) contains the full pipeline DOT source at run start
    -- time, available for future features (e.g., reconstructing the exact
    -- graph used for a historical run) but unused by the initial
    -- implementation. Only tags 1 and 8 are used by the UI.
    -- bytes_b64 is present because fetchFirstTurn omits the bytes_render parameter,
    -- defaulting to base64. If bytes_render were set to "hex" or "len_only", the
    -- response would use bytes_hex or bytes_len instead and this access would fail.
    bytes = base64Decode(rawTurn.bytes_b64)
    -- The @msgpack/msgpack library (pinned at 3.0.0-beta2) always decodes
    -- MessagePack maps to plain JavaScript objects, never Map instances.
    -- There is no `useMaps` or equivalent option in this library version.
    -- Integer keys in the msgpack payload are accepted by the default
    -- mapKeyConverter and are automatically coerced to string keys by
    -- JavaScript's object property semantics (e.g., payload[8] and
    -- payload["8"] resolve identically). No special decoder configuration
    -- is needed.
    -- If a different msgpack decoder is used in the future that returns
    -- Map objects, convert with Object.fromEntries(payload.entries())
    -- before field access.
    payload = msgpackDecode(bytes)
    -- Access fields by their string-encoded integer tag.
    -- Go's msgpack encoder produces string keys (e.g., "1" not 1).
    -- The || fallback handles both forms defensively.
    RETURN {
        declared_type: rawTurn.declared_type,
        data: { graph_name: payload["8"] || payload[8], run_id: payload["1"] || payload[1] }
    }
```

**Cross-context traversal for forked contexts.** The `fetchFirstTurn` pagination follows CXDB's parent chain via `parent_turn_id` links. For forked contexts (created for parallel branches), the parent chain extends across context boundaries — the child context's turns link back to the parent context's turns via the fork point's `parent_turn_id`. Walking to depth 0 therefore discovers the parent context's `RunStarted` turn, not a turn within the child context. This is correct because Kilroy's parallel branch contexts share the parent's `RunStarted` (same `graph_name`, same `run_id`) via the linked parent chain. CXDB's `get_before` implementation (`turn_store/mod.rs`) walks `parent_turn_id` without any context boundary check, confirming this cross-context traversal. If a future Kilroy version emits a new `RunStarted` in each forked child context, the pagination would still work (it would find the child's `RunStarted` at the child's depth-0 position), but the current behavior discovers the parent's `RunStarted` instead.

**Pagination cost.** In the worst case (headDepth = 5000), fetching the first turn requires 50 paginated requests of 100 turns each. For typical Kilroy contexts (headDepth < 1000), this completes in under 10 pages. The `client_tag` prefix filter (Phase 1) ensures pagination only runs for Kilroy contexts, not for unrelated contexts that may share the CXDB instance. Each page request transfers at most 100 turns worth of JSON (roughly 50–200 KB depending on payload size), avoiding the memory spike of a single unbounded request. The `MAX_PAGES` cap of 50 means contexts deeper than ~5000 turns are skipped for discovery; these are retried on subsequent polls in case the depth was a transient artifact. When a context repeatedly hits the pagination cap (i.e., returns `null` from `fetchFirstTurn` poll after poll due to depth, not due to transient network errors), implementations should emit a warning log to help operators diagnose the situation — the context will keep being retried but discovery will be permanently deferred until the context's head depth shrinks below the cap or a future HTTP endpoint exposes `get_first_turn` directly.

**Note on CXDB internals.** The CXDB turn store has a `get_first_turn` method that walks back from the head to find depth=0 directly, but this is not exposed via the HTTP API. If a future CXDB release adds an HTTP endpoint for fetching the first turn (or exposes the binary protocol's `GetRangeByDepth` over HTTP), the pagination approach here should be replaced with a single targeted request. This runs once per context (results are cached).

The `graph_name` from the `RunStarted` turn is matched against the normalized graph ID in each loaded DOT file (Section 4.4). The normalization rules (unquote, unescape, trim) apply to the DOT-side graph ID; the `graph_name` value from CXDB is compared as-is. In practice, Kilroy's DOT parser (`kilroy/internal/attractor/dot/parser.go`) only accepts unquoted graph identifiers (the `tokenIdent` lexer path), so `graph_name` in `RunStarted` is always an unquoted, unescaped identifier that matches the DOT graph ID without normalization mismatch. If a future Kilroy version supports quoted graph names in DOT files, both the Kilroy parser and the UI's normalization would need to produce the same unquoted value — but this is not a concern for the initial implementation. Contexts whose `graph_name` matches the currently displayed pipeline are used for the status overlay — regardless of which CXDB instance they reside on.

The `RunStarted` turn also contains a `run_id` field (see `specification/contracts/cxdb-upstream.md` for the full field inventory) that uniquely identifies the pipeline run. All contexts belonging to the same run (e.g., parallel branches) share the same `run_id`. The discovery algorithm records both `graph_name` and `run_id` for each context.

**Caching.** The context-to-pipeline mapping is cached in memory, keyed by `(cxdb_index, context_id)`. Both positive results (RunStarted contexts mapped to a pipeline) and negative results (non-Kilroy contexts and confirmed non-RunStarted contexts stored as `null`) are cached. The first turn of a context is immutable — once a context is successfully classified, it is never re-fetched. Only newly appeared context IDs (and previously failed or empty fetches that were not cached) trigger discovery requests. The `client_tag` prefix filter (whether server-side via CQL or client-side in the fallback path) prevents fetching turns for non-Kilroy contexts entirely. Three cases are left unmapped (not cached as `null`) and retried on subsequent polls: (a) when a `fetchFirstTurn` call fails due to a transient error (non-200 response, timeout), (b) when `fetchFirstTurn` returns `null` (empty context with no turns yet — common during early pipeline startup or transient CXDB lag), and (c) when `client_tag` is `null` — null-tag contexts are queued in the null-tag backlog (up to `NULL_TAG_BATCH_SIZE` = 5 per poll cycle, newest first by context_id) and subjected to `fetchFirstTurn`. This applies in both discovery paths: the CQL-empty supplemental path (CQL-enabled CXDB where Kilroy lacks key 30 and the session has disconnected) and the full context list fallback path (legacy CXDB without CQL). If `fetchFirstTurn` confirms the context is a Kilroy run (first turn is `RunStarted`), it is cached positively. If it confirms a non-Kilroy first turn, it is cached as `null`. If the fetch fails transiently, the context remains uncached and is retried in a future poll cycle. This mechanism enables discovery of completed Kilroy runs on both CQL-enabled and legacy CXDB deployments where `client_tag` is permanently `null` after session disconnect. This prevents transient failures, empty contexts, and transiently-missing tags from permanently classifying a valid Kilroy context as non-Kilroy.

**`client_tag` stability requirement and current limitation.** The `client_tag` prefix filter assumes `client_tag` is stable across polls. CXDB resolves `client_tag` with a fallback chain: first from stored metadata (extracted from the first turn's msgpack payload key 30), then from the active session's tag. If the first turn's payload does not include context metadata (key 30 is absent), the `client_tag` in the context list is only present while the session is active (`is_live == true`). Once the session disconnects, `client_tag` becomes `null`, and the UI's prefix filter would fail to match — permanently excluding the context from discovery if it has already been cached as non-Kilroy. **Kilroy must embed `client_tag` in the first turn's context metadata** (key 30) for reliable classification.

**Current state: Kilroy does NOT embed key 30.** As of the current Kilroy implementation, no component injects key 30 into turn payloads. Kilroy's `EncodeTurnPayload` (`msgpack_encode.go`) only emits tags defined in the `kilroy-attractor-v1` registry bundle (tags 1-12 for `RunStarted`). Tag 30 is not in the bundle. `BinaryClient.AppendTurn` (`binary_client.go`) writes raw msgpack payload bytes to the wire without injecting additional metadata. CXDB's binary protocol handler (`protocol/mod.rs`, `parse_append_turn`) passes the payload verbatim to the store. The key 30 / `context_metadata` convention is defined in CXDB's Go client types (`cxdb/clients/go/types/conversation.go` line 167: `ContextMetadata *ContextMetadata \`msgpack:"30"\``) as a client-side convention for `ConversationItem` users. Kilroy uses its own type system (`com.kilroy.attractor.*`) and does not use `ConversationItem`.

**Consequences for discovery:**

- **CQL search returns zero Kilroy contexts.** CXDB's CQL secondary indexes (`cql/indexes.rs`) are built from `context_metadata_cache`, which only has `client_tag` if `extract_context_metadata` (`store.rs`) found key 30 in the payload. Since Kilroy payloads lack key 30, the query `tag ^= "kilroy/"` returns zero results. The CQL-first discovery path produces empty results for all Kilroy contexts.

- **Context list fallback works only during active sessions.** The fallback endpoint resolves `client_tag` from the active session's tag via `context_to_json`'s `.or_else` fallback. This works while the Kilroy agent is connected. After session disconnect (`SessionTracker.unregister` in `metrics.rs` removes all context-to-session mappings), `client_tag` becomes `null` for all that run's contexts. Completed pipelines become undiscoverable on fresh page loads.

- **The UI's `knownMappings` cache and null-tag backlog mitigate this.** Once a context is discovered during an active session, it remains in the cache. For a fresh page load after pipeline completion (when `client_tag` is permanently null), the null-tag backlog mechanism (`NULL_TAG_BATCH_SIZE` = 5 per poll cycle, iterated with a counter over the full candidate list to prevent starvation) attempts `fetchFirstTurn` for unclassified null-tag contexts. This applies in both paths: for CQL-enabled CXDB (where the supplemental context list fetch — running on every CQL-supported poll cycle — collects null-tag contexts), and for legacy CXDB without CQL (where the full context list fallback returns null-tag contexts). Running the supplemental fetch on every poll cycle (not only when CQL is empty) is essential for mixed deployments where CQL finds new runs with key 30 but legacy completed runs have null `client_tag` and are invisible to CQL. Discovery completes within a bounded number of poll cycles proportional to the number of null-tag contexts divided by `NULL_TAG_BATCH_SIZE`.

**Required Kilroy-side change (prerequisite).** For reliable discovery — both CQL search and post-disconnect context list lookups — Kilroy must embed context metadata at key 30 in the first turn's payload. This can be done by: (a) adding a tag 30 field to the `RunStarted` type in the `kilroy-attractor-v1` registry bundle, or (b) wrapping the encoded payload in an outer map that includes key 30 alongside the registry-encoded data. Until this change is made, the context list fallback with session-tag resolution is the only reliable discovery path, limited to active sessions. The UI's existing `knownMappings` cache and the graceful-degradation principle (Section 1.2) ensure that pipelines discovered during an active session remain visible for the duration of the browser session.

**Fallback behavior until Kilroy implements key 30.** The `discoverPipelines` algorithm handles the current state via the supplemental context list fetch. The algorithm issues a supplemental `fetchContexts(index, limit=10000)` on every CQL-supported poll cycle regardless of whether CQL returned results. The supplemental fetch serves three roles:

1. **CQL returned zero results (current default, no key 30):** All Kilroy contexts have `client_tag` resolved from the active session's tag (`context_to_json`'s `.or_else` fallback). These appear in the supplemental fetch with non-null `kilroy/`-prefixed tags but are invisible to CQL. They are merged into `contexts` via dedup on `context_id`, enabling discovery of all active runs.

2. **CQL returned some results but missed others (mixed deployment):** Once Kilroy partially upgrades to emit key 30, new runs appear in CQL results while older active runs — whose key 30 metadata has not yet been extracted, or whose instances haven't been upgraded — appear only in the supplemental list with a non-null session-resolved `client_tag`. The old `IF contexts IS EMPTY` guard would silently drop these, making those runs permanently undiscovered even though their agents are running. The dedup-based merge ensures they are appended to `contexts` and reach Phase 2 discovery.

3. **Any deployment (null-tag backlog):** Completed runs whose sessions have disconnected — where `client_tag` becomes permanently `null` after session disconnect — are collected into `supplementalNullTagCandidates` on every supplemental pass. These are processed via the null-tag backlog: up to `NULL_TAG_BATCH_SIZE` = 5 per poll cycle (iterated with a counter over the full sorted list to prevent starvation) are subjected to `fetchFirstTurn`. This enables discovery of completed pipelines on CQL-enabled CXDB instances even after all sessions disconnect.

A fresh page load after all sessions disconnect will therefore discover completed pipelines within a bounded number of poll cycles, proportional to the number of null-tag contexts divided by `NULL_TAG_BATCH_SIZE`. The supplemental fetch adds one additional HTTP request per CXDB instance per poll cycle when CQL is supported, which is acceptable overhead given the graceful-degradation requirement.

**Metadata extraction asymmetry for forked contexts.** CXDB populates the `context_metadata_cache` via two paths: (1) on append, `maybe_cache_metadata` (`store.rs` lines 161-178) extracts metadata from the first turn appended to the context — for new contexts this is the depth-0 `RunStarted` turn, but for forked contexts this is the first turn appended to the child (at depth = base_depth + 1), which is an application turn (e.g., `StageStarted`, `Prompt`), not `RunStarted`; (2) on cache miss (e.g., after CXDB restart), `load_context_metadata` (`store.rs` lines 151-156) calls `get_first_turn(context_id)`, which walks the parent chain to depth=0 — crossing context boundaries for forked contexts and finding the parent's `RunStarted` turn. For forked contexts, these two paths extract metadata from **different turns** with potentially different payloads. The Go client types confirm the convention: `conversation.go` line 165 says "By convention, only included in the first turn (depth=1) of a context."

**Current state (key 30 absent).** Since Kilroy does not currently embed key 30 in any turn payload (see "`client_tag` stability requirement" above), neither extraction path finds `client_tag` metadata. `extract_context_metadata` returns `None` for `client_tag` regardless of which turn it examines. The asymmetry between the two extraction paths is structurally real but currently moot — both paths yield `None`.

**After Kilroy implements key 30.** Once Kilroy embeds `client_tag` in context metadata (key 30) of both the parent's `RunStarted` and the child's first appended turn, `maybe_cache_metadata` will find it on the hot path for forked contexts. After a CXDB restart, `load_context_metadata` will find the parent's `RunStarted` metadata instead, which also has `client_tag`. Both paths will produce the same `client_tag` value (`kilroy/{run_id}`) because Kilroy uses the same `run_id` for parent and child contexts. However, other metadata fields (`title`, `labels`) may differ between the two turns. This asymmetry would be invisible during normal operation but an implementer testing against a freshly-restarted CXDB might observe different CQL search results than against a long-running instance.

**Metadata labels optimization (not required for initial implementation).** The CXDB server extracts and caches metadata from the first turn of every context (key 30 of the msgpack payload), including `client_tag`, `title`, and `labels`. If Kilroy embeds `graph_name` and `run_id` in the context metadata labels (e.g., `["kilroy:graph=alpha_pipeline", "kilroy:run=01KJ7..."]`), the UI could read them from the context list response's `labels` field, eliminating all `fetchFirstTurn` pagination. However, the CQL search response (the primary discovery path) does not include `labels` — only the full context list endpoint does (see `specification/contracts/cxdb-upstream.md`). This means the optimization is incompatible with the CQL-first discovery path without one of: (a) falling back to the context list endpoint (losing CQL's scalability benefits), (b) making separate per-context requests to `GET /v1/contexts/{id}` which does return `labels`, (c) a CXDB enhancement to include `labels` in CQL search results, or (d) using server-side SSE subscription (non-goal #11) — the `ContextMetadataUpdated` SSE event carries `labels` (confirmed in CXDB's `events.rs` and `http/mod.rs`), so the Go proxy server could collect labels from these events and serve them without per-context HTTP requests, elegantly bypassing both the CQL limitation and per-context HTTP overhead. Option (d) is the most efficient workaround because it avoids polling entirely for metadata discovery, but it requires the server-side SSE infrastructure described in non-goal #11. This is a Kilroy-side change (not a CXDB change) that would simplify discovery significantly but requires solving the CQL `labels` gap. The pagination approach works correctly today and is used for the initial implementation.

**Context lineage optimization (not required for initial implementation).** CXDB tracks cross-context lineage via `ContextLinked` events. When a context is forked from another (e.g., for parallel branches), CXDB records `parent_context_id`, `root_context_id`, and `spawn_reason` in the context's provenance. The context list endpoint returns this data when `include_lineage=1` is passed. A future optimization could use lineage to skip `fetchFirstTurn` for child contexts: if a child's `parent_context_id` is already in `knownMappings`, the child inherits the parent's `graph_name`/`run_id` mapping. This would reduce discovery latency proportionally to the number of parallel branches. The current approach (fetching the first turn independently for each context) is correct but performs redundant work for forked contexts that share the same `RunStarted` data.

**Multiple runs of the same pipeline.** When CXDB contains contexts from multiple runs of the same pipeline (same `graph_name`, different `run_id`), the UI uses only the most recent run. The most recent run is determined by lexicographic comparison of `run_id` values across run groups — the run with the lexicographically greatest `run_id` is the active run. **Why `run_id` ULID lex order.** Kilroy generates `run_id` as a ULID (Universally Unique Lexicographically Sortable Identifier) using `github.com/oklog/ulid/v2` (`internal/attractor/engine/runid.go`): `ulid.New(ulid.Timestamp(t), entropy)` encodes the creation timestamp in the most significant 48 bits. Lexicographic order on ULIDs is therefore equivalent to time order: a lexicographically larger `run_id` means a more recently started run, regardless of which CXDB instance the contexts reside on. **Why not `context_id`.** CXDB's `context_id` is allocated from a per-instance monotonically increasing counter (`turn_store/mod.rs` lines 347-348) that starts at 1 and is independent on each CXDB server. When multiple CXDB instances are configured, the counter on each instance grows independently: CXDB-0 may have accumulated 550 contexts (an old run's `context_id`s are 500–550) while CXDB-1 has only 20 contexts (a newer run's `context_id`s are 12–20). Comparing `context_id` values across instances would incorrectly select CXDB-0's old run (higher counter) over CXDB-1's newer run (lower counter). `run_id` ULID comparison is immune to this because it encodes the wall-clock time of run creation, not a per-instance counter. **Why not `created_at_unix_ms`.** CXDB's `ContextHead.created_at_unix_ms` is updated on every `append_turn` (`turn_store/mod.rs` lines 458-463) — it reflects the most recent turn's timestamp, not the context's original creation time. Using `max(created_at_unix_ms)` for run selection would select the run with the most recent *activity*, not the most recently *created* run. This causes incorrect flips when an older run's context receives a late turn (e.g., a delayed parallel branch completing) after a newer run has started. Contexts from older runs are ignored for status overlay purposes. This prevents stale data from a completed run from conflicting with an in-progress run.

**Cross-instance merging.** If contexts from the same run (same `run_id`) exist on multiple CXDB instances (e.g., parallel branches written to separate servers), their turns are merged into a single status map. The UI does not distinguish which CXDB instance a turn came from.
