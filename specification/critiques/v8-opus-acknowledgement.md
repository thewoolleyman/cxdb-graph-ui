# CXDB Graph UI Spec — Critique v8 (opus) Acknowledgement

All 3 issues were valid and applied to the specification. Issue #1 was a correctness gap — the polling algorithm had no step to filter contexts by run_id, contradicting Section 5.5's "most recent run" rule. Issue #2 identified a data loss scenario during extended CXDB outages where lifecycle turns could be permanently skipped. Issue #3 fixed a stale-data bug where `lastTurnId` froze at its first-assigned value across poll cycles.

## Issue #1: Run ID filtering is missing from the polling algorithm

**Status: Applied to specification**

Added an explicit step 3 ("Determine active run per pipeline") to Section 6.1's polling algorithm, between discovery (step 2) and turn fetching (now step 4). The new step groups discovered contexts by `run_id` per pipeline, selects the active run by highest `created_at_unix_ms`, excludes old-run contexts from subsequent steps, and resets per-context status maps and `lastSeenTurnId` cursors when the active `run_id` changes. Updated step 4 to specify "active run" contexts only. Updated step 6's `mergeStatusMaps` call to clarify it operates on active-run contexts. Renumbered steps 4–7 accordingly.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 — added step 3 "Determine active run per pipeline"; renumbered steps 4–7; updated step 4 and step 6 to reference active-run filtering

## Issue #2: Extended CXDB outage creates an unrecoverable turn gap

**Status: Applied to specification**

Added a "Gap recovery" paragraph to Section 6.1 after the "Turn fetch limit" paragraph. When the oldest fetched turn has `turn_id > lastSeenTurnId + 1`, the poller issues additional paginated requests using `before_turn_id` to fill the gap. Recovery is bounded (one request per 100 missed turns) and runs at most once per context per poll cycle. Recovered turns are prepended to the batch before caching and status derivation.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 — added "Gap recovery" paragraph specifying gap detection and backward pagination to fill missed turns

## Issue #3: NodeStatus.lastTurnId never updates after initial assignment

**Status: Applied to specification**

Replaced the `IS null` guard in `updateContextStatusMap` with a numeric comparison: `lastTurnId` is now updated whenever `turn.turn_id > existingMap[nodeId].lastTurnId` (or when `lastTurnId IS null`). Updated the "lastTurnId assignment" explanatory paragraph to describe the new behavior — `lastTurnId` correctly advances across poll cycles as new turns with higher IDs are processed.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 pseudocode — changed `IF lastTurnId IS null` to `IF lastTurnId IS null OR turn.turn_id > existingMap[nodeId].lastTurnId`
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 "lastTurnId assignment" paragraph — rewritten to describe numeric comparison behavior across poll cycles

## Not Addressed (Out of Scope)

- None — all issues were addressed.
