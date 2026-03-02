# CXDB Graph UI Spec — Critique v26 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v25 cycle had two critics (opus and codex). All 6 issues were applied: opus's 4 issues (integer-tag-based msgpack field access for `decodeFirstTurn`, msgpack CDN dependency with pinned URL, CQL search bootstrap lag documentation, SSE-based metadata labels workaround). Codex's 2 issues overlapped: the msgpack dependency gap was resolved by the same Section 4.1.1, and edge attribute parsing rules now reference node parsing rules. This critique is informed by reading the CXDB source (`server/src/`), the Kilroy attractor engine (`internal/attractor/engine/`), and the published `kilroy-attractor-v1` registry bundle (`kilroy/data/registry/bundle_kilroy-attractor-v1_004673dd423a.json`).

---

## Issue #1: The spec can now document the exact `RunStarted` tag numbers — the registry bundle is stable and publicly available in the Kilroy source tree, eliminating the "must verify" hedge

### The problem

Section 5.5's `decodeFirstTurn` pseudocode says:

> The tag numbers for RunStarted fields are defined in the kilroy-attractor-v1 registry bundle (published by Kilroy). The UI needs only two fields:
>   graph_name — tag defined in the bundle's RunStarted type descriptor
>   run_id     — tag defined in the bundle's RunStarted type descriptor
> Because tag numbers are assigned by the Kilroy project (not CXDB) and may vary across bundle versions, the implementer MUST verify the exact tag numbers against the published kilroy-attractor-v1 bundle descriptor.

The published registry bundle (`kilroy/data/registry/bundle_kilroy-attractor-v1_004673dd423a.json`) defines the `com.kilroy.attractor.RunStarted` v1 field tags:

- Tag `1`: `run_id` (string)
- Tag `8`: `graph_name` (string, optional)

These tag numbers are stable: CXDB's type registry versioning model means existing tags are never reassigned (new fields get new tags, existing tags are immutable within a version). The "may vary across bundle versions" hedge is overly cautious and forces every implementer to independently locate and parse the registry bundle JSON. Since the spec already documents the CXDB API in comparable detail, specifying the tag numbers directly is both safe and useful.

### Suggestion

Replace the "MUST verify" block with concrete tag numbers:

```
-- RunStarted field tags (from kilroy-attractor-v1 bundle, version 1):
--   Tag 1: run_id (string)
--   Tag 8: graph_name (string, optional)
-- These tags are stable within bundle version 1. New bundle versions
-- add fields with new tags; existing tags are never reassigned.
RETURN {
    declared_type: rawTurn.declared_type,
    data: { graph_name: payload["8"] || payload[8], run_id: payload["1"] || payload[1] }
}
```

