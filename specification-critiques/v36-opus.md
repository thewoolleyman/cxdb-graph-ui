# CXDB Graph UI Spec -- Critique v36 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-25

## Prior Context

The v35 cycle had two critics (opus and codex). Opus raised four issues: `StageFailed` with `will_retry: true` causing premature error status (applied -- pseudocode now checks `will_retry`), `node_id` optionality mismatches in Section 5.4 (applied -- table updated with registry-accurate annotations), `AssistantMessage` Kilroy-side 8,000-character truncation (applied -- documented in Section 7.2), and missing retry flow holdout scenario (deferred as proposed scenario). Codex raised one issue: initial pipeline missing `/edges` prefetch (applied -- Section 4.5 Step 4 now prefetches both `/nodes` and `/edges`). All issues were addressed or deferred.

This critique is informed by reading the **Kilroy source code** (`kilroy/internal/cxdb/kilroy_registry.go`, `kilroy/internal/cxdb/msgpack_encode.go`, `kilroy/internal/attractor/engine/cxdb_sink.go`, `kilroy/internal/attractor/engine/cxdb_events.go`, `kilroy/internal/cxdb/binary_client.go`, `kilroy/internal/cxdb/client.go`) and the **CXDB server source code** (`cxdb/server/src/store.rs`, `cxdb/server/src/http/mod.rs`, `cxdb/server/src/protocol/mod.rs`, `cxdb/server/src/cql/indexes.rs`, `cxdb/server/src/metrics.rs`) as well as the **CXDB Go client types** (`cxdb/clients/go/types/conversation.go`).

---

## Issue #1: The spec incorrectly claims CXDB's binary protocol embeds `client_tag` at key 30 in stored payloads -- CQL search cannot discover Kilroy contexts

### The problem

Section 5.5 (line 768) states:

> "Kilroy satisfies this requirement via the binary protocol: Kilroy calls `DialBinary` with the tag `kilroy/{run_id}` as the session-level `client_tag`, and CXDB's binary protocol embeds the session's `client_tag` at key 30 in the outer msgpack envelope of stored payloads."

This claim is factually incorrect. I traced the complete write path through both codebases and confirmed that **no component -- neither Kilroy nor CXDB -- injects key 30 into turn payloads.**

**Evidence from Kilroy:**

1. `EncodeTurnPayload` (`msgpack_encode.go` lines 12-30): Maps named data fields to numeric tags using `registryFieldTags`. The `kilroy-attractor-v1` registry bundle defines tags 1-12 for `RunStarted`. Tag 30 does not exist in the bundle. The function only emits tags found in the registry -- it never injects additional keys.

2. `CXDBSink.Append` (`cxdb_sink.go` lines 111-117): Passes the `data` map directly to `append()`, which calls `EncodeTurnPayload` then `BinaryClient.AppendTurn`. No outer envelope wrapping occurs.

3. `BinaryClient.AppendTurn` (`binary_client.go` lines 198-280): Writes the raw msgpack payload bytes to the wire. No metadata injection.

**Evidence from CXDB server:**

4. `parse_append_turn` (`protocol/mod.rs` lines 155-185): Reads the raw payload bytes from the binary frame. Passes them verbatim to `store.append_turn`. No metadata injection.

5. `encode_http_payload` (`http/mod.rs` lines 1480-1501): For HTTP appends, encodes the JSON data using registry descriptors. Also no key 30 injection.

6. `extract_context_metadata` (`store.rs` lines 587-608): Reads key 30 from the raw payload. Since nothing injects key 30, this returns `None` for `client_tag` on Kilroy `RunStarted` payloads.

**Where the key 30 convention actually lives:**

The tag 30 / `context_metadata` pattern is defined in `cxdb/clients/go/types/conversation.go` line 167:
```go
ContextMetadata *ContextMetadata `msgpack:"30" json:"context_metadata,omitempty"`
```
With the comment: "By convention, only included in the first turn (depth=1) of a context." This is a **client-side convention** that `cxdb.ConversationItem` users implement. Kilroy uses its own type system (`com.kilroy.attractor.*`) and does not use `cxdb.ConversationItem`.

**Consequences:**

- **CQL search is broken for Kilroy contexts.** CQL secondary indexes (`cql/indexes.rs` lines 107-121) are built from `context_metadata_cache`, which only has `client_tag` if `extract_context_metadata` found key 30. Since Kilroy payloads lack key 30, the query `tag ^= "kilroy/"` returns zero results. The entire CQL-first discovery path described in Sections 5.2 and 5.5 produces empty results.

- **Context list fallback loses `client_tag` after session disconnect.** `context_to_json` (`http/mod.rs` lines 1320-1324) falls back to the session's `client_tag` via `.or_else(|| session.as_ref().map(|s| s.client_tag.clone()))`. This works while the session is active. But `SessionTracker.unregister` (`metrics.rs` lines 88-98) removes all context-to-session mappings when the binary session disconnects. After Kilroy exits, `get_session_for_context` returns `None`, and `client_tag` becomes `null` for all that run's contexts. Completed pipelines become undiscoverable.

### Suggestion

The spec must correct the factual claim and address the architectural gap. Two options:

