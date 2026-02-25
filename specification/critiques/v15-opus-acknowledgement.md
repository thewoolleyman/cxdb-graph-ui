# CXDB Graph UI Spec — Critique v15 (opus) Acknowledgement

All 3 issues were valid and applied to the specification. Issue #1 added a per-type field inventory to Section 5.4, documenting which types carry `node_id` and other key fields. Issue #2 corrected the `limit` parameter documentation from "1–65535" to "u32 with no server-enforced maximum" and removed the artificial 65535 cap in `fetchFirstTurn`. Issue #3 added stale pipeline detection using the `is_live` context field, introducing a new "stale" node status for crashed/dead pipelines. All claims were verified against the CXDB server source (`server/src/http/mod.rs`).

## Issue #1: Section 5.4 type table omits `run_id` from RunStarted and documents no per-type field inventory

**Status: Applied to specification**

Verified against CXDB source: the Kilroy turn types (RunStarted, StageStarted, etc.) are application-level types defined in the `kilroy-attractor-v1` registry bundle, not in the CXDB core. The field inventory was constructed from the spec's own usage patterns across Sections 5.3, 5.5, and 6.2.

Applied the suggested expansion:

1. **Section 5.4** — Replaced the two-column type table with a three-column table including "Key Data Fields." RunStarted now documents `graph_name`, `graph_dot`, `run_id`. All types with `node_id` are listed. GitCheckpoint notes `node_id` as conditional ("if present"). ParallelBranchCompleted documents `branch_key` (no `node_id`).

2. **Section 5.4** — Added explanatory paragraph after the table documenting: (a) which types carry `node_id` and are processed by the status derivation algorithm, (b) that types without `node_id` are silently skipped via the null guard, (c) that GitCheckpoint's ambiguity is handled by the null guard, and (d) that fields should be verified against the registry bundle for implementation.

3. **Section 5.5** — Added a cross-reference "(see Section 5.4 for the full field inventory)" where `run_id` is first mentioned on RunStarted.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 5.4 — expanded type table with Key Data Fields column, added field inventory explanation
- `specification/cxdb-graph-ui-spec.md`: Section 5.5 — added Section 5.4 cross-reference for RunStarted fields

## Issue #2: Turns endpoint `limit` range "1–65535" is not a server-enforced constraint

**Status: Applied to specification**

Verified against CXDB source: `server/src/http/mod.rs` lines 744–747 parse `limit` as `u32` with default 64 and no enforced maximum. The protocol layer (`server/src/protocol/mod.rs` line 75) also uses `u32`. The "65535" assumption was a u16 artifact with no basis in the server implementation.

Applied both suggested changes:

1. **Section 5.3** — Changed the `limit` parameter description from "Maximum number of turns to return (1–65535)" to "Maximum number of turns to return (parsed as u32; no server-enforced maximum). The UI uses at most 100 for polling and `headDepth + 1` for discovery."

2. **Section 5.5 `fetchFirstTurn`** — Changed `fetchLimit = min(headDepth + 1, 65535)` to `fetchLimit = headDepth + 1`. Updated the comment from "CXDB limit max is 65535" to "CXDB parses limit as u32 with no enforced maximum." Updated the prose after `fetchFirstTurn` to reflect that the first turn is always fetched in a single request regardless of context depth (the pagination loop is retained as a defensive measure but will not execute for single-request fetches).

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 5.3 — corrected `limit` parameter description
- `specification/cxdb-graph-ui-spec.md`: Section 5.5 — removed 65535 cap in `fetchFirstTurn`, updated comment and prose

## Issue #3: No detection of crashed/stale pipelines

**Status: Applied to specification**

Verified against CXDB source: `server/src/http/mod.rs` lines 1305–1331 confirm `is_live` is included in context list responses, computed as `session.is_some()` — `true` when an active session is connected, `false` when no session is writing to the context.

Applied the suggested stale detection mechanism across multiple sections:

1. **Section 5.2** — Updated `is_live` documentation from "unused by the UI" to "used for stale pipeline detection (see Section 6.2)."

2. **Section 6.1 step 3** — Added `checkPipelineLiveness` pseudocode after the `determineActiveRuns` block. The function checks whether ANY active-run context has `is_live == true`, returning a boolean pipeline liveness flag.

3. **Section 6.1 step 6** — Added `applyStaleDetection` to the processing chain (after `applyErrorHeuristic`).

4. **Section 6.2** — Added `applyStaleDetection` pseudocode and description after the error heuristic section. When `pipelineIsLive` is false, all "running" nodes without lifecycle resolution are reclassified as "stale."

5. **Section 6.2 NodeStatus type** — Added `"stale"` to the status union type.

6. **Section 6.3** — Added `stale` row to the CSS status class table (`node-stale`, orange/amber fill, no animation) and added the `.node-stale` CSS rule with `fill: #ffcc80`.

7. **Section 8.2** — Added pipeline stall warning: when all active-run contexts have `is_live == false` and at least one node is "stale," the indicator shows "Pipeline stalled — no active sessions."

8. **Section 9 Invariant #6** — Updated the status mutual exclusivity invariant to include `stale`.

9. **Section 11 Definition of Done** — Added stale detection checklist items.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 5.2 — `is_live` now documented as used
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 — added `checkPipelineLiveness` pseudocode, updated step 6
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 — added `applyStaleDetection` pseudocode, updated NodeStatus type
- `specification/cxdb-graph-ui-spec.md`: Section 6.3 — added `stale` CSS class
- `specification/cxdb-graph-ui-spec.md`: Section 8.2 — added pipeline stall warning
- `specification/cxdb-graph-ui-spec.md`: Section 9 — updated invariant #6
- `specification/cxdb-graph-ui-spec.md`: Section 11 — added stale detection to Definition of Done

## Not Addressed (Out of Scope)

- **Holdout scenario for agent crash.** The critique suggested adding a holdout scenario. Holdout scenarios are maintained separately from the spec and are not modified during spec revisions. The scenario is valid and should be added to `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` as a follow-up.
