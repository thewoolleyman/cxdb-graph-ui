# CXDB Graph UI Spec — Critique v42 (opus) Acknowledgement

All four issues from the v42 opus critique were evaluated. Issues #1, #2, and #4 were applied to the specification, verified against Kilroy source (`comments.go`, `cxdb_events.go`, `handlers.go`). Issue #3 was deferred as a proposed holdout scenario.

## Issue #1: Comment-stripping specification omits unterminated-string error handling present in Kilroy's `stripComments`

**Status: Applied to specification**

The comment handling paragraph in Section 3.2 was updated to add unterminated string error handling alongside the existing unterminated block comment error. The new text states: "An unterminated string (a `\"` with no matching closing `\"` before end of input) encountered during comment stripping is also a parse error." This was verified against Kilroy's `stripComments` function (`kilroy/internal/attractor/dot/comments.go` line 67), which explicitly checks for `inString == true` after processing all input and returns `fmt.Errorf("dot: unterminated string (while stripping comments)")`.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 3.2 comment handling paragraph to document unterminated string as a parse error

## Issue #2: The spec does not document that `StageStarted` includes `handler_type` in the detail panel rendering

**Status: Applied to specification**

The `StageStarted` row in Section 7.2's per-type rendering table was updated from a fixed "Stage started" label to include the `handler_type` field: `"Stage started" + (if data.handler_type is non-empty: ": {data.handler_type}")`. The explanatory paragraph later in Section 7.2 was also updated to describe the `handler_type` values (e.g., "codergen", "tool", "wait.human") and their source in Kilroy's `resolvedHandlerType` function (`cxdb_events.go` line 72, `handlers.go` lines 174-182). This helps operators identify what kind of execution is beginning, particularly for conditional nodes with `TypeOverride`.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 7.2 `StageStarted` rendering row and explanatory paragraph to include `handler_type`

## Issue #3: No holdout scenario tests gap recovery with turn deduplication across the recovery boundary

**Status: Deferred — proposed holdout scenario written**

A proposed holdout scenario "Gap recovery does not double-count already-processed turns" was written to `holdout-scenarios/proposed-holdout-scenarios-to-review.md`. The scenario tests that gap recovery's prepended older turns are correctly deduplicated against previously processed turns, and that `turnCount` reflects only newly processed turns (501-650), not the full history.

Changes:
- `holdout-scenarios/proposed-holdout-scenarios-to-review.md`: Added proposed scenario for gap recovery deduplication

## Issue #4: Tool gate nodes produce ToolCall/ToolResult turns — clarification note

**Status: Applied to specification**

A new "Tool gate turns" paragraph was added to Section 7.2, before the "Custom routing values in `StageFinished`" paragraph. The note explains that tool gate nodes (shape=parallelogram) produce `ToolCall` and `ToolResult` turns with `tool_name: "shell"`, referencing Kilroy's `ToolHandler` (`handlers.go` lines 536-549 and 621-652), and clarifies that the standard per-type rendering handles these turns identically to LLM task tool turns. This is a documentation clarification, not a functional change.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "Tool gate turns" paragraph to Section 7.2

## Not Addressed (Out of Scope)

- Issue #3 is deferred to the holdout scenario review process. The spec already documents gap recovery and turn deduplication behavior; the gap is in holdout scenario coverage.
