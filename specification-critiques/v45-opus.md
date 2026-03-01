# CXDB Graph UI Spec — Critique v45 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-25

## Prior Context

The v44 round applied three spec changes: (1) `InterviewStarted` rendering now includes `question_type`, (2) `InterviewCompleted` rendering now includes `duration_ms` with a shared `formatMilliseconds` helper, (3) `ParallelBranchCompleted` and `ParallelCompleted` field lists in Section 5.4 were completed. Three proposed holdout scenarios were deferred (StageFinished status=fail, anonymous graph rejection, DOT attribute concatenation/multiline).

---

## Issue #1: `RunCompleted` lacks `node_id` but spec does not document this omission in the turn type table's key data fields

### The problem

Section 5.4's turn type table lists `RunCompleted` with key data fields: `run_id`, `final_status`. Section 7.2's pipeline-level turns discussion correctly notes that `RunCompleted` "carries only `run_id` and `final_status`" and therefore never appears in the per-node detail panel because it has no `node_id`.

However, examining Kilroy's `cxdbRunCompleted` (`cxdb_events.go` lines 159-172), the turn actually carries six fields: `run_id`, `timestamp_ms`, `final_status`, `final_git_commit_sha`, `cxdb_context_id`, and `cxdb_head_turn_id`. The spec's field list omits `final_git_commit_sha`, `cxdb_context_id`, and `cxdb_head_turn_id`.

While `RunCompleted` is filtered out by the `node_id IS null` guard and its rendering row is noted as "unreachable in practice," the field inventory matters for completeness — the spec claims to be the canonical reference for field inventory, and the v44 round corrected similar omissions for `ParallelBranchCompleted` and `ParallelCompleted`. An implementer cross-referencing against CXDB raw turn data would see unexpected fields.

### Suggestion

Update Section 5.4's `RunCompleted` row to: `run_id`, `final_status`, `final_git_commit_sha`, `cxdb_context_id`, `cxdb_head_turn_id`. Add a note that none of these additional fields affect UI behavior since `RunCompleted` has no `node_id` and is filtered out by the status derivation guard. Similarly, update `RunFailed` to include `git_commit_sha` (currently only lists `run_id`, `reason`, `node_id`; source at `cxdb_events.go` line 319 includes `git_commit_sha`).

## Issue #2: `StageFailed` field inventory missing `attempt` in the turn type table

### The problem

Section 5.4's turn type table lists `StageFailed` with key data fields: `node_id`, `failure_reason`, `will_retry` (optional, boolean), `attempt` (optional). Looking more carefully, `attempt` IS listed — but Section 7.2's rendering for `StageFailed` does not include it. The rendering shows: `data.failure_reason` appended with " (will retry)" if `data.will_retry == true`.

Kilroy's `cxdbStageFailed` (`cxdb_events.go` line 185-197) always emits `attempt`:

```go
"attempt": attempt,
```

The `attempt` field tells the operator which retry iteration failed. For operators watching a pipeline that is retrying a failing node (e.g., attempt 3 of 5), the attempt number provides essential context — "failure on attempt 1" has different implications than "failure on attempt 4." Currently, `StageRetrying` renders `attempt` but `StageFailed` drops it, creating an asymmetry: the operator sees "Retrying (attempt 3, delay 1.5s)" followed by a bare "connection timeout (will retry)" with no attempt number.

### Suggestion

Update the `StageFailed` rendering row in Section 7.2 to include the attempt number:

> `StageFailed` | `data.failure_reason` + (if `data.will_retry == true`: " (will retry, attempt {`data.attempt`})") + (if `data.will_retry != true` and `data.attempt` is present and > 0: " (attempt {`data.attempt`})") | blank | highlighted (only if `data.will_retry != true`)

This gives operators consistent attempt visibility across both the retry and failure events.

## Issue #3: Kilroy's `cxdbRunFailed` can be called with an empty `nodeID` string, but the spec assumes it always carries one

### The problem

