# CXDB Graph UI Spec — Critique v15 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v14 critique raised 3 issues, all applied: (1) fixed the error heuristic to filter by ToolResult turns only, preventing non-ToolResult turns from diluting the detection window; (2) corrected `next_before_turn_id` semantics and added an early-exit optimization in `fetchFirstTurn`; (3) added explicit pseudocode for the active run determination algorithm. This critique continues cross-referencing the spec against the CXDB server source.

---

## Issue #1: Section 5.4 type table omits `run_id` from RunStarted and documents no per-type field inventory

### The problem

Section 5.4 describes RunStarted as: "First turn in a context. Contains `graph_name` and `graph_dot`." But `run_id` — a field the spec critically depends on — is not mentioned. Section 5.5 (line 492) later says "The `RunStarted` turn also contains a `run_id` field" and the discovery algorithm extracts `runId = firstTurn.data.run_id`. An implementer reading Section 5.4 as the authoritative type reference would not know `run_id` exists on RunStarted.

More broadly, the type table provides only prose descriptions ("Agent invoked a tool (`tool_name`, `arguments_json`)") without systematically documenting which fields exist on which types. The status derivation algorithm (Section 6.2) accesses `turn.data.node_id` on every turn and relies on the null check (`IF nodeId IS null`) to skip types that lack this field. But the spec never documents which types carry `node_id`:

- **Have `node_id`:** StageStarted, StageFinished, StageFailed, ToolResult, ToolCall, Prompt (inferred from Section 6.2 processing and Section 5.3 example)
- **Lack `node_id`:** RunStarted (pipeline-level, no node context), GitCheckpoint (mentioned as "node boundary" but field presence unclear), ParallelBranchCompleted (branch-level event)

Without explicit field documentation, an implementer must reverse-engineer field presence from algorithm pseudocode and examples scattered across Sections 5.3, 5.5, and 6.2. GitCheckpoint and ParallelBranchCompleted are particularly ambiguous — the algorithm silently skips them via the null check, but an implementer won't know whether this is intentional handling of absent fields or a latent bug.

### Suggestion

Expand Section 5.4 to include a field inventory per type. At minimum, add a "Key Fields" column to the type table:

| Type ID | Description | Key Data Fields |
|---------|-------------|-----------------|
| `com.kilroy.attractor.RunStarted` | First turn in a context | `graph_name`, `graph_dot`, `run_id` |
| `com.kilroy.attractor.Prompt` | LLM prompt sent to agent | `node_id`, `text` |
| `com.kilroy.attractor.ToolCall` | Agent invoked a tool | `node_id`, `tool_name`, `arguments_json` |
| `com.kilroy.attractor.ToolResult` | Tool result | `node_id`, `tool_name`, `output`, `is_error` |
| `com.kilroy.attractor.GitCheckpoint` | Git commit at node boundary | `node_id` (if present), `sha` |
| `com.kilroy.attractor.StageStarted` | Node execution began | `node_id` |
| `com.kilroy.attractor.StageFinished` | Node execution completed | `node_id` |
| `com.kilroy.attractor.StageFailed` | Node execution failed | `node_id` |
| `com.kilroy.attractor.ParallelBranchCompleted` | Parallel branch finished | `branch_key` |

For types whose exact fields are uncertain (GitCheckpoint, ParallelBranchCompleted), note the uncertainty explicitly so the implementer knows to verify against the registry bundle rather than assuming.

---

## Issue #2: Turns endpoint `limit` range "1–65535" is not a server-enforced constraint — misleads implementers and artificially caps `fetchFirstTurn`

### The problem

Section 5.3 documents the `limit` parameter as "Maximum number of turns to return (1–65535)." The `fetchFirstTurn` algorithm (Section 5.5, line 466) uses `min(headDepth + 1, 65535)` with the comment "CXDB limit max is 65535."

The CXDB server source (`server/src/http/mod.rs`) parses `limit` as `u32` with no enforced maximum — the parameter accepts any valid u32 value up to 4,294,967,295. The "65535" value appears to be a u16 assumption that does not match the server implementation.

This has two consequences:

1. **Misleading documentation.** An implementer reading "1–65535" would reasonably conclude that values above 65535 are rejected by the server. They are not.

