# CXDB Graph UI Spec — Critique v43 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-25

## Prior Context

The v42 round applied three spec changes: (1) Section 3.2's comment handling paragraph now documents unterminated string errors matching Kilroy's `stripComments`, (2) Section 7.2's `StageStarted` rendering now includes `handler_type`, (3) Section 7.2 gained a "Tool gate turns" clarification paragraph, and (4) Section 4.2 gained a "CXDB `node_id` matching assumption" paragraph scoping normalization to Kilroy-generated data. Two holdout scenarios were deferred (gap recovery deduplication and CQL-empty supplemental discovery).

---

## Issue #1: `StageFinished` rendering omits `notes` and `suggested_next_ids` fields that Kilroy emits

### The problem

Section 5.4's turn type table documents `StageFinished` with fields: `node_id`, `status`, `preferred_label` (optional), `failure_reason` (optional), `notes` (optional), `suggested_next_ids` (optional, array). Section 7.2's per-type rendering table for `StageFinished` renders `status`, `preferred_label`, and `failure_reason` — but silently drops `notes` and `suggested_next_ids`.

Examining Kilroy's `cxdbStageFinished` (`cxdb_events.go` lines 80-89), both fields are always emitted:
```go
"notes":              out.Notes,
"suggested_next_ids": out.SuggestedNextIDs,
```

The `notes` field carries implementation-level observations from the handler (e.g., "applied workaround for flaky test", "retried 2 times before success") — free-form text that is the only narrative record of what happened during node execution beyond the raw tool call/result stream. The `suggested_next_ids` field shows which edges the pipeline selected at a conditional/routing node, which is useful for understanding branching decisions.

An implementer seeing these fields in Section 5.4 but not in Section 7.2's rendering table may wonder whether they should be displayed. The current spec neither renders them nor explicitly states they are omitted by design.

### Suggestion

Either:
- (a) Add `notes` to the `StageFinished` rendering: append `(if data.notes is non-empty: "\n{data.notes}")` after the `failure_reason` component. Display `suggested_next_ids` as a comma-joined list if non-empty. Or:
- (b) Add an explicit note to Section 7.2 stating that `notes` and `suggested_next_ids` are intentionally omitted from the detail panel as they duplicate information available from the turn stream and edge labels respectively.

Option (a) is preferred because `notes` is the only field that provides a concise summary of what happened during a stage, which is otherwise only available by scrolling through dozens of individual turn rows.

## Issue #2: `StageRetrying` rendering omits `delay_ms`, losing useful temporal context for operators

### The problem

Section 7.2's per-type rendering table renders `StageRetrying` as: `"Retrying (attempt {data.attempt})"`. This omits the `delay_ms` field documented in Section 5.4's turn type table.

Kilroy's `cxdbStageRetrying` (`cxdb_events.go` lines 200-211) always emits `delay_ms`:
```go
"delay_ms": delayMS,
```

For an operator monitoring a pipeline with retry loops, knowing the backoff delay is operationally significant — it tells them how long to wait before the next attempt begins and whether the backoff is escalating (suggesting a persistent rather than transient failure). Displaying "Retrying (attempt 3, delay 30s)" is more useful than "Retrying (attempt 3)" when the operator is deciding whether to intervene.

### Suggestion

Update the `StageRetrying` row in the per-type rendering table from:

> `StageRetrying` | "Retrying (attempt {`data.attempt`})" | blank | blank

to:

> `StageRetrying` | "Retrying (attempt {`data.attempt`}" + (if `data.delay_ms` is present and > 0: ", delay {formatted_delay}") + ")" | blank | blank

Where `formatted_delay` converts milliseconds to a human-readable duration (e.g., 1500 → "1.5s", 60000 → "60s"). This is a minor enhancement, not a correctness issue.

## Issue #3: No holdout scenario covers the interaction between `StageFailed` with `will_retry=true` and subsequent `StageRetrying` turn ordering in the status map

### The problem

Section 6.2 specifies that `StageFailed` with `will_retry=true` sets status to "running" and does NOT set `hasLifecycleResolution`. The spec also documents `StageRetrying` as a non-lifecycle turn that infers "running". These two turns typically appear in sequence during a retry cycle: `StageFailed(will_retry=true)` → `StageRetrying` → `StageStarted` (new attempt).

The existing holdout scenarios test error loop detection and lifecycle resolution, but none verify the specific retry sequence. An implementer might incorrectly treat `StageFailed` as always setting `hasLifecycleResolution=true` (ignoring the `will_retry` guard), which would cause all subsequent non-lifecycle turns (including `StageRetrying` and the new `StageStarted`) to be ignored for that node. The node would freeze at "error" when it should show "running" during retry.

### Suggestion

Add a holdout scenario:

```
### Scenario: Node retrying after StageFailed with will_retry=true shows as running
Given a pipeline run is active with the implement node running
  And the agent encounters an error and Kilroy emits StageFailed with will_retry=true
  And Kilroy subsequently emits StageRetrying and then StageStarted for a new attempt
When the UI polls CXDB
Then the implement node is colored blue (running), not red (error)
  And hasLifecycleResolution is false for the implement node
  And the detail panel shows the StageFailed, StageRetrying, and StageStarted turns
```

## Issue #4: The spec does not document what happens when the Go server receives a request to a non-existent route (e.g., `GET /foo`)

### The problem

Section 3.2 documents routes for `/`, `/dots/{name}`, `/dots/{name}/nodes`, `/dots/{name}/edges`, `/api/dots`, `/api/cxdb/instances`, and `/api/cxdb/{index}/*`. It does not specify the response for a request to a path that matches none of these routes (e.g., `GET /foo`, `GET /api/other`, `GET /favicon.ico`).

This matters because: (1) browsers automatically request `/favicon.ico` on page load, and (2) debugging tools or monitoring agents may probe arbitrary paths. Without a specified behavior, an implementer might return an HTML error page, a JSON error, or let Go's default mux behavior serve a 301 redirect (Go's `http.ServeMux` redirects `/tree` to `/tree/` by default for patterns ending in `/`). The spec's "no build toolchain" and "single HTML file" principles suggest the server should be minimally predictable.

### Suggestion

Add a brief note to Section 3.2 or Section 3.3:

> Requests to paths not matching any registered route return 404 with a plain-text body. The server does not serve directory listings, automatic redirects, or HTML error pages for unmatched routes.

This is a minor completeness issue, not a correctness problem.
