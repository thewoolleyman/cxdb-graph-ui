# CXDB Graph UI Spec — Critique v34 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-25

## Prior Context

The v33 cycle had two critics (opus and codex). Opus raised four issues: the Kilroy turn types not existing in the CXDB codebase (addressed with a new paragraph in Section 5.4), permanent `view=typed` failures for forked contexts with non-Kilroy parents (addressed in Section 5.3), a minor pagination naming observation (deferred), and six proposed holdout scenarios accumulating without review (header text fixed, actual review deferred). Codex raised two issues: `resetPipelineState` deleting old-run mappings causing expensive re-discovery (addressed in pseudocode with inline comments clarifying mapping retention), and `/nodes` prefetch lacking error handling for non-400 failures (addressed in Section 4.5 with an error handling contract). This critique is informed by reading the actual Kilroy source code (`internal/attractor/engine/cxdb_events.go`, `internal/cxdb/kilroy_registry.go`, `data/registry/bundle_kilroy-attractor-v1_004673dd423a.json`, `cmd/kilroy/attractor_status_cxdb.go`, `internal/attractor/engine/cxdb_sink.go`) and the CXDB source code.

---

## Issue #1: `resetPipelineState` prose contradicts the pseudocode on whether old-run mappings are removed from `knownMappings`

### The problem

The v33 codex critique identified that `resetPipelineState` should NOT remove old-run entries from `knownMappings` (to avoid expensive re-discovery). The acknowledgement says this was fixed: "Updated `resetPipelineState` call in `determineActiveRuns` pseudocode with inline comments clarifying mapping retention" and "Updated Invariant #10 to state mappings are 'never removed'."

The pseudocode in the `determineActiveRuns` function (around line 808-816) was indeed updated correctly:

```
resetPipelineState(pipeline.graphId)  -- clear per-context status maps, cursors, turn cache for old run
-- IMPORTANT: resetPipelineState does NOT remove old-run entries from
-- knownMappings.
```

And Invariant #10 now states "never removed."

However, the **prose description** of `resetPipelineState` immediately after the pseudocode block (line 824) was NOT updated and still says the opposite:

> "The `resetPipelineState` helper clears the per-context status maps, `lastSeenTurnId` cursors, and per-pipeline turn cache for all contexts that belonged to the old run. **It also removes `knownMappings` entries whose `runId` matches the old run's `run_id`.** These entries are removed for memory hygiene..."

This directly contradicts the pseudocode comments, Invariant #10, and the intended fix from the v33 acknowledgement. An implementer reading the prose would remove old-run entries, causing exactly the expensive re-discovery problem that was supposed to be fixed.

### Suggestion

Update the prose description of `resetPipelineState` (the paragraph starting with "The `lookupContext` helper...") to match the pseudocode and Invariant #10. Replace the sentence about removing `knownMappings` entries with language that matches the pseudocode: `resetPipelineState` clears per-context status maps, `lastSeenTurnId` cursors, and per-pipeline turn cache, but does NOT remove old-run entries from `knownMappings`.

---

## Issue #2: The spec's `decodeFirstTurn` documents `RunStarted` tag 8 as `graph_name` but the actual registry bundle also includes tag 12 (`graph_dot`) containing the full DOT source — a missed opportunity for the UI

### The problem

Reading the actual `kilroy-attractor-v1` registry bundle at `/Users/cwoolley/workspace/kilroy/data/registry/bundle_kilroy-attractor-v1_004673dd423a.json` and the Go code at `kilroy_registry.go` line 36, the `RunStarted` type has a tag 12 field:

```go
"12": field("graph_dot", "string", opt()),
```

And in `cxdb_events.go` line 30-32:

```go
if len(e.DotSource) > 0 {
    data["graph_dot"] = string(e.DotSource)
}
```

This means the `RunStarted` turn's msgpack payload contains the full DOT source of the pipeline graph at the time the run started. The spec's `decodeFirstTurn` function (Section 5.5) only extracts tags 1 (`run_id`) and 8 (`graph_name`), and the field inventory comment lists tags 1 through 11 but omits tag 12 entirely.

This is relevant because:

