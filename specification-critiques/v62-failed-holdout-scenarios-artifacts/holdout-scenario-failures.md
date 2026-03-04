# Holdout Scenario Failures — v62

## Critical Failures

### FAIL: [Detail Panel] Click a node to see details — React crash on CXDB turn rendering

**Section:** Batch 9 — Detail Panel
**Scenario:** Click a node to see details (with CXDB status data present)
**Screenshot:** `batch9-detail-panel-crash.png`

**What happened:** When the mock CXDB is active (`pipeline_running` scenario) and a node with CXDB activity is clicked, the React app crashes with a white screen. The error is:

```
TypeError: Cannot read properties of undefined (reading 'split')
    at Ki (index-Bmp4OIjF.js:43:55)
    at Gp (index-Bmp4OIjF.js:43:153)
    at Yp (index-Bmp4OIjF.js:46:1359)
```

**Root cause:** The detail panel component expects CXDB turns to have a specific data structure. The mock returns `declared_type` as a plain string (e.g., `"ToolCall"`, `"com.kilroy.attractor.StageStarted"`), but the detail panel's rendering code calls `.split()` on an undefined property, suggesting it expects `declared_type` to be an object (e.g., `{type_id: "..."}`) or expects a field that doesn't exist on the mock turn objects.

**Impact:** This is a **critical crash** — clicking any node with CXDB activity kills the entire UI. The detail panel must be wrapped in an error boundary and must handle both typed and raw turn formats defensively.

---

### FAIL: [Status Overlay] implement node shows as running instead of complete in pipeline_running scenario

**Section:** Batch 8 — CXDB Status Overlay
**Scenario:** Pipeline actively running — nodes colored by status
**Screenshot:** `batch8-pipeline-running.png`

**What happened:** With mock scenario `pipeline_running`, the `implement` node gets CSS class `node-running` (blue) instead of `node-complete` (green). The mock includes a `StageFinished` turn for `implement` with `status: "pass"`, which should promote the node to complete status.

**Expected:** implement=green (complete), fix_fmt=blue (running), others=gray (pending)
**Actual:** implement=blue (running), fix_fmt=blue (running), others=gray (pending)

**Root cause:** The status engine does not process `StageFinished` turns to promote nodes from `running` to `complete`. All nodes that have any lifecycle event (StageStarted or later) show as `running` regardless of whether StageFinished has been received.

---

### FAIL: [Status Overlay] StageFinished with status=fail does not color node as error

**Section:** Batch 8 — CXDB Status Overlay
**Scenario:** StageFinished with status=fail colors node as error
**Mock scenario:** `stage_finished_fail`

**What happened:** fix_fmt has CSS class `node-running` (blue). Expected `node-error` (red).

**Expected:** fix_fmt=red (error), implement=green (complete)
**Actual:** fix_fmt=blue (running), implement=blue (running)

---

### FAIL: [Status Overlay] RunFailed does not mark node as error

**Section:** Batch 8 — CXDB Status Overlay
**Scenario:** RunFailed marks specified node as error
**Mock scenario:** `run_failed`

**What happened:** fix_fmt has CSS class `node-running` (blue). Expected `node-error` (red).

**Expected:** fix_fmt=red (error)
**Actual:** fix_fmt=blue (running)

---

### FAIL: [Status Overlay] Error loop detection not working

**Section:** Batch 8 — CXDB Status Overlay
**Scenario:** Agent stuck in error loop (per-context scoping)
**Mock scenario:** `error_loop`

**What happened:** fix_fmt has CSS class `node-running` (blue). Expected `node-error` (red) due to 3 consecutive ToolResult errors.

**Expected:** fix_fmt=red (error)
**Actual:** fix_fmt=blue (running)

---

### FAIL: [Status Overlay] Pipeline completed shows all nodes as stale instead of complete

**Section:** Batch 8 — CXDB Status Overlay
**Scenario:** Pipeline completed successfully
**Mock scenario:** `pipeline_complete`

**What happened:** All traversed nodes show CSS class `node-stale` (orange) and the "Pipeline stalled — no active sessions" banner appears. Expected all traversed nodes to show as `node-complete` (green).

**Root cause:** The pipeline completion detection treats `is_live: false` as "stalled" without checking whether all nodes have lifecycle resolution (StageFinished). A pipeline where all nodes are finished AND is_live is false should be detected as "completed", not "stalled".

**Expected:** All traversed nodes=green (complete)
**Actual:** All traversed nodes=orange (stale), "Pipeline stalled" banner shown

---

### FAIL: [Status Overlay] Second run shows stale instead of run B progress

**Section:** Batch 8 — CXDB Status Overlay
**Scenario:** Second run of same pipeline while first run data exists
**Mock scenario:** `second_run`

**What happened:** All traversed nodes show as `node-stale` with "Pipeline stalled" banner. Expected run B's progress (implement=complete, fix_fmt=running).

**Expected:** implement=green, fix_fmt=blue (from run B), others=gray
**Actual:** All traversed=stale, "Pipeline stalled"

---

### FAIL: [Status Overlay] no_pipeline scenario retains stale state from prior scenario

**Section:** Batch 8 — CXDB Status Overlay
**Scenario:** No active pipeline run
**Mock scenario:** `no_pipeline`

**What happened:** After switching from another scenario to `no_pipeline`, nodes retain `node-stale` class and "Pipeline stalled" banner. Expected all nodes to be gray (pending).

**Expected:** All nodes=gray (pending)
**Actual:** Multiple nodes=stale, "Pipeline stalled" banner persists

---

## Summary of Root Causes

1. **Status engine does not process StageFinished turns:** The core issue. Nodes transition to `running` on StageStarted but never transition to `complete` on StageFinished, `error` on StageFinished(status=fail), or `error` on RunFailed.

2. **Error loop heuristic not implemented or not triggering:** 3 consecutive ToolResult errors within a context do not promote the node to error state.

3. **Stale detection does not account for completed pipelines:** When `is_live: false` and all nodes have StageFinished, the pipeline should be shown as complete (green), not stalled (orange).

4. **Detail panel crashes on CXDB turn data:** The CXDB Activity section in the detail panel has an unhandled TypeError when processing turn objects, crashing the entire React component tree.

5. **State not cleared between scenario switches:** When CXDB returns empty contexts (no_pipeline), the previous status map is not cleared.
