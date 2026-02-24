# CXDB Graph UI Specification

A local web dashboard that renders Attractor pipeline DOT files as interactive SVG graphs with real-time execution status from CXDB. The DOT graph is the pipeline definition; CXDB holds the execution trace. The UI overlays one on the other — nodes are colored by their execution state, and clicking a node shows its CXDB activity.

---

## Table of Contents

1. [Overview and Goals](#1-overview-and-goals)
2. [Architecture](#2-architecture)
3. [Server](#3-server)
4. [DOT Rendering](#4-dot-rendering)
5. [CXDB Integration](#5-cxdb-integration)
6. [Status Overlay](#6-status-overlay)
7. [Detail Panel](#7-detail-panel)
8. [UI Layout and Interaction](#8-ui-layout-and-interaction)
9. [Invariants](#9-invariants)
10. [Non-Goals](#10-non-goals)
11. [Definition of Done](#11-definition-of-done)

---

## 1. Overview and Goals

### 1.1 Problem Statement

CXDB provides turn-by-turn inspection of agent activity during Attractor pipeline runs. It shows a chronological log of tool calls, prompts, and results — useful for debugging a single agent's behavior. But it has no visual representation of the pipeline graph.

During an Attractor run, operators need to answer: Which node is active? Which nodes completed? Where did errors occur? How far along is the pipeline? Answering these questions requires mentally mapping CXDB turn data (which contains `node_id` fields) back to the DOT graph structure. This is tedious and error-prone.

The CXDB Graph UI solves this by rendering the DOT pipeline as an interactive SVG and overlaying CXDB execution state onto it. Nodes are color-coded by status. Clicking a node shows its CXDB turns. The result is a "mission control" view of pipeline execution.

### 1.2 Design Principles

**Single-origin server.** The browser communicates with one HTTP server that serves static assets, DOT files, and proxies CXDB API requests. This eliminates CORS issues without requiring CXDB configuration changes.

**No build toolchain.** The frontend is a single HTML file with inline CSS and JavaScript. External dependencies are loaded from CDN. There is no npm, no bundler, no TypeScript, no framework.

**Generic pipeline support.** The UI is not hardcoded to any specific pipeline or repository. It accepts DOT file paths and CXDB addresses as command-line arguments. Any Attractor pipeline DOT file is a valid input.

**Read-only.** The UI reads DOT files from disk and reads from the CXDB HTTP API. It never writes to CXDB, never modifies DOT files, and never controls pipeline execution.

**Graceful degradation.** The pipeline graph renders from the DOT file alone. CXDB status is an overlay. If CXDB is unreachable, the graph is still useful for understanding pipeline structure.

---

## 2. Architecture

The system has two components: a Go HTTP server and a browser-side single-page application.

```
┌──────────────────────────────────────────────────┐
│  Browser (index.html)                            │
│                                                  │
│  ┌────────────┐  ┌───────────┐  ┌────────────┐  │
│  │ Graphviz   │  │ Status    │  │ Detail     │  │
│  │ WASM       │  │ Poller    │  │ Panel      │  │
│  │ (CDN)      │  │ (3s)      │  │ (sidebar)  │  │
│  └─────┬──────┘  └─────┬─────┘  └─────┬──────┘  │
│        │               │              │          │
│   DOT → SVG       fetch JSON     show turns      │
└────────┼───────────────┼──────────────┼──────────┘
         │               │              │
         ▼               ▼              ▼
┌──────────────────────────────────────────────────┐
│  Go Server (main.go)                             │
│                                                  │
│  GET /              → index.html                 │
│  GET /dots/{name}   → DOT file from --dot flags  │
│  GET /api/cxdb/{i}/* → reverse proxy to CXDB[i]  │
└──────────┬───────────────────────┬───────────────┘
           │                       │
    ┌──────┴──────┐         ┌──────┴──────┐
    │ CXDB-0      │   ...   │ CXDB-N      │
    │ :9010       │         │ :9011       │
    └─────────────┘         └─────────────┘
```

**Why Go.** Go is already a dependency in the Attractor/Kilroy ecosystem. The server uses only the standard library — no `go.mod`, no external packages. It runs with `go run main.go`.

**Why browser-side DOT rendering.** The `@hpcc-js/wasm-graphviz` library compiles Graphviz to WebAssembly and runs entirely in the browser. This avoids requiring the `dot` binary on the host, supports interactive SVG manipulation, and renders DOT changes without server restart.

**Why a proxy for CXDB.** CXDB's HTTP API (port 9010) does not set CORS headers. The browser cannot fetch from a different origin. The Go server reverse-proxies `/api/cxdb/*` to CXDB, putting all requests on a single origin. When multiple CXDB instances are configured, the server proxies each under a numeric index (`/api/cxdb/0/*`, `/api/cxdb/1/*`, etc.).

---

## 3. Server

### 3.1 Command-Line Interface

```
go run ui/main.go [OPTIONS]
```

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--port` | integer | `9030` | TCP port for the UI server |
| `--cxdb` | URL (repeatable) | `http://127.0.0.1:9010` | CXDB HTTP API base URL. May be specified multiple times for multiple CXDB instances. |
| `--dot` | path (repeatable) | (required) | Path to a pipeline DOT file. May be specified multiple times. |

Both `--dot` and `--cxdb` are repeatable. The UI auto-discovers which CXDB instances contain contexts for which pipelines (Section 5.5). No manual pairing is required.

If no `--cxdb` flags are provided, the default (`http://127.0.0.1:9010`) is used as the sole instance. If no `--dot` flags are provided, the server exits with an error message and usage help.

**Examples:**

```bash
# Single pipeline, default CXDB
go run ui/main.go --dot /path/to/pipeline-alpha.dot

# Multiple pipelines, single CXDB
go run ui/main.go \
  --dot /path/to/pipeline-alpha.dot \
  --dot /path/to/pipeline-beta.dot \
  --dot /path/to/pipeline-gamma.dot

# Multiple pipelines, multiple CXDB instances
go run ui/main.go \
  --dot /path/to/pipeline-alpha.dot \
  --dot /path/to/pipeline-beta.dot \
  --cxdb http://127.0.0.1:9010 \
  --cxdb http://127.0.0.1:9011

# Custom CXDB address
go run ui/main.go --dot pipeline.dot --cxdb http://10.0.0.5:9010
```

The server prints the URL on startup: `Kilroy Pipeline UI: http://127.0.0.1:9030`

### 3.2 Routes

#### `GET /` — Dashboard

Serves `index.html` from the same directory as `main.go`. Returns 404 if the file is missing.

#### `GET /dots/{name}` — DOT Files

Serves DOT files registered via `--dot` flags. The `{name}` is the base filename (e.g., `pipeline-alpha.dot`).

- The server builds a map from base filename to absolute path at startup.
- Only filenames registered via `--dot` are servable. Requests for unregistered names return 404.
- Files are read fresh on each request. DOT file regeneration is picked up without server restart.

#### `GET /api/cxdb/{index}/*` — CXDB Reverse Proxy

Each `--cxdb` flag registers a CXDB instance at a zero-based index. The proxy route includes the index to disambiguate instances.

- `/api/cxdb/0/v1/contexts` → first `--cxdb` URL + `/v1/contexts`
- `/api/cxdb/1/v1/contexts` → second `--cxdb` URL + `/v1/contexts`

The server strips `/api/cxdb/{index}` and forwards the remainder to the corresponding CXDB base URL.

- Request and response bodies are passed through unmodified.
- No header injection, body rewriting, or caching.
- If a CXDB instance is unreachable, returns 502 Bad Gateway for that index.
- Index out of range returns 404.

The browser fetches `/api/cxdb/instances` to get the list of configured CXDB URLs and their indices. This is a server-generated JSON response, not proxied:

```json
{ "instances": ["http://127.0.0.1:9010", "http://127.0.0.1:9011"] }
```

### 3.3 Server Properties

- The server is stateless. It caches nothing. Every request reads from disk or proxies to CXDB.
- The server uses only Go standard library packages. No external dependencies.
- The server binds to `0.0.0.0:{port}` (all interfaces).

---

## 4. DOT Rendering

### 4.1 Graphviz WASM

The browser loads `@hpcc-js/wasm-graphviz` from a CDN (jsDelivr). This library compiles Graphviz to WebAssembly and exposes a `layout(dotString, "svg", "dot")` function that returns SVG markup.

The UI calls this function with the raw DOT file content fetched from `/dots/{name}`. The resulting SVG is injected into the main content area.

### 4.2 SVG Node Identification

Graphviz SVG output wraps each node in a predictable structure:

```xml
<g id="node1" class="node">
  <title>expand_spec</title>
  <polygon points="..." fill="..." stroke="..."/>
  <text>expand_spec</text>
</g>
```

The `<title>` element contains the DOT node ID. This is the key used to match CXDB turn data to SVG elements.

**Matching algorithm:**

```
FOR EACH g IN svg.querySelectorAll('g.node'):
    nodeId = g.querySelector('title').textContent.trim()
    status = nodeStatusMap[nodeId] OR "pending"
    g.setAttribute('data-status', status)
    g.classList.add('node-' + status)
```

### 4.3 Edge Identification

Edges follow a similar structure:

```xml
<g id="edge1" class="edge">
  <title>expand_spec&#45;&gt;check_expand_spec</title>
  <path d="..."/>
</g>
```

The title contains `source->target` with HTML entity encoding for `->` (`&#45;&gt;`).

### 4.4 Pipeline Tabs

When multiple DOT files are provided via `--dot`, the UI renders a tab bar. Each tab is labeled with the DOT file's graph ID (extracted from the `digraph <name> {` declaration) or the filename if parsing fails.

Switching tabs fetches the DOT file fresh, re-renders the SVG, and clears the CXDB status overlay. The status overlay rebuilds on the next poll cycle.

---

## 5. CXDB Integration

### 5.1 API Endpoints Consumed

The UI reads from CXDB HTTP APIs (default port 9010). All requests go through the server's `/api/cxdb/{index}/*` proxy, where `{index}` identifies the CXDB instance.

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/cxdb/instances` | GET | Server-generated list of configured CXDB instances |
| `/api/cxdb/{i}/v1/contexts` | GET | List all contexts on CXDB instance `i` |
| `/api/cxdb/{i}/v1/contexts/{id}/turns?limit={n}&order={dir}` | GET | Fetch turns for a context on instance `i` |

### 5.2 Context List Response

```
GET /v1/contexts
```

Returns:

```json
{
  "active_sessions": [
    {
      "client_tag": "kilroy/01KJ7JPB3C2AHNP9AYX7D19BWK",
      "session_id": "54",
      "last_activity_at": 1771929214261
    }
  ],
  "active_tags": ["kilroy/01KJ7JPB3C2AHNP9AYX7D19BWK"],
  "contexts": [
    {
      "context_id": "33",
      "created_at_unix_ms": 1771929214262,
      "head_depth": 100,
      "head_turn_id": "6064",
      "is_live": false
    }
  ],
  "count": 20
}
```

### 5.3 Turn Response

```
GET /v1/contexts/{context_id}/turns?limit=20&order=desc
```

Returns:

```json
{
  "meta": {
    "context_id": "33",
    "head_depth": 104,
    "head_turn_id": "6068",
    "registry_bundle_id": "kilroy-attractor-v1#283a6b572820"
  },
  "turns": [
    {
      "data": {
        "node_id": "implement",
        "run_id": "01KJ7JPB3C2AHNP9AYX7D19BWK",
        "tool_name": "shell",
        "arguments_json": "{\"command\":\"cargo test\"}",
        "output": "test result: ok...",
        "is_error": false
      },
      "declared_type": {
        "type_id": "com.kilroy.attractor.ToolResult",
        "type_version": 1
      },
      "depth": 102,
      "turn_id": "6066"
    }
  ]
}
```

### 5.4 Turn Type IDs

| Type ID | Description |
|---------|-------------|
| `com.kilroy.attractor.RunStarted` | First turn in a context. Contains `graph_name` and `graph_dot`. |
| `com.kilroy.attractor.Prompt` | LLM prompt sent to agent |
| `com.kilroy.attractor.ToolCall` | Agent invoked a tool (`tool_name`, `arguments_json`) |
| `com.kilroy.attractor.ToolResult` | Tool result (`output`, `is_error`) |
| `com.kilroy.attractor.GitCheckpoint` | Git commit at node boundary |
| `com.kilroy.attractor.StageStarted` | Node execution began |
| `com.kilroy.attractor.StageFinished` | Node execution completed |
| `com.kilroy.attractor.StageFailed` | Node execution failed |
| `com.kilroy.attractor.ParallelBranchCompleted` | Parallel branch finished |

### 5.5 Pipeline Discovery

CXDB is a generic context store with no first-class pipeline concept. The UI discovers which contexts belong to which pipeline by reading the `RunStarted` turn. When multiple CXDB instances are configured, the UI queries all of them and builds a unified mapping.

**Discovery algorithm:**

```
FUNCTION discoverPipelines(cxdbInstances, knownMappings):
    FOR EACH (index, instance) IN cxdbInstances:
        contexts = fetchContexts(index)

        FOR EACH context IN contexts:
            key = (index, context.context_id)
            IF key IN knownMappings:
                CONTINUE  -- already discovered

            firstTurn = fetchTurns(index, context.context_id, limit=1, order=asc)
            IF firstTurn.declared_type.type_id == "com.kilroy.attractor.RunStarted":
                graphName = firstTurn.data.graph_name
                knownMappings[key] = graphName

    RETURN knownMappings
```

The `graph_name` from the `RunStarted` turn is matched against the graph ID in each loaded DOT file (the identifier after `digraph` in the DOT source). Contexts whose `graph_name` matches the currently displayed pipeline are used for the status overlay — regardless of which CXDB instance they reside on.

**Caching.** The context-to-pipeline mapping is cached in memory, keyed by `(cxdb_index, context_id)`. The `RunStarted` turn is immutable — once a context is mapped, it is never re-fetched. Only newly appeared context IDs trigger discovery requests.

**Cross-instance merging.** If contexts matching the same pipeline exist on multiple CXDB instances (e.g., parallel branches written to separate servers), their turns are merged into a single status map. The UI does not distinguish which CXDB instance a turn came from.

---

## 6. Status Overlay

### 6.1 Polling

The UI polls all configured CXDB instances every 3 seconds using `setInterval`. Each poll cycle:

1. For each CXDB instance, fetch `GET /api/cxdb/{i}/v1/contexts` — get context lists
2. Run pipeline discovery for any new `(index, context_id)` pairs (Section 5.5)
3. For each context matching the active pipeline (across all instances), fetch recent turns
4. Merge turns from all matching contexts, build the node status map (Section 6.2)
5. Apply CSS classes to SVG nodes (Section 6.3)

The polling interval is constant. It does not adapt to pipeline activity or CXDB load. Requests to different CXDB instances within a single poll cycle are issued in parallel.

### 6.2 Node Status Map

The status map associates each DOT node ID with an execution status.

```
TYPE NodeStatus:
    status      : "pending" | "running" | "complete" | "error"
    lastTurnId  : String | null
    toolName    : String | null
    turnCount   : Integer
    errorCount  : Integer
```

**Status derivation algorithm:**

```
FUNCTION buildNodeStatusMap(dotNodeIds, turns):
    map = {}
    FOR EACH nodeId IN dotNodeIds:
        map[nodeId] = NodeStatus { status: "pending", turnCount: 0, errorCount: 0 }

    -- turns are ordered newest-first
    currentNodeId = null

    FOR EACH turn IN turns:
        nodeId = turn.data.node_id
        IF nodeId IS null OR nodeId NOT IN map:
            CONTINUE

        IF currentNodeId IS null:
            currentNodeId = nodeId
            map[nodeId].status = "running"
            map[nodeId].toolName = turn.data.tool_name

        ELSE IF nodeId != currentNodeId:
            -- older turn on a different node: that node completed
            IF map[nodeId].status == "pending":
                map[nodeId].status = "complete"

        IF turn.data.is_error == true:
            map[nodeId].errorCount++

        map[nodeId].turnCount++
        map[nodeId].lastTurnId = turn.turn_id

    -- promote to error if running node has consecutive errors
    IF currentNodeId IS NOT null AND map[currentNodeId].errorCount >= 3:
        map[currentNodeId].status = "error"

    RETURN map
```

When multiple CXDB contexts match the active pipeline (e.g., parallel branches), turns from all contexts are merged and sorted by depth before applying the algorithm. Each context contributes its own "running" node if it is currently active.

### 6.3 CSS Status Classes

After building the status map, the UI walks SVG `<g class="node">` elements and applies CSS classes:

| Status | CSS Class | Visual |
|--------|-----------|--------|
| `pending` | `node-pending` | Gray fill |
| `running` | `node-running` | Blue fill, pulsing animation |
| `complete` | `node-complete` | Green fill |
| `error` | `node-error` | Red fill |

```css
.node-pending polygon, .node-pending ellipse   { fill: #e0e0e0; }
.node-running polygon, .node-running ellipse   { fill: #90caf9; animation: pulse 1.5s infinite; }
.node-complete polygon, .node-complete ellipse  { fill: #a5d6a7; }
.node-error polygon, .node-error ellipse        { fill: #ef9a9a; }

@keyframes pulse {
    0%, 100% { opacity: 1; }
    50%      { opacity: 0.6; }
}
```

Status classes are reapplied on every poll cycle. The SVG itself is not re-rendered — only `data-status` attributes and CSS classes are updated.

---

## 7. Detail Panel

Clicking an SVG node opens a detail panel. The panel displays information from both the DOT file and CXDB.

### 7.1 DOT Attributes

The detail panel parses the DOT source to extract node attributes. These are displayed as static metadata:

| Field | Source | Description |
|-------|--------|-------------|
| Node ID | DOT node identifier | e.g., `implement`, `verify_fmt` |
| Type | DOT `shape` attribute | Human-readable label (e.g., "LLM Task", "Tool Gate") |
| Model Class | DOT `class` attribute | e.g., `hard` (Opus), default (Sonnet) |
| Prompt | DOT `prompt` attribute | Full prompt text, scrollable |
| Tool Command | DOT `tool_command` attribute | Shell command for tool gate nodes |
| Question | DOT `question` attribute | Human gate question text |
| Goal Gate | DOT `goal_gate` attribute | Whether this is a goal gate |

### 7.2 CXDB Activity

The detail panel shows recent CXDB turns for the selected node, filtered from the most recent poll data:

| Column | Source | Description |
|--------|--------|-------------|
| Type | `declared_type.type_id` | Turn type (ToolCall, ToolResult, Prompt) |
| Tool | `data.tool_name` | Tool invoked (e.g., `shell`, `write_file`) |
| Output | `data.output` | Truncated output (expandable) |
| Error | `data.is_error` | Highlighted if true |

Turns are ordered newest-first. The panel shows at most 20 turns per node.

### 7.3 Shape-to-Type Label Mapping

| Shape | Display Label |
|-------|--------------|
| `Mdiamond` | Start |
| `Msquare` | Exit |
| `box` | LLM Task |
| `diamond` | Conditional |
| `parallelogram` | Tool Gate |
| `hexagon` | Human Gate |

---

## 8. UI Layout and Interaction

### 8.1 Layout

```
┌──────────────────────────────────────────────────────┐
│  [Pipeline A] [Pipeline B] [Pipeline C]    ● CXDB OK │
├──────────────────────────────────────┬───────────────┤
│                                      │               │
│           SVG Pipeline Graph         │    Detail     │
│                                      │    Panel      │
│           (rendered from DOT)        │   (sidebar)   │
│                                      │               │
└──────────────────────────────────────┴───────────────┘
```

- **Top bar:** Pipeline tabs (one per `--dot` file), CXDB connection indicator
- **Center:** SVG graph area
- **Right sidebar:** Detail panel (hidden until a node is clicked)

### 8.2 CXDB Connection Indicator

The top bar displays connection status for each configured CXDB instance:

- **Green dot + "CXDB OK":** All instances reachable on last poll
- **Yellow dot + "1/2 CXDB":** Some instances reachable, some not. Hover shows per-instance status.
- **Red dot + "CXDB unreachable":** No instances reachable. Includes the configured URLs for diagnostics.

The indicator updates on every poll cycle. When a CXDB instance is unreachable, the graph remains visible with the last known status from that instance. Polling continues — status resumes automatically when instances become reachable.

### 8.3 Interaction

- **Click node:** Opens detail panel for that node
- **Click outside panel or close button:** Closes detail panel
- **Click pipeline tab:** Switches to that pipeline's DOT file, re-renders SVG
- **Browser zoom (Ctrl+scroll):** Zooms the SVG natively

---

## 9. Invariants

### Graph Rendering

1. **Every DOT node appears in the SVG.** The UI does not filter, hide, or skip nodes. The graph is rendered as-is by Graphviz WASM.

2. **SVG rendering is deterministic.** The same DOT input always produces the same SVG layout. Node positions are determined entirely by Graphviz, not by the UI.

3. **Graph renders without CXDB.** If CXDB is unreachable, the graph renders with all nodes in pending (gray) state. CXDB is an overlay, not a prerequisite.

4. **DOT files are never modified.** The UI reads DOT files. It never writes to them.

### Status Overlay

5. **Status is derived from CXDB turns, never fabricated.** A node is "running" only if its `node_id` appears on the most recent CXDB turn. A node is "complete" only if a later node has activity. The UI does not infer status beyond what the turn data provides.

6. **Status is mutually exclusive.** Every node has exactly one status: `pending`, `running`, `complete`, or `error`.

7. **Polling interval is constant at 3 seconds.** It does not back off, speed up, or adapt.

8. **Unknown node IDs in CXDB are ignored.** If a turn references a `node_id` not in the loaded DOT file, the UI silently skips it.

9. **Pipeline scoping is strict.** The status overlay only uses CXDB contexts whose `RunStarted` turn's `graph_name` matches the active DOT file's graph ID. Turns from unrelated contexts never appear. This holds across all configured CXDB instances.

10. **Context-to-pipeline mapping is immutable.** Once a context is mapped to a pipeline via its `RunStarted` turn, the mapping is never re-evaluated. The `RunStarted` turn does not change. Mappings are keyed by `(cxdb_index, context_id)`.

11. **CXDB instances are polled independently.** A single unreachable CXDB instance does not prevent polling of other instances. The connection indicator shows per-instance status.

### Server

12. **The server is stateless.** It caches nothing. Every DOT request reads from disk. Every CXDB request is proxied in real time.

13. **Only registered DOT files are servable.** The `/dots/` endpoint serves only files registered via `--dot` flags. Unregistered filenames return 404.

14. **CXDB proxy is transparent.** Requests and responses are forwarded without modification.

### Detail Panel

15. **Content is displayed verbatim.** Prompt text, tool commands, and CXDB output are shown as-is (with HTML escaping for XSS prevention). The UI does not summarize or reformat.

---

## 10. Non-Goals

1. **No pipeline editing.** The UI is read-only. Pipeline modification uses the YAML → compile → DOT workflow.

2. **No execution control.** The UI does not start, stop, pause, or resume pipeline runs.

3. **No CXDB writes.** The UI never writes to CXDB.

4. **No authentication.** This is a local developer tool. No login, no sessions, no access control.

5. **No persistent state.** Closing the browser discards all UI state. Nothing is saved to disk or localStorage.

6. **No custom graph layout.** The UI uses Graphviz's layout engine as-is. Users cannot rearrange nodes.

7. **No historical playback.** The UI shows current or final state. There is no timeline slider or step-through mode.

8. **No JS build toolchain.** No npm, webpack, bundler, TypeScript, or framework. A single HTML file with CDN imports.

9. **No mobile support.** The UI targets desktop browsers at 1200px+ width.

10. **No notifications.** The UI does not produce desktop notifications, sounds, or alerts.

---

## 11. Definition of Done

### Core Functionality

- [ ] `go run ui/main.go --dot <path>` starts the server and prints the URL
- [ ] Multiple `--dot` flags register multiple pipelines
- [ ] `GET /` serves the dashboard HTML
- [ ] `GET /dots/{name}` serves registered DOT files, returns 404 for others
- [ ] `GET /api/cxdb/{i}/*` proxies to the corresponding CXDB instance
- [ ] `GET /api/cxdb/instances` returns the configured CXDB URLs
- [ ] Multiple `--cxdb` flags register multiple CXDB instances
- [ ] DOT file rendered as SVG in the browser via `@hpcc-js/wasm-graphviz`
- [ ] All node shapes render correctly (Mdiamond, Msquare, box, diamond, parallelogram, hexagon)
- [ ] Pipeline tabs switch between loaded DOT files

### CXDB Integration

- [ ] UI polls CXDB every 3 seconds
- [ ] Pipeline discovery via `RunStarted` turn's `graph_name` field
- [ ] Context-to-pipeline mapping is cached (no redundant discovery requests)
- [ ] Nodes colored by status: gray (pending), blue/pulse (running), green (complete), red (error)
- [ ] Status overlay updates without re-rendering the SVG
- [ ] Connection indicator shows per-instance CXDB reachable/unreachable state
- [ ] Pipeline discovery works across multiple CXDB instances
- [ ] Unreachable CXDB instance does not block polling of other instances

### Detail Panel

- [ ] Clicking a node opens the detail panel
- [ ] Panel shows DOT attributes: node ID, type, prompt, tool_command, question
- [ ] Panel shows recent CXDB turns: type, tool name, output, error flag
- [ ] Panel closes on click-outside or close button

### Resilience

- [ ] Graph renders when CXDB is unreachable
- [ ] CXDB status resumes automatically when CXDB becomes reachable
- [ ] DOT file changes are picked up on tab switch (no server restart needed)
- [ ] DOT syntax errors display an error message instead of crashing

### Security

- [ ] `/dots/` only serves files registered via `--dot` (no path traversal)
- [ ] All user-sourced content in the detail panel is HTML-escaped
