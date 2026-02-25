# CXDB Graph UI Spec — Critique v33 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-25

## Prior Context

The v32 cycle resolved the active-run selection instability by switching to `context_id` and removed stale line-number references. A proposed holdout scenario for late-branch flips was added. This critique focuses on two remaining implementation risks: repeated re-discovery of old runs after a run change, and initialization/prefetch error handling beyond DOT parse errors.

---

## Issue #1: `resetPipelineState` deletes old-run mappings, which forces expensive re-discovery every poll

### The problem
Section 6.1 says `resetPipelineState` removes `knownMappings` entries whose `runId` matches the old run for memory hygiene. However, `discoverPipelines` treats any missing `(cxdb_index, context_id)` as undiscovered and re-fetches `RunStarted` via `fetchFirstTurn`. Old-run contexts remain in CXDB context lists, so removing their mappings causes them to be re-discovered on every poll cycle. This is especially costly because `fetchFirstTurn` can require up to 50 paginated requests per context in deep pipelines. It also violates the stated invariant that context-to-pipeline mapping is immutable once resolved (Invariants #10).

The spec currently has no guard to mark old-run contexts as permanently irrelevant after a run switch. Removing them from `knownMappings` effectively guarantees repeat work and extra CXDB load, especially when many historical runs exist. Since old contexts are never reused (context IDs are monotonic and not recycled), keeping their negative mapping is safe and prevents re-fetching.

### Suggestion
Revise `resetPipelineState` to retain old-run mappings but mark them as inactive for the current pipeline instead of deleting them. Two concrete options:

1. Keep the entries in `knownMappings` as-is and add a separate `inactiveRunIdsByPipeline` set so `determineActiveRuns` ignores them when it sees a newer run ID; or
2. Replace old-run mappings with a sentinel `{ graphName, runId, inactive: true }` so `discoverPipelines` skips re-fetching while the rest of the system can explicitly ignore inactive runs.

Also update Invariant #10 to clarify that mappings remain cached even after run switches, while active-run selection logic ignores old runs. Add a holdout scenario to ensure that after a run change, `fetchFirstTurn` is not re-issued for old context IDs.

---

## Issue #2: Initialization prefetch of `/nodes` lacks a defined error path for non-400 failures

### The problem
Section 4.5 mandates prefetching `/dots/{name}/nodes` for all pipelines during initialization (Step 4). The holdout scenarios cover a 400 response due to DOT parse errors and explicitly say the browser should continue with an empty `dotNodeIds` set. However, the spec does not define behavior for other failures during this prefetch step (network error, 404 because a DOT file was removed between `/api/dots` and `/nodes`, or 500 from an internal server error). Because Step 6 (polling) depends on Step 4 completing, an unhandled rejection in the prefetch promises could block polling entirely or stall the initialization sequence. The holdout scenarios only capture the DOT parse error case, not general fetch failures.

### Suggestion
Define the error handling contract for `/nodes` prefetch beyond the 400 parse error case:

- For any non-200 response (including 404/500) or network error, log a warning and proceed with an empty `dotNodeIds` set for that pipeline.
- Polling should still start, and the active tab should still render (Step 5) even if some prefetches fail.

Add a holdout scenario such as:

```
Scenario: /nodes prefetch network failure does not block polling
Given the UI initializes with multiple DOT files
  And one /dots/{name}/nodes request fails with 500
When initialization continues
Then polling still starts for all pipelines
  And the active tab renders its SVG
  And the pipeline with the failed /nodes prefetch uses an empty dotNodeIds set
```

This ensures the initialization sequence is robust to transient server errors and aligns with the graceful-degradation principle in Section 1.2.

---

If these are addressed, I do not see other major gaps. The spec is detailed and internally consistent after the v32 updates, and the remaining risks are mainly around long-lived runs and error handling during startup.
