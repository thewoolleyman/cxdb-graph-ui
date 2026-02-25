# CXDB Graph UI Spec — Critique v33 (codex) Acknowledgement

Both issues from the v33 codex critique were evaluated and applied to the specification.

## Issue #1: `resetPipelineState` deletes old-run mappings, forcing expensive re-discovery every poll

**Status: Applied to specification**

Revised the `resetPipelineState` call in the `determineActiveRuns` pseudocode (Section 6.1) to explicitly document that old-run entries are retained in `knownMappings`. Added inline comments explaining that `resetPipelineState` clears per-context status maps, cursors, and turn caches — but does NOT remove old-run entries from `knownMappings`, since doing so would force expensive `fetchFirstTurn` re-discovery for every old-run context on every poll cycle. Also updated Invariant #10 to clarify that mappings are never removed once resolved, and that the `determineActiveRuns` algorithm naturally ignores old-run contexts because their `runId` does not match the current active run.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated `resetPipelineState` call in `determineActiveRuns` pseudocode with inline comments clarifying mapping retention
- `specification/cxdb-graph-ui-spec.md`: Updated Invariant #10 to state mappings are "never removed" and explain the rationale

## Issue #2: Initialization prefetch of `/nodes` lacks a defined error path for non-400 failures

**Status: Applied to specification**

Added an "Error handling" note to Step 4 of the initialization sequence (Section 4.5) defining behavior for all `/nodes` prefetch failure modes: 400, 404, 500, and network errors all result in logging a warning and proceeding with an empty `dotNodeIds` set. A failed prefetch does not block steps 5 (render first pipeline) or 6 (start polling). This aligns with the graceful-degradation principle in Section 1.2.

Additionally, a proposed holdout scenario for `/nodes` prefetch non-400 failures was written to `holdout-scenarios/proposed-holdout-scenarios-to-review.md` to complement the existing DOT parse error scenario.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added error handling contract to Step 4 of Section 4.5
- `holdout-scenarios/proposed-holdout-scenarios-to-review.md`: Added proposed scenario for `/nodes` prefetch non-400 failure

## Not Addressed (Out of Scope)

- None. Both issues were fully addressed.
