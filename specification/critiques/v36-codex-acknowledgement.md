# CXDB Graph UI Spec — Critique v36 (codex) Acknowledgement

Both issues from the v36 codex critique were evaluated and applied to the specification.

## Issue #1: Cached status map for inactive pipelines is undefined even after background polling

**Status: Applied to specification**

Updated Section 6.1 step 6 to compute merged status maps for **all loaded pipelines** on every poll cycle, not just the active pipeline. The previous text stated "Per-context maps for inactive pipelines are also updated but their merged maps are not computed until the user switches to that tab." This was inconsistent with Section 4.4's claim that a cached status map is "immediately reapplied" on tab switch and the "Switch between pipeline tabs" holdout scenario requiring no gray flash.

The new text specifies that `mergeStatusMaps`, `applyErrorHeuristic`, and `applyStaleDetection` run for each loaded pipeline on every poll cycle, and the resulting merged map is cached as the pipeline's current display map. On tab switch, the cached merged map is immediately applied to the new SVG.

Also updated Section 4.4's tab-switch paragraph to explicitly reference Section 6.1 step 6 as the source of the cached merged status map, making the dependency between the two sections clear.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 6.1 step 6 to merge status maps for all pipelines per poll cycle
- `specification/cxdb-graph-ui-spec.md`: Updated Section 4.4 tab-switch paragraph to reference Section 6.1 step 6

## Issue #2: RunStarted.graph_name matching lacks the same normalization rules used for DOT graph IDs

**Status: Applied to specification**

Added a clarification to the `graph_name` matching paragraph in Section 5.5 explaining the normalization relationship. The DOT-side graph ID is normalized per Section 4.4 (unquote, unescape, trim), while the `graph_name` value from CXDB's `RunStarted` is compared as-is.

Verified against Kilroy source: the Kilroy DOT parser (`parser.go` line 86) only accepts `tokenIdent` (unquoted identifiers) for graph names — it rejects quoted graph names. Therefore `graph_name` in `RunStarted` (set from `e.Graph.Name` in `cxdb_events.go`) is always an unquoted, unescaped identifier that matches the DOT graph ID without normalization mismatch. This means the normalization concern is theoretical for current Kilroy-generated pipelines. The new text documents this explicitly and notes that a future Kilroy version supporting quoted graph names would need to ensure both parsers produce the same normalized value.

A holdout scenario for quoted graph ID pipeline discovery was not added because Kilroy's parser currently rejects quoted graph names, making the scenario untestable against real Kilroy pipelines. If Kilroy adds quoted graph name support in the future, this scenario should be revisited.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated `graph_name` matching paragraph in Section 5.5 with normalization clarification

## Not Addressed (Out of Scope)

- None. Both issues were fully addressed.