1. **Completeness:** The spec's field inventory for `RunStarted` v1 is incomplete — it lists "run_id (1), timestamp_ms (2), repo_path (3), base_sha (4), run_branch (5), logs_root (6), worktree_dir (7), graph_name (8), goal (9), modeldb_catalog_sha256 (10), modeldb_catalog_source (11)" but is missing `graph_dot (12)`.

2. **Future utility:** The `graph_dot` field means the UI could theoretically reconstruct the exact DOT file that was used for a specific run, even if the DOT file on disk has since been regenerated. This is a non-goal for the initial implementation (the spec explicitly reads DOT files fresh from disk), but an implementer should know it exists.

3. **Size concern:** Since the full DOT source is embedded in the RunStarted payload, `decodeFirstTurn`'s msgpack decode processes this potentially large string even though it only needs two small fields. This is a minor performance note, not a bug.

### Suggestion

Update the `decodeFirstTurn` field inventory comment (around line 709-710) to include `graph_dot (12)`. No code change is needed — the UI correctly ignores unused fields. Add a brief note that `graph_dot` contains the pipeline DOT source at run start time, available for future features but unused by the initial implementation.

---

## Issue #3: The spec documents only 9 turn types in Section 5.4 but the actual Kilroy registry bundle defines 20 types — several of which carry `node_id` and would affect status derivation or detail panel rendering

### The problem

Section 5.4's type table lists 9 turn types:
- `RunStarted`, `Prompt`, `ToolCall`, `ToolResult`, `GitCheckpoint`, `StageStarted`, `StageFinished`, `StageFailed`, `ParallelBranchCompleted`

Reading the actual `kilroy-attractor-v1` registry bundle (`kilroy_registry.go` lines 23-206) and the actual emitting code (`cxdb_events.go`), Kilroy defines and actively emits 20 types:

1. `RunStarted`
2. `RunCompleted`
3. `RunFailed`
4. `StageStarted`
5. `StageFinished`
6. `StageFailed`
7. `StageRetrying`
8. `ToolCall`
9. `ToolResult`
10. `Prompt`
11. `AssistantMessage`
12. `GitCheckpoint`
13. `CheckpointSaved`
14. `Artifact`
15. `BackendTraceRef`
16. `Blob`
17. `ParallelStarted`
18. `ParallelBranchStarted`
19. `ParallelBranchCompleted`
20. `ParallelCompleted`

And three more interview-related types:
21. `InterviewStarted`
22. `InterviewCompleted`
23. `InterviewTimeout`

Several of these carry `node_id` and are actively emitted:

- **`AssistantMessage`** (tag 2 = `node_id`, optional) — emitted for every LLM response. Contains `model`, `input_tokens`, `output_tokens`, `tool_use_count`, and `text`. This is a high-frequency turn type that the status derivation algorithm (Section 6.2) would process as a non-lifecycle turn (inferring "running"), which is correct. However, the detail panel rendering (Section 7.2) has no row in the per-type rendering table for `AssistantMessage` — it would fall through to "Other/unknown" and display "[unsupported turn type]" instead of showing the model name, token counts, and assistant text. This is a significant gap for the "mission control" use case.

- **`RunCompleted`** and **`RunFailed`** — run-level lifecycle events that mark the entire pipeline as completed or failed. The UI has no concept of run-level completion — it only tracks per-node status. A `RunCompleted` turn does not carry `node_id`, so it would be silently skipped by the `IF nodeId IS null` guard. But the detail panel has no rendering for these types either, so they appear as "[unsupported turn type]" if a user looks at turns for a node that happens to be referenced.

- **`InterviewStarted`**, **`InterviewCompleted`**, **`InterviewTimeout`** — human gate interaction events. These carry `node_id` (tag 2). `InterviewStarted` has `question_text` and `question_type`. `InterviewCompleted` has `answer_value` and `duration_ms`. `InterviewTimeout` has `question_text` and `duration_ms`. The status derivation would infer "running" for these (correct), but the detail panel shows "[unsupported turn type]" for all three. For human gate nodes, these interview events are the most relevant turns to display.

- **`StageRetrying`** (tag 2 = `node_id`) — emitted when a stage is about to retry. Contains `attempt` count and `delay_ms`. The status derivation would infer "running" (correct), but the detail panel shows "[unsupported turn type]".

