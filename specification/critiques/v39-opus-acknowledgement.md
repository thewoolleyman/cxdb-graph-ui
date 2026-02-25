# CXDB Graph UI Spec — Critique v39 (opus) Acknowledgement

All four issues from the v39 opus critique were evaluated and applied to the specification. Changes were verified against the Kilroy source code (`handlers.go` shapeToType function, `cxdb_events.go` cxdbRunFailed function).

## Issue #1: Shape-to-type mapping is incomplete — five shapes used in Kilroy pipelines are missing from Section 7.3

**Status: Applied to specification**

The Section 7.3 shape-to-type label mapping table was expanded from six to ten entries plus a default row. The five missing shapes were added: `circle` (Start), `doublecircle` (Exit), `component` (Parallel), `tripleoctagon` (Parallel Fan-in), and `house` (Stack Manager Loop). An explanatory paragraph was added documenting which SVG elements each shape produces. A note was added to Section 6.3 confirming that the `polygon`, `ellipse`, `path` CSS selectors cover all ten shapes, with an explicit callout for `doublecircle`'s dual-ellipse rendering. Two proposed holdout scenarios were written covering the extended shape set for both rendering and status coloring.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Expanded Section 7.3 table from 6 to 10 shapes plus default row, with explanatory paragraph
- `specification/cxdb-graph-ui-spec.md`: Added SVG element coverage note to Section 6.3
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added proposed scenarios for extended shape coverage in rendering and status coloring

## Issue #2: `RunFailed` with `node_id` falls through to the non-lifecycle "infer running" branch in the status derivation pseudocode

**Status: Applied to specification**

An explicit `RunFailed` case was added to the `updateContextStatusMap` pseudocode in Section 6.2, setting `newStatus = "error"` and `hasLifecycleResolution = true`. `RunFailed` was added to the lifecycle turn override condition (alongside `StageFinished` and `StageFailed`). The "Lifecycle turn precedence" paragraph was updated to mention `RunFailed` as an authoritative lifecycle signal, noting that Kilroy's `cxdbRunFailed` always passes a `node_id`. The "Once a node has `hasLifecycleResolution`" sentence was updated to include `RunFailed` in the list of lifecycle turns that can modify a resolved node's status.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added `RunFailed` case to `updateContextStatusMap` pseudocode (Section 6.2)
- `specification/cxdb-graph-ui-spec.md`: Added `RunFailed` to lifecycle turn override condition (Section 6.2)
- `specification/cxdb-graph-ui-spec.md`: Updated "Lifecycle turn precedence" paragraph (Section 6.2)

## Issue #3: The `default` case in Kilroy's `shapeToType` is not reflected in the spec's shape-to-type mapping

**Status: Applied to specification**

A default/fallback row was added to the Section 7.3 table: "*(any other)* -> LLM Task (default)". This matches Kilroy's `shapeToType` `default` case which returns `"codergen"`. The explanatory paragraph notes this ensures the UI handles DOT files with unexpected shapes gracefully.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added default row to Section 7.3 table

## Issue #4: No holdout scenario covers `RunFailed` with `node_id` marking a node as error

**Status: Applied to holdout scenarios**

A proposed holdout scenario "Pipeline run fails on a specific node (RunFailed with node_id)" was written to `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`. The scenario tests that a `RunFailed` turn with `node_id` marks the node as red (error) with `hasLifecycleResolution = true`, and that the detail panel shows the failure reason.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added proposed scenario for RunFailed with node_id

## Not Addressed (Out of Scope)

- None. All four issues were fully addressed.
