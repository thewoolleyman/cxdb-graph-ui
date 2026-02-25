# CXDB Graph UI Spec — Critique v49 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-codex)
**Date:** 2026-02-25

## Prior Context

The v48 acknowledgement introduced the null-tag backlog for the fallback discovery path (legacy CXDB without CQL) and added a holdout that exercises discovery-after-disconnect on that legacy path.

---

## Issue #1: Null-tag backlog skipped when CQL is available

### The problem

Section 5.5 now funnels null `client_tag` contexts into a backlog only when `cqlSupported[index] == false` (fallback path). On modern CXDB builds where the CQL endpoint exists but Kilroy still omits key 30 metadata (current reality), the CQL call returns an empty list, so the spec triggers the supplemental `/v1/contexts` fetch. However, the supplemental loop only appends contexts whose `client_tag` is non-null (`contexts.append(ctx)`), and the subsequent discovery loop never enqueues null-tag contexts because the `cqlSupported[index] == false` guard is not satisfied. After a run completes and its session disconnects, every Kilroy context on such an instance has `client_tag: null`, so a fresh browser session sees **zero** contexts: the backlog never runs, `fetchFirstTurn` is never attempted, and completed runs remain undiscoverable. This contradicts the later prose (“The UI's `knownMappings` cache and null-tag backlog mitigate this”) and leaves the original defect in place for the default deployment (CXDB with CQL enabled but no key-30 metadata).

### Suggestion

Extend the backlog mechanism to cover the CQL-success-but-empty path. Concretely:

1. When `contexts` comes from CQL plus supplemental data, retain the null-tag entries instead of dropping them—e.g., push them into `nullTagCandidates` whenever `context.client_tag` is `null`, regardless of `cqlSupported[index]`.
2. Run the backlog batch unconditionally whenever `nullTagCandidates` is non-empty, so `fetchFirstTurn` still executes for historical contexts on CQL-enabled instances.
3. Update the narrative in Section 5.5 (“Consequences for discovery”) to make clear that the backlog is invoked in both CQL-empty and fallback scenarios.

Without this change, operators cannot rediscover completed runs after a page reload on the exact CXDB configuration the spec calls “current state.”

## Issue #2: Holdouts still miss the CQL-empty null-tag regression

### The problem

The new holdout (“Fallback discovery finds completed run after session disconnect on legacy CXDB”) only covers the 404 fallback path. There is still no acceptance test for the CQL-supported-but-empty case described above—i.e., CQL returns 200 with zero contexts, the supplemental list returns contexts with `client_tag: null`, and the UI must use `fetchFirstTurn` to classify them. Because the holdouts do not cover this scenario, the regression from Issue #1 would slip through even after the spec fix.

### Suggestion

Add a pipeline discovery holdout that simulates a CQL-enabled CXDB where Kilroy contexts lack key-30 metadata:

```
### Scenario: CQL-empty supplemental discovery handles null client_tag after disconnect
Given CXDB supports CQL search but Kilroy contexts omit key 30 metadata
  And GET /v1/contexts/search?q=tag ^= "kilroy/" returns 200 with contexts: []
  And the supplemental GET /v1/contexts?limit=10000 returns a completed Kilroy context with client_tag: null and is_live: false
When the UI polls for discovery
Then the context is enqueued in the null-tag backlog despite cqlSupported being true
  And fetchFirstTurn classifies it via RunStarted.graph_name
  And the pipeline tab shows the completed run's status
```

This locks in the dual-path expectation and ensures future edits keep the backlog active for both legacy and CQL-enabled deployments.
