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

#### `GET /dots/{name}/nodes` — DOT Node Attributes

Returns a JSON object mapping node IDs to their parsed DOT attributes for the named DOT file.

```json
{
  "implement": {
    "shape": "box",
    "class": "hard",
    "prompt": "Implement the feature according to the spec...",
    "tool_command": null,
    "question": null,
    "goal_gate": null
  },
  "check_fmt": {
    "shape": "parallelogram",
    "class": null,
    "prompt": null,
    "tool_command": "cargo fmt --check",
    "question": null,
    "goal_gate": null
  }
}
```

The server parses node attribute blocks from the DOT source. Parsing rules:

- **Attribute syntax:** Both quoted (`key="value"`) and unquoted (`key=value`) attribute values are supported.
- **Named nodes only:** Global default blocks (`node [...]`, `edge [...]`, `graph [...]`) are excluded. Only named node definitions (e.g., `implement [shape=box, prompt="..."]`) are parsed.
- **Subgraph scope:** Nodes defined inside `subgraph` blocks are included.
- **Escape sequences:** Quoted attribute values support these DOT escapes: `\"` → `"`, `\n` → newline, `\\` → `\`. Other escape sequences are passed through verbatim.

The file is read fresh on each request. Returns 404 if the DOT file is not registered.

#### `GET /api/cxdb/{index}/*` — CXDB Reverse Proxy

Each `--cxdb` flag registers a CXDB instance at a zero-based index. The proxy route includes the index to disambiguate instances.

- `/api/cxdb/0/v1/contexts` → first `--cxdb` URL + `/v1/contexts`
- `/api/cxdb/1/v1/contexts` → second `--cxdb` URL + `/v1/contexts`

The server strips `/api/cxdb/{index}` and forwards the remainder to the corresponding CXDB base URL.

- Request and response bodies are passed through unmodified.
- No header injection, body rewriting, or caching.
- If a CXDB instance is unreachable, returns 502 Bad Gateway for that index.
- Index out of range returns 404.

#### `GET /api/dots` — DOT File List

Returns a JSON array of available DOT filenames (registered via `--dot` flags). This is a server-generated response used by the browser to build pipeline tabs.

```json
{ "dots": ["pipeline-alpha.dot", "pipeline-beta.dot"] }
```

#### `GET /api/cxdb/instances` — CXDB Instance List

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

The browser loads `@hpcc-js/wasm-graphviz` from jsDelivr CDN at a pinned version:

```
https://cdn.jsdelivr.net/npm/@hpcc-js/wasm-graphviz@1.6.1/dist/index.min.js
```

This library compiles Graphviz to WebAssembly and exposes a `Graphviz.load()` async factory that returns an instance with a `layout(dotString, "svg", "dot")` method. The UI calls this with the raw DOT file content fetched from `/dots/{name}`. The resulting SVG is injected into the main content area.

If the CDN is unreachable, the WASM module fails to load and the graph area displays an error message. The rest of the UI (tabs, connection indicator) still renders.

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

When multiple DOT files are provided via `--dot`, the UI renders a tab bar. Each tab is labeled with the DOT file's graph ID or the filename as a fallback.

**Graph ID extraction.** The browser extracts the graph ID from the DOT source when the file is first fetched, using a regex pattern that handles both quoted and unquoted names: `/digraph\s+("(?:[^"\\]|\\.)*"|\w+)/`. If the regex does not match (e.g., the DOT file uses `graph` instead of `digraph`, or has unusual formatting), the tab falls back to the base filename. Tabs initially display filenames (from the `/api/dots` response) and update to graph IDs as each DOT file is fetched and parsed.

Switching tabs fetches the DOT file fresh and re-renders the SVG. If a cached status map exists for the newly selected pipeline (from a previous poll cycle), it is immediately reapplied to the new SVG. Otherwise, all nodes start as pending. The next poll cycle refreshes the status with live data. This avoids a gray flash when switching between tabs for pipelines that have already been polled.

### 4.5 Initialization Sequence

When the browser loads `index.html`, the following sequence executes:

1. **Load Graphviz WASM** — Import `@hpcc-js/wasm-graphviz` from CDN. During loading, the graph area shows "Loading Graphviz...".
2. **Fetch DOT file list** — `GET /api/dots` returns available DOT filenames. Build the tab bar.
3. **Fetch CXDB instance list** — `GET /api/cxdb/instances` returns configured CXDB URLs.
4. **Render first pipeline** — Fetch the first DOT file via `GET /dots/{name}`, render it as SVG.
5. **Start polling** — Trigger the first CXDB poll immediately (t=0). After each poll completes, schedule the next poll 3 seconds later via `setTimeout`. The first poll triggers pipeline discovery for all contexts.

Steps 2 and 3 run in parallel. Step 4 requires steps 1 and 2 to complete. Step 5 requires step 3 to complete but does not block on step 4.

---

## 5. CXDB Integration

### 5.1 API Endpoints Consumed

The UI reads from CXDB HTTP APIs (default port 9010). All requests go through the server's `/api/cxdb/{index}/*` proxy, where `{index}` identifies the CXDB instance.

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/cxdb/instances` | GET | Server-generated list of configured CXDB instances |
| `/api/cxdb/{i}/v1/contexts` | GET | List all contexts on CXDB instance `i` |
| `/api/cxdb/{i}/v1/contexts/{id}/turns?limit={n}&before_turn_id={id}` | GET | Fetch turns for a context on instance `i` |

### 5.2 Context List Response

```
GET /v1/contexts
```

The endpoint supports a `tag` query parameter for server-side filtering: `GET /v1/contexts?tag=kilroy/...` returns only contexts whose `client_tag` matches the given value exactly. The UI uses this to filter for Kilroy contexts (see Section 5.5).

Returns:

```json
{
  "active_sessions": [
    {
      "client_tag": "kilroy/01KJ7JPB3C2AHNP9AYX7D19BWK",
      "session_id": "54",
      "connected_at": 1771929210000,
      "last_activity_at": 1771929214261,
      "context_count": 2,
      "peer_addr": "127.0.0.1:54321"
    }
  ],
  "active_tags": ["kilroy/01KJ7JPB3C2AHNP9AYX7D19BWK"],
  "contexts": [
    {
      "context_id": "33",
      "created_at_unix_ms": 1771929214262,
      "head_depth": 100,
      "head_turn_id": "6064",
      "is_live": false,
      "client_tag": "kilroy/01KJ7JPB3C2AHNP9AYX7D19BWK"
    }
  ],
  "count": 20
}
```

Each context object includes a `client_tag` field (optional string) identifying the application that created it. Kilroy sets this to `kilroy/{run_id}`. The `is_live` field is `true` when the context has an active session writing to it. Additional fields (`title`, `labels`, `session_id`, `last_activity_at`) may be present but are unused by the UI.

### 5.3 Turn Response

```
GET /v1/contexts/{context_id}/turns?limit=100
```

Returns (turns are always ordered newest-first; CXDB does not support ascending order):

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
      "decoded_as": {
        "type_id": "com.kilroy.attractor.ToolResult",
        "type_version": 1
      },
      "depth": 102,
      "turn_id": "6066",
      "parent_turn_id": "6065"
    }
  ],
  "next_before_turn_id": "6066"
}
```

**Query parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `limit` | `64` | Maximum number of turns to return (1–65535) |
| `before_turn_id` | `0` | Pagination cursor. When `0` (default), returns the most recent turns. When set to a turn ID, returns turns older than that ID. Use `next_before_turn_id` from the previous response to fetch the next page. |
| `view` | `typed` | Response format: `typed` (decoded JSON), `raw` (msgpack), or `both` |

**Response fields:**

- `declared_type` — the type as written by the client when the turn was appended.
- `decoded_as` — the type after registry resolution. May differ from `declared_type` when `type_hint_mode` is `latest` or `explicit`. The UI uses `declared_type.type_id` for type matching (sufficient because Attractor types do not use version migration).
- `next_before_turn_id` — pagination cursor for fetching older turns. Pass this as the `before_turn_id` query parameter to get the next page. `null` when there are no more turns.
- `parent_turn_id` — the turn this was appended after (present but unused by the UI).

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

The algorithm has two phases: (1) identify Kilroy contexts using `client_tag`, and (2) fetch the `RunStarted` turn to extract `graph_name` and `run_id`.

Kilroy contexts are identified by their `client_tag`, which follows the format `kilroy/{run_id}`. The contexts endpoint supports server-side filtering via the `tag` query parameter, but since the `run_id` portion varies, the UI fetches all contexts and filters client-side by prefix.

```
FUNCTION discoverPipelines(cxdbInstances, knownMappings):
    FOR EACH (index, instance) IN cxdbInstances:
        contexts = fetchContexts(index)

        FOR EACH context IN contexts:
            key = (index, context.context_id)
            IF key IN knownMappings:
                CONTINUE  -- already discovered (positive or negative)

            -- Phase 1: Filter by client_tag prefix
            IF context.client_tag IS null OR NOT context.client_tag.startsWith("kilroy/"):
                knownMappings[key] = null  -- not a Kilroy context
                CONTINUE

            -- Phase 2: Fetch RunStarted turn (first turn of the context)
            firstTurn = fetchFirstTurn(index, context.context_id, context.head_depth)
            IF firstTurn IS NOT null AND firstTurn.declared_type.type_id == "com.kilroy.attractor.RunStarted":
                graphName = firstTurn.data.graph_name
                runId = firstTurn.data.run_id
                knownMappings[key] = { graphName, runId }
            ELSE:
                knownMappings[key] = null  -- has kilroy tag but unexpected first turn

    RETURN knownMappings
```

**Fetching the first turn.** CXDB returns turns newest-first and does not support ascending order. The `before_turn_id` parameter paginates backward from a given turn ID. To reach the first turn of a context, the algorithm requests up to `headDepth + 1` turns (capped at the CXDB maximum of 65,535) to fetch the entire context in as few requests as possible:

```
FUNCTION fetchFirstTurn(cxdbIndex, contextId, headDepth):
    IF headDepth == 0:
        -- Context has exactly one turn; limit=1 returns it
        RETURN fetchTurns(cxdbIndex, contextId, limit=1).turns[0]

    -- Fetch the entire context in one request when possible.
    -- headDepth + 1 = total turn count. CXDB limit max is 65535.
    fetchLimit = min(headDepth + 1, 65535)

    -- Paginate backward to the oldest turn.
    cursor = 0  -- 0 means "start from newest"
    lastTurns = null
    LOOP:
        response = fetchTurns(cxdbIndex, contextId, limit=fetchLimit, before_turn_id=cursor)
        IF response.turns IS EMPTY:
            BREAK
        lastTurns = response.turns
        IF response.next_before_turn_id IS null:
            BREAK  -- reached the oldest page
        cursor = response.next_before_turn_id

    -- The last element of the final page is the oldest (first) turn
    IF lastTurns IS NOT null:
        RETURN lastTurns[lastTurns.length - 1]
    RETURN null
```

For contexts with ≤65,535 turns (virtually all Kilroy pipelines), the first turn is fetched in a single request. Contexts exceeding 65,535 turns require at most `ceil(headDepth / 65535)` requests. This runs once per context (results are cached). The `client_tag` prefix filter (Phase 1) ensures pagination only runs for Kilroy contexts, not for unrelated contexts that may share the CXDB instance.

The `graph_name` from the `RunStarted` turn is matched against the graph ID in each loaded DOT file (the identifier after `digraph` in the DOT source). Contexts whose `graph_name` matches the currently displayed pipeline are used for the status overlay — regardless of which CXDB instance they reside on.

The `RunStarted` turn also contains a `run_id` field that uniquely identifies the pipeline run. All contexts belonging to the same run (e.g., parallel branches) share the same `run_id`. The discovery algorithm records both `graph_name` and `run_id` for each context.

**Caching.** The context-to-pipeline mapping is cached in memory, keyed by `(cxdb_index, context_id)`. Both positive results (RunStarted contexts mapped to a pipeline) and negative results (non-Kilroy contexts and non-RunStarted contexts stored as `null`) are cached. The first turn of a context is immutable — once a context is classified, it is never re-fetched. Only newly appeared context IDs trigger discovery requests. The `client_tag` prefix filter prevents fetching turns for non-Kilroy contexts entirely.

**Multiple runs of the same pipeline.** When CXDB contains contexts from multiple runs of the same pipeline (same `graph_name`, different `run_id`), the UI uses only the most recent run. The most recent run is determined by the highest `created_at_unix_ms` among the `RunStarted` contexts for that pipeline. Contexts from older runs are ignored for status overlay purposes. This prevents stale data from a completed run from conflicting with an in-progress run.

**Cross-instance merging.** If contexts from the same run (same `run_id`) exist on multiple CXDB instances (e.g., parallel branches written to separate servers), their turns are merged into a single status map. The UI does not distinguish which CXDB instance a turn came from.

---

## 6. Status Overlay

### 6.1 Polling

The UI polls all configured CXDB instances every 3 seconds. Each poll cycle:

1. For each CXDB instance, fetch `GET /api/cxdb/{i}/v1/contexts` — get context lists. If an instance is unreachable (502), skip it and retain its per-context status maps from the last successful poll.
2. Run pipeline discovery for any new `(index, context_id)` pairs (Section 5.5)
3. **Determine active run per pipeline.** For each loaded pipeline, group discovered contexts by `run_id`. The active run is the one whose contexts have the highest `created_at_unix_ms` value. Contexts from non-active runs are excluded from steps 4–7. When the active `run_id` changes for a pipeline (a new run has started), reset all per-context status maps and `lastSeenTurnId` cursors for that pipeline's old-run contexts, and clear the per-pipeline turn cache (step 5) for that pipeline. This implements the "most recent run" rule described in Section 5.5.
4. For each context in the **active run** of **any loaded pipeline** (across all instances), fetch recent turns: `GET /api/cxdb/{i}/v1/contexts/{id}/turns?limit=100` (returns newest-first by default). Turns are fetched for all pipelines, not just the active tab — this ensures per-context status maps stay current for inactive pipelines, preventing stale data on tab switch.
5. **Cache raw turns** — Store the raw turn arrays from step 4 in a per-pipeline turn cache, keyed by `(cxdb_index, context_id)`. This cache is replaced (not appended) on each successful fetch. When a CXDB instance is unreachable, its entries in the turn cache are retained from the previous successful fetch. The detail panel (Section 7.2) reads from this cache.
6. Run `updateContextStatusMap` per context (updating persistent per-context maps and advancing each context's `lastSeenTurnId` cursor), then `mergeStatusMaps` across **active-run** contexts for the **active pipeline** (Section 6.2). Per-context maps for inactive pipelines are also updated but their merged maps are not computed until the user switches to that tab. Per-context status maps from unreachable instances are included in the merge using their cached values.
7. Apply CSS classes to SVG nodes for the active pipeline (Section 6.3)

**Poll scheduling.** The poller uses `setTimeout` (not `setInterval`). After a poll cycle completes, the next poll is scheduled 3 seconds later. This prevents overlapping poll cycles when CXDB instances respond slowly — at most one poll cycle is in flight at any time. The effective interval is 3 seconds plus poll execution time.

The polling interval is constant. It does not adapt to pipeline activity or CXDB load. Requests to different CXDB instances within a single poll cycle are issued in parallel.

**Status caching on failure.** The UI retains per-context status maps from the last successful poll. When a CXDB instance is unreachable, its contexts' status maps are not discarded — they participate in the merge using cached values. This ensures that status is preserved (not reverted to "pending") when a CXDB instance goes down temporarily. Cached status maps are only replaced when fresh data is successfully fetched for that context.

**Turn fetch limit.** Each context poll fetches at most 100 recent turns (`limit=100`; CXDB always returns turns newest-first). This window may not contain lifecycle turns for nodes that completed early in a long-running pipeline. The persistent status map (Section 6.2) ensures completed nodes retain their status even when their lifecycle turns fall outside this window.

**Gap recovery.** After step 4, if any context's fetched turns do not reach back to `lastSeenTurnId` (i.e., the oldest fetched turn has `turn_id > lastSeenTurnId + 1`, using numeric comparison), the poller issues additional paginated requests using `before_turn_id` to fetch the missing turns until `lastSeenTurnId` is reached or `next_before_turn_id` is null. This ensures lifecycle events (e.g., `StageFinished`) that occurred during a CXDB outage are not permanently lost. Gap recovery runs at most once per context per poll cycle and is bounded by the number of turns missed (typically one additional request per 100 missed turns). The recovered turns are prepended (in oldest-first order) to the context's turn batch before step 5 caches them and step 6 processes them for status derivation.

### 6.2 Node Status Map

The status map associates each DOT node ID with an execution status. The status map is **persistent** — it accumulates across poll cycles rather than being recomputed from scratch. This prevents completed nodes from reverting to "pending" when their lifecycle turns fall outside the 100-turn fetch window.

```
TYPE NodeStatus:
    status      : "pending" | "running" | "complete" | "error"
    lastTurnId  : String | null
    toolName    : String | null
    turnCount   : Integer
    errorCount  : Integer
```

**Status map lifecycle:**

1. A new status map is initialized (all nodes "pending") when a pipeline is first displayed.
2. On each poll cycle, fetched turns are processed and node statuses are **promoted** according to the precedence `pending < running < complete < error`. Statuses are never demoted.
3. The status map is **reset** (all nodes back to "pending") only when the active `run_id` changes — i.e., a new run of the same pipeline is detected (Section 5.5).

**Turn ID comparison.** CXDB turn IDs are numeric strings (e.g., `"6066"`). All turn ID comparisons in the UI — including the deduplication check, `lastSeenTurnId` tracking, and `lastTurnId` on `NodeStatus` — must use numeric ordering: `parseInt(turn.turn_id, 10)`. The `<=` operator on turn IDs in the pseudocode below denotes numeric comparison, not lexicographic string comparison. Lexicographic comparison breaks for IDs of different lengths (e.g., `"999" > "1000"` lexicographically).

**Status derivation algorithm (per context):**

The algorithm processes turns from a single CXDB context and promotes statuses in an existing per-context status map. When multiple contexts match the active pipeline (e.g., parallel branches), the algorithm runs independently per context and the results are merged (see below).

```
FUNCTION updateContextStatusMap(existingMap, dotNodeIds, turns, lastSeenTurnId):
    -- Initialize entries for any new node IDs not yet in the map
    FOR EACH nodeId IN dotNodeIds:
        IF nodeId NOT IN existingMap:
            existingMap[nodeId] = NodeStatus { status: "pending", turnCount: 0, errorCount: 0 }

    PRECEDENCE = { "error": 3, "running": 2, "complete": 1, "pending": 0 }

    -- Track the newest turn ID in this batch for the next poll cycle
    newLastSeenTurnId = lastSeenTurnId

    -- turns are ordered newest-first
    FOR EACH turn IN turns:
        -- Skip turns already processed in a previous poll cycle
        IF lastSeenTurnId IS NOT null AND turn.turn_id <= lastSeenTurnId:
            BREAK  -- all remaining turns are older, stop processing

        -- Record the newest turn ID (first iteration only, since turns are newest-first)
        IF newLastSeenTurnId == lastSeenTurnId:
            newLastSeenTurnId = turn.turn_id

        nodeId = turn.data.node_id
        typeId = turn.declared_type.type_id
        IF nodeId IS null OR nodeId NOT IN existingMap:
            CONTINUE

        -- Determine the status this turn implies
        newStatus = null
        IF typeId == "com.kilroy.attractor.StageFinished":
            newStatus = "complete"
        ELSE IF typeId == "com.kilroy.attractor.StageFailed":
            newStatus = "error"
        ELSE IF typeId == "com.kilroy.attractor.StageStarted":
            newStatus = "running"
        ELSE:
            -- Non-lifecycle turns: infer running
            newStatus = "running"

        -- Only promote, never demote (except: error always wins)
        IF newStatus == "error" OR PRECEDENCE[newStatus] > PRECEDENCE[existingMap[nodeId].status]:
            existingMap[nodeId].status = newStatus

        IF turn.data.is_error == true:
            existingMap[nodeId].errorCount++

        existingMap[nodeId].turnCount++
        IF existingMap[nodeId].toolName IS null:
            existingMap[nodeId].toolName = turn.data.tool_name

        -- Update lastTurnId to the most recent turn for this node (numeric comparison)
        IF existingMap[nodeId].lastTurnId IS null
           OR turn.turn_id > existingMap[nodeId].lastTurnId:
            existingMap[nodeId].lastTurnId = turn.turn_id

    -- Heuristic fallback: promote to error if running node has 3+ errors
    -- (only applies when no StageFailed turn was present)
    FOR EACH nodeId IN dotNodeIds:
        IF existingMap[nodeId].status == "running" AND existingMap[nodeId].errorCount >= 3:
            existingMap[nodeId].status = "error"

    RETURN (existingMap, newLastSeenTurnId)
```

**Turn deduplication.** Each per-context status map tracks a `lastSeenTurnId` — the newest `turn_id` processed in the previous poll cycle. On each poll, the algorithm skips turns with `turn_id <= lastSeenTurnId`, processing only newly appended turns. Since CXDB returns turns newest-first, the algorithm breaks out of the loop as soon as it hits a previously-seen turn. This prevents `turnCount` and `errorCount` from being inflated by re-processing overlapping turns across poll cycles. The cursor is initialized to `null` (process all turns) when a context is first discovered, and resets to `null` when the active `run_id` changes.

**lastTurnId assignment.** The `lastTurnId` field on `NodeStatus` records the most recent turn for that node. It is updated whenever a turn's `turn_id` exceeds the stored value (using numeric comparison). Within a single poll batch, the first encounter per node captures the newest turn ID (since turns arrive newest-first). Across poll cycles, new turns always have higher IDs than previously stored values (due to deduplication), so `lastTurnId` correctly advances to reflect the latest activity for each node.

**Lifecycle turn precedence.** Because turns are processed newest-first, the most recent lifecycle event takes priority. A `StageFinished` turn definitively marks a node "complete" — even for the last node in a pipeline, which has no subsequent node to trigger the heuristic. A `StageFailed` turn definitively marks a node "error" regardless of the error count heuristic. The promotion-only rule ensures that once a node is marked "complete" or "error", it retains that status even when its lifecycle turns fall outside the 100-turn fetch window on subsequent polls.

**Multi-context merging.** When multiple CXDB contexts match the active pipeline (e.g., parallel branches), the algorithm runs independently per context, producing one per-context status map. The per-context maps are then merged into a single display map using the following precedence (highest wins):

```
error > running > complete > pending
```

```
FUNCTION mergeStatusMaps(dotNodeIds, perContextMaps):
    PRECEDENCE = { "error": 3, "running": 2, "complete": 1, "pending": 0 }
    merged = {}
    FOR EACH nodeId IN dotNodeIds:
        merged[nodeId] = NodeStatus { status: "pending", turnCount: 0, errorCount: 0 }
        FOR EACH contextMap IN perContextMaps:
            contextStatus = contextMap[nodeId]
            IF PRECEDENCE[contextStatus.status] > PRECEDENCE[merged[nodeId].status]:
                merged[nodeId].status = contextStatus.status
                merged[nodeId].toolName = contextStatus.toolName
                merged[nodeId].lastTurnId = contextStatus.lastTurnId
            merged[nodeId].turnCount += contextStatus.turnCount
            merged[nodeId].errorCount += contextStatus.errorCount
    RETURN merged
```

This ensures that parallel branches each contribute their own "running" node, and a node that is "running" in one context but "complete" in another shows as "running." The per-context maps are persistent (accumulated across polls); the merged map is recomputed each poll cycle from the current per-context maps.

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

The detail panel displays node attributes extracted from the DOT source. Attributes are parsed server-side and served via `GET /dots/{name}/nodes` (see Section 3.2). This avoids complex DOT parsing in browser JavaScript.

| Field | Source | Description |
|-------|--------|-------------|
| Node ID | DOT node identifier | e.g., `implement`, `verify_fmt` |
| Type | DOT `shape` attribute | Human-readable label (e.g., "LLM Task", "Tool Gate") |
| Model Class | DOT `class` attribute | e.g., `hard` (Opus), default (Sonnet) |
| Prompt | DOT `prompt` attribute | Full prompt text, scrollable |
| Tool Command | DOT `tool_command` attribute | Shell command for tool gate nodes |
| Question | DOT `question` attribute | Human gate question text |
| Goal Gate | DOT `goal_gate` attribute | Boolean flag — if `"true"`, this conditional node acts as a goal gate (displayed as a badge on the detail panel header). Goal gates use the same `diamond` shape as regular conditionals. |

### 7.2 CXDB Activity

The detail panel shows recent CXDB turns for the selected node. Turns are sourced from the per-pipeline turn cache (Section 6.1, step 4), filtered to those where `turn.data.node_id` matches the selected node's DOT ID. When the selected node has matching turns across multiple contexts (e.g., parallel branches), turns from all matching contexts are combined and sorted newest-first by `turn_id` (using numeric comparison — see Section 6.2).

| Column | Source | Description |
|--------|--------|-------------|
| Type | `declared_type.type_id` | Turn type (ToolCall, ToolResult, Prompt) |
| Tool | `data.tool_name` | Tool invoked (e.g., `shell`, `write_file`) |
| Output | `data.output` | Truncated output (expandable) |
| Error | `data.is_error` | Highlighted if true |

Turns are ordered newest-first. The panel shows at most 20 turns per node. If all of a node's turns have scrolled out of the 100-turn poll window (i.e., the node completed early and subsequent nodes have generated many turns), the detail panel shows the node's DOT attributes but displays "No recent CXDB activity" in place of the turn list. The node's status remains correct via the persistent status map (Section 6.2).

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

5. **Status is derived from CXDB turns, never fabricated.** A node's status is determined primarily by lifecycle turns (`StageStarted` → running, `StageFinished` → complete, `StageFailed` → error). When lifecycle turns are absent, a heuristic fallback infers status from turn activity. The UI does not infer status beyond what the turn data provides.

6. **Status is mutually exclusive.** Every node has exactly one status: `pending`, `running`, `complete`, or `error`.

7. **Polling delay is constant at 3 seconds.** After each poll cycle completes, the next poll is scheduled 3 seconds later via `setTimeout`. At most one poll cycle is in flight at any time. The delay does not back off, speed up, or adapt.

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

11. **No SSE event streaming.** CXDB exposes a `/v1/events` Server-Sent Events endpoint for real-time push notifications (e.g., `TurnAppended`, `ContextCreated`). The UI uses polling instead for simplicity — no persistent connection management, simpler error recovery, and 3-second latency is sufficient for the "mission control" use case.

---

## 11. Definition of Done

### Core Functionality

- [ ] `go run ui/main.go --dot <path>` starts the server and prints the URL
- [ ] Multiple `--dot` flags register multiple pipelines
- [ ] `GET /` serves the dashboard HTML
- [ ] `GET /dots/{name}` serves registered DOT files, returns 404 for others
- [ ] `GET /dots/{name}/nodes` returns parsed DOT node attributes as JSON
- [ ] `GET /api/dots` returns the list of available DOT filenames
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
- [ ] Status derived from StageStarted/StageFinished/StageFailed lifecycle turns when present
- [ ] Multiple runs of the same pipeline: only the most recent run_id is used
- [ ] Parallel branch contexts merged with precedence: error > running > complete > pending
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
