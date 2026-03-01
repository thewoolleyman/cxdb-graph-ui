# CXDB Graph UI Spec — Critique v38 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-25

## Prior Context

The v37 opus critique was fully applied: the spec now clarifies untruncated Prompt.text, adds the CQL-empty supplemental fetch path, documents /dots/{name} read errors, and explains why DOT files are read from disk rather than RunStarted.graph_dot.

---

## Issue #1: CQL-empty supplemental discovery is not reflected in the cached context list, causing false "stale" classification

### The problem
Section 5.5 adds the supplemental `fetchContexts` path when CQL returns zero results, but Section 6.1 step 1 still says that on a successful CQL response the UI stores `searchResponse.contexts` into `cachedContextLists[i]` (replacing any previous value). When CQL is supported but returns an empty list (the common current case before Kilroy key 30), the UI will overwrite `cachedContextLists[i]` with `[]` even though the supplemental context list contains live Kilroy contexts (discovered via session tags).

This empties the data source used by `lookupContext` in `checkPipelineLiveness`. As a result:

- `pipelineIsLive` becomes false for pipelines that are actively running (because `lookupContext` cannot find the active-run contexts in the empty cached list).
- `applyStaleDetection` then reclassifies running nodes as stale, and the top bar shows "Pipeline stalled" even though the agent is live.

This is a correctness issue: the supplemental discovery exists precisely to handle CQL-empty results, but the liveness signal and stale detection still act as if there are no contexts.

### Suggestion
When CQL returns zero results and the supplemental `fetchContexts` path runs, use that supplemental list as the authoritative `contexts` for the instance in the current poll cycle (and store it in `cachedContextLists[i]`). Two concrete spec updates:

1. In Section 6.1 step 1, specify that `cachedContextLists[i]` is populated from the same list used for discovery in the current cycle (CQL results when non-empty, otherwise the supplemental context list).
2. In the `discoverPipelines` pseudocode, explicitly return (or expose) the supplemental list so the caller can use it for `contextLists` and liveness checks.

This aligns the liveness signal with the discovery path and prevents false "stale" status when CQL is empty but active sessions exist.

---

## Issue #2: Spec requires dropping removed DOT nodes, but the status-map algorithms never define the removal step

### The problem
Section 4.4 says that when `/dots/{name}/nodes` changes, "removed nodes are dropped from the maps." However, the algorithm in Section 6.2 (`updateContextStatusMap`) only adds entries for new node IDs and never removes entries for deleted nodes. `mergeStatusMaps` iterates only over `dotNodeIds`, so deleted nodes do not show up visually, but the per-context maps and cached merged maps retain stale entries indefinitely.

This is a spec inconsistency: the behavior is required in Section 4.4 but never specified in the status-map lifecycle. An implementer following the pseudocode literally will never drop removed nodes, which contradicts the documented expectation and creates unbounded growth if DOT files are regenerated repeatedly with different node sets.

### Suggestion
Add an explicit pruning step tied to `dotNodeIds` refresh. For example:

- In the tab-switch handling (Section 4.4) or in `updateContextStatusMap`, specify: "Before processing turns, remove any keys from the per-context status map that are not present in `dotNodeIds`."
- Similarly, when computing the merged map, ensure that any cached merged status maps are rebuilt from the pruned per-context maps so removed nodes are dropped from memory as well as from the display.

This makes the spec consistent with Section 4.4 and prevents unbounded growth of per-context status maps across DOT regeneration.

---

## Issue #3: Error loop heuristic does not preserve cross-poll consecutive errors, contradicting the holdout scenario about interleaving

### The problem
The holdout scenario "Agent stuck in error loop (per-context scoping)" describes three most recent ToolResult errors with interleaved Prompt/ToolCall turns. The spec implements this by filtering ToolResult turns in a single poll window. However, the spec also acknowledges that the per-context turn cache is replaced every poll cycle (Section 6.1 step 5) and that the heuristic only sees the current 100-turn window (Section 6.2 "Error heuristic window limitation").

This means a realistic error loop spanning multiple poll cycles will not be detected even if each cycle contains 1-2 error ToolResults. For a slow or throttled tool (e.g., retries every 10-20 seconds), the last three ToolResult errors may be split across multiple polls, and the heuristic will never fire. The holdout scenario does not specify that the three ToolResult errors must all appear in the same poll window, so the current algorithm does not actually satisfy the scenario under typical timing.

### Suggestion
Clarify or adjust the spec to align with the holdout scenario:

- Option A (spec change): Amend the holdout scenario to explicitly state that the three error ToolResults are within the same poll window (e.g., within the most recent 100 turns), matching the documented limitation.
- Option B (algorithm change): Persist a small per-context per-node error history across polls (e.g., the last 3 ToolResult `is_error` flags) and have `applyErrorHeuristic` consult that history instead of only the current turn cache. This would satisfy the scenario as written while still avoiding cross-context ordering.

Either change is acceptable, but the spec and holdout scenarios should be made consistent.
