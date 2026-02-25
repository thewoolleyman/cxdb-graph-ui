# CXDB Graph UI Spec — Critique v40 (codex) Acknowledgement

All three issues from the v40 codex critique were evaluated. Issues #2 and #3 were applied to the specification. Issue #1 was deferred as a proposed holdout scenario update, since the extended shape scenarios already exist in the proposed holdout scenarios file from v39.

## Issue #1: Holdout scenarios still test only the original six shapes

**Status: Applied to holdout scenarios**

The v39-opus acknowledgement already wrote proposed holdout scenarios covering all ten shapes (both "Nodes rendered with correct shapes — extended" and "Status coloring applies to all node shapes — extended") to `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`. These proposed scenarios include `circle`, `doublecircle`, `component`, `tripleoctagon`, and `house`. The proposed scenarios are awaiting promotion to the main holdout scenarios file. No additional spec change is needed — the proposed scenarios already address the gap.

## Issue #2: Definition of Done still lists only six shapes

**Status: Applied to specification**

The Definition of Done checklist item was updated to list all ten Kilroy node shapes plus a reference to Section 7.3 for the full mapping. The updated entry reads: "All node shapes render correctly (Mdiamond, Msquare, box, diamond, parallelogram, hexagon, circle, doublecircle, component, tripleoctagon, house — see Section 7.3 for the full shape-to-type mapping)".

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 11 Definition of Done shape checklist to include all 10 shapes with Section 7.3 reference

## Issue #3: The RunFailed-with-node_id case is still absent from the official holdout scenarios

**Status: Applied to holdout scenarios**

The v39-opus acknowledgement already wrote a proposed holdout scenario "Pipeline run fails on a specific node (RunFailed with node_id)" to `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`. This proposed scenario tests that a `RunFailed` turn with `node_id` marks the node as red (error) with `hasLifecycleResolution = true`, and that the detail panel shows the failure reason. Promotion of proposed scenarios to the main holdout scenarios file is a separate review step, not a spec revision action.

## Not Addressed (Out of Scope)

- Issue #1 and #3 are deferred to the holdout scenario review process. The proposed scenarios already exist and are awaiting promotion.
