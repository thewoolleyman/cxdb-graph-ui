# CXDB Graph UI Spec — Critique v22 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v21 cycle had two critics (opus and codex). All 8 issues were applied: opus's 5 re-raised issues from v18/v19 were addressed (dead code removed, `/api/dots` format resolved, context list caching added, `hasLifecycleResolution` AND semantics, node-ID prefetch step). Codex's 3 issues were applied (empty contexts retried instead of permanently classified, node list prefetch for inactive pipelines, `/api/dots` format fix). This critique is informed by reading the CXDB server source code (`server/src/http/mod.rs`, `server/src/events.rs`, `server/src/turn_store/mod.rs`, `server/src/store.rs`, `clients/go/`) to verify the spec's assumptions against the actual implementation.

---

## Issue #1: `fetchFirstTurn` fetches the entire context history — unbounded memory and latency for deep contexts

### The problem

Section 5.5's `fetchFirstTurn` retrieves the first turn by requesting `limit=headDepth + 1` turns. The spec states "CXDB imposes no limit maximum" and relies on fetching the entire context in a single request. However, examining the CXDB source (`server/src/turn_store/mod.rs`, line 503–521), the `get_last` function walks backward from the head through the parent chain, allocating a `Vec` for all returned turns. For deep contexts (e.g., `headDepth` = 50,000 during a long-running pipeline), this fetches and JSON-serializes 50,001 turns, including their decoded payloads (the spec uses the default `view=typed` format). This creates significant problems:

1. **Memory.** Each turn's decoded `data` may contain multi-kilobyte fields (`output`, `arguments_json`, `text`). At 50K turns, this could be tens or hundreds of megabytes in a single HTTP response.
2. **Latency.** The server's `get_last` walks the parent chain sequentially (line 510–519 of `turn_store/mod.rs`), and the HTTP handler then projects every turn through the type registry. This could take many seconds, blocking the poller.
3. **The entire response is discarded except `turns[0]`.** Only the first turn is used. The remaining 49,999 turns are fetched, serialized, transferred, parsed, and thrown away.

The CXDB HTTP API (`server/src/http/mod.rs`, line 739–941) supports `before_turn_id` for backward pagination, but there is no forward-pagination endpoint to fetch turns starting from depth 0. The binary protocol has `GetRangeByDepth` (message type 8 in `protocol/mod.rs`), but the HTTP API does not expose it.

### Suggestion

Instead of fetching the entire context, use a targeted approach: request `limit=1` with a `before_turn_id` that would be older than or equal to the first turn. Since CXDB's `get_before` (line 524–556 of `turn_store/mod.rs`) walks backward from `before_turn_id`, and the first turn has no parent (`parent_turn_id = 0`), requesting `limit=1` with `before_turn_id=0` falls through to `get_last` with `limit=1` (line 535–536), returning the single most recent turn — not the first.

The correct approach is to paginate backward from the end: request the last `limit=100` turns, then check if the response contains a turn with `depth == 0`. If not, continue paginating with `before_turn_id` until the `depth == 0` turn is found or no more pages remain. This is bounded by O(headDepth / 100) requests in the worst case but avoids the single-request memory spike. Add a maximum page count (e.g., 5) to prevent runaway pagination for extremely deep contexts.

Alternatively, document that the UI only needs `declared_type.type_id` and `data.graph_name` / `data.run_id` from the first turn. If the turn type can be determined without full payload decoding, the UI could pass `view=raw` and check `declared_type.type_id` without triggering full projection — though this still requires fetching all turns.

The simplest and most robust fix: add a dedicated `GET /dots/{name}/first-turn` or equivalent server-side helper that uses the CXDB binary protocol's `GetRangeByDepth` (which exists in the protocol but is not HTTP-exposed) to fetch depth=0 directly. Short of that, the spec should at minimum document the O(headDepth) cost and add a maximum depth threshold (e.g., if `headDepth > 10000`, skip RunStarted discovery for this context and rely on `client_tag` alone for pipeline association).

---

## Issue #2: Spec assumes `GET /v1/contexts` returns ALL contexts with `limit=10000`, but the CXDB source returns contexts in descending order — oldest contexts may be truncated

### The problem

Section 5.2 and 5.5 state the UI passes `limit=10000` to "ensure all contexts are returned." The CXDB server source (`server/src/http/mod.rs`, line 204–286) calls `store.list_recent_contexts(limit)`, which returns contexts ordered by **most recent first** (the function name says "recent"). The CQL search endpoint (line 385–387) explicitly sorts `by context_id descending (most recent first)`.

If a CXDB instance accumulates more than 10,000 contexts over its lifetime (plausible on a shared development server running for weeks), the `limit=10000` cap will truncate the oldest contexts. These may include active Kilroy pipeline contexts from an ongoing run if 10,000+ non-Kilroy contexts were created more recently. The spec's assumption that "all contexts are returned" is fragile.

More importantly, the spec does not document that contexts are returned newest-first. The context list response example (Section 5.2) shows a single context without clarifying ordering. An implementer might assume the order is arbitrary or oldest-first.

### Suggestion

