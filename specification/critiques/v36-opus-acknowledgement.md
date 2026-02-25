# CXDB Graph UI Spec — Critique v36 (opus) Acknowledgement

All four issues from the v36 opus critique were evaluated. Issues #1 and #2 were applied to the specification. Issue #3 was already resolved in a prior round. Issue #4 was deferred as proposed holdout scenarios. Changes were verified against the Kilroy source code (`msgpack_encode.go`, `binary_client.go`, `cxdb_sink.go`, `parser.go`, `cxdb_events.go`), CXDB server source (`store.rs`, `protocol/mod.rs`, `http/mod.rs`, `cql/indexes.rs`, `metrics.rs`), and CXDB Go client types (`conversation.go`).

## Issue #1: The spec incorrectly claims CXDB's binary protocol embeds `client_tag` at key 30 in stored payloads

**Status: Applied to specification**

The factual claim that "CXDB's binary protocol embeds the session's `client_tag` at key 30 in the outer msgpack envelope of stored payloads" was incorrect. Verified by tracing the complete write path through both codebases:

- Kilroy's `EncodeTurnPayload` only emits tags from the `kilroy-attractor-v1` registry bundle (tags 1-12 for `RunStarted`). Tag 30 is not in the bundle.
- `BinaryClient.AppendTurn` writes raw payload bytes without metadata injection.
- CXDB's `parse_append_turn` passes payload bytes verbatim to the store.
- The key 30 convention lives in `cxdb/clients/go/types/conversation.go` for `ConversationItem` users; Kilroy uses its own type system.

Replaced the incorrect paragraph with a detailed section documenting: (a) the current state (Kilroy does NOT embed key 30), (b) consequences for CQL search and post-disconnect discovery, (c) `knownMappings` cache as partial mitigation, (d) required Kilroy-side change as a prerequisite, and (e) fallback behavior and workaround options for operators. Also added a "CQL discovery limitation" note in the discovery introduction paragraph (Section 5.5) explaining why CQL returns empty results for Kilroy contexts and why the context list fallback is not triggered.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Replaced "`client_tag` stability requirement" paragraph with corrected version documenting the key 30 gap
- `specification/cxdb-graph-ui-spec.md`: Added "CQL discovery limitation" note to the discovery introduction

## Issue #2: The metadata extraction asymmetry paragraph assumes key 30 is present in RunStarted

**Status: Applied to specification**

Updated the metadata extraction asymmetry paragraph to separate the structural analysis (which is correct) from the conditional claim about `client_tag` availability. The paragraph now has two sub-sections: "Current state (key 30 absent)" explaining that both extraction paths yield `None` since no payload contains key 30, and "After Kilroy implements key 30" explaining the expected behavior once the prerequisite is met. The structural analysis about `maybe_cache_metadata` vs `load_context_metadata` extracting from different turns is preserved as it remains relevant for the future implementation.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated "Metadata extraction asymmetry for forked contexts" paragraph with current-state and future-state sections

## Issue #3: The `decodeFirstTurn` pseudocode compares `rawTurn.declared_type` (an object) to a string

**Status: Not addressed — already resolved in a prior round**

The `decodeFirstTurn` pseudocode in the current spec (lines 705-706) already uses `rawTurn.declared_type.type_id` for the type check:

```
typeId = rawTurn.declared_type.type_id
IF typeId != "com.kilroy.attractor.RunStarted":
```

This is consistent with the turn response format in Section 5.3 where `declared_type` is an object with `type_id` and `type_version` fields. The issue was likely fixed during a prior revision cycle. No change needed.

## Issue #4: No holdout scenario covers CQL search returning zero Kilroy contexts when they exist

**Status: Deferred — proposed holdout scenarios written**

Two proposed holdout scenarios were added to `holdout-scenarios/proposed-holdout-scenarios-to-review.md`:

1. **CQL search returns zero Kilroy contexts, fallback discovers them** — Tests the current default behavior where CQL succeeds but returns empty results due to missing key 30 metadata. Verifies that the UI does not fall back (since CQL returned 200, not 404) and no contexts are discovered via the CQL path.

2. **Completed pipeline remains discoverable after fresh page load (once key 30 is implemented)** — Tests that after Kilroy implements key 30, completed pipelines are discoverable via CQL search even after session disconnect and fresh page load.

The `client_tag` disappearing after session disconnect is now documented in the main spec as part of Issue #1's "Consequences for discovery" section. Adding a separate holdout scenario for this specific failure mode is captured in the second proposed scenario.

Changes:
- `holdout-scenarios/proposed-holdout-scenarios-to-review.md`: Added two proposed holdout scenarios

## Not Addressed (Out of Scope)

- None. All four issues were addressed (two applied to spec, one already resolved, one deferred as proposed holdout scenarios).
