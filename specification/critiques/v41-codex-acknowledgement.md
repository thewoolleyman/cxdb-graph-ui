# CXDB Graph UI Spec — Critique v41 (codex) Acknowledgement

Both issues from the v41 codex critique were evaluated. Both identify holdout scenario gaps for normalization edge cases that are already specified in the spec but lack explicit test coverage. Both were deferred as proposed holdout scenarios.

## Issue #1: Holdout scenarios do not cover quoted/escaped graph IDs and discovery normalization

**Status: Applied to holdout scenarios**

A proposed holdout scenario "Quoted graph ID with escapes normalizes for tab label and pipeline discovery" was written to `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`. The scenario tests that a DOT file with a quoted, escaped graph ID (e.g., `digraph "my \"quoted\" pipeline" {`) correctly normalizes the ID for tab labels, pipeline discovery matching against `RunStarted.graph_name`, and duplicate graph ID rejection. The spec already documents the normalization rules in Sections 3.2 and 4.4 (strip outer quotes, resolve `\"` to `"` and `\\` to `\`, trim whitespace), so no spec change is needed — only holdout scenario coverage is missing.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added proposed scenario for quoted/escaped graph ID normalization

## Issue #2: Holdout scenarios do not cover quoted node IDs and /nodes + /edges normalization

**Status: Applied to holdout scenarios**

A proposed holdout scenario "Quoted node IDs normalize correctly for /nodes, /edges, status overlay, and detail panel" was written to `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`. The scenario tests that a DOT file with a quoted node ID (e.g., `"review step" [shape=box]`) correctly normalizes the ID for `/nodes` keys, `/edges` source/target values, SVG `<title>` matching, status overlay application, and detail panel lookup. The spec already documents the normalization rules in Section 3.2 and their scope limitation (Kilroy-generated DOT files use only unquoted, alphanumeric node IDs), so no spec change is needed — only holdout scenario coverage is missing.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added proposed scenario for quoted node ID normalization

## Not Addressed (Out of Scope)

- Both issues are deferred to the holdout scenario review process. The spec already documents the normalization rules; the gap is in holdout scenario coverage, not in the specification itself.
