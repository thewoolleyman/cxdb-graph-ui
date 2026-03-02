# CXDB Console Guide

CXDB (Context Debugger) is an AI context store that persists the conversational context (turns, blobs, metadata) that AI agents produce during Kilroy pipeline runs. The web console at `http://127.0.0.1:9120/` provides a real-time operational view.

## Opening the Console

From this repo, run:

```bash
script/start-cxdb-ui.sh
```

This starts the CXDB frontend (served by nginx on port 9120) and opens it in your browser. The CXDB server itself must already be running (via `script/start-cxdb.sh` or as part of `script/setup.sh`).

## Dashboard Overview

### Top Bar

- **Environment filter** (`All` / `Prod` / `Stage` / `Dev`) — filters contexts by deployment environment.
- **Theme selector** — UI theme toggle.
- **Live Mode** — streams updates in real-time via SSE. Shows connection status.

### Left Sidebar

- **Search (CQL)** — query bar accepting Context Query Language. Search by tags (e.g., `tag = "amplifier"`) or free-text keywords. The `?` links to the CQL reference docs.
- **Contexts / Activity tabs** — toggle between the context list and a cross-context event feed.
- **Tag filter & sort** — filter by tag or sort alphabetically.

### Context List

Each entry in the sidebar represents a context stream. Key info per entry:

| Field | Meaning |
|-------|---------|
| Status indicator | `live` (green), `active` (blue), `disconnected` (grey) |
| Session number | Which session within the run (e.g., 2, 3, 4, 5 for parallel branches) |
| Run ID | The Kilroy run identifier (e.g., `kilroy/<ULID>`) |
| Last activity | Relative timestamp of the most recent turn |
| Depth | How many turns have been appended to this context |
| Head | The latest turn sequence number |

### Main Dashboard

When no context is selected, the main area shows system-level metrics:

- **In-Memory Index Capacity** — gauge showing memory usage with OK/WARN/HOT/CRIT thresholds.
- **Objects** — counts of contexts, turns, blobs, filesystem snapshots, types, and bundles.
- **Storage** — disk usage breakdown for turns, blobs, and free space.
- **Performance** — throughput (tps, req/s) and p95 latency for `append`, `get_last`, `get_blob`, and `http` operations.
- **Filesystem Snapshots** — count and size of captured file-tree snapshots.
- **Sessions & Errors** — active/idle/total session counts and error summary (clickable for details).

## Seeing What Agents Are Doing

### In the CXDB Console

Click any context in the left sidebar to open its turn-by-turn log. The turn list shows:

- **Turns** (chat bubble icon) — the agent's reasoning and prompts.
- **Tool Calls** (wrench icon) — actions the agent is taking (e.g., `write_file`, `read_file`, `bash`).
- **Tool Results** — the output of those actions.

When you click a turn, the right panel shows:

- **Summary fields** — key-value pairs like `node_id`, `run_id`, `status`, `branch_key`.
- **Full Data** — expandable JSON tree with all fields.
- **Turn Metadata** — the turn type (Prompt, ToolCall, ToolResult, ParallelBranchCompleted, etc.).
- **Provenance tab** — lineage and causality information for the turn.
- **Raw Payload** — the complete raw data.

#### Key fields for understanding agent activity

| Field | What it tells you |
|-------|-------------------|
| `node_id` | Which pipeline stage the agent is executing (`implement`, `check_implement`, `check_toolchain`, etc.) |
| `branch_key` | Which parallel branch (`dod_a`, `dod_b`, etc.) |
| `previous_node` / `completed_nodes` | Pipeline progress so far |
| `text` | The actual prompt or instructions the agent received |
| `tool_name` | What tool the agent called (`write_file`, `bash`, etc.) |
| `arguments_json.file_path` | Which file it's working on |
| `base_sha` | The git commit the run branched from |

#### Navigation shortcuts

| Key | Action |
|-----|--------|
| `j` / `k` | Move through turns |
| `o` | Open a selected context |
| `F` | Follow mode — auto-scroll to latest turn in live contexts |
| `a` | Jump to the Activity feed |
| `Cmd+K` | Search |
| `Esc` | Close context detail |

The **Activity tab** (may show a badge like `99+`) provides a cross-context event feed — useful for seeing all agents' activity interleaved chronologically.

### In a JetBrains IDE (Git Log)

Kilroy agents work in attractor branches within this repository. To see these branches and what agents have committed:

1. Open this project in a JetBrains IDE (GoLand, IntelliJ, etc.).
2. Go to **Git** menu → **Show Git Log** (or use the Git tool window at the bottom).
3. In the log view, **uncheck the `Branch` filter** (the branch selector near the top of the log panel) so it shows **all branches**, not just the currently checked-out one.
4. Look for branches prefixed with `attractor/` — these are the branches created by Kilroy pipeline runs.
5. Each attractor branch shows the commits made by agents during that run, giving you a clear view of what code was written, modified, or deleted.

This approach lets you see the actual diffs and commit history from each agent's work, complementing the turn-level detail available in the CXDB console.

### Worktree Location

Kilroy runs operate in their own worktree at:

```
~/.local/state/kilroy/attractor/runs/<RUN_ID>/worktree/
```

You can `cd` into this directory to inspect the working state directly, or open it as a separate project in your IDE.

## Understanding the Pipeline Graph

Kilroy pipelines are defined as DAGs (directed acyclic graphs). A typical pipeline flows through nodes like:

```
start → implement → check_implement → dod_fanout (parallel branches) → ...
```

When the pipeline reaches a fanout node, it spawns multiple parallel contexts — each appears as a separate entry in the CXDB sidebar. The `model_stylesheet` in the context metadata defines which Claude model each node class uses (e.g., Opus for `.hard` tasks, Sonnet for others).

Status updates with `ParallelBranchCompleted` metadata indicate when a branch finishes and reports back to the orchestrator.
