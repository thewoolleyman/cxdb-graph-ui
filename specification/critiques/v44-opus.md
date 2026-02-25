# CXDB Graph UI Spec — Critique v44 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-25

## Prior Context

The v43 round applied four spec changes: (1) `StageFinished` rendering now includes `notes` and `suggested_next_ids`, (2) `StageRetrying` rendering now includes `delay_ms`, (3) Section 3.3 now documents 404 behavior for unmatched routes, and (4) all pseudocode turn_id comparisons now use the explicit `numericTurnId()` helper. Two holdout scenarios were deferred (StageFailed retry sequence and DOT comment stripping safety).

---

## Issue #1: `InterviewStarted` rendering drops `question_type`, losing the gate mode distinction operators need

### The problem

Section 7.2's per-type rendering table renders `InterviewStarted` as: Output = `data.question_text`, Tool = blank, Error = blank. This drops the `question_type` field, which is documented in Section 5.4's turn type table and always emitted by Kilroy's `cxdbInterviewStarted` (`cxdb_events.go` line 283):

```go
"question_type": questionType,
```

The `question_type` field distinguishes between gate modes (e.g., `"multiple_choice"`, `"free_text"`, `"yes_no"`). For an operator monitoring a pipeline waiting at a human gate, knowing whether the gate expects a free-text answer or a selection from predefined choices is operationally relevant — it determines what kind of response is needed and how urgently the operator should act (a `"yes_no"` gate can be answered immediately; a `"free_text"` gate may require investigation).

Similarly, `InterviewCompleted` emits `duration_ms` alongside `answer_value` (`cxdb_events.go` line 296), but the rendering only shows `data.answer_value`. The duration tells the operator how long the pipeline was blocked waiting for human input — useful for identifying bottlenecks in human-in-the-loop workflows.

### Suggestion

Update the `InterviewStarted` row in the per-type rendering table to:

> `InterviewStarted` | `data.question_text` + (if `data.question_type` is non-empty: " [{`data.question_type`}]") | blank | blank

Update the `InterviewCompleted` row to:

> `InterviewCompleted` | `data.answer_value` + (if `data.duration_ms` is present and > 0: " (waited {formatted_duration})") | blank | blank

Where `formatted_duration` uses the same millisecond-to-human-readable conversion as `StageRetrying`. This is a minor enhancement, not a correctness issue.

## Issue #2: Section 5.4's `ParallelBranchCompleted` field list is incomplete relative to Kilroy source

### The problem

Section 5.4's turn type table documents `ParallelBranchCompleted` with key data fields: `node_id`, `branch_key`, `status`. However, Kilroy's `cxdbParallelBranchCompleted` (`cxdb_events.go` lines 247-255) emits five fields beyond `run_id` and `timestamp_ms`:

```go
"branch_key":   branchKey,
"branch_index": branchIndex,
"status":       status,
"duration_ms":  durationMS,
```

The `branch_index` and `duration_ms` fields are omitted from the table. While `ParallelBranchCompleted` falls through to the "Other/unknown" rendering row and is not high-priority, the turn type table is described as the canonical reference for field inventory. An implementer cross-referencing the spec against CXDB raw turn data would see unexpected fields.

The same issue exists for `ParallelBranchStarted` (table lists `node_id, branch_key, branch_index` but the source also emits `run_id` and `timestamp_ms` — though these meta-fields may be intentionally excluded as they appear on all turn types) and `ParallelCompleted` (table lists `node_id, success_count, failure_count` but the source also emits `duration_ms`).

### Suggestion

Update Section 5.4's turn type table to include the missing fields:

- `ParallelBranchCompleted`: `node_id`, `branch_key`, `branch_index`, `status`, `duration_ms`
- `ParallelCompleted`: `node_id`, `success_count`, `failure_count`, `duration_ms`

These additions are documentation-only — they do not change the UI's behavior since these types fall through to "Other/unknown."

## Issue #3: No holdout scenario verifies that `StageFinished` with `status: "fail"` produces a red (error) node, not green (complete)

### The problem

Section 6.2 documents a critical branch in the status derivation: `StageFinished` with `data.status == "fail"` sets the node to "error" (red), while all other status values set it to "complete" (green). This is the only turn type where the `data.status` field's value changes the visual outcome.

The existing holdout scenarios test:
- "Pipeline completed successfully" — all nodes green (success case)
- "Pipeline completed — last node marked complete via StageFinished" — final node green (success case)
- "Agent stuck in error loop" — error via heuristic, not `StageFinished`

None explicitly test the `StageFinished(status: "fail")` → red path. An implementer could handle all `StageFinished` turns as "complete" (ignoring the `status` field check) and pass every existing holdout scenario. The spec's Definition of Done item says "StageFinished with status='fail' sets error, not complete" but this is not exercised by a holdout scenario.

### Suggestion

Add a holdout scenario:

```
### Scenario: Node with StageFinished status=fail shows as error, not complete
Given a pipeline run is active with the implement node running
  And CXDB contains a StageFinished turn for implement with status: "fail"
When the UI polls CXDB
Then the implement node is colored red (error), not green (complete)
  And hasLifecycleResolution is true for the implement node
  And the detail panel shows "Stage finished: fail" with the failure_reason
```

## Issue #4: `formatted_delay` conversion for `StageRetrying` is underspecified for sub-second and large values

### The problem

Section 7.2 specifies that `StageRetrying` renders `delay_ms` as a "human-readable duration" with examples: "1500 → '1.5s', 60000 → '60s'". But the conversion rules are not fully specified for edge cases:

- **Sub-second values** (e.g., `delay_ms: 250`): Should this display as "0.3s", "250ms", or "0s"?
- **Zero delay** (e.g., `delay_ms: 0`): The spec says "if `data.delay_ms` is present and > 0" — so zero is excluded. But what about `delay_ms: 1`? Should it show "0s" (rounding) or "1ms"?
- **Large values** (e.g., `delay_ms: 300000`): Should this display as "300s" or "5m"?

Kilroy's retry backoff (`engine.go`) uses delays ranging from a few hundred milliseconds to tens of seconds. Without clear formatting rules, two implementations could display the same delay differently.

### Suggestion

Add a brief formatting specification to Section 7.2 or a shared helper definition:

> `formatted_delay`: If `delay_ms >= 1000`, display as `{delay_ms / 1000}s` (one decimal place if not a whole number, e.g., 1500 → "1.5s", 2000 → "2s"). If `delay_ms < 1000`, display as `{delay_ms}ms` (e.g., 250 → "250ms"). Examples: 0 → excluded by guard, 1 → "1ms", 250 → "250ms", 1500 → "1.5s", 60000 → "60s".

This is a minor specificity issue, not a correctness problem.