### Suggestion

Add entries to the Section 5.4 type table and the Section 7.2 per-type rendering table for at least the high-value missing types:

| Turn Type | Output Column | Tool Column | Error Column |
|-----------|---------------|-------------|--------------|
| `AssistantMessage` | `data.text` (truncated) | `data.model` | blank |
| `InterviewStarted` | `data.question_text` | blank | blank |
| `InterviewCompleted` | `data.answer_value` | blank | blank |
| `InterviewTimeout` | `data.question_text` | blank | highlighted ("timeout") |
| `StageRetrying` | "Retrying (attempt {data.attempt})" | blank | blank |
| `RunCompleted` | `data.final_status` | blank | blank |
| `RunFailed` | `data.reason` | blank | highlighted |

The existing "Other/unknown" fallback handles the remaining low-value types (`Artifact`, `Blob`, `BackendTraceRef`, `CheckpointSaved`, `ParallelStarted`, `ParallelBranchStarted`, `ParallelCompleted`). At minimum, update the Section 5.4 type table to list all types that carry `node_id`, since those affect status derivation.

---

## Issue #4: The Kilroy `cxdb_bootstrap.go` reveals that Kilroy sets `client_tag` to `kilroy/{run_id}` via the binary protocol's `DialBinary` call — confirming the spec's assumption, but also revealing that Kilroy uses the binary protocol (not HTTP) for context creation, which has implications for the spec's `client_tag` stability requirement

### The problem

The spec's Section 5.5 states: "Kilroy must embed `client_tag` in the first turn's context metadata (key 30) for reliable classification." Reading the actual Kilroy code at `cxdb_bootstrap.go` line 124:

```go
bin, err := cxdb.DialBinary(probeCtx, cfg.CXDB.BinaryAddr, fmt.Sprintf("kilroy/%s", strings.TrimSpace(runID)))
```

The `client_tag` is set as the third argument to `DialBinary`, which is the session-level tag. CXDB's binary protocol sets this tag on the session, and CXDB's `session_tracker` resolves `client_tag` from the active session. The CXDB `context_to_json` function then falls back to the session tag if no cached metadata is available.

The key insight is that Kilroy does NOT explicitly embed `client_tag` in the first turn's context metadata (msgpack key 30). Looking at `cxdb_events.go`, the `cxdbRunStarted` function constructs a data map with fields like `run_id`, `graph_name`, etc. — but there is no key 30 (`context_metadata`) in this map. The CXDB server's `extract_context_metadata` function (`store.rs`) extracts metadata from the **raw msgpack payload** of the first turn, looking for key 30. If key 30 is absent in the payload, the only `client_tag` source is the session.

However, looking more carefully at the CXDB binary protocol's `AppendTurn` implementation, the binary protocol encodes the data map into msgpack and the CXDB server wraps it with additional metadata including the session's `client_tag` at key 30 in the outer envelope. So the `client_tag` IS present in the stored payload — it comes from the binary protocol's session, not from the application-level data map.

This means the spec's `client_tag` stability requirement is actually met in practice (Kilroy sets it via the binary session tag, and CXDB embeds it in the payload), but the mechanism is different from what the spec suggests (explicit embedding in the data map). The spec's concern about `client_tag` disappearing after session disconnect is correct in theory but does not apply to the binary protocol path, only to the HTTP path where `client_tag` comes from the session only and is not embedded in the payload.

### Suggestion

This is a documentation observation, not a required spec change. The spec's `client_tag` stability requirement (Section 5.5) is correct and conservative. The note about Kilroy needing to embed `client_tag` in context metadata is a reasonable defensive requirement. No change is needed unless the spec revision is otherwise underway, in which case a brief clarification that Kilroy's binary protocol session tag satisfies this requirement (CXDB embeds session metadata in stored payloads) would help implementers understand why `client_tag` is reliably available in practice.

---

If these are addressed, I do not see other major spec gaps. The most significant finding is Issue #3 (11 undocumented turn types with `node_id` that would render as "[unsupported turn type]" in the detail panel), which directly affects the user experience of the "mission control" dashboard. Issue #1 (the `resetPipelineState` contradiction) is a latent bug that would cause the exact performance problem the v33 fix was intended to prevent.
