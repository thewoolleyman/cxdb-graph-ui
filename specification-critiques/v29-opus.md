# CXDB Graph UI Spec — Critique v29 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-25

## Prior Context

The v28 cycle had two critics (opus and codex). All 6 issues were applied: opus's 4 issues (context scoping note for `before_turn_id`, CQL `total_count` pre-limit semantics, context list `tag` post-limit ordering, blob-level failure scope note) and codex's 2 issues (graph ID normalization alignment with node ID rules, clarification that `turnCount`/`errorCount`/`toolName` on `NodeStatus` are internal-only). This critique is informed by a detailed read of the CXDB source (`server/src/http/mod.rs`, `server/src/store.rs`, `server/src/turn_store/mod.rs`, `server/src/metrics.rs`, `server/src/cql/indexes.rs`, `server/src/events.rs`, `server/src/projection/mod.rs`) to verify the spec's claims against the actual implementation.

---

## Issue #1: The `fetchFirstTurn` pagination with `view=raw` skips `get_turn_meta` payload loading on the response path — but `declared_type_id` and `declared_type_version` come from `TurnMeta`, not `TurnRecord`, and the spec does not document this distinction

### The problem

Section 5.5's `fetchFirstTurn` relies on `rawTurn.declared_type.type_id` being present in the `view=raw` response. The spec states: "The `declared_type` field (containing `type_id` and `type_version`) is present in both `view=raw` and `view=typed` responses — it comes from the turn metadata, not the type registry."

This is correct — and verified in the CXDB source (`http/mod.rs` lines 807-808):

```rust
let declared_type_id = item.meta.declared_type_id.clone();
let declared_type_version = item.meta.declared_type_version;
```

The `declared_type` fields come from `TurnMeta` (the per-turn metadata stored alongside the turn record), not from type registry resolution. This is extracted from the turn metadata before the `view` parameter even determines which additional fields to include (lines 829-845 are unconditional, lines 847-911 are view-dependent).

However, the CXDB source reveals that `TurnMeta` is loaded via `self.turn_store.get_turn_meta(record.turn_id)?` in `Store::get_last` and `Store::get_before` (lines 271 and 298). This call can fail with `StoreError::NotFound("turn meta")` if the meta entry is missing (turn_store/mod.rs line 500). The meta store is a separate file from the turn store — it is written during `append_turn` but could theoretically be corrupted or out-of-sync independently.

The spec documents blob-level failure scope (Section 5.3) but does not mention meta-level failure. For the `view=raw` path used by `fetchFirstTurn`, the meta store is still accessed — meaning `view=raw` does not fully eliminate infrastructure dependencies. If the turn meta is corrupted, the entire turn fetch fails even with `view=raw`, identical to the blob corruption case.

This is not a correctness issue for the spec's pseudocode (the error is handled by the per-context skip logic), but an implementer reading "view=raw eliminates the type registry dependency" might incorrectly assume it reduces the blast radius of other CXDB internal failures.

### Suggestion

Add a brief clarifying note after the `view=raw` explanation in Section 5.5:

> Note: `view=raw` eliminates only the type registry dependency. The turn metadata (which holds `declared_type`) and the blob store (which holds the raw payload) are still accessed for every turn. Failures in either subsystem are handled by the existing per-context error handling (Section 6.1, step 4).

---

## Issue #2: The CQL search endpoint passes `live_contexts` from the session tracker to influence `is_live` resolution, but the spec does not document that CQL `is_live` filtering operates on session-tracker state rather than a stored field

### The problem

Section 5.2 documents the CQL search response as including `is_live` for each context. The spec's stale pipeline detection (Section 6.2) depends on `is_live` to detect crashed agents. However, the CQL search handler (`http/mod.rs` lines 411, 423-424) resolves `is_live` dynamically:

```rust
let live_contexts = session_tracker.get_live_context_ids();
// ...
let session = session_tracker.get_session_for_context(context_id);
let is_live = session.is_some();
```

The `live_contexts` HashSet is also passed into the CQL executor (`store.search_contexts` at line 414), where it is used for CQL's `is_live` filter operator (not currently used by the UI's query, but available in CQL). The `is_live` field in the response is resolved per-context from the session tracker, not from any stored field.

The context list fallback resolves `is_live` identically (`context_to_json` at line 1315: `let is_live = session.is_some()`). So both paths agree.

The operational implication is that `is_live` changes instantaneously when a session disconnects — there is no lag or caching delay. When a Kilroy agent crashes, the binary protocol session terminates, the session tracker removes the session (tracked in `metrics.rs` `disconnect_session`), and the very next HTTP request that checks `is_live` for that context will see `false`. This means stale detection can fire on the poll cycle immediately after a crash — a useful property that the spec does not explicitly call out. The spec's statement "all active-run contexts transition to is_live: false" (Section 8.2) could be misread as a gradual transition rather than an instant signal.

### Suggestion

Add a note to Section 5.2 or Section 6.2 clarifying the `is_live` resolution mechanism:

