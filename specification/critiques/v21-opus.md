# CXDB Graph UI Spec — Critique v21 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v20 cycle had two critics (opus and codex). All 5 issues were applied: opus's 3 issues added DOT string concatenation and multi-line value parsing to Section 3.2, extended `resetPipelineState` to remove old-run `knownMappings` entries, and added `path` to all CSS status selectors. Codex's 2 issues added transient error handling to discovery (try/catch with retry on failure) and graph ID uniqueness enforcement at startup.

However, v18 and v19 critiques (6 issues from opus, 5 from codex across both rounds) were never acknowledged or revised. This critique re-raises the most impactful of those unresolved issues that are still present in the current spec, along with new issues.

---

## Issue #1: `fetchFirstTurn` still has unreachable dead code — trailing `RETURN null` after unconditional return

### The problem

This was first raised in v18-opus Issue #1 and has not been addressed. The `fetchFirstTurn` pseudocode in Section 5.5 contains a trailing `RETURN null` (line 503 of the spec) after `RETURN response.turns[0]`:

```
    response = fetchTurns(cxdbIndex, contextId, limit=headDepth + 1)
    IF response.turns IS EMPTY:
        RETURN null
    RETURN response.turns[0]  -- oldest turn (oldest-first ordering) = first turn
    RETURN null
```

The final `RETURN null` is unreachable. Every preceding code path returns before reaching it. An implementer reading this will wonder whether the line signals a missed edge case or an incomplete refactor. It should be removed.

### Suggestion

Delete the unreachable `RETURN null` on what is currently line 503 of the spec. The function's control flow is already complete without it.

---

## Issue #2: `/api/dots` response format is still contradictory — prose says "array" but example shows an object

### The problem

This was first raised in v18-codex Issue #1 and re-raised in v19-codex Issue #2. Neither has been addressed. Section 3.2 describes `GET /api/dots` as:

> "Returns a JSON array of available DOT filenames"

But the example response is an object with a `dots` field:

```json
{ "dots": ["pipeline-alpha.dot", "pipeline-beta.dot"] }
```

This is a spec-level contradiction. An implementer could legitimately return either a raw array or an object wrapper and claim compliance. The initialization sequence (Section 4.5) does not disambiguate which schema the browser expects.

### Suggestion

Pick one format and make both the prose and the example consistent. If the object form is intended, change the prose to "Returns a JSON object with a `dots` array containing the available DOT filenames." If a raw array is intended, update the example to `["pipeline-alpha.dot", "pipeline-beta.dot"]`.

---

## Issue #3: `determineActiveRuns` and `checkPipelineLiveness` are undefined when a CXDB instance is unreachable

### The problem

This was raised in v19-opus Issue #3 and v19-codex Issue #1, and remains unaddressed. The `determineActiveRuns` function (Section 6.1, step 3) iterates `knownMappings` and calls `lookupContext(contextLists, index, contextId)` to access `created_at_unix_ms`. Similarly, `checkPipelineLiveness` calls `lookupContext` to access `is_live`. Both depend on `contextLists` from step 1 of the current poll cycle.

When a CXDB instance is unreachable, step 1 says "skip it and retain its per-context status maps." But `contextLists` contains no data for that instance. The spec does not define what `lookupContext` returns when the requested context's instance has no data.

This causes two cascading failures:

1. **Active run determination breaks.** If a pipeline's contexts span two instances and one is down, the remaining instance's contexts alone determine the active run. If those belong to an older run, the active run appears to change, triggering `resetPipelineState` and wiping cached status — the opposite of the intended "retain cached status during outages" behavior.

2. **Stale detection fires falsely.** If liveness defaults to false for unreachable contexts, `applyStaleDetection` marks running nodes as stale during an outage, contradicting the holdout scenario "CXDB becomes unreachable mid-session."

### Suggestion

Cache the last successful context list per instance. When an instance is unreachable, use its cached context list for `lookupContext` calls in `determineActiveRuns` and `checkPipelineLiveness`. This preserves active-run determination and liveness signals through transient outages. Add explicit pseudocode for caching and fallback, and update step 1 to note that cached context lists are retained for unreachable instances.

---

## Issue #4: Merged `hasLifecycleResolution` flag suppresses error and stale heuristics in parallel branches

### The problem

This was raised in v19-opus Issue #1 and remains unaddressed. The `mergeStatusMaps` function propagates `hasLifecycleResolution` from ANY per-context map to the merged map using OR semantics. Both `applyErrorHeuristic` and `applyStaleDetection` guard on `NOT mergedMap[nodeId].hasLifecycleResolution`.

This creates a bug when a node has completed in one parallel branch (context A: `StageFinished`, `hasLifecycleResolution = true`) but is actively failing in another branch (context B: 5 consecutive `ToolResult` errors, `hasLifecycleResolution = false`). After merging: status = "running" (correct per merge precedence), but `hasLifecycleResolution = true` (propagated from context A). The error heuristic skips the node, and the stale heuristic also skips it. The node displays as "running" with no visual indication of the error loop in context B.

### Suggestion

Change the merge to propagate `hasLifecycleResolution` only when ALL per-context maps have it set for the node (AND instead of OR). This way the error and stale heuristics fire if any branch lacks lifecycle resolution. Alternatively, run the error and stale heuristics per-context before merging, so each branch's error/stale state is independently determined before the cross-context merge.

---

## Issue #5: Poller updates inactive pipelines but the spec never requires loading their node IDs

### The problem

This was raised in v18-codex Issue #2 and remains unaddressed. Section 6.1 step 6 says "Per-context maps for inactive pipelines are also updated." The `updateContextStatusMap` function requires `dotNodeIds` for each pipeline. However, the initialization sequence (Section 4.5) only guarantees fetching the first DOT file (step 4: "Fetch the first DOT file via `GET /dots/{name}`"). There is no step that fetches `/dots/{name}/nodes` for all pipelines before polling starts.

Without node IDs for inactive pipelines, `updateContextStatusMap` cannot initialize status entries for their nodes, and the holdout scenario "Switch between pipeline tabs" (which expects cached status to be immediately reapplied) cannot be satisfied.

### Suggestion

Add a step to the initialization sequence (Section 4.5) that fetches `/dots/{name}/nodes` for every pipeline listed by `/api/dots` before starting the poller. This ensures `dotNodeIds` is available for all pipelines from the first poll cycle, supporting the "no gray flash" requirement on tab switch.
