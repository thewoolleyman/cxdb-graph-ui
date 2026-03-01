# CXDB Graph UI Spec — Critique v28 (codex) Acknowledgement

Both issues from v28-codex have been applied to the specification. The changes align graph ID normalization with node ID normalization (adding explicit `\\` escape handling and whitespace trimming), and clarify that `turnCount`, `errorCount`, and `toolName` on `NodeStatus` are internal-only fields not displayed in the detail panel.

## Issue #1: Graph ID unescaping is underspecified and diverges from node ID normalization

**Status: Applied to specification**

Updated graph ID normalization in both Section 3.2 (server-side, `/dots/{name}`) and Section 4.4 (browser-side graph ID extraction) to explicitly include `\\` → `\` escape handling and leading/trailing whitespace trimming, matching the node ID normalization rules already documented in Section 3.2's `/dots/{name}/nodes` description. Both locations now cross-reference node ID normalization to make clear they use the same routine. Previously, graph ID normalization only mentioned `\"` → `"` unescaping; `\\` handling was implicit, and whitespace trimming was not mentioned.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated graph ID normalization in Section 3.2 to add `\\` → `\` and whitespace trimming, with cross-reference to node ID normalization.
- `specification/cxdb-graph-ui-spec.md`: Updated graph ID normalization in Section 4.4 to add `\\` → `\` and whitespace trimming, with cross-reference to node ID normalization.

## Issue #2: Detail panel references per-node counters that are never surfaced in the UI

**Status: Applied to specification**

Updated the error loop detection heuristic paragraph in Section 6.2 to explicitly state that `errorCount`, `turnCount`, and `toolName` on `NodeStatus` are internal-only bookkeeping fields — not displayed in the detail panel. Removed the contradictory "shown in the detail panel" statement. Clarified that the detail panel's CXDB Activity section (Section 7.2) shows individual turn rows from the turn cache, not aggregated counters from `NodeStatus`. This resolves the ambiguity where an implementer could not determine whether to build UI for these fields.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Replaced "display-only lifetime counter (shown in the detail panel)" in Section 6.2's error heuristic paragraph with explicit internal-only designation and cross-reference to Section 7.2.

## Not Addressed (Out of Scope)

- None. Both issues were applied.
