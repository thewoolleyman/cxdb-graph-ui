# CXDB Graph UI Spec — Critique v45 (codex) Acknowledgement

Both issues from the v45 codex critique were evaluated. Both propose holdout scenario additions for existing spec requirements. Issue #1 is substantially covered by an existing proposed scenario; Issue #2 is a new gap and was written as a proposed holdout scenario.

## Issue #1: Holdout scenarios do not verify the CQL-empty supplemental discovery path

**Status: Deferred — covered by existing proposed scenario (v42-codex)**

The spec already documents the supplemental context list fetch in Section 5.5 (`discoverPipelines` pseudocode: when CQL returns zero results, the supplemental `fetchContexts` is issued and `kilroy/`-prefixed contexts are added). The gap is in holdout scenario coverage. However, a very similar end-to-end scenario already exists in `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` from v42-codex: "CQL-empty supplemental discovery populates status overlay and liveness." That scenario covers the full path — CQL empty → supplemental fetch → pipeline discovery → status overlay → liveness check — which is a superset of what the v45-codex scenario requests. Adding a duplicate scenario would create redundancy without adding coverage value. The v42-codex scenario should be incorporated into the holdout scenarios document as-is.

Changes:
- None (covered by existing proposed scenario)

## Issue #2: Holdout scenarios do not cover nodes and edges inside subgraphs

**Status: Applied to holdout scenarios**

The spec already requires that nodes and edges inside `subgraph` blocks be included in `/dots/{name}/nodes` and `/dots/{name}/edges` (Section 3.2). The gap is in holdout scenario coverage. A proposed holdout scenario "Nodes and edges inside subgraphs are included in /nodes and /edges responses" was written to `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`. The scenario verifies that a DOT file with `subgraph cluster_a { a [shape=box] }` produces the correct nodes and edges in the API responses.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added proposed scenario for subgraph-scoped nodes and edges

## Not Addressed (Out of Scope)

- Both issues are deferred to the holdout scenario review process. The spec already documents the required behaviors; the gaps are in holdout scenario coverage only.
