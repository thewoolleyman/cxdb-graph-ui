# CXDB Graph UI Spec — Critique v44 (codex) Acknowledgement

Both issues from the v44 codex critique were evaluated. Both propose holdout scenario additions for existing spec requirements and were deferred as proposed holdout scenarios.

## Issue #1: Holdout scenarios do not cover anonymous graph rejection at server startup

**Status: Deferred — proposed holdout scenario written**

The spec already requires anonymous graph rejection in Section 3.2 (the graph ID regex does not match anonymous graphs, and the server exits with a non-zero code when the regex fails to match). The gap is in holdout scenario coverage, not in the spec itself. A proposed holdout scenario "Anonymous graph rejected at server startup" was written to `holdout-scenarios/proposed-holdout-scenarios-to-review.md`, covering the startup failure path when a DOT file contains `digraph {` with no graph identifier.

Changes:
- `holdout-scenarios/proposed-holdout-scenarios-to-review.md`: Added proposed scenario for anonymous graph rejection

## Issue #2: Holdout scenarios do not test DOT attribute concatenation or multiline quoted strings

**Status: Deferred — proposed holdout scenario written**

The spec already documents `+` concatenation and multi-line quoted string parsing rules in Section 3.2 (under "String concatenation" and "Multi-line quoted values"). The gap is in holdout scenario coverage. A proposed holdout scenario "DOT attribute concatenation and multiline quoted values" was written to `holdout-scenarios/proposed-holdout-scenarios-to-review.md`, covering both the `+` concatenation operator and literal newlines inside quoted attribute values.

Changes:
- `holdout-scenarios/proposed-holdout-scenarios-to-review.md`: Added proposed scenario for DOT attribute concatenation and multiline quoted values

## Not Addressed (Out of Scope)

- Both issues are deferred to the holdout scenario review process. The spec already documents the required parsing rules and startup validation; the gaps are in holdout scenario coverage only.
