# CXDB Graph UI Spec — Critique v20 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-24

## Prior Context

No acknowledgement file exists for v19, so changes since the last critique are unknown and prior issues may still be open.

---

## Issue #1: Pipeline discovery permanently ignores contexts after transient turn fetch failures

### The problem
Section 5.5 caches context-to-pipeline mappings forever once a context is classified. The discovery algorithm sets `knownMappings[key] = null` when the `RunStarted` turn is missing or unexpected, but it does not define behavior for transient failures fetching the first turn (e.g., CXDB returns non-200 because the type registry bundle is missing, or the instance is temporarily unreachable). Because the mapping is immutable, a transient failure can permanently classify a valid Kilroy context as `null`, causing the pipeline to never appear for that run even after CXDB recovers or the registry is published.

This is especially likely during early setup: the spec already calls out registry-missing failures in Section 5.3 and step 4 of the poller, but discovery happens before the per-context polling error handling, and it has no retry semantics. The result is a sticky false-negative mapping that contradicts the intent of “graceful degradation.”

### Suggestion
Distinguish between “confirmed non-Kilroy” and “unknown due to error.” Only cache `null` when the first turn fetch succeeds and the first turn is definitively not `RunStarted` (or the context lacks a `kilroy/` tag). If fetching the first turn fails (non-200, timeout, or typed-registry error), mark the mapping as `unknown` and retry on subsequent polls. Alternatively, use `view=raw` or `view=both` for the `RunStarted` fetch to avoid typed-registry dependency during discovery. Add a holdout scenario covering transient discovery failure (e.g., registry missing at first poll, later published, mapping should recover).

---

## Issue #2: Graph ID collisions across multiple DOT files are undefined

### The problem
Pipeline discovery matches CXDB contexts to DOT files by graph ID (`RunStarted.data.graph_name` vs the DOT `digraph` identifier). The spec also allows multiple `--dot` files, but it does not state that graph IDs must be unique across those files. If two DOT files share the same graph ID, the UI’s pipeline tabs and status overlay become ambiguous: both tabs would match the same contexts and display identical status data, even if the DOT structures differ. This makes tab labels misleading and breaks the “generic pipeline support” promise.

### Suggestion
Define a uniqueness requirement for graph IDs across loaded DOT files. The simplest fix mirrors the basename collision check in Section 3.2: on startup, parse each DOT’s graph ID and exit with a clear error if duplicates exist. Alternatively, if duplicates are allowed, define a disambiguation strategy (e.g., match by filename instead of graph ID, and require `RunStarted` to carry the filename). Add a holdout scenario for duplicate graph IDs to ensure the behavior is explicit.
