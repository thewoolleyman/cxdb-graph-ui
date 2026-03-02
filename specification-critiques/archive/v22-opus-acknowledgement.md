# CXDB Graph UI Spec — Critique v22 (opus) Acknowledgement

All five issues from v22-opus have been evaluated. Four were applied to the specification with changes informed by the CXDB server source code. One (Issue #5) pertains to the holdout scenarios document, which is a reference file outside the spec, and is acknowledged but not applied as a spec change.

## Issue #1: `fetchFirstTurn` fetches the entire context history — unbounded memory and latency for deep contexts

**Status: Applied to specification**

Replaced the single-request approach (`limit=headDepth + 1`) with bounded backward pagination. The new `fetchFirstTurn` paginates backward from the head in pages of 100 turns, checking each page for a turn with `depth == 0`. Capped at 50 pages (MAX_PAGES) to prevent runaway pagination. Added documentation of the O(headDepth / PAGE_SIZE) pagination cost, the memory improvement over the single-request approach, and a note about CXDB's unexposed `get_first_turn` internal method. Updated the turn parameter table to remove the `headDepth + 1` reference.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Rewrote the `fetchFirstTurn` pseudocode and surrounding prose in Section 5.5.
- `specification/cxdb-graph-ui-spec.md`: Updated the `limit` parameter description in the turn query parameters table (Section 5.3).

## Issue #2: Spec assumes `GET /v1/contexts` returns ALL contexts with `limit=10000`, but the CXDB source returns contexts in descending order — oldest contexts may be truncated

**Status: Applied to specification**

Documented the context list ordering as newest-first (descending by `created_at_unix_ms`) in Section 5.2, matching the CXDB `list_recent_contexts` implementation. Added a "Truncation risk" paragraph documenting that `limit=10000` is a heuristic, the failure mode (silent non-discovery of old pipelines on busy instances), and a pointer to CXDB prefix-based tag filtering as a potential future improvement (noting the current exact-match limitation). Also added a note in Section 5.5's discovery algorithm description about the newest-first ordering.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added ordering documentation and truncation risk paragraph to Section 5.2.
- `specification/cxdb-graph-ui-spec.md`: Added newest-first ordering note to Section 5.5 discovery algorithm description.

## Issue #3: The spec does not account for CXDB's `ContextLinked` events and cross-context lineage, which could simplify pipeline discovery

**Status: Applied to specification**

Added a "Context lineage optimization" paragraph after the caching description in Section 5.5. Documents that CXDB tracks cross-context lineage (`parent_context_id`, `root_context_id`, `spawn_reason`) available via `include_lineage=1`, and describes how it could be used to skip `fetchFirstTurn` for child contexts by inheriting the parent's mapping. Explicitly labeled as "not required for initial implementation" to keep the initial build simple.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "Context lineage optimization" paragraph to Section 5.5.

## Issue #4: `resetPipelineState` removes old-run `knownMappings` entries, but new contexts reusing the same CXDB context IDs could cause misclassification

**Status: Applied to specification**

Updated the `resetPipelineState` rationale in Section 6.1. The removal of old-run mappings is now justified as memory hygiene (old entries accumulate indefinitely and never match the active run), with an explicit note that CXDB context IDs are monotonically increasing and never reused. Removed the incorrect statement about "same context IDs appear in a future run."

Changes:
- `specification/cxdb-graph-ui-spec.md`: Corrected the `resetPipelineState` rationale paragraph in Section 6.1.

## Issue #5: The holdout scenario "Agent stuck in error loop" does not match the spec's per-context scoping of the error heuristic

**Status: Not addressed**

The holdout scenario is ambiguous about per-context scoping, as the critique correctly identifies. However, the holdout scenarios document (`holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`) is a reference file outside the spec — changes to it are outside the scope of a spec revision. The spec's `applyErrorHeuristic` pseudocode in Section 6.2 clearly defines per-context scoping via `getMostRecentToolResultsForNodeInContext`, which is the authoritative definition. The holdout scenario should be updated separately to clarify per-context scoping and add the negative case (errors across contexts), but this is deferred as a holdout-scenarios update task.

## Not Addressed (Out of Scope)

- Holdout scenario update for per-context error scoping (Issue #5) — deferred as a separate holdout-scenarios maintenance task, not a spec change.
