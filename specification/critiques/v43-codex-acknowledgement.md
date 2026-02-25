# CXDB Graph UI Spec — Critique v43 (codex) Acknowledgement

Both issues from the v43 codex critique were evaluated. Issue #1 was applied to the specification by making all pseudocode turn_id comparisons explicitly numeric. Issue #2 was deferred as a proposed holdout scenario.

## Issue #1: Turn ID numeric comparison rule is contradicted by multiple pseudocode snippets

**Status: Applied to specification**

The pseudocode in Sections 6.1 (gap recovery) and 6.2 (`updateContextStatusMap`, error heuristic helper) was updated to use an explicit `numericTurnId(id)` helper at every turn_id comparison site, replacing bare `>` and `<=` operators on raw string IDs. The "Turn ID comparison" note in Section 6.2 was expanded to define `numericTurnId(id)` as equivalent to `parseInt(id, 10)` and to enumerate all pseudocode locations that must use numeric comparison: gap recovery detection, gap recovery loop, `updateContextStatusMap` (cursor computation, deduplication check, `lastTurnId` update), `getMostRecentToolResultsForNodeInContext` sorting, and the detail panel's within-context sorting. This eliminates the ambiguity where an implementer following the pseudocode literally could use lexicographic comparison, especially at digit-boundary crossings (e.g., turn_id 999 vs 1000).

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 6.1 gap recovery pseudocode to use `numericTurnId()` at both comparison sites
- `specification/cxdb-graph-ui-spec.md`: Updated Section 6.2 `updateContextStatusMap` pseudocode to use `numericTurnId()` at three comparison sites (cursor computation, deduplication, lastTurnId update)
- `specification/cxdb-graph-ui-spec.md`: Updated Section 6.2 error heuristic helper description to use `numericTurnId()` for sorting
- `specification/cxdb-graph-ui-spec.md`: Expanded "Turn ID comparison" note to define `numericTurnId()` helper and enumerate all affected locations

## Issue #2: Holdout scenarios do not cover DOT comment stripping and quoted-comment safety

**Status: Deferred — proposed holdout scenario written**

A proposed holdout scenario "DOT comment stripping preserves quoted-string content and rejects unterminated constructs" was written to `holdout-scenarios/proposed-holdout-scenarios-to-review.md`. The scenario includes three sub-scenarios: (1) a node prompt containing `//` inside a quoted string is preserved while standalone comments are stripped, (2) an unterminated block comment returns 400, and (3) an unterminated quoted string returns 400. This complements the existing v40-opus proposed scenario (basic comment stripping) by explicitly testing the error paths for unterminated constructs, which are the most failure-prone parsing paths.

Changes:
- `holdout-scenarios/proposed-holdout-scenarios-to-review.md`: Added proposed scenarios for DOT comment stripping safety and unterminated construct errors

## Not Addressed (Out of Scope)

- Issue #2 is deferred to the holdout scenario review process. The spec already documents comment-stripping rules including unterminated-construct errors (Section 3.2); the gap is in holdout scenario coverage.
