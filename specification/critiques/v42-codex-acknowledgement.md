# CXDB Graph UI Spec — Critique v42 (codex) Acknowledgement

Both issues from the v42 codex critique were evaluated. Issue #1 was deferred as a proposed holdout scenario. Issue #2 was applied to the specification with a clarifying note about the CXDB `node_id` matching assumption, verified against Kilroy source (`dot/parser.go`, `model/model.go`, `cxdb_events.go`).

## Issue #1: Holdout scenarios do not cover the CQL-empty supplemental discovery path

**Status: Applied to holdout scenarios**

A proposed holdout scenario "CQL-empty supplemental discovery populates status overlay and liveness" was written to `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`. The scenario tests the full end-to-end flow: CQL returns empty results, the supplemental context list discovers Kilroy contexts, status overlays update, and liveness checks work correctly (preventing false stale detection). This complements the existing proposed scenarios (v37-opus for discovery, v38-codex for liveness) by verifying the complete path from discovery through rendering.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added proposed scenario for CQL-empty supplemental discovery end-to-end

## Issue #2: CXDB `node_id` normalization rules are underspecified for generic pipelines

**Status: Applied to specification**

A new "CXDB `node_id` matching assumption" paragraph was added to Section 4.2, before the matching algorithm pseudocode. The paragraph explicitly documents that the UI assumes `turn.data.node_id` values from CXDB are already normalized and does not apply additional normalization before comparison. This assumption is verified against Kilroy source: Kilroy's DOT parser normalizes node IDs during parsing (`dot/parser.go`), stores them as `model.Node.ID` (`model/model.go`), and passes `node.ID` directly to CXDB event functions (`cxdb_events.go` — e.g., `"node_id": node.ID` at line 70). The paragraph notes that non-Kilroy pipelines emitting raw (un-normalized) DOT identifiers as CXDB `node_id` values would not match, and supporting such pipelines is out of scope for the initial implementation. This narrows the "Generic pipeline support" principle to clarify that while the UI supports generic DOT files (via server-side normalization), it requires CXDB `node_id` values to already be normalized.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "CXDB `node_id` matching assumption" paragraph to Section 4.2

## Not Addressed (Out of Scope)

- Issue #1 is deferred to the holdout scenario review process. The spec already documents the CQL-empty supplemental discovery path; the gap is in holdout scenario coverage.