The `||` fallback handles both string-encoded integer keys (Go's msgpack encoder) and integer keys (other encoders), as the existing spec text already describes.

---

## Issue #2: Section 5.4 lists `graph_dot` as a `RunStarted` data field, but `graph_dot` is not in the `kilroy-attractor-v1` registry bundle and is silently dropped during msgpack encoding — an implementer would expect to find it in turn data but it does not exist

### The problem

Section 5.4's turn type table states:

| Type ID | Key Data Fields |
|---------|-----------------|
| `com.kilroy.attractor.RunStarted` | `graph_name`, `graph_dot`, `run_id` |

The Kilroy engine (`internal/attractor/engine/cxdb_events.go` lines 30-32) conditionally adds `graph_dot` to the data map:

```go
if len(e.DotSource) > 0 {
    data["graph_dot"] = string(e.DotSource)
}
```

However, the `kilroy-attractor-v1` registry bundle's `RunStarted` v1 type has NO `graph_dot` field. Its 11 fields are: `run_id` (tag 1), `timestamp_ms` (tag 2), `repo_path` (tag 3), `base_sha` (tag 4), `run_branch` (tag 5), `logs_root` (tag 6), `worktree_dir` (tag 7), `graph_name` (tag 8), `goal` (tag 9), `modeldb_catalog_sha256` (tag 10), `modeldb_catalog_source` (tag 11).

The Kilroy `EncodeTurnPayload` function (`internal/cxdb/msgpack_encode.go` lines 19-28) converts named field keys to their registry tag numbers. Fields not in the registry AND not already numeric-string keys are silently dropped. Since `"graph_dot"` is neither in the registry nor a numeric string, it is **silently dropped** during msgpack encoding and never reaches CXDB.

Listing `graph_dot` as a `RunStarted` field in the spec misleads an implementer into expecting it in the turn data (whether `view=typed` or `view=raw`). While the UI does not use `graph_dot` (it fetches DOT files from `/dots/{name}`), documenting a phantom field creates confusion about the data model and raises questions about whether the UI should be using it as a DOT source instead.

### Suggestion

Remove `graph_dot` from Section 5.4's `RunStarted` key data fields:

| Type ID | Key Data Fields |
|---------|-----------------|
| `com.kilroy.attractor.RunStarted` | `graph_name`, `run_id` |

Optionally add a note that `RunStarted` also carries `timestamp_ms`, `repo_path`, `base_sha`, `run_branch`, `logs_root`, `worktree_dir`, `goal`, `modeldb_catalog_sha256`, and `modeldb_catalog_source`, but none of these are used by the UI.

---

## Issue #3: The `graph_name` field is optional in the `RunStarted` type — the spec does not handle the case where a `RunStarted` turn has a null or empty `graph_name`, which would cause a silent pipeline discovery failure

### The problem

The registry bundle marks `graph_name` as `optional: true` for `RunStarted` v1. This means a valid `RunStarted` turn can have `graph_name` absent from the msgpack payload entirely. Even when present, the Kilroy engine sets it to `e.Graph.Name`, which could be an empty string if the graph has no name.

The `discoverPipelines` pseudocode extracts `graph_name` unconditionally from `decodeFirstTurn`'s result and caches it in `knownMappings`:

```
knownMappings[key] = { graphName, runId }
```

If `graphName` is `null`, `undefined`, or an empty string:

1. The context is cached in `knownMappings` with a non-null mapping (graphName is null/empty but the mapping object exists)
2. The `determineActiveRuns` loop checks `mapping.graphName == pipeline.graphId` — this will never match any pipeline
3. The mapping is permanently cached as a positive result, so the context is never re-evaluated
4. The context's turns are permanently excluded from the status overlay with no diagnostic output

This is a silent data loss scenario. A context with valid turns and a valid `run_id` — but missing or empty `graph_name` — would be invisible in the UI.

### Suggestion

Add a guard after `decodeFirstTurn` succeeds that treats a null or empty `graph_name` as a classification failure. Either:

(a) Cache it as a null mapping (same as a non-Kilroy context):
```
IF firstTurn.data.graph_name IS null OR firstTurn.data.graph_name == "":
    knownMappings[key] = null  -- RunStarted but no graph_name; cannot match any pipeline
    CONTINUE
```

Or (b) leave it uncached so it retries on subsequent polls (in case the DOT graph ID was not yet set when the `RunStarted` was emitted — though this would be a Kilroy bug). Option (a) is recommended since the first turn is immutable.

---

## Issue #4: The `fetchFirstTurn` pagination walks the CXDB parent chain to depth 0, but for forked contexts (parallel branches) this traversal crosses into the parent context's turn history — the spec does not document this cross-context behavior or its correctness implications

### The problem

Section 5.5's `fetchFirstTurn` paginates backward from the head using `before_turn_id` to find the depth-0 turn. CXDB's `get_before` implementation (`turn_store/mod.rs` lines 539-555) walks the parent chain via `parent_turn_id` links.

For forked contexts (created via CXDB's context linking for parallel branches), the parent chain extends into the parent context's turns. The turn at the fork point has a `parent_turn_id` pointing to a turn in the parent context. Walking to depth 0 therefore traverses: child's turns -> parent context's turns -> ... -> parent's depth-0 turn (the `RunStarted`).

This traversal is actually correct for Kilroy's parallel branch pattern: forked branch contexts inherit the parent's `RunStarted` turn (which contains the same `graph_name` and `run_id`), so the depth-0 turn discovered by `fetchFirstTurn` correctly classifies the child context. This is why the pagination approach works without needing the context lineage optimization described later in Section 5.5.

However, the spec does not explain this cross-context traversal behavior. An implementer reading the `fetchFirstTurn` pseudocode would assume it only traverses turns within the target context. The fact that it crosses context boundaries (via CXDB's parent chain linking) is a non-obvious CXDB internal behavior that should be documented, both for correctness understanding and to prevent future breakage if Kilroy's forking model changes (e.g., if forked contexts emit their own `RunStarted` at depth N rather than inheriting the parent's depth-0 turn).

### Suggestion

Add a note to the `fetchFirstTurn` section explaining:

1. For forked contexts (parallel branches), the `before_turn_id` pagination follows CXDB's parent chain across context boundaries — the depth-0 turn found is from the parent context, not the child.
2. This is correct because Kilroy's parallel branch contexts share the parent's `RunStarted` turn (same `graph_name`, same `run_id`) via the linked parent chain.
3. If a future Kilroy version emits a new `RunStarted` in each forked child context, the pagination would still work (it would find the child's `RunStarted` at the child's depth-0 position), but the current behavior discovers the parent's `RunStarted` instead.
