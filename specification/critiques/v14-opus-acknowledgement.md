# CXDB Graph UI Spec — Critique v14 (opus) Acknowledgement

All 3 issues were valid and applied to the specification. Issue #1 fixed the error heuristic to filter by ToolResult turns only, preventing non-ToolResult turns from diluting the error detection window. Issue #2 corrected the `next_before_turn_id` semantics and added an early-exit optimization in `fetchFirstTurn`. Issue #3 added explicit pseudocode for the active run determination algorithm. All claims were verified against the CXDB server source (`server/src/http/mod.rs`) and type definitions (`clients/rust/src/types/conversation.rs`).

## Issue #1: Error heuristic likely never fires — `getMostRecentTurnsForNodeInContext` returns ALL turn types, but only ToolResult turns have `is_error`

**Status: Applied to specification**

Verified against CXDB source: `clients/rust/src/types/conversation.rs:229` confirms `is_error: bool` exists only on the `ToolResult` struct. `ToolCall`, `UserInput`, `Assistant`, and `SystemMessage` structs have no `is_error` field. During a typical error loop (Prompt → ToolCall → ToolResult(is_error:true) → repeat), the 3 most recent turns by any type would include non-ToolResult turns where `is_error` is `undefined`, causing the `ALL(turn.data.is_error == true)` check to always fail.

Applied the suggested fix:

1. **Section 6.2 pseudocode** — Renamed `getMostRecentTurnsForNodeInContext` to `getMostRecentToolResultsForNodeInContext` in the `applyErrorHeuristic` function. Updated the comment to specify "ToolResult errors."

2. **Section 6.2 helper description** — Updated the helper name and description to specify that it filters by `declared_type.type_id == "com.kilroy.attractor.ToolResult"`. Added an explanation of why only ToolResult turns are considered: they are the only type carrying `is_error`, and including other turn types would dilute the detection window given the interleaved Prompt → ToolCall → ToolResult turn cycle.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 — renamed helper to `getMostRecentToolResultsForNodeInContext`, updated pseudocode and description to filter by ToolResult type

## Issue #2: `next_before_turn_id` semantics are mischaracterized — it is null only when the response is empty, not when no more pages exist

**Status: Applied to specification**

Verified against CXDB source: `server/src/http/mod.rs:916` shows `let next_before = turns.first().map(|t| t.record.turn_id.to_string())`, confirming `next_before_turn_id` is null only when the response turns array is empty, not when there are no more pages.

Applied all three suggested changes:

1. **Section 5.3** — Corrected the `next_before_turn_id` response field description. Now reads: "Set to the oldest turn's ID in the response; `null` when the response contains no turns." Added a note that the definitive "no more pages" signal is `response.turns.length < limit`.

2. **Section 5.5 `fetchFirstTurn`** — Added a `response.turns.length < fetchLimit` early-exit check before the `next_before_turn_id IS null` check. This eliminates the extra HTTP request for contexts with ≤65,535 turns (virtually all Kilroy pipelines). The `next_before_turn_id IS null` check is retained as a defensive guard with a comment noting it is unreachable after the preceding checks.

3. **Section 6.1 gap detection** — Updated the comment on the `next_before_turn_id IS NOT null` condition from "older turns exist to paginate" to "response was non-empty (more turns may exist to paginate)." Also updated the prose explanation of the guard to accurately describe what a non-null `next_before_turn_id` actually means.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 5.3 — corrected `next_before_turn_id` description
- `specification/cxdb-graph-ui-spec.md`: Section 5.5 — added `turns.length < fetchLimit` early-exit in `fetchFirstTurn`
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 — updated gap detection comment and prose explanation

## Issue #3: "Determine active run per pipeline" (polling step 3) is the only multi-step algorithm in the polling cycle without pseudocode

**Status: Applied to specification**

The critique correctly identified that step 3 was the sole algorithm in the spec described only in prose despite having comparable complexity to algorithms with explicit pseudocode. The data joining (discovery mapping + context list), grouping/comparison, state reset, and active run tracking were all implicit.

Applied the suggested pseudocode with minor adjustments:

**Section 6.1 step 3** — Added a `determineActiveRuns` pseudocode block after the step 3 prose. The pseudocode covers: (1) joining `knownMappings` with `contextLists` to access `created_at_unix_ms`, (2) grouping candidates by `run_id` and selecting the group with the highest `max(created_at_unix_ms)`, (3) detecting run changes via `previousActiveRunIds` and calling `resetPipelineState`, and (4) returning active contexts by pipeline. Also added prose noting that `contextLists` must be retained from step 1, and that `previousActiveRunIds` is maintained across poll cycles. Added descriptions of the `lookupContext` and `resetPipelineState` helpers.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 step 3 — added `determineActiveRuns` pseudocode, `previousActiveRunIds` state tracking note, and helper descriptions

## Not Addressed (Out of Scope)

- None — all issues were addressed.
