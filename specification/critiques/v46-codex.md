# CXDB Graph UI Spec — Critique v46 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-codex)
**Date:** 2026-02-25

## Prior Context

The v45 acknowledgement incorporated the RunCompleted and RunFailed field inventory updates, adjusted the StageFailed rendering to surface attempt numbers, softened the RunFailed `node_id` language, and added a MAX_GAP_PAGES cursor scenario to the proposed holdout list. No changes were applied to the primary holdout scenarios file.

---

## Issue #1: Holdout scenarios still omit the StageFailed retry and failure paths

### The problem
Sections 6.2 and 7.2 now rely on nuanced StageFailed handling: `StageFailed` with `will_retry == true` must leave the node in "running" without setting `hasLifecycleResolution`, while terminal StageFailed (or StageFinished with `status == "fail"`) must drive the node to "error". These behaviors are also codified in Invariant #5 and the Definition of Done checklist (“StageFailed with will_retry=true sets running, not error; StageFinished with status="fail" sets error, not complete”).

However, `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` still lacks any scenario that exercises either the retry flow (`StageFailed` → `StageRetrying` → `StageStarted`/`StageFinished`) or the terminal failure (`StageFinished { status: "fail" }` or `StageFailed { will_retry != true }`). The only references to these cases live in the "Proposed" staging file (entries from v35-opus and v44-opus), so the canonical acceptance suite does not actually verify the requirements that were just strengthened in the spec.

An implementation could regress (e.g., flagging `StageFailed` with `will_retry=true` as error, or treating `StageFinished` with status "fail" as success) and still pass every published holdout, directly contradicting the spec’s invariants and risking false operator signals.

### Suggestion
Promote the existing proposed scenarios into the main holdout document (or author equivalent new ones) so the official acceptance suite covers both:
- The retry sequence (`StageFailed` with `will_retry=true`, followed by `StageRetrying`/`StageStarted`, ultimately resolving via `StageFinished`)
- The terminal failure case (`StageFinished` with `status="fail"` and/or `StageFailed` with `will_retry != true`)

This locks the newly documented lifecycle rules into the regression suite and prevents future implementations from drifting.

## Issue #2: No canonical holdout validates RunFailed status handling

### The problem
Section 6.2 explicitly treats `RunFailed` turns as authoritative lifecycle events that must set the affected node to "error" and mark `hasLifecycleResolution = true`. Section 7.2 and the Definition of Done likewise expect the detail panel to surface the failure reason when `RunFailed` includes a `node_id`. Despite this, the published holdout scenarios never cover a pipeline that terminates via `RunFailed`.

The only mention appears in `holdout-scenarios/proposed-holdout-scenarios-to-review.md` (v39-opus entry). Because the canonical holdout file omits this case, an implementation could accidentally ignore `RunFailed` (leaving the node blue or pending) without failing acceptance. That undermines the spec’s guarantee that catastrophic pipeline failures are surfaced correctly.

### Suggestion
Add a RunFailed-focused scenario to `cxdb-graph-ui-holdout-scenarios.md`, ensuring the acceptance suite asserts:
- A `RunFailed` turn with `node_id` promotes the node to red/error and sets `hasLifecycleResolution`
- The detail panel shows the failure reason for that node

Promoting the existing proposed scenario would satisfy this requirement and keep the regression suite aligned with the spec.
