# CXDB Graph UI Spec — Critique v16 (codex) Acknowledgement

Both issues were valid and applied. Issue #1 added an explicit startup check rejecting duplicate DOT basenames, with a corresponding holdout scenario. Issue #2 added the missing stale pipeline holdout scenario that was deferred from v15.

## Issue #1: Duplicate DOT basenames are undefined and can silently collide

**Status: Applied to specification**

Added an explicit startup validation rule in Section 3.2 under the `GET /dots/{name}` route: if two `--dot` flags resolve to the same base filename, the server exits with a non-zero code and prints an error identifying the conflicting paths. This prevents silent collisions where one pipeline becomes unreachable or mislabeled.

Also added a holdout scenario ("Duplicate DOT basenames rejected") to the Server section of the holdout scenarios file to make this behavior testable.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 3.2 — added duplicate basename rejection rule to the DOT file map description
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: added "Duplicate DOT basenames rejected" scenario

## Issue #2: Holdout scenarios do not cover the new stale pipeline detection path

**Status: Applied to holdout scenarios**

Added the suggested holdout scenario ("Pipeline stalled after agent crash") to the CXDB Status Overlay section of the holdout scenarios file. The scenario covers: active pipeline with a running node, all active-run contexts transitioning to `is_live: false`, the running node being marked stale (orange), and the top bar showing the stall warning. This was a follow-up from the v15 acknowledgement that had been deferred.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: added "Pipeline stalled after agent crash" scenario to CXDB Status Overlay section

## Not Addressed (Out of Scope)

- None. All issues were addressed.
