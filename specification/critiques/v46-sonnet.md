# CXDB Graph UI Spec — Critique v46 (sonnet)

**Critic:** sonnet (claude-sonnet-4-6)
**Date:** 2026-02-25

## Prior Context

The v45 round was productive. Opus applied four changes: (1) `RunCompleted` key data fields table updated to include `final_git_commit_sha`, `cxdb_context_id`, `cxdb_head_turn_id`; (2) `RunFailed` updated to include `git_commit_sha`; (3) `StageFailed` rendering in Section 7.2 now includes `attempt` number; (4) `RunFailed` `node_id` empty-string edge case documented in Sections 6.2 and 7.2. Codex raised two holdout-scenario gaps (CQL-empty supplemental discovery, subgraph nodes/edges) — both deferred to the proposed scenarios file.

---

## Issue #1: `GitCheckpoint` turn has an undocumented `status` field in Section 5.4

### The problem

The spec's Section 5.4 turn type table lists `GitCheckpoint` with key data fields: `node_id`, `git_commit_sha`. However, the actual Kilroy source (`cxdb_events.go`, `cxdbCheckpointSaved` function) emits three fields beyond `run_id` and `timestamp_ms`:

```go
_, _, _ = e.CXDB.Append(ctx, "com.kilroy.attractor.GitCheckpoint", 1, map[string]any{
    "run_id":         e.Options.RunID,
    "node_id":        nodeID,
    "status":         string(status),  // <-- not in spec's key data fields
    "git_commit_sha": sha,
    "timestamp_ms":   nowMS(),
})
```

The `status` field records the `StageStatus` (e.g., `"success"`, `"fail"`, `"retry"`) at the time the git checkpoint was made. This follows the same `StageStatus` value set as `StageFinished.status`. An implementer reading the spec table would not know this field exists.

While `GitCheckpoint` is listed as "low-value" and falls through to "Other/unknown" in the detail panel (Section 7.2), the pattern established by v45 is to keep the key data fields column accurate. Operators examining raw turn data in CXDB would see a `status` field with no documentation.

### Suggestion

Update the Section 5.4 `GitCheckpoint` row's key data fields to: `node_id`, `git_commit_sha`, `status`. Add a note that `status` uses the same `StageStatus` value set as `StageFinished.status` and records the stage status at checkpoint time. This is a documentation precision issue consistent with the v45-opus Issue #1 fix pattern.

---

## Issue #2: `ToolCall` and `ToolResult` turns have an undocumented `call_id` field in Section 5.4

### The problem

The spec's Section 5.4 turn type table lists `ToolCall` with key data fields: `node_id` (optional), `tool_name`, `arguments_json`. However, all three call paths that emit `ToolCall` turns include a `call_id` field:

1. **CLI stream path** (`cli_stream_cxdb.go` line 65): `"call_id": call.ID`
2. **Tool gate path** (`handlers.go` line 545): `"call_id": callID`
3. **Codergen router path** (`codergen_router.go` line 1818): `"call_id": callID`

Similarly, `ToolResult` turns include `call_id` on all three paths (`cli_stream_cxdb.go` line 86, `handlers.go` line 635, `codergen_router.go` line 1835).

The `call_id` field links a `ToolCall` turn to its corresponding `ToolResult` turn — it is the correlation ID for the tool invocation round-trip. For the CLI stream path, `call_id` is the Anthropic tool_use ID (e.g., `"toolu_abc"`). For the tool gate path, it is a ULID generated at the time of the call (`ulid.Make().String()`). Without this field documented, operators examining raw turn data and implementers building detail panel logic do not know it exists.

The current detail panel rendering (Section 7.2) does not display `call_id` and does not require it. However, the field is consistently present in all real-world Kilroy `ToolCall` and `ToolResult` turns, and its absence from the spec's key data fields creates a misleading picture of the turn structure.

### Suggestion

Update the Section 5.4 `ToolCall` row's key data fields to: `node_id` (optional), `tool_name`, `arguments_json`, `call_id`. Update the `ToolResult` row to: `node_id` (optional), `tool_name`, `output`, `is_error`, `call_id`. Add a note that `call_id` correlates a `ToolCall` with its `ToolResult` (same ID appears in both); it is an Anthropic tool_use ID for LLM-driven tool calls and a ULID for tool gate invocations. This field is not rendered by the detail panel but is present in all real-world turns.

---

## Issue #3: `ParallelStarted` turn has undocumented `join_policy` and `error_policy` fields in Section 5.4

### The problem

The spec's Section 5.4 turn type table lists `ParallelStarted` with key data fields: `node_id`, `branch_count`. However, the actual `cxdbParallelStarted` function emits two additional fields:

```go
_, _, _ = e.CXDB.Append(ctx, "com.kilroy.attractor.ParallelStarted", 1, map[string]any{
    "run_id":       e.Options.RunID,
    "node_id":      nodeID,
    "timestamp_ms": nowMS(),
    "branch_count": branchCount,
    "join_policy":  joinPolicy,   // <-- not in spec
    "error_policy": errorPolicy,  // <-- not in spec
})
```