Section 6.2 states: "Kilroy's `cxdbRunFailed` always passes a `node_id`, so in practice `RunFailed` turns always enter the status derivation." Section 7.2 reiterates: "`RunFailed`, by contrast, always carries a `node_id` (Kilroy's `cxdbRunFailed` always passes one) and does appear in the detail panel for the failed node."

Examining `cxdbRunFailed` in `cxdb_events.go` (lines 315-327):

```go
func (e *Engine) cxdbRunFailed(ctx context.Context, nodeID string, sha string, reason string) (string, error) {
    ...
    turnID, _, err := e.CXDB.Append(ctx, "com.kilroy.attractor.RunFailed", 1, map[string]any{
        ...
        "node_id": nodeID,
        ...
    })
```

The function always includes `"node_id"` in the map, but Go's msgpack encoding will encode an empty string `""` as a string, not omit the key. An empty `node_id` would pass the `IF nodeId IS null` guard (it is not null, it is `""`) but would fail the `IF nodeId NOT IN existingMap` guard (since `""` is not a DOT node ID).

Checking how `cxdbRunFailed` is called in the engine (`engine.go`):

```go
e.cxdbRunFailed(runCtx, nodeID, sha, reason)
```

The `nodeID` parameter comes from the engine's current execution context. If the engine fails before entering any node (e.g., during graph initialization), `nodeID` could be an empty string. This edge case means the spec's assertion "always passes a `node_id`" is technically correct (a `node_id` key is always present), but the value may be empty, in which case the turn would be silently filtered out by the `NOT IN existingMap` guard.

This is not a bug — the `NOT IN existingMap` guard handles it correctly. But the spec's language is misleading. An implementer who trusts "always carries a `node_id`" might skip the null/empty check for `RunFailed` specifically, which would break if they encounter a `RunFailed` with an empty `node_id`.

### Suggestion

Soften the language in Sections 6.2 and 7.2 from "always passes a `node_id`" to "always includes a `node_id` field, but the value may be an empty string if the run fails before entering a node (e.g., during graph initialization). An empty `node_id` is effectively filtered out by the `NOT IN existingMap` guard." This is a documentation precision issue, not a behavior change.

## Issue #4: No holdout scenario tests gap recovery with lifecycle turns that arrive during the gap

### The problem

Section 6.1 documents gap recovery in detail, including the pseudocode. The holdout scenario "Lifecycle turn missed during poll gap is recovered" (in the holdout scenarios file) tests the basic case: a StageFinished turn is missed and recovered via pagination.

However, there is a subtler gap recovery scenario not covered: when gap recovery hits the `MAX_GAP_PAGES` limit (10 pages = 1,000 turns) and some lifecycle turns fall outside the recovered window. The spec says: "the tradeoff is that intermediate turns beyond the 1,000-turn window are lost — but because statuses are never demoted, any promotions from lost turns are not critical."

This claim deserves a holdout scenario because an implementer might incorrectly implement the cursor advancement after hitting `MAX_GAP_PAGES`. The spec says:

> `lastSeenTurnId = recoveredTurns[0].turn_id  -- oldest recovered turn becomes new cursor`

If an implementer instead set `lastSeenTurnId` to the newest recovered turn (an easy mistake since the main `newLastSeenTurnId` computation takes the max), the next poll cycle's gap detection would break — the cursor would jump forward past unrecovered turns, and those turns would never be recovered. The spec documents this correctly but the holdout scenarios do not exercise it.

### Suggestion

Add a holdout scenario:

```
### Scenario: Gap recovery bounded by MAX_GAP_PAGES advances cursor correctly
Given a pipeline run is active with a context that accumulated 2000+ turns during a poll gap
  And the gap recovery issues MAX_GAP_PAGES (10) paginated requests covering 1000 turns
  And a StageFinished turn for node A exists beyond the 1000-turn recovery window
When gap recovery completes
Then lastSeenTurnId is set to the oldest recovered turn's turn_id
  And node A retains its previous status (running) since the StageFinished was not recovered
  And the next poll cycle's 100-turn window contains the most recent state
```

This is a minor completeness issue for the holdout scenarios.
