# CXDB Graph UI Spec — Critique v35 (codex) Acknowledgement

The single issue from the v35 codex critique was evaluated and applied to the specification.

## Issue #1: Initial pipeline never fetches /edges, so human gate choices are missing until a tab switch

**Status: Applied to specification**

Updated the initialization sequence (Section 4.5, Step 4) to prefetch both `/dots/{name}/nodes` AND `/dots/{name}/edges` for all pipelines during initialization. Previously, Step 4 only prefetched `/nodes`. The `/edges` prefetch ensures that human gate choices (derived from outgoing edge labels — Section 7.1) are available for the initially rendered pipeline without requiring a tab switch. Added corresponding error handling: if any `/edges` prefetch fails, the browser logs a warning and proceeds with an empty edge list for that pipeline, mirroring the existing `/nodes` error handling policy.

Also updated the Step 4 heading from "Prefetch node IDs for all pipelines" to "Prefetch node IDs and edges for all pipelines" and updated the dependency description to note that both `/nodes` and `/edges` for each pipeline can be fetched concurrently.

A proposed holdout scenario verifying that human gate choices appear on the first pipeline without a tab switch has been written to `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 4.5 Step 4 to prefetch `/edges` alongside `/nodes` for all pipelines
- `specification/cxdb-graph-ui-spec.md`: Updated Step 4 heading and dependency description
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added proposed holdout scenario for human gate choices on first pipeline

## Not Addressed (Out of Scope)

- None. The issue was fully addressed.
