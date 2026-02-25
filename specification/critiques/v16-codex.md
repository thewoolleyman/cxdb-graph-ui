# CXDB Graph UI Spec — Critique v16 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-24

## Prior Context

v15’s issues were all applied: the type table now includes key fields (including RunStarted.run_id), the turns limit is documented as u32 without a server cap, and stale-pipeline detection was added using is_live with a new stale node status. The holdout scenario for stale pipelines was noted as a follow-up and still has not been added.

---

## Issue #1: Duplicate DOT basenames are undefined and can silently collide

### The problem
The server keys DOT files by base filename (`/dots/{name}`) and `/api/dots` returns those filenames. The spec does not define behavior when two `--dot` flags point to different paths that share the same basename (e.g., `pipelines/alpha/pipeline.dot` and `pipelines/beta/pipeline.dot`). In that case, the map will collide and one pipeline becomes unreachable or mislabeled, and the UI can render the wrong graph under a tab that appears to be correct. This is an easy footgun in multi-repo or monorepo setups.

### Suggestion
Add an explicit startup check in Section 3.2/3.3: reject duplicate basenames with a clear error message and non-zero exit. Alternatively, document a disambiguation scheme (e.g., auto-prefix with an index or hash) and describe how `/api/dots` and tab labels reflect it. Add a server holdout scenario covering duplicate basenames so the expected behavior is testable.

---

## Issue #2: Holdout scenarios do not cover the new stale pipeline detection path

### The problem
The spec now includes stale detection and a “Pipeline stalled — no active sessions” indicator, but the holdout scenarios have no coverage for this behavior. As a result, the most user-visible addition from v15 is untested, and an implementer could omit it while still passing all holdout scenarios.

### Suggestion
Add a holdout scenario mirroring the spec’s stale detection rule, for example:

```
### Scenario: Pipeline stalled after agent crash
Given a pipeline run is active with a node in running state
  And all active-run contexts transition to is_live: false
When the UI polls CXDB
Then the running node is marked stale (orange)
  And the top bar shows "Pipeline stalled — no active sessions"
```
