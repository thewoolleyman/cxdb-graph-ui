# CXDB Graph UI Spec — Critique v33 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-25

## Prior Context

The v32 cycle had two critics (opus and codex). Both independently identified the `created_at_unix_ms` update semantics as a risk for active-run selection. The fix adopted `context_id` as the primary sort key in `determineActiveRuns`. Opus also corrected an impossible proposed holdout scenario (depth-0 forked contexts with 50+ turns), added `title` to the CQL response documentation (already present), and cleaned up fragile line number references. This critique is informed by detailed reading of the CXDB source (`turn_store/mod.rs`, `store.rs`, `http/mod.rs`, `events.rs`, `cql/indexes.rs`) and the Go client types (`clients/go/types/conversation.go`, `clients/go/types/builders.go`).

---

## Issue #1: The spec's turn type system (`com.kilroy.attractor.*`) does not exist in the CXDB codebase — the actual Go client types use `cxdb.ConversationItem`

### The problem

The spec's Section 5.4 documents turn types like `com.kilroy.attractor.RunStarted`, `com.kilroy.attractor.ToolResult`, `com.kilroy.attractor.StageStarted`, etc. These type IDs appear throughout the spec — in pipeline discovery, status derivation, error heuristics, and the detail panel rendering.

However, reading the actual CXDB Go client types at `/Users/cwoolley/workspace/cxdb/clients/go/types/conversation.go`, the canonical turn type is `cxdb.ConversationItem` (type ID constant: `TypeIDConversationItem = "cxdb.ConversationItem"`, version 3). This is a tagged union with an `item_type` discriminator (`ItemType` enum) that distinguishes variants like `user_input`, `assistant_turn`, `tool_call`, `tool_result`, `system`, and `handoff`.

The CXDB types have no concept of `node_id`, `graph_name`, `run_id`, `StageStarted`, `StageFinished`, or `StageFailed`. These are Kilroy/Attractor-specific concepts. A grep for `com.kilroy.attractor`, `RunStarted`, `StageStarted`, `StageFinished`, `StageFailed`, `node_id`, or `graph_name` across the entire `/Users/cwoolley/workspace/cxdb/clients/go/` directory returns zero results.

This means the `com.kilroy.attractor.*` types are defined **outside** the CXDB project — presumably in the Kilroy/Attractor codebase. The spec correctly states these types are in the `kilroy-attractor-v1` registry bundle (Section 5.4: "These types are defined in the `kilroy-attractor-v1` registry bundle"), but an implementer looking at the CXDB codebase alone cannot find them.

This is not a spec error per se — the spec documents the types it needs — but it creates a verification gap: the spec references field names (`data.node_id`, `data.graph_name`, `data.run_id`, `data.tool_name`, `data.arguments_json`, `data.output`, `data.is_error`, `data.text`) and type IDs that cannot be confirmed from the CXDB source. An implementer cannot independently verify that:

