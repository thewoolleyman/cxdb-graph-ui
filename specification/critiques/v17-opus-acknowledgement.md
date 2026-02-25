# CXDB Graph UI Spec — Critique v17 (opus) Acknowledgement

All 3 issues were valid and applied. Issue #1 fixed the SVG status class accumulation bug by adding explicit class removal before adding the new status class. Issue #2 replaced the pagination loop in `fetchFirstTurn` with a single fetch for the `headDepth > 0` case, eliminating the unnecessary second HTTP request. Issue #3 tightened the error loop holdout scenario to specify ToolResult turns with interleaving, matching the spec's heuristic.

## Issue #1: SVG status class application never removes previous status classes — visual corruption on node transitions

**Status: Applied to specification**

The matching algorithm in Section 4.2 now removes all status classes before adding the current one. Added a `STATUS_CLASSES` constant listing all five status class names (`node-pending`, `node-running`, `node-complete`, `node-error`, `node-stale`) and a `classList.remove(...STATUS_CLASSES)` call before `classList.add`. This prevents class accumulation across status transitions — e.g., a node transitioning from `running` to `complete` no longer retains the `node-running` class and its pulse animation.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 4.2 — added `STATUS_CLASSES` constant and `classList.remove` call to the matching algorithm pseudocode

## Issue #2: `fetchFirstTurn` loop always makes an unnecessary second HTTP request despite prose claiming "single request"

**Status: Applied to specification**

Replaced the pagination loop in the `headDepth > 0` branch with a single fetch. Since `headDepth + 1` is designed to return all turns in one request, the loop was unnecessary and always triggered a second empty-response request. The new pseudocode makes a single `fetchTurns` call with `limit=headDepth + 1` and returns `response.turns[0]` (the oldest turn in oldest-first ordering). The `headDepth == 0` branch is unchanged.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 5.5 — replaced `fetchFirstTurn` pagination loop with single-fetch implementation for `headDepth > 0` case

## Issue #3: Error loop holdout scenario does not match the spec's ToolResult-only heuristic

**Status: Applied to holdout scenarios**

Updated the holdout scenario to specify that the 3 most recent **ToolResult** turns must each have `is_error: true`, and added an explicit condition that non-ToolResult turns (Prompt, ToolCall) are interleaved between them. The interleaving condition ensures that an implementation checking all turn types (rather than only ToolResult turns) would fail the test, aligning the holdout with the spec's `getMostRecentToolResultsForNodeInContext` filter.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: updated "Agent stuck in error loop" scenario to specify ToolResult turns with interleaving

## Not Addressed (Out of Scope)

- None. All issues were addressed.
