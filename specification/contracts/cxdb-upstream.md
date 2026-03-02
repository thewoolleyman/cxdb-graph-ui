# CXDB Upstream Contract

This document defines the CXDB HTTP API surface consumed by the CXDB Graph UI — the contract between the UI and upstream CXDB instances.

---

## API Endpoints Consumed

The UI reads from CXDB HTTP APIs (default port 9110). All requests go through the server's `/api/cxdb/{index}/*` proxy, where `{index}` identifies the CXDB instance.

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/cxdb/instances` | GET | Server-generated list of configured CXDB instances |
| `/api/cxdb/{i}/v1/contexts/search?q={cql}` | GET | CQL search for contexts on CXDB instance `i` (primary discovery) |
| `/api/cxdb/{i}/v1/contexts` | GET | List all contexts on CXDB instance `i` (fallback discovery) |
| `/api/cxdb/{i}/v1/contexts/{id}/turns?limit={n}&before_turn_id={id}` | GET | Fetch turns for a context on instance `i` |

## Context Discovery Endpoints

**Primary: CQL search.** CXDB provides a CQL (Context Query Language) search endpoint at `GET /v1/contexts/search?q={cql}` that supports server-side prefix filtering via the `^=` (starts with) operator:

```
GET /v1/contexts/search?q=tag ^= "kilroy/"
```

This returns only contexts whose `client_tag` starts with `"kilroy/"`, using CXDB's secondary indexes (`tag_sorted` B-tree in `server/src/cql/indexes.rs`) for efficient server-side filtering. The CQL search response has a different shape from the context list response:

```json
{
  "contexts": [],
  "total_count": 5,
  "elapsed_ms": 2,
  "query": "tag ^= \"kilroy/\""
}
```

Each context object in the `contexts` array contains: `context_id`, `head_turn_id`, `head_depth`, `created_at_unix_ms`, `is_live`, `client_tag` (from cached metadata), and `title` (from cached metadata). The CQL search response does **not** include `labels`, `session_id`, `last_activity_at`, `lineage`, `provenance`, `active_sessions`, or `active_tags` — the CQL endpoint builds lightweight context objects directly rather than calling the full `context_to_json` used by the context list endpoint. The absence of `labels` is significant for the metadata labels optimization (Section 5.5): since CQL search is the primary discovery path, the optimization cannot read `graph_name`/`run_id` from labels without per-context requests or a CXDB enhancement to include `labels` in CQL results. If the context lineage optimization (Section 5.5) is implemented in the future, the UI would need a separate context list request or individual context fetches for lineage data.

**`client_tag` resolution asymmetry.** The `client_tag` field is resolved differently between the two discovery endpoints:

- **CQL search**: `client_tag` comes from cached metadata only (extracted from the first turn's msgpack payload key 30, stored in `context_metadata_cache`). If metadata extraction has not yet occurred (context just created, first turn not yet appended or not yet processed), `client_tag` is absent from the context object.
- **Context list fallback**: `client_tag` comes from cached metadata first, then falls back to the active session's tag (`context_to_json`'s `.or_else` fallback to the active session's `client_tag`). This means `client_tag` is available for live contexts even before metadata extraction completes.

This difference means a context may appear in the fallback context list (with `client_tag` resolved from the active session) before it appears in CQL search results (which require cached metadata). The bootstrap lag note below covers the timing implications. An implementer testing with the context list fallback might observe `client_tag` appearing for all live contexts, then be surprised when switching to CQL to find it missing during the brief metadata extraction window for newly created contexts.

CQL results are sorted by `context_id` descending (most recent first), as implemented in CXDB's `store.rs`. Since CXDB allocates context IDs monotonically from a global counter, this is effectively equivalent to creation-time ordering. The context list fallback sorts by `created_at_unix_ms` descending — note that `created_at_unix_ms` on `ContextHead` is updated on every `append_turn` (`turn_store/mod.rs` lines 458-463), so this sort reflects the most recent *activity* time, not creation time. The `determineActiveRuns` algorithm (Section 6.1) does not depend on response ordering — it scans all candidates to find the maximum `context_id` — so this difference has no functional impact.

The CQL search endpoint also accepts an optional `limit` query parameter. When present, matching contexts are sorted by `context_id` descending and truncated to the specified count. The response's `total_count` field reflects the number of matching contexts **before** truncation — it may be larger than `contexts.length` when a `limit` is applied (CXDB's `store.rs` lines 389-392 compute `total_count` before `sorted_ids.truncate(limit)`). The UI omits `limit` to retrieve all Kilroy contexts, so `total_count == contexts.length` in normal operation. The discovery algorithm needs to see all contexts to determine the active run. Environments with hundreds of historical Kilroy runs will produce proportionally larger CQL search responses, but this is acceptable for the initial implementation — paginating CQL results would complicate discovery logic for a scenario that is not performance-critical at expected scale.

**CQL error response.** When a CQL query is malformed, the endpoint returns 400 with a JSON error body:

```json
{
  "error": "Parse error: unexpected token at position 5",
  "error_type": "ParseError",
  "position": 5,
  "field": null
}
```

This is distinct from 404 (CQL not supported) and network errors (instance unreachable). A 400 means CQL is supported but the query was rejected. Since the UI's query (`tag ^= "kilroy/"`) is hardcoded and correct, a 400 is unlikely in practice but could occur against a misconfigured proxy or incompatible CQL version. The `discoverPipelines` pseudocode (Section 5.5) handles this case explicitly.

**CQL search bootstrap lag.** CQL secondary indexes are built from cached metadata, which is extracted from the first turn's msgpack payload. A newly created context may not appear in CQL search results until its first turn is appended and metadata is extracted. The context list fallback resolves `client_tag` from the active session as well (via `context_to_json`'s session-tag fallback), so it can discover contexts earlier. This race window is typically sub-second (the time between context creation and first turn append) and does not affect the UI's behavior — the context would be discovered on the next poll cycle after metadata extraction. No code change is needed; this is a documentation note for completeness.

CQL search eliminates two problems that the context list fallback has: (1) the `limit=10000` heuristic and its truncation risk — CQL returns all matching contexts regardless of total context count, and (2) client-side prefix filtering — the server handles it, reducing payload size and client complexity.

**Fallback: context list.** If the CQL search endpoint returns 404 (indicating an older CXDB version that lacks CQL support), the UI falls back to the full context list:

```
GET /v1/contexts?limit=10000
```

The fallback endpoint supports a `limit` query parameter (default: 20) controlling the maximum number of contexts returned. Contexts are returned in **descending order by `created_at_unix_ms`** (which reflects the most recent turn's timestamp, not the original context creation time — see `ContextHead.created_at_unix_ms` update semantics below), matching CXDB's `list_recent_contexts` implementation which sorts by `created_at_unix_ms` descending. The UI passes `limit=10000` to ensure all contexts are returned — the default of 20 is insufficient when non-Kilroy contexts (e.g., Claude Code sessions) accumulate on the instance.

**Fallback truncation risk.** The `limit=10000` value is a heuristic. If a CXDB instance accumulates more than 10,000 contexts over its lifetime (plausible on a shared development server running for weeks), the oldest contexts will be truncated from the response. Because contexts are ordered newest-first, this truncation affects the oldest contexts. Active Kilroy pipeline contexts are typically recent and unlikely to be truncated, but long-running pipelines on busy instances could be affected. The failure mode is silent: pipelines whose contexts are truncated will not be discovered, and no error is surfaced. This truncation risk is the primary reason to prefer CQL search.

The fallback endpoint also supports a `tag` query parameter for server-side filtering: `GET /v1/contexts?tag=kilroy/...` returns only contexts whose `client_tag` matches the given value exactly. The UI does not use server-side tag filtering because the `run_id` portion of the Kilroy tag varies; the CQL `^=` operator handles prefix matching instead. **Caution:** The `tag` query parameter filters AFTER the `limit` truncation. CXDB calls `list_recent_contexts(limit)` first (line 221), then applies `tag_filter` to the truncated result (lines 236-241). If 15,000 contexts exist and `limit=10000`, the oldest 5,000 are discarded before `tag` filtering runs. Matching contexts in the discarded tail are silently lost. This is an additional reason the UI uses client-side prefix filtering (for the fallback path) rather than server-side `tag` filtering — and why the CQL `^=` operator (which filters before response construction) is the preferred discovery path.

Returns:

```json
{
  "active_sessions": [
    {
      "client_tag": "kilroy/01KJ7JPB3C2AHNP9AYX7D19BWK",
      "session_id": "54",
      "connected_at": 1771929210000,
      "last_activity_at": 1771929214261,
      "context_count": 2,
      "peer_addr": "127.0.0.1:54321"
    }
  ],
  "active_tags": ["kilroy/01KJ7JPB3C2AHNP9AYX7D19BWK"],
  "contexts": [
    {
      "context_id": "33",
      "created_at_unix_ms": 1771929214262,
      "head_depth": 100,
      "head_turn_id": "6068",
      "is_live": false,
      "client_tag": "kilroy/01KJ7JPB3C2AHNP9AYX7D19BWK"
    }
  ],
  "count": 20
}
```

Each context object includes a `client_tag` field (optional string) identifying the application that created it. Kilroy sets this to `kilroy/{run_id}`. CXDB filters out empty-string `client_tag` values in the context list fallback endpoint — `context_to_json`'s `.filter(|t| !t.is_empty())` converts empty strings to `None`, which is omitted from the JSON response. The CQL search endpoint does not apply this filter (it reads directly from cached metadata), but `extract_context_metadata` stores whatever the msgpack payload contains, so an empty-string `client_tag` could theoretically appear in CQL results if the first turn's metadata key 1 is an empty string. In practice, Kilroy always sets a non-empty `client_tag` (`kilroy/{run_id}`), so this asymmetry has no functional impact. The `client_tag` field is either a non-empty string or absent (null) in normal operation. The UI's prefix filter need not check for empty strings. The `is_live` field is `true` when the context has an active session writing to it; the UI uses this for stale pipeline detection (see Section 6.2). Additional fields (`title`, `labels`, `session_id`, `last_activity_at`) may be present but are unused by the UI.

**`is_live` resolution.** The `is_live` field is resolved dynamically from CXDB's session tracker, not from a stored field. Both the CQL search endpoint (via `session_tracker.get_session_for_context(context_id)`, `is_live = session.is_some()`) and the context list fallback (`context_to_json`) resolve `is_live` identically. When a binary protocol session disconnects (agent exits or crashes), the session is immediately removed from the tracker (`metrics.rs` `disconnect_session`). The next HTTP request for that context sees `is_live: false` with no caching delay. This means stale detection (Section 6.2) can fire on the very first poll cycle after an agent crash — `is_live` transitions instantaneously, not gradually.

## Turn Response

```
GET /v1/contexts/{context_id}/turns?limit=100
```

Returns (turns are always ordered oldest-first — ascending by depth within the context's parent chain):

```json
{
  "meta": {
    "context_id": "33",
    "head_depth": 104,
    "head_turn_id": "6068",
    "registry_bundle_id": "kilroy-attractor-v1#283a6b572820"
  },
  "turns": [
    {
      "data": {
        "node_id": "implement",
        "run_id": "01KJ7JPB3C2AHNP9AYX7D19BWK",
        "tool_name": "shell",
        "arguments_json": "{\"command\":\"cargo test\"}",
        "output": "test result: ok...",
        "is_error": false
      },
      "declared_type": {
        "type_id": "com.kilroy.attractor.ToolResult",
        "type_version": 1
      },
      "decoded_as": {
        "type_id": "com.kilroy.attractor.ToolResult",
        "type_version": 1
      },
      "depth": 102,
      "turn_id": "6066",
      "parent_turn_id": "6065"
    }
  ],
  "next_before_turn_id": "6066"
}
```

**Query parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `limit` | `64` | Maximum number of turns to return (parsed as u32; no server-enforced maximum). The UI uses 100 for polling and discovery pagination. |
| `before_turn_id` | `0` | Pagination cursor. When `0` (default) or omitted, returns the most recent `limit` turns from the context head, in oldest-first order — both values are equivalent and delegate to CXDB's `get_last(context_id, limit)` internally (`turn_store/mod.rs` line 535-536). When set to a non-zero turn ID, returns turns older than that ID (walking backward via `parent_turn_id`), also in oldest-first order. Both code paths produce the same ordering (`results.reverse()` at the end). The `fetchFirstTurn` pseudocode (Section 5.5) uses `cursor = 0` as a sentinel meaning "start from head (no before_turn_id)" — this works because omitting the parameter and passing `0` are functionally identical. Use `next_before_turn_id` from the previous response to fetch the next page. **Context scoping note.** The `context_id` parameter verifies the context exists but does not scope the `before_turn_id` traversal. CXDB resolves `before_turn_id` from a global turn table (`turn_store/mod.rs` line 539-542: `self.turns.get(&before_turn_id)`) and walks `parent_turn_id` links without context boundary checks. This is why `fetchFirstTurn` (Section 5.5) correctly discovers the parent context's `RunStarted` turn for forked contexts — the parent chain naturally crosses context boundaries. The UI's pagination is safe because it uses `next_before_turn_id` from the same context's response chain. **Defensive note.** Because `before_turn_id` is resolved globally, callers must ensure that the cursor passed as `before_turn_id` originates from the same context's response chain. Mixing cursors across contexts produces silently incorrect results — the returned turns belong to the wrong context's parent chain. The gap recovery pseudocode (Section 6.1) maintains `lastSeenTurnId` per `(cxdb_index, context_id)` pair to prevent this. Implementers should assert that the cursor and context_id are from the same mapping. |
| `view` | `typed` | Response format: `typed` (decoded JSON), `raw` (msgpack), or `both` |
| `bytes_render` | `base64` | Raw payload encoding when `view=raw` or `view=both`: `base64` (response field: `bytes_b64`), `hex` (response field: `bytes_hex`), or `len_only` (response field: `bytes_len`, no payload data). The UI uses the default (`base64`) and accesses `bytes_b64`. This parameter has no effect when `view=typed`. |

**Type registry dependency.** The default `view=typed` format requires every turn's `declared_type` to be registered in CXDB's type registry. For Kilroy turns, this means the `kilroy-attractor-v1` registry bundle (shown in the response's `meta.registry_bundle_id` field) must be published to the CXDB instance before the UI can fetch turns. If any single turn in a context references an unregistered type, the entire turn fetch request for that context fails (CXDB's type resolution is per-turn with no skip-on-error fallback — `http/mod.rs` line 849-850: `registry.get_type_version(...).ok_or_else(|| StoreError::NotFound(...))`). This can occur during development (before the registry bundle is published), after a version mismatch (newer Attractor types not in the bundle), or in forked contexts that inherit parent turns with non-Kilroy types. The polling algorithm handles this failure mode as a per-context error (see Section 6.1, step 4).

**Permanent failure for forked contexts with non-Kilroy parents.** The forked-context case deserves special attention because it can cause **permanent** `view=typed` failures, not just transient ones. CXDB's `get_last` / `get_before` walks the parent chain across context boundaries (`turn_store/mod.rs`), so turns from the parent context are included in the child's response. If a Kilroy context was forked from a parent that contains turns with `cxdb.ConversationItem` types (e.g., from a Claude Code session or other non-Kilroy client), and the `cxdb.ConversationItem` registry bundle is not published on that CXDB instance, then `view=typed` fetches will fail for the child context every poll cycle — the parent turns are immutable and will always be in the response window until enough child turns are appended to push them out. This is distinct from the transient "registry not yet published" scenario. The per-context error handling (Section 6.1, step 4: skip and retain cache) handles the failure gracefully, but the context will not update until either the missing bundle is published or the non-Kilroy parent turns fall outside the fetch window.

**Blob-level failure scope.** CXDB loads payload blobs for all turns in the response window. The Store wrapper (`store.rs` lines 268-274 for `get_last`, lines 295-301 for `get_before`) calls `self.blob_store.get(&record.payload_hash)?` for each turn, using `?` error propagation with no per-turn skip. If any single payload blob is corrupted or missing (disk error, incomplete write), the entire request fails with 500 — even if the most recent turns are intact. The failure persists across poll cycles until the corrupted blob falls outside the 100-turn fetch window (as new turns are appended and the window slides forward). For slow-moving contexts, this could take hours. The per-context error handling (Section 6.1, step 4: skip and retain cache) mitigates this by preserving last-known status, but the context will not update until the blob is no longer in the window. This is a distinct failure mode from the type registry miss — blob corruption is less obvious because the 500 error does not indicate which specific blob failed.

**`view=raw` subsystem dependencies.** The `view=raw` parameter eliminates only the type registry dependency. The turn metadata store (which holds `declared_type_id` and `declared_type_version` — loaded via `self.turn_store.get_turn_meta(record.turn_id)?` at `turn_store/mod.rs` line 496-500) and the blob store (which holds the raw payload) are still accessed for every turn regardless of the `view` parameter. The `declared_type` fields are extracted from `TurnMeta` unconditionally before the view-dependent code path runs (`http/mod.rs` lines 807-808). If the turn metadata is corrupted or missing, the entire turn fetch fails with the same blast radius as blob corruption — `view=raw` does not reduce the number of CXDB subsystems involved. Failures in either subsystem are handled by the existing per-context error handling (Section 6.1, step 4).

**Response fields:**

- `declared_type` — the type as written by the client when the turn was appended.
- `decoded_as` — the type after registry resolution. May differ from `declared_type` when `type_hint_mode` is `latest` or `explicit`. The UI uses `declared_type.type_id` for type matching (sufficient because Attractor types do not use version migration).
- `next_before_turn_id` — pagination cursor for fetching older turns. Set to the oldest turn's ID in the response; `null` when the response contains no turns. Pass this as the `before_turn_id` query parameter to get the next page. Note: a non-null value means the response was non-empty, not that older turns definitely exist — the definitive "no more pages" signal is `response.turns.length < limit`.
- `parent_turn_id` — the turn this was appended after (present but unused by the UI).

## Turn Type IDs

| Type ID | Description | Key Data Fields |
|---------|-------------|-----------------|
| `com.kilroy.attractor.RunStarted` | First turn in a context (pipeline-level) | `graph_name`, `run_id`, `graph_dot` (optional) |
| `com.kilroy.attractor.RunCompleted` | Pipeline run completed (pipeline-level) | `run_id`, `final_status`, `final_git_commit_sha`, `cxdb_context_id`, `cxdb_head_turn_id` |
| `com.kilroy.attractor.RunFailed` | Pipeline run failed (pipeline-level) | `run_id`, `reason`, `node_id` (optional), `git_commit_sha` |
| `com.kilroy.attractor.Prompt` | LLM prompt sent to agent | `node_id`, `text` |
| `com.kilroy.attractor.ToolCall` | Agent invoked a tool | `node_id` (optional per registry, always populated in practice), `tool_name`, `arguments_json`, `call_id` |
| `com.kilroy.attractor.ToolResult` | Tool result | `node_id` (optional per registry, always populated in practice), `tool_name`, `output`, `is_error`, `call_id` |
| `com.kilroy.attractor.AssistantMessage` | LLM response | `node_id` (optional), `text`, `model`, `input_tokens`, `output_tokens`, `tool_use_count` |
| `com.kilroy.attractor.GitCheckpoint` | Git commit at node boundary | `node_id`, `git_commit_sha`, `status` |
| `com.kilroy.attractor.CheckpointSaved` | Checkpoint saved to disk | `run_id`, `node_id` (optional), `checkpoint_path` |
| `com.kilroy.attractor.Artifact` | Build artifact produced | `node_id` (optional), `name`, `mime`, `content_hash` |
| `com.kilroy.attractor.BackendTraceRef` | LLM backend trace reference | `node_id` (optional), `provider`, `backend` |
| `com.kilroy.attractor.Blob` | Raw binary data | `bytes` |
| `com.kilroy.attractor.StageStarted` | Node execution began | `node_id`, `handler_type` (optional) |
| `com.kilroy.attractor.StageFinished` | Node execution completed | `node_id`, `status`, `preferred_label` (optional), `failure_reason` (optional), `notes` (optional), `suggested_next_ids` (optional, array) |
| `com.kilroy.attractor.StageFailed` | Node execution failed | `node_id`, `failure_reason`, `will_retry` (optional, boolean), `attempt` (optional) |
| `com.kilroy.attractor.StageRetrying` | Node about to retry | `node_id`, `attempt`, `delay_ms` (optional) |
| `com.kilroy.attractor.ParallelStarted` | Parallel execution began | `node_id`, `branch_count`, `join_policy`, `error_policy` |
| `com.kilroy.attractor.ParallelBranchStarted` | Single parallel branch began | `node_id`, `branch_key`, `branch_index` |
| `com.kilroy.attractor.ParallelBranchCompleted` | Parallel branch finished | `node_id`, `branch_key`, `branch_index`, `status`, `duration_ms` |
| `com.kilroy.attractor.ParallelCompleted` | All parallel branches finished | `node_id`, `success_count`, `failure_count`, `duration_ms` |
| `com.kilroy.attractor.InterviewStarted` | Human gate question posed | `node_id`, `question_text`, `question_type` |
| `com.kilroy.attractor.InterviewCompleted` | Human gate answer received | `node_id`, `answer_value`, `duration_ms` |
| `com.kilroy.attractor.InterviewTimeout` | Human gate timed out | `node_id`, `question_text`, `duration_ms` |

Types with `node_id` are processed by the status derivation algorithm (Section 6.2). Types without `node_id` (RunStarted, RunCompleted, Blob) are silently skipped via the `IF nodeId IS null` guard. RunFailed carries an optional `node_id` — when present, it participates in status derivation; when absent, it is skipped. GitCheckpoint, CheckpointSaved, Artifact, BackendTraceRef, and AssistantMessage may or may not carry `node_id` depending on context — the null guard handles both cases. These types are defined in the `kilroy-attractor-v1` registry bundle (in the Kilroy/Attractor codebase) and their fields should be verified against the bundle if field-level details are needed beyond what is documented here. The `optional` annotations in the table above match the registry bundle definition (e.g., `ToolCall.node_id` is `opt()` in the registry), not necessarily the current Kilroy emitting code (which always populates them in practice). Fields marked optional in the registry may be absent from turns emitted by future Kilroy versions or third-party Attractor implementations. The `IF nodeId IS null` guard in the status derivation algorithm (Section 6.2) handles all cases regardless of optionality.

**Field notes for specific turn types.** `GitCheckpoint.status` records the `StageStatus` (e.g., `"success"`, `"fail"`, `"retry"`) at the time the git checkpoint was made — it uses the same `StageStatus` value set as `StageFinished.status` (see `runtime/status.go`). This field does not affect UI rendering since `GitCheckpoint` falls through to the "Other/unknown" detail panel row, but operators examining raw turn data in CXDB will see it. `ToolCall.call_id` and `ToolResult.call_id` are a correlation ID linking a tool invocation round-trip: the same `call_id` appears in both the `ToolCall` turn and its corresponding `ToolResult` turn. For LLM-driven tool calls (CLI stream path), `call_id` is the Anthropic `tool_use` ID (e.g., `"toolu_abc"`). For tool gate invocations (`handlers.go`), it is a ULID generated at call time. For Codergen-routed calls (`codergen_router.go`), it is also a ULID. The `call_id` field is not rendered by the detail panel but is present in all real-world Kilroy `ToolCall` and `ToolResult` turns. `ParallelStarted.join_policy` and `ParallelStarted.error_policy` are string values from Kilroy's parallel handler configuration that describe how the parallel fan-out is coordinated — specifically which branches must complete and what happens on branch failure. These fields do not affect UI rendering since `ParallelStarted` falls through to the "Other/unknown" detail panel row, but they are operationally significant for operators debugging failing parallel nodes.

**Kilroy types vs. CXDB canonical types.** The `com.kilroy.attractor.*` types above are distinct from CXDB's own canonical conversation type (`cxdb.ConversationItem`, defined in `clients/go/types/conversation.go` in the CXDB repository). The CXDB types use an `item_type` discriminator with variants like `user_input`, `assistant_turn`, `tool_call`, `tool_result`, `system`, and `handoff` — they have no concept of `node_id`, `graph_name`, `run_id`, `StageStarted`, `StageFinished`, or `StageFailed`. The Kilroy types are defined in the Kilroy/Attractor codebase (not the CXDB codebase) and are published to CXDB via the registry bundle mechanism. An implementer cannot verify the Kilroy field tags or type IDs from the CXDB source alone — the canonical source for the `kilroy-attractor-v1` bundle definition is the Attractor repository. The `decodeFirstTurn` tags (tag 1 = `run_id`, tag 8 = `graph_name`) are documented inline in Section 5.5 and are stable within bundle version 1 per CXDB's versioning model (existing tags are never reassigned).
