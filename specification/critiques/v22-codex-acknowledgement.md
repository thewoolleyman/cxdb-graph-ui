# CXDB Graph UI Spec — Critique v22 (codex) Acknowledgement

Both issues from v22-codex have been applied to the specification. DOT regeneration now refreshes cached metadata, and server-side graph ID parsing is specified to match the browser's algorithm.

## Issue #1: DOT regeneration does not refresh cached node/edge metadata

**Status: Applied to specification**

Updated Section 4.4's tab-switch behavior to specify that on every tab switch (or any event that refetches a DOT file), the UI also refetches `/dots/{name}/nodes` and `/dots/{name}/edges` to refresh cached node/edge metadata and updates `dotNodeIds`. When the node list changes, new nodes are initialized as "pending" and removed nodes are dropped from per-context status maps. This ensures the "DOT file regenerated while UI is open" holdout scenario is fully satisfied — not just SVG rendering, but also status overlays, detail panel data, and human-gate choices reflect the regenerated DOT file.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Extended the tab-switch paragraph in Section 4.4 to include node/edge metadata refetch and `dotNodeIds` reconciliation.

## Issue #2: Server-side graph ID extraction is underspecified and may disagree with browser normalization

**Status: Applied to specification**

Updated Section 3.2's graph ID uniqueness check to explicitly specify that the server uses the same parsing and normalization logic as the browser (Section 4.4): the same regex pattern, quoted ID unquoting, and escape sequence resolution. This ensures the server's uniqueness check and the browser's pipeline discovery produce identical normalized graph IDs for the same DOT file.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Expanded the graph ID uniqueness paragraph in Section 3.2 to specify the shared parsing algorithm.

## Not Addressed (Out of Scope)

- None. Both issues were applied.
