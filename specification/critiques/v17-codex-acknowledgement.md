# CXDB Graph UI Spec — Critique v17 (codex) Acknowledgement

Both issues were valid and applied. Issue #1 added a `GET /dots/{name}/edges` server endpoint as the concrete data source for edge labels, and referenced it from the detail panel's human gate "Choices" field. Issue #2 added a holdout scenario for the non-200 turn fetch error handling path.

## Issue #1: Human gate "choices" are specified but no source for outgoing edge labels is defined

**Status: Applied to specification**

Added a new server route `GET /dots/{name}/edges` in Section 3.2 that returns a JSON array of edges with `source`, `target`, and `label` fields parsed from the DOT source. Added a "Choices" row to the Section 7.1 detail panel attributes table that references this endpoint: for human gate nodes, choices are the labels of outgoing edges whose `source` matches the node's ID. Also added the endpoint to the Definition of Done checklist.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 3.2 — added `GET /dots/{name}/edges` route with JSON response format and parsing rules
- `specification/cxdb-graph-ui-spec.md`: Section 7.1 — added "Choices" field to detail panel attributes table referencing the edges endpoint
- `specification/cxdb-graph-ui-spec.md`: Section 11 — added `GET /dots/{name}/edges` to Definition of Done checklist

## Issue #2: Polling error handling for failed turn fetches is untested in holdout scenarios

**Status: Applied to holdout scenarios**

Added the suggested holdout scenario ("Turn fetch fails for one context") to the CXDB Connection Handling section of the holdout scenarios file. The scenario covers: a pipeline run active across multiple contexts, one context returning a non-200 response, the failing context being skipped for that poll cycle with its last known status preserved, and other contexts continuing to update normally.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: added "Turn fetch fails for one context" scenario to CXDB Connection Handling section

## Not Addressed (Out of Scope)

- None. All issues were addressed.
