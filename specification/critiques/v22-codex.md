# CXDB Graph UI Spec — Critique v22 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-24

## Prior Context

The v21 acknowledgements report that all earlier issues were applied: empty contexts now retry, node-ID prefetching was added, `/api/dots` response format was made consistent, context list caching for unreachable CXDB instances was specified, the `hasLifecycleResolution` merge semantics changed to AND, and the `fetchFirstTurn` dead code was removed. This critique focuses on remaining gaps introduced by DOT regeneration and graph ID parsing consistency.

---

## Issue #1: DOT regeneration does not refresh cached node/edge metadata

### The problem

The spec requires `/dots/{name}` to be read fresh on every request and includes a holdout scenario where a DOT file is regenerated while the UI is open. However, the initialization sequence prefetches `/dots/{name}/nodes` once at startup, and the detail panel relies on cached `/dots/{name}/nodes` and `/dots/{name}/edges` data thereafter. When a DOT file changes (new nodes, removed nodes, changed prompts, or new edge labels), the UI will re-render the SVG after a tab click, but the cached node/edge metadata and `dotNodeIds` remain stale. That breaks three behaviors:

- Status overlays may omit newly added nodes because `dotNodeIds` was never refreshed.
- Detail panel prompts/tool commands/questions can display old data for updated nodes.
- Human-gate choices derived from outgoing edge labels can be out of sync with the updated DOT graph.

This is a direct mismatch with the “DOT file regenerated while UI is open” scenario, which expects the refreshed graph structure to be reflected in UI behavior, not just the SVG rendering.

### Suggestion

On every tab switch (or any time `/dots/{name}` is refetched), also refetch `/dots/{name}/nodes` and `/dots/{name}/edges`, replace the cached metadata, and refresh `dotNodeIds` for that pipeline. When the node list changes, either (a) reinitialize per-context status entries for new nodes and drop removed nodes, or (b) reset the per-context status maps for that pipeline so the overlay is guaranteed to align with the new graph.

---

## Issue #2: Server-side graph ID extraction is underspecified and may disagree with browser normalization

### The problem

Section 3.2 says the server enforces graph ID uniqueness by parsing the graph ID “after `digraph`.” Section 4.4 provides a detailed browser-side extraction algorithm that supports quoted IDs and escape sequences and normalizes the result (unquote + unescape). The server’s extraction rules are not specified, so an implementation could treat quoted identifiers, escaped quotes, or non-`\w+` IDs differently from the browser. That creates two risks:

- The server could falsely reject two DOT files with different quoted IDs that normalize to different names, or fail to detect conflicts that the UI treats as identical.
- The UI could match `RunStarted.data.graph_name` against a normalized browser graph ID that differs from the server’s parsed ID, resulting in confusing “duplicate graph ID” errors or unexpected pipeline discovery behavior.

### Suggestion

Specify that the server uses the same graph ID parsing and normalization logic as the browser (the regex in Section 4.4 plus unquoting and unescaping). Document this explicitly in the graph ID uniqueness check, ideally with shared pseudocode or a short paragraph mirroring the browser’s algorithm.
