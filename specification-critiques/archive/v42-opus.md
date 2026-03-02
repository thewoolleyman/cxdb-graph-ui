# CXDB Graph UI Spec — Critique v42 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-25

## Prior Context

The v41 round applied two spec changes: (1) Section 6.2's lifecycle turn precedence paragraph now documents custom routing values in `StageFinished.data.status`, and (2) Section 7.2 has a new paragraph about custom routing values in `StageFinished` detail panel rendering. Issue #3 (documenting `view`/`bytes_render` parameters) was correctly rejected as already present. Three proposed holdout scenarios were written (custom routing outcomes, quoted graph IDs, quoted node IDs). The codex issues about holdout normalization gaps were deferred.

---

## Issue #1: Comment-stripping specification omits unterminated-string error handling present in Kilroy's `stripComments`

### The problem

Section 3.2's comment handling paragraph specifies that "An unterminated block comment (`/*` with no matching `*/`) is a parse error" but does not mention the complementary error case: an unterminated string encountered during comment stripping. Kilroy's `stripComments` function (`kilroy/internal/attractor/dot/comments.go` lines 66-68) explicitly checks for this condition — if `inString` is still `true` after processing all input, it returns `fmt.Errorf("dot: unterminated string (while stripping comments)")`.

This matters because the comment stripping phase tracks quoted-string state to avoid treating `//` or `/*` inside strings as comment delimiters. If the input has an unbalanced `"` (e.g., `node_a [prompt="unterminated`), the string-tracking state machine ends in `inString == true`. Without explicit error handling for this case, an implementer might silently proceed with corrupted output — the comment stripper would have consumed the rest of the input as "inside a string," potentially swallowing node/edge definitions that follow the unterminated quote.

The spec already mentions that "the parser must track whether it is inside a quoted string (with escape handling for `\"` and `\\`)" but only specifies an error for unterminated block comments, not for unterminated strings. Since the comment-stripping phase runs before the main node/edge parser, catching the unterminated string here provides an earlier, more precise error than waiting for downstream parsing to fail in a confusing way.

### Suggestion

Amend the comment handling paragraph in Section 3.2 to add:

> An unterminated string (a `"` with no matching closing `"` before end of input) encountered during comment stripping is also a parse error. This matches Kilroy's `stripComments`, which returns an error for both unterminated block comments and unterminated strings.

## Issue #2: The spec does not document that `StageStarted` includes `handler_type` in the detail panel rendering, losing useful operator information

### The problem

Section 7.2's per-type rendering table shows `StageStarted` rendering as the fixed label "Stage started". However, the `StageStarted` turn carries a `handler_type` field (documented in Section 5.4's turn type table: `node_id`, `handler_type` (optional), `attempt` (optional)). The `handler_type` value comes from `resolvedHandlerType()` in Kilroy (`cxdb_events.go` line 72, `handlers.go` lines 174-182), which returns values like `"codergen"`, `"tool"`, `"conditional"`, `"wait.human"`, `"parallel"`, `"start"`, `"exit"`, `"parallel.fan_in"`, `"stack.manager_loop"`.

For an operator watching a pipeline, seeing "Stage started: codergen" or "Stage started: tool" is significantly more informative than just "Stage started", especially when multiple `StageStarted` turns appear in succession (e.g., after a retry). The `handler_type` tells the operator what kind of execution is beginning. This is particularly useful for conditional nodes that may have a `TypeOverride` causing them to use a different handler than their shape would suggest.

### Suggestion

Update the `StageStarted` row in the per-type rendering table from:

> `StageStarted` | "Stage started" (fixed label) | blank | blank

to:

> `StageStarted` | "Stage started" + (if `data.handler_type` is non-empty: ": {`data.handler_type`}") | blank | blank

This is a minor enhancement, not a correctness issue. The current "fixed label" rendering is functional but discards available information.

## Issue #3: No holdout scenario tests gap recovery with turn deduplication across the recovery boundary

### The problem

Section 6.2 describes gap recovery (fetching turns between `lastSeenTurnId` and the current window) and turn deduplication (skipping turns with `turn_id <= lastSeenTurnId`). The existing holdout scenario "Lifecycle turn missed during poll gap is recovered" tests that a `StageFinished` turn outside the 100-turn window is recovered. However, no holdout scenario verifies the deduplication behavior at the boundary — specifically, that turns already processed in the previous poll cycle are not double-counted after gap recovery prepends them to the batch.

The risk is an implementation that correctly fetches gap-recovery pages but fails to skip already-processed turns, inflating `turnCount` and `errorCount`. Because these are internal-only fields not displayed in the UI, the error would be silent — but it could cause the error loop heuristic to fire incorrectly if `errorCount` is used instead of the specified "3 consecutive recent ToolResult errors" check (an implementer might take a shortcut using the counter).

### Suggestion

Add a holdout scenario:

```
### Scenario: Gap recovery does not double-count already-processed turns
Given a pipeline run is active with the implement node running
  And the UI has polled successfully, processing turns up to turn_id 500
  And 150 new turns are appended (turn_ids 501-650)
When the UI polls CXDB on the next cycle
Then the initial fetch (limit=100) returns turns 551-650
  And gap recovery fetches turns 501-550 (back to lastSeenTurnId 500)
  And turns 1-500 are NOT re-processed (skipped by deduplication)
  And turnCount for the node reflects only newly processed turns (501-650)
```

## Issue #4: The `ToolHandler` in Kilroy emits `ToolCall` and `ToolResult` turns with `tool_name: "shell"`, but the spec's detail panel does not clarify that tool gate nodes produce these same turn types as LLM task nodes

### The problem

An implementer reading the detail panel section (7.2) might assume that `ToolCall` and `ToolResult` turns are exclusive to LLM task (codergen) nodes, since the primary narrative describes them in the context of agent tool use. However, Kilroy's `ToolHandler` (`handlers.go` lines 536-549 and 621-652) also emits `ToolCall` and `ToolResult` turns for tool gate nodes (shape=parallelogram), with `tool_name: "shell"` and the command output/exit status.

This is not a spec error — the status derivation correctly handles these turns regardless of node type, and the detail panel rendering table covers `ToolCall` and `ToolResult` generically. But there is no mention that tool gate nodes produce the same turn types as LLM tasks. An implementer might be confused when a tool gate node's detail panel shows `ToolCall`/`ToolResult` rows instead of something tool-gate-specific, and might wonder if they have a bug in their node_id matching.

### Suggestion

Add a brief note to Section 7.2, perhaps near the per-type rendering table:

> **Tool gate turns.** Tool gate nodes (shape=parallelogram) produce `ToolCall` and `ToolResult` turns with `tool_name: "shell"`, the same turn types used by LLM task nodes. The `ToolCall.arguments_json` contains the shell command; the `ToolResult.output` contains stdout/stderr and `is_error` reflects the exit code. No special rendering is needed — the standard per-type rendering handles tool gate turns identically to LLM task tool turns.

This is a documentation clarification, not a functional issue.