The `join_policy` and `error_policy` fields describe how the parallel fan-out is configured: whether all branches must complete, what happens when branches fail, etc. These are operationally significant — an operator debugging a failing parallel node benefits from knowing the join and error policies that govern it.

The v45-opus acknowledgement corrected `ParallelBranchCompleted` and `ParallelCompleted` field inventories. `ParallelStarted` has the same gap.

### Suggestion

Update the Section 5.4 `ParallelStarted` row's key data fields to: `node_id`, `branch_count`, `join_policy`, `error_policy`. Add a brief note that `join_policy` and `error_policy` are string values from Kilroy's parallel handler configuration (their exact allowed values can be verified against Kilroy's `ParallelHandler` implementation). This matches the v45-opus pattern of completing field inventories for parallel turn types.

---

## Issue #4: No holdout scenario covers the human gate `InterviewStarted`/`InterviewCompleted`/`InterviewTimeout` turn sequence

### The problem

Section 7.2 specifies rendering for three interview turn types (`InterviewStarted`, `InterviewCompleted`, `InterviewTimeout`) and Section 5.4 documents their fields. These types are high-value for operator UX — the detail panel must show what question was posed, what answer was received, and how long the pipeline waited. The v44 round added `question_type` to `InterviewStarted` rendering and `duration_ms` to `InterviewCompleted` rendering.

The holdout scenarios include a "Click a human gate node" scenario (in the Detail Panel section) that verifies the panel shows the node type, question text from DOT attributes, and available choices from outgoing edges. But no holdout scenario verifies that CXDB `InterviewStarted`, `InterviewCompleted`, or `InterviewTimeout` turns are rendered correctly in the detail panel's CXDB Activity section (Section 7.2).

Specifically, no scenario tests:
- `InterviewStarted` renders `data.question_text` + `[{data.question_type}]` in the Output column
- `InterviewCompleted` renders `data.answer_value` + ` (waited {formatted_duration})` using `formatMilliseconds`
- `InterviewTimeout` renders `data.question_text` in Output with the Error column highlighted as "timeout"
- The distinction between `InterviewCompleted.answer_value` (the resolved CXDB data, e.g. `"approve"`) and the DOT `question` attribute (the question prompt)

An implementation could render bare `[unsupported turn type]` for all three and still pass the existing holdout scenarios.

### Suggestion

Add a holdout scenario for the human gate interview turn rendering:

```
### Scenario: Human gate interview turns render in detail panel
Given a pipeline run includes a human gate node (shape=hexagon, id="review_gate")
  And CXDB contains an InterviewStarted turn for review_gate:
    - question_text: "Approve the implementation?"
    - question_type: "SingleSelect"
  And CXDB contains an InterviewCompleted turn for review_gate:
    - answer_value: "YES"
    - duration_ms: 45000
When the user clicks the review_gate node
Then the detail panel's CXDB Activity section shows the InterviewStarted turn
  With Output: "Approve the implementation? [SingleSelect]"
  And the detail panel shows the InterviewCompleted turn
  With Output: "YES (waited 45s)"
```

And a separate scenario for timeout:

```
### Scenario: InterviewTimeout turn renders with error highlight
Given CXDB contains an InterviewTimeout turn for a human gate node:
    - question_text: "Confirm deployment?"
    - duration_ms: 300000
When the user clicks that node
Then the detail panel shows the InterviewTimeout turn
  With Output: "Confirm deployment?"
  And the Error column is highlighted with "timeout"
```

---

## Issue #5: `StageStarted` handler type rendering is not covered by any holdout scenario

### The problem

Section 7.2 specifies that `StageStarted` renders as "Stage started" + (if `data.handler_type` is non-empty: ": {`data.handler_type`}"). The spec notes that `handler_type` values like `"codergen"`, `"tool"`, `"wait.human"` come from Kilroy's `resolvedHandlerType` function. This is operationally significant for conditional nodes with `TypeOverride` that use a non-default handler.

No holdout scenario verifies the `StageStarted` rendering, particularly the handler_type display. An implementation could render `[unsupported turn type]` for `StageStarted` and pass all existing scenarios. Similarly, no scenario verifies the handler_type variation ("Stage started" vs. "Stage started: codergen" vs. "Stage started: tool").

### Suggestion

Add a holdout scenario:

```
### Scenario: StageStarted turn renders handler_type in detail panel
Given CXDB contains a StageStarted turn for an LLM task node with handler_type: "codergen"
When the user clicks that node
Then the detail panel shows the StageStarted turn
  With Output: "Stage started: codergen"
Given CXDB contains a StageStarted turn for a tool gate node with handler_type: "tool"
When the user clicks that node
Then the detail panel shows the StageStarted turn
  With Output: "Stage started: tool"
Given CXDB contains a StageStarted turn with handler_type: "" (empty)
When the user clicks that node
Then the detail panel shows the StageStarted turn
  With Output: "Stage started" (no colon suffix)
```

=== CRITIQUE SKILL COMPLETE ===
WARNING: If you are executing this skill as part of a loop (e.g., spec:critique-revise-loop), you are NOT done. Return to the loop protocol now and execute the next step. Check the loop's exit criteria before stopping.
=== END CRITIQUE SKILL ===
