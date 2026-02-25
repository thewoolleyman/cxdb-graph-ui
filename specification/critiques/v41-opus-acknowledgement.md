# CXDB Graph UI Spec — Critique v41 (opus) Acknowledgement

All four issues from the v41 opus critique were evaluated. Issues #1 and #2 were applied to the specification, informed by verification against Kilroy's `runtime/status.go` source (`ParseStageStatus`, `IsCanonical`, and `custom_outcome_routing_test.go`). Issue #3 was not addressed because the `view` and `bytes_render` parameters are already documented. Issue #4 was deferred as a proposed holdout scenario.

## Issue #1: StageFinished.data.status can contain custom routing values beyond the five canonical statuses

**Status: Applied to specification**

The lifecycle turn precedence paragraph in Section 6.2 was updated to explicitly document custom routing values. The previous text stated the status field values as a closed set of five canonical values. The new text explains that the `status` field has five canonical values and may also contain custom routing values (e.g., `"process"`, `"done"`, `"port"`, `"needs_dod"`) used for multi-way conditional branching, referencing `ParseStageStatus` in `runtime/status.go` lines 31-39 and `custom_outcome_routing_test.go`. The text now explicitly states: "The UI must not assume a closed set of status values — the `status == 'fail'` check is the only branch that matters."

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 6.2 lifecycle turn precedence paragraph to document custom routing values in StageFinished.data.status

## Issue #2: StageFinished detail panel rendering does not account for custom routing status values

**Status: Applied to specification**

A new "Custom routing values in `StageFinished`" paragraph was added to Section 7.2, before the existing "Pipeline-level turns without `node_id`" paragraph. The note explains that for conditional nodes using custom routing outcomes, `data.status` and `data.preferred_label` may contain the same value, and the rendering displays both as-is with no deduplication applied. An example is provided: a conditional node with `status: "process"` and `preferred_label: "process"` displays as "Stage finished: process — process".

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "Custom routing values in `StageFinished`" paragraph to Section 7.2

## Issue #3: The spec does not document the `view` query parameter for the turns endpoint

**Status: Not addressed**

The `view` and `bytes_render` query parameters are already documented in Section 5.3's query parameters table. The `view` row reads: `view | typed | Response format: typed (decoded JSON), raw (msgpack), or both`. The `bytes_render` row reads: `bytes_render | base64 | Raw payload encoding when view=raw or view=both: base64 (response field: bytes_b64), hex (response field: bytes_hex), or len_only (response field: bytes_len, no payload data). The UI uses the default (base64) and accesses bytes_b64. This parameter has no effect when view=typed.` The critique appears to have been based on an earlier version of the spec that lacked these rows, but they were already present at the time of critique.

## Issue #4: Holdout scenarios do not test custom routing outcomes in StageFinished

**Status: Deferred — proposed holdout scenario written**

A proposed holdout scenario "Conditional node with custom routing outcome shows as complete" was written to `holdout-scenarios/proposed-holdout-scenarios-to-review.md`. The scenario tests that a `StageFinished` turn with a custom status value (e.g., `"process"`) correctly results in a "complete" (green) node rather than an error, and that the detail panel renders both `data.status` and `data.preferred_label` without deduplication.

Changes:
- `holdout-scenarios/proposed-holdout-scenarios-to-review.md`: Added proposed scenario for custom routing outcomes in StageFinished

## Not Addressed (Out of Scope)

- Issue #3 is not addressed because the `view` and `bytes_render` parameters are already documented in Section 5.3.
