---
name: cxdb:status
description: Query CXDB to show pipeline context status, detect stuck agents, error loops, and suggest fixes.
user-invocable: true
---

Show a real-time status summary of all CXDB contexts for active Kilroy pipeline runs. Detect problems (error loops, stale agents, failed branches) and suggest fixes.

The CXDB API base URL is `http://127.0.0.1:9020` (nginx frontend).

## Step 1 — Fetch all contexts

```bash
curl -sf http://127.0.0.1:9020/v1/contexts
```

If the request fails (connection refused, timeout, non-200), report:

> CXDB is not reachable at `http://127.0.0.1:9020`. Start it with:
> ```
> script/start-cxdb.sh
> ```

If the response is an empty list, report:

> No active contexts in CXDB. Nothing to report.

Then stop.

## Step 2 — Fetch recent turns for each context

For each context returned, fetch the 10 most recent turns:

```bash
curl -sf http://127.0.0.1:9020/v1/contexts/{CONTEXT_ID}/turns?limit=10&order=desc
```

## Step 3 — Identify the pipeline DOT file

Look at the `client_tags` on each context to find the Kilroy run ID (typically formatted as `kilroy/<ULID>`). Then locate the pipeline DOT file at the repo root:

- `pipeline.dot`

Read the DOT file to get the list of node names so you can map `node_id` values from turns to human-readable pipeline stages.

## Step 4 — Parse turn data

For each context, extract from the most recent turns:

- **`data.node_id`** — current pipeline stage
- **`data.branch_key`** — parallel branch identifier
- **`declared_type.type_id`** — turn type (e.g., `ToolCall`, `ToolResult`, `GitCheckpoint`, `Text`)
- **`data.is_error`** — whether the turn is an error
- **`data.status`** — status field (e.g., `pass`, `fail`)
- **`data.tool_name`** — which tool was called
- **`data.output`** — output text (scan for validation failures)

## Step 5 — Build summary table

Present a table with one row per context:

| Context | Node | Branch | Status | Last Activity | Depth/Head |
|---------|------|--------|--------|---------------|------------|

Where:
- **Context** — short context ID (first 8 chars or session number)
- **Node** — the `node_id` mapped to the DOT file node name
- **Branch** — the `branch_key` value (or `—` if not on a branch)
- **Status** — derived from turn analysis: `running`, `error`, `complete`, `stale`, `disconnected`
- **Last Activity** — relative time of the most recent turn
- **Depth/Head** — from context metadata

## Step 6 — Detect problems

Scan all contexts for these issues:

### Error loops
Consecutive `is_error: true` turns on the same `node_id`. This often indicates a tool schema mismatch or validation failure (e.g., repeated `write_file` validation errors).

### Stale contexts
Contexts with `status: live` but no turn activity in the last 5 minutes.

### Failed branches
`GitCheckpoint` turns with `status: fail` — indicates a branch did not pass its gate check.

### Disconnected contexts
Contexts that appear disconnected (no longer streaming) but were expected to still be active based on pipeline progress.

## Step 7 — Report problems and suggest fixes

For each detected problem, print a warning block with a suggested fix:

- **Error loop** on node `X`:
  > Agent is stuck in an error loop on node `X`. The tool `{tool_name}` is repeatedly failing.
  > **Fix:** Stop the run with `/kilroy:status` → Stop, check the tool schema or input validation, then re-run.

- **Failed branch** `B` at checkpoint:
  > Branch `B` failed its git checkpoint. The consolidation step will proceed without this branch's changes.
  > **Fix:** Review the branch output for errors. You may need to manually apply the intended changes.

- **Stale context** (no activity for >5 min):
  > Context `{id}` appears stale — no turns in the last 5 minutes.
  > **Fix:** Check if the agent process is still running. If not, resume with `/kilroy:status` → Resume.

- **All branches complete but consolidator not started**:
  > All parallel branches have completed but no consolidation context is active.
  > **Fix:** The pipeline may need a manual restart. Use `/kilroy:status` → Resume.

## Step 8 — Offer next steps

After the report, suggest relevant actions:

- **If errors detected:** "Use `/kilroy:status` to stop the run, fix the issue, and re-run."
- **If everything looks healthy:** "Pipeline is progressing normally. Open `http://localhost:9020` for the full CXDB console."
- **If run appears complete:** "All contexts are complete. Use `/kilroy:land` to merge and push."