1. Document the context list ordering as newest-first (descending by creation time), matching the CXDB implementation.
2. Consider using the `tag` query parameter for server-side filtering: while the spec notes that `run_id` varies, a prefix-based approach could work. The CXDB `tag` filter uses exact match (line 236: `if tag != filter`), so prefix filtering is not supported server-side. Document this limitation explicitly and consider filing a feature request for prefix-based tag filtering on the CXDB side.
3. As an alternative safeguard, use the CXDB SSE endpoint's `context_created` events to maintain a running list of context IDs, falling back to the context list endpoint only for the initial snapshot. The spec already documents SSE as a non-goal (Section 10, item 11), but this is a polling-efficiency concern, not a real-time push concern — the SSE event could supplement the context list to avoid truncation.
4. At minimum, add a note that 10,000 is a heuristic and may miss contexts on heavily-used CXDB instances, and document what the failure mode looks like (pipelines silently not discovered).

---

## Issue #3: The spec does not account for CXDB's `ContextLinked` events and cross-context lineage, which could simplify pipeline discovery

### The problem

CXDB supports cross-context lineage tracking via `ContextLinked` events (`server/src/events.rs`, line 37–45). When a context is forked or spawned from another, CXDB records `parent_context_id`, `root_context_id`, and `spawn_reason`. The context list endpoint includes this data in the `lineage` field (`server/src/http/mod.rs`, line 1366–1392) when `include_lineage=1` is passed.

The spec's pipeline discovery algorithm treats each context independently, fetching the `RunStarted` turn from every Kilroy-tagged context to determine its `graph_name` and `run_id`. For parallel branches (which are forked from a parent context), this means N redundant `RunStarted` fetches — all children of the same root context share the same `run_id` and `graph_name`.

By using `include_lineage=1` on the context list request, the UI could discover that contexts are children of an already-classified parent and inherit the parent's `graph_name`/`run_id` mapping without fetching the child's first turn. This would reduce discovery latency proportionally to the number of parallel branches.

### Suggestion

This is not a correctness issue — the current approach works. However, the spec should acknowledge that CXDB context lineage exists and document the decision not to use it (or, preferably, incorporate it as an optimization). If incorporated, the discovery algorithm should: (1) request `include_lineage=1` on the context list, (2) when a context has a `parent_context_id` that is already in `knownMappings`, inherit the parent's mapping, and (3) fall back to `fetchFirstTurn` only for root contexts or contexts whose parent is unmapped. Add this as a documented optimization, not a requirement, to keep the initial implementation simple.

---

## Issue #4: `resetPipelineState` removes old-run `knownMappings` entries, but new contexts reusing the same CXDB context IDs could cause misclassification

### The problem

Section 6.1 step 3 states that `resetPipelineState` "removes `knownMappings` entries whose `runId` matches the old run's `run_id`." This allows re-discovery if "the same context IDs appear in a future run with different `RunStarted` data."

CXDB context IDs are monotonically increasing integers allocated from a global counter (`server/src/store.rs`). They are never reused — once context 33 is created, no future context will have ID 33. The spec's rationale for removing old-run mappings ("if the same context IDs appear in a future run") describes a scenario that cannot occur in practice.

While removing stale mappings is harmless (and slightly reduces memory), the stated rationale is incorrect and may confuse an implementer into thinking context ID reuse is possible and must be defended against. This could lead to unnecessary defensive coding.

### Suggestion

Update the rationale for removing old-run `knownMappings` entries. The correct justification is memory hygiene: old-run entries will never match the active run and consume memory indefinitely. Remove the statement about "same context IDs appear in a future run" since CXDB context IDs are globally unique and never recycled. This is a documentation accuracy fix, not a behavioral change.

---

## Issue #5: The holdout scenario "Agent stuck in error loop" does not match the spec's per-context scoping of the error heuristic

### The problem

The holdout scenario "Agent stuck in error loop" states:

> Given a pipeline run is active
>   And the 3 most recent ToolResult turns on a node each have is_error: true
>   And non-ToolResult turns (Prompt, ToolCall) are interleaved between them
> When the UI polls CXDB
> Then that node is colored red (error)

This scenario describes "the 3 most recent ToolResult turns on a node" without specifying which context they belong to. The spec's `applyErrorHeuristic` (Section 6.2) scopes error detection per-context: it calls `getMostRecentToolResultsForNodeInContext` which examines "a single context's cached turns." If the 3 error ToolResults are spread across 3 different contexts (e.g., 3 parallel branches each with 1 error), the heuristic will NOT fire because no single context has 3 consecutive errors.

The holdout scenario is ambiguous — it should explicitly state that the 3 ToolResult errors are within the same CXDB context, matching the spec's per-context error heuristic behavior.

### Suggestion

Update the holdout scenario to clarify the per-context scoping:

```
Given a pipeline run is active
  And a single CXDB context has 3 most recent ToolResult turns on a node with is_error: true
  And non-ToolResult turns (Prompt, ToolCall) are interleaved between the ToolResult turns
When the UI polls CXDB
Then that node is colored red (error)
```

Also consider adding a complementary holdout scenario that documents the negative case: "3 errors spread across 3 contexts do not trigger the error heuristic."