**(a) Require Kilroy to embed context metadata at key 30 in the first turn's payload (preferred).** Kilroy's `cxdbRunStarted` would need to include a `context_metadata` field at key 30 in the data map passed to `EncodeTurnPayload`. Since `EncodeTurnPayload` only emits tags found in the registry, the `kilroy-attractor-v1` registry bundle would need to add a tag 30 field to `RunStarted` (or Kilroy would need to wrap the encoded payload in an outer map). This is a Kilroy-side change. The spec should describe it as a prerequisite and document the required payload structure rather than claiming it happens automatically.

**(b) Redesign discovery to not depend on CQL `tag` search or post-disconnect `client_tag`.** This would mean always using the context list fallback with client-side filtering, and accepting that completed pipelines are only discoverable if the UI's `knownMappings` cache retains them from when the session was active. The spec's `knownMappings` caching (Section 5.5) partially handles this -- once a context is discovered, it stays in the cache. But a fresh page load after a pipeline completes would fail to discover it.

Option (a) is strongly preferred. The spec should replace the incorrect claim with: "Kilroy must embed `client_tag` in the first turn's context metadata (key 30 of the msgpack payload) for CQL search to discover Kilroy contexts. This is a Kilroy-side convention, not a CXDB binary protocol feature. The UI's CQL discovery path (`tag ^= "kilroy/"`) requires this metadata to be present. Until Kilroy implements this, the context list fallback with session-tag resolution is the only reliable discovery path, limited to active sessions."

---

## Issue #2: The metadata extraction asymmetry paragraph (line 770) assumes key 30 is present in RunStarted, which it is not

### The problem

Section 5.5 (line 770) discusses metadata extraction paths for forked contexts:

> "Both paths produce the same `client_tag` value (`kilroy/{run_id}`) because Kilroy uses the same `run_id` for parent and child contexts."

Given Issue #1, neither path produces a `client_tag` value. The `RunStarted` payload does not contain key 30, so `extract_context_metadata` returns `None` for `client_tag` regardless of whether it is called via `maybe_cache_metadata` (hot path) or `load_context_metadata` (restart path). The paragraph's reasoning about "different turns with potentially different payloads" is structurally correct but moot -- both payloads lack key 30 entirely.

### Suggestion

If Issue #1's option (a) is adopted (Kilroy adds key 30 to `RunStarted`), then the paragraph's claim about "both paths produce the same `client_tag` value" becomes correct and the text can remain. If option (b) is adopted instead, revise the paragraph to state that neither path yields a `client_tag` for Kilroy contexts, and explain the implications for forked context discoverability.

---

## Issue #3: The `decodeFirstTurn` pseudocode compares `rawTurn.declared_type` (an object) to a string

### The problem

Section 5.5's `decodeFirstTurn` pseudocode contains:

```
IF rawTurn.declared_type != "com.kilroy.attractor.RunStarted":
    RETURN null  -- not a RunStarted turn
```

However, Section 5.3 defines the turn response format with `declared_type` as an object:

```json
{
  "turn_id": "6066",
  "declared_type": { "type_id": "com.kilroy.attractor.StageStarted", "version": 1 },
  "data": { ... }
}
```

Comparing an object to a string would never match. An implementing agent would need to guess whether to use `rawTurn.declared_type` (string) or `rawTurn.declared_type.type_id` (object property).

The RETURN statement at the end of `decodeFirstTurn` also references `rawTurn.declared_type` for the return value, which is correct if it returns the full object. But the guard condition is inconsistent.

### Suggestion

Change the guard condition from:

```
IF rawTurn.declared_type != "com.kilroy.attractor.RunStarted":
```

to:

```
IF rawTurn.declared_type.type_id != "com.kilroy.attractor.RunStarted":
```

This is consistent with the turn response format documented in Section 5.3.

---

## Issue #4: No holdout scenario covers CQL search returning zero Kilroy contexts when they exist

### The problem

The holdout scenarios test various failure modes (CXDB unreachable, DOT parse errors, stale pipelines) but there is no scenario covering the CQL search path returning zero results despite Kilroy contexts existing on the instance. Given Issue #1, this is the **default behavior** for current Kilroy contexts, not an edge case.

Even if Issue #1 is fixed (Kilroy adds key 30), the bootstrap lag documented in Section 5.2 means CQL search may return zero results during the brief window between context creation and first turn append. A holdout scenario should verify that the fallback path handles this correctly.

Related: there is no scenario covering the `client_tag` disappearing after session disconnect, which would affect completed pipeline discoverability on fresh page loads.

### Suggestion

Add holdout scenarios:

```
### Scenario: CQL search returns zero Kilroy contexts, fallback discovers them
Given CXDB has Kilroy contexts but CQL search for tag ^= "kilroy/" returns zero results
  (either because metadata key 30 is absent or because metadata extraction has not yet completed)
When the UI polls for pipeline discovery
Then the UI falls back to the context list endpoint
  And applies client-side prefix filtering on client_tag
  And discovers the Kilroy contexts via session-tag resolution
```

```
### Scenario: Completed pipeline remains discoverable after fresh page load
Given a Kilroy pipeline completed and its agent session has disconnected
  And the UI's knownMappings cache has been cleared (fresh page load)
When the UI polls for pipeline discovery
Then the completed pipeline's contexts are still discoverable
  (via CQL search if key 30 metadata exists, or via context list with stored metadata)
  And the pipeline graph shows the final status overlay
```
