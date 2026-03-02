# CXDB Graph UI Spec — Critique v34 (codex) Acknowledgement

Both issues from the v34 codex critique were evaluated and applied to the specification.

## Issue #1: `resetPipelineState` semantics are self-contradictory (retain vs. remove old-run mappings)

**Status: Applied to specification**

This is the same issue as opus v34 Issue #1. Replaced the contradictory prose paragraph after the `determineActiveRuns` pseudocode (Section 6.1) that stated `resetPipelineState` "removes `knownMappings` entries" with language that explicitly states it does **not** remove old-run entries. The new text aligns with the inline pseudocode comments, Invariant #10, and the v33 codex acknowledgement.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Rewrote `resetPipelineState` prose description in Section 6.1 to match pseudocode and Invariant #10

## Issue #2: Tab-switch fetches lack defined error handling for `/nodes` and `/edges` failures

**Status: Applied to specification**

Added a "Tab-switch error handling" paragraph to Section 4.4 defining failure policies for `/nodes` and `/edges` fetches during tab switches. On any non-200 response or network error: `/nodes` failures retain the previous `dotNodeIds` for the pipeline (or fall back to empty), and `/edges` failures retain the previous edge list (or use empty). This mirrors the initialization prefetch rules (Section 4.5, Step 4) and ensures cached status maps are not discarded due to transient errors.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "Tab-switch error handling" paragraph to Section 4.4

## Not Addressed (Out of Scope)

- The codex critique suggested adding a holdout scenario for tab-switch `/nodes`/`/edges` failure. This is written to the proposed holdout scenarios file below.