1. `RunStarted` has `graph_name` at msgpack tag 8 and `run_id` at tag 1 (Section 5.5's `decodeFirstTurn`)
2. `ToolResult` has `is_error` as a boolean field
3. `StageFinished` vs `StageFailed` are separate types (not a single type with a status field)

The spec's `decodeFirstTurn` hardcodes these tags. If the Kilroy bundle changes its tag assignments, the UI breaks silently.

### Suggestion

Add a brief note in Section 5.4 or an appendix specifying where the `kilroy-attractor-v1` registry bundle is defined (e.g., the Kilroy/Attractor repository path) and how an implementer can obtain or verify the type definitions. If the bundle JSON is available, the spec should either include the relevant type descriptors inline or reference the canonical source. At minimum, confirm that the `decodeFirstTurn` tags (tag 1 = `run_id`, tag 8 = `graph_name`) can be verified against the actual bundle definition, and note that the CXDB source (`clients/go/types/`) contains CXDB's own canonical types — not the Kilroy pipeline types.

---

## Issue #2: The CXDB Go client's `ConversationItem` type structure suggests the UI's turn rendering assumptions may be misaligned with how CXDB actually returns typed data

### The problem

The spec's Section 7.2 (Detail Panel — CXDB Activity) describes per-type rendering keyed on `declared_type.type_id`:

| Turn Type | Output Column | Tool Column | Error Column |
|-----------|--------------|-------------|--------------|
| `Prompt` | `data.text` | blank | blank |
| `ToolCall` | `data.arguments_json` | `data.tool_name` | blank |
| `ToolResult` | `data.output` | `data.tool_name` | `data.is_error` |
| `StageStarted` | "Stage started" | blank | blank |
| `StageFinished` | "Stage finished" | blank | blank |
| `StageFailed` | "Stage failed" | blank | blank |

The CXDB Go client's `ConversationItem` type (`conversation.go`) uses a completely different structure with integer msgpack tags. The top-level `ConversationItem` has:
- Tag 1: `item_type` (string discriminator: `"user_input"`, `"assistant_turn"`, `"tool_call"`, `"tool_result"`, etc.)
- Tag 2: `status` (string: `"pending"`, `"streaming"`, `"complete"`, `"error"`)
- Tag 10: `user_input` (nested struct)
- Tag 11: `turn` (AssistantTurn, with nested `ToolCalls` array)
- Tag 20: `assistant` (legacy)
- Tag 21: `tool_call` (legacy)
- Tag 22: `tool_result` (legacy)
- Tag 30: `context_metadata` (with `client_tag` at sub-tag 1)

The critical point is that CXDB's type projection system decodes the raw msgpack into JSON using the registry's field descriptors. When the UI fetches turns with `view=typed`, CXDB's projection engine (`projection/mod.rs`) maps integer tags to field names using the registry bundle's field specs. The resulting `data` object has human-readable field names like `data.node_id`, `data.tool_name`, etc. — as long as the registry bundle describes those fields.

The spec assumes the Kilroy registry bundle defines these exact field names. But the CXDB codebase reveals that CXDB's **own** canonical type (`cxdb.ConversationItem`) has a completely different field layout from the Kilroy types. This means:

1. If a context contains turns with `cxdb.ConversationItem` type (e.g., from non-Kilroy clients sharing the CXDB instance), the `view=typed` fetch will succeed but the `data` fields will not match the Kilroy schema. The spec's "Other/unknown" row in the rendering table handles this.

2. More subtly, the `view=typed` fetch **fails entirely** (returns 500) if any single turn in the context references a `declared_type_id` that is NOT in the registry (line 849-850 of `http/mod.rs`: `registry.get_type_version(...).ok_or_else(|| StoreError::NotFound(...))`). The spec documents this at Section 5.3 ("Type registry dependency"). But the spec does not address what happens if a **forked context** inherits parent turns with `cxdb.ConversationItem` types (which are only in the registry if the `cxdb.ConversationItem` bundle has been published). A Kilroy child context's parent chain may include turns from the parent context that use different types.

This is already partially addressed by the spec's per-context error handling (Section 6.1, step 4: skip and retain cache). But the failure mode is subtler than described: it is not just "type registry missing at startup" — it can occur permanently for forked contexts whose parent chains contain non-Kilroy turns, even after the Kilroy bundle is published.

### Suggestion

Add a note in Section 5.3 ("Type registry dependency") acknowledging that forked contexts may permanently fail `view=typed` fetches if their parent chain includes turns with types not in any published registry bundle. This is distinct from the transient "registry not yet published" scenario. The per-context error handling already handles the failure, but the permanent nature of this failure (the parent chain does not change) means the context will never successfully fetch turns until the missing bundle is published or the turns fall outside the fetch window. This is especially relevant because CXDB's `get_last` / `get_before` walks the parent chain across context boundaries, so turns from the parent context are included in the child's response.

---

## Issue #3: The `next_before_turn_id` response field is set to the **first** (oldest) turn's ID, but the spec's pagination logic uses it to fetch **older** turns — a naming/semantic mismatch worth documenting

### The problem

The spec's Section 5.3 documents `next_before_turn_id` as "pagination cursor for fetching older turns. Set to the oldest turn's ID in the response." Looking at the CXDB source at `http/mod.rs` line 916:

```rust
let next_before = turns.first().map(|t| t.record.turn_id.to_string());
```

The `turns` array is in oldest-first order (after `results.reverse()` in `get_last` / `get_before`). So `turns.first()` is indeed the oldest turn. Passing this ID as `before_turn_id` to the next request tells CXDB to walk backward from that turn's parent, yielding even older turns. This is correct.

However, the spec's `fetchFirstTurn` pseudocode at line 674 states:

```
cursor = response.turns[0].turn_id  -- oldest turn's ID becomes the next before_turn_id
```

This is consistent with the source. But there is a subtle issue: the spec's Section 5.3 also states "`null` when the response contains no turns." Looking at the source:

```rust
let next_before = turns.first().map(|t| t.record.turn_id.to_string());
```

When `turns` is empty, `turns.first()` returns `None`, and `.map(...)` produces `None`, which serializes as JSON `null`. This is correct.

But the spec says "a non-null value means the response was non-empty, not that older turns definitely exist — the definitive 'no more pages' signal is `response.turns.length < limit`." This is accurate for regular pagination but potentially misleading for `fetchFirstTurn`: if the context has exactly `PAGE_SIZE` turns starting from a given cursor, `turns.length == PAGE_SIZE` does NOT mean there are more turns. The next page could be empty. The `fetchFirstTurn` algorithm handles this correctly (it checks `depth == 0`, not `turns.length < limit`), but the general pagination guidance in Section 5.3 could mislead an implementer building other pagination features.

### Suggestion

This is a minor documentation observation, not a required change. The `fetchFirstTurn` algorithm is correct. No spec change is needed unless the spec is revised for other reasons, in which case consider noting that the `turns.length < limit` heuristic is an optimization hint, not a guarantee — the true termination condition for first-turn discovery is finding `depth == 0`.

---

## Issue #4: Six proposed holdout scenarios remain in `cxdb-graph-ui-holdout-scenarios.md` without incorporation or rejection

### The problem

The `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` file contains six active proposed scenarios (plus one explicitly REMOVED):

1. "RunStarted with null or empty graph_name" (v26-opus)
2. "CXDB downgrades and CQL becomes unavailable mid-session" (v27-opus)
3. "Forked context discovered via parent's RunStarted turn" (v29-opus)
4. "DOT prompt containing HTML markup renders as literal text" (v29-codex)
5. "Pipeline tab label with HTML-like graph ID renders as literal text" (v30-codex)
6. "Active run selection stable when older run spawns late branch context" (v32)

These have been accumulating across critique rounds but have not been reviewed for incorporation into the main holdout scenarios document. Several of these (especially #3, #4, and #5) test distinct code paths not covered by existing holdout scenarios and would strengthen the test coverage. The proposed file states "All previously proposed scenarios have been incorporated" at the top, which is misleading since six proposals remain.

### Suggestion

Review each proposed scenario and either:
(a) Incorporate it into `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`, or
(b) Reject it with a rationale and remove it from the proposed file.

The current accumulation creates confusion about whether these scenarios represent spec invariants or merely suggestions. At a minimum, update the misleading header text.

---

If these are addressed, I do not see other major spec gaps. The most significant finding is Issue #1 (the Kilroy turn types not existing in the CXDB source), which creates a verification gap for implementers. The spec is otherwise thorough and well-aligned with the CXDB source behavior.
