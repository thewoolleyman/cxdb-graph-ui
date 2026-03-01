# CXDB Graph UI Spec — Critique v40 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-25

## Prior Context

The v39 opus acknowledgement reports that the spec now includes the expanded 10-shape mapping (plus default), CSS coverage notes, and RunFailed handling in status derivation. A RunFailed holdout scenario was drafted in `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` but not added to the main holdout scenarios file.

---

## Issue #1: Holdout scenarios still test only the original six shapes

### The problem
Section 7.3 now documents ten shapes plus a default mapping, and Section 6.3 explicitly states the CSS selectors cover all ten. However, the holdout scenarios file still lists only the original six shapes in both:

- "Nodes rendered with correct shapes"
- "Status coloring applies to all node shapes"

An implementation could pass the holdouts while ignoring `circle`, `doublecircle`, `component`, `tripleoctagon`, and `house`, leaving the expanded spec untested.

### Suggestion
Update the two shape-related holdout scenarios to include the full ten-shape set (or explicitly reference the Section 7.3 mapping table). Ensure the scenarios call out the alternate start/exit shapes (`circle`, `doublecircle`) and the parallel/fan-in/stack shapes.

## Issue #2: Definition of Done still lists only six shapes

### The problem
The Definition of Done checklist item "All node shapes render correctly" still enumerates only six shapes. This now conflicts with the expanded shape vocabulary in Section 7.3 and the CSS coverage note in Section 6.3. A reader using the DoD as the acceptance gate could stop short of implementing or validating the additional five shapes.

### Suggestion
Update the Definition of Done shape checklist to match the ten shapes (plus default handling), or reference Section 7.3 directly to avoid future drift.

## Issue #3: The RunFailed-with-node_id case is still absent from the official holdout scenarios

### The problem
The spec now treats `RunFailed` with `node_id` as a lifecycle resolution that sets the node to error and surfaces the reason in the detail panel. The only test coverage is a proposed scenario in `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`, not the primary holdout scenarios file. This leaves a gap between the status derivation logic and the official behavioral tests.

### Suggestion
Promote the proposed "RunFailed with node_id" scenario into `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`, including the detail-panel reason display, so implementations are forced to cover this lifecycle path.