> **`is_live` resolution.** The `is_live` field is resolved dynamically from CXDB's session tracker, not from a stored field. When a binary protocol session disconnects (agent exits or crashes), the session is immediately removed from the tracker. The next HTTP request for that context sees `is_live: false` with no caching delay. This means stale detection (Section 6.2) can fire on the very first poll cycle after an agent crash. Both the CQL search endpoint and the context list fallback resolve `is_live` identically.

---

## Issue #3: The spec does not document the `ContextMetadataUpdated` SSE event, which could be relevant for a future optimization where the Go proxy subscribes to SSE server-side for reduced discovery latency

### The problem

Section 10 (Non-Goals, item 11) mentions a potential future optimization: "the Go proxy server could optionally subscribe to CXDB's SSE endpoint server-side (using the Go client's `SubscribeEvents` function with automatic reconnection) to reduce discovery latency — e.g., immediately triggering discovery when a `ContextCreated` event with a `kilroy/`-prefixed `client_tag` arrives."

However, the CXDB source reveals that `ContextCreated` events may NOT include a meaningful `client_tag`. Looking at `http/mod.rs` lines 297-301, the HTTP `POST /v1/contexts` handler publishes:

```rust
event_bus.publish(StoreEvent::ContextCreated {
    context_id: head.context_id.to_string(),
    session_id: "http".to_string(),
    client_tag,
    // ...
});
```

The `client_tag` here comes from the HTTP request header, which is set by the caller. But for binary protocol sessions (which Kilroy uses), the `client_tag` is available at session creation time, and the `ContextCreated` event includes it. The important subtlety is that `client_tag` in the SSE event comes from the session, not from the context metadata — the metadata (which is what CQL indexes) is extracted from the first turn's payload, which happens asynchronously.

CXDB also emits a `ContextMetadataUpdated` event (`events.rs` lines 27-36) when the first turn's metadata is extracted. This event includes `client_tag`, `title`, and `labels`. For the SSE-based optimization, `ContextMetadataUpdated` would be a more reliable trigger than `ContextCreated` because it fires after the metadata cache is populated — meaning CQL search would also find the context at that point.

The Go client (`clients/go/events.go` lines 19-25) defines `ContextMetadataUpdatedEvent` with `ClientTag`, `Title`, and `Labels` fields, confirming this event is part of the public SSE API.

### Suggestion

Amend the SSE mention in Section 10, item 11 to note:

> CXDB emits both `ContextCreated` (when the context is created, with `client_tag` from the session) and `ContextMetadataUpdated` (when the first turn's metadata is extracted, with `client_tag`, `title`, and `labels` from the payload). The `ContextMetadataUpdated` event is the more reliable trigger for discovery because it fires after the metadata cache and CQL secondary indexes are populated.

---

## Issue #4: The spec's holdout scenarios do not cover the `fetchFirstTurn` pagination path for forked contexts — where the first turn (`depth=0`) is in the parent context and the child context's own turns start at `depth > 0`

### The problem

Section 5.5 documents that forked contexts' parent chains extend into the parent context: "Walking to depth 0 therefore discovers the parent context's `RunStarted` turn, not a turn within the child context." This is a critical correctness claim — if the pagination breaks for forked contexts, pipeline discovery fails for parallel branches.

The `fetchFirstTurn` algorithm relies on `response.turns[0].depth == 0` to find the first turn. For a forked context with `head_depth = 500`, the pagination walks backward through pages of 100 turns. When the walk crosses the context boundary (from child to parent), the turns come from the parent context. The algorithm continues until it finds `depth == 0`.

This works correctly because CXDB's `get_before` follows `parent_turn_id` links (which cross context boundaries for forked contexts), and the `depth` field is per-turn (reflecting position in the parent chain, not context-relative depth).

However, the holdout scenarios have no scenario that exercises this path. The existing scenarios test:
- Context matched via RunStarted (Scenario: "Context matched to pipeline via RunStarted turn") — but this assumes the RunStarted is in the same context.
- Multiple contexts for parallel branches — but tests merging, not discovery.

A forked context's child does not contain a RunStarted turn at all — it inherits the parent's RunStarted through the parent chain. If an implementer's `fetchFirstTurn` incorrectly stops at the context boundary (e.g., by checking `context_id` matches or by breaking when turns come from a different context), pipeline discovery silently fails for all parallel branches.

### Suggestion

Add a holdout scenario:

```
### Scenario: Forked context discovered via parent's RunStarted turn
Given a pipeline run creates a parent context with RunStarted(graph_name="alpha_pipeline")
  And the parent context forks a child context for a parallel branch
  And the child context has head_depth=500
  And the child's parent chain extends into the parent context
When the UI runs pipeline discovery for the child context
Then fetchFirstTurn paginates through the child's turns into the parent context
  And discovers the parent's RunStarted turn at depth=0
  And the child context is correctly mapped to the alpha_pipeline tab
```