2. **Unnecessary pagination in `fetchFirstTurn`.** The algorithm caps at 65535 turns per request. For the (admittedly rare) context with, say, 100,000 turns, this forces 2 paginated requests. Since the server accepts larger limits, a single request with `limit=headDepth+1` would suffice. The cap serves no purpose if it's not a server constraint.

### Suggestion

1. **Section 5.3** — Change the `limit` description from "Maximum number of turns to return (1–65535)" to "Maximum number of turns to return (parsed as u32; no server-enforced maximum). The UI uses at most 100 for polling and `headDepth + 1` for discovery."

2. **Section 5.5 `fetchFirstTurn`** — Remove the 65535 cap. Change:
   ```
   fetchLimit = min(headDepth + 1, 65535)
   ```
   to:
   ```
   fetchLimit = headDepth + 1
   ```
   And remove the "CXDB limit max is 65535" comment. This makes `fetchFirstTurn` a single request for all contexts regardless of depth, which is the stated intent ("fetches the entire context in as few requests as possible").

---

## Issue #3: No detection of crashed/stale pipelines — a "running" node persists indefinitely when the agent process dies

### The problem

The spec's stated purpose (Section 1.1) is to answer: "Which node is active? Which nodes completed? Where did errors occur?" A crashed pipeline violates this contract: a node displays as "running" (blue, pulsing) indefinitely when the agent process has actually died.

The failure mode:

1. Agent starts executing a node → StageStarted is written → node shows "running"
2. Agent process crashes (OOM, signal, host reboot, network partition)
3. No StageFinished or StageFailed turn is written (the process is dead)
4. The CXDB session disconnects → `is_live` becomes `false` on all affected contexts
5. The UI continues showing the node as "running" with its pulse animation
6. The operator sees an apparently active pipeline that is actually dead

This scenario is not covered by the error loop heuristic (which requires 3 consecutive ToolResult errors) or any other detection mechanism in the spec. The `is_live` field is available in the context list response (Section 5.2) but is documented as "unused by the UI."

For a "mission control" dashboard, this is a significant observability gap. The most critical thing an operator needs to know is whether the pipeline is alive or dead. A stale "running" indicator is worse than no indicator — it actively misleads.

The CXDB context list already provides the signal: when ALL contexts for a pipeline's active run have `is_live: false`, no agent is writing to any of them. Combined with a node status of "running" (no lifecycle resolution), this is a strong signal that the pipeline has stalled.

### Suggestion

Add a "stale" detection mechanism using `is_live`:

1. **Section 5.2** — Remove `is_live` from the "unused" list. Document it as used for stale pipeline detection.

2. **Section 6.1** — After step 3 (determine active run), add a liveness check:

   ```
   FUNCTION checkPipelineLiveness(pipeline, activeContexts, contextLists):
       -- A pipeline is "live" if ANY of its active-run contexts has is_live == true
       FOR EACH ctx IN activeContexts:
           contextInfo = lookupContext(contextLists, ctx.index, ctx.contextId)
           IF contextInfo.is_live == true:
               RETURN true
       RETURN false
   ```

3. **Section 6.2** — After `applyErrorHeuristic`, add:

   ```
   IF NOT pipelineIsLive:
       FOR EACH nodeId IN dotNodeIds:
           IF mergedMap[nodeId].status == "running"
              AND NOT mergedMap[nodeId].hasLifecycleResolution:
               mergedMap[nodeId].status = "stale"
   ```

4. **Section 6.3** — Add a `stale` CSS class:

   | Status | CSS Class | Visual |
   |--------|-----------|--------|
   | `stale` | `node-stale` | Orange/amber fill, no animation |

   This distinguishes "actively running" (blue, pulsing) from "was running but pipeline is dead" (orange, static).

5. **Section 8.2** — Extend the connection indicator to include pipeline liveness. When all contexts for the active run are `is_live: false` and at least one node is "running," show a warning like "Pipeline stalled — no active sessions."

6. Add a holdout scenario:

   ```
   ### Scenario: Agent crashes mid-node
   Given a pipeline run is active with the implement node running
     And the agent process crashes (no StageFinished/StageFailed written)
     And all CXDB contexts for the run transition to is_live: false
   When the UI polls CXDB
   Then the implement node is colored orange (stale), not blue (running)
     And the UI indicates the pipeline has no active sessions
   ```
