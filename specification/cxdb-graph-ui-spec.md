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

**Why a proxy for CXDB.** CXDB's REST endpoints (contexts, turns) do not set CORS headers. The SSE endpoint (`/v1/events`) does set `Access-Control-Allow-Origin: *`, but the UI uses polling, not SSE (Section 10). The browser cannot fetch from a different origin for the REST endpoints. The Go server reverse-proxies `/api/cxdb/*` to CXDB, putting all requests on a single origin. When multiple CXDB instances are configured, the server proxies each under a numeric index (`/api/cxdb/0/*`, `/api/cxdb/1/*`, etc.).

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

- The server builds a map from base filename to absolute path at startup. If two `--dot` flags resolve to the same base filename (e.g., `pipelines/alpha/pipeline.dot` and `pipelines/beta/pipeline.dot` both have basename `pipeline.dot`), the server exits with a non-zero code and prints an error identifying the conflicting paths. This prevents silent collisions where one pipeline becomes unreachable.
- **Graph ID uniqueness.** At startup, the server parses each DOT file to extract its graph ID (the identifier after `digraph`). If two DOT files share the same graph ID, the server exits with a non-zero code and prints an error identifying the conflicting files and graph ID. Duplicate graph IDs would cause ambiguous pipeline discovery — both pipelines would match the same CXDB contexts, producing identical and misleading status overlays. This check mirrors the basename collision check and runs at startup alongside it.
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
- **String concatenation:** Quoted values support the DOT `+` concatenation operator: `prompt="first part" + "second part"` is equivalent to `prompt="first partsecond part"` (fragments are joined with no separator, per DOT semantics). The parser must handle `+` between consecutive quoted strings within an attribute value.
- **Multi-line quoted values:** Quoted attribute values may span literal newlines. A value that begins with `"` extends to the next unescaped `"`, regardless of intervening newlines. A line-by-line parser is insufficient — the parser must handle multi-line strings.
- **Named nodes only:** Global default blocks (`node [...]`, `edge [...]`, `graph [...]`) are excluded. Only named node definitions (e.g., `implement [shape=box, prompt="..."]`) are parsed.
- **Subgraph scope:** Nodes defined inside `subgraph` blocks are included.
- **Escape sequences:** Quoted attribute values support these DOT escapes: `\"` → `"`, `\n` → newline, `\\` → `\`. Other escape sequences are passed through verbatim.

The file is read fresh on each request. Returns 404 if the DOT file is not registered.

#### `GET /dots/{name}/edges` — DOT Edge List

Returns a JSON array of edges parsed from the named DOT file. Each edge includes the source node, target node, and label (if present).

```json
[
  { "source": "check_goal", "target": "implement", "label": "fail" },
  { "source": "check_goal", "target": "done", "label": "pass" },
  { "source": "implement", "target": "check_fmt", "label": null }
]
```

The server parses edge statements from the DOT source (`source -> target` syntax). Edge labels come from the `label` attribute in the edge's attribute block (e.g., `check_goal -> done [label="pass"]`). Edges without a `label` attribute have `label: null`. Edges inside `subgraph` blocks are included.

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

Returns a JSON object with a `dots` array containing the available DOT filenames (registered via `--dot` flags). This is a server-generated response used by the browser to build pipeline tabs.

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
STATUS_CLASSES = ["node-pending", "node-running", "node-complete", "node-error", "node-stale"]

FOR EACH g IN svg.querySelectorAll('g.node'):
    nodeId = g.querySelector('title').textContent.trim()
    status = nodeStatusMap[nodeId] OR "pending"
    g.setAttribute('data-status', status)
    g.classList.remove(...STATUS_CLASSES)
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
2. **Fetch DOT file list** — `GET /api/dots` returns available DOT filenames (as a JSON object with a `dots` array). Build the tab bar.
3. **Fetch CXDB instance list** — `GET /api/cxdb/instances` returns configured CXDB URLs.
4. **Prefetch node IDs for all pipelines** — For every DOT filename returned by `/api/dots`, fetch `GET /dots/{name}/nodes` to obtain `dotNodeIds` for each pipeline. This ensures that background polling (step 6) can compute per-context status maps for all pipelines from the first poll cycle, not just the active tab. Without this, the holdout scenario "Switch between pipeline tabs" (which expects cached status to be immediately reapplied with no gray flash) cannot be satisfied.
5. **Render first pipeline** — Fetch the first DOT file via `GET /dots/{name}`, render it as SVG.
6. **Start polling** — Trigger the first CXDB poll immediately (t=0). After each poll completes, schedule the next poll 3 seconds later via `setTimeout`. The first poll triggers pipeline discovery for all contexts.

Steps 2 and 3 run in parallel. Steps 4 and 5 require steps 1 and 2 to complete. Step 4 fetches node IDs for all pipelines in parallel. Step 5 may run concurrently with step 4's requests for non-first pipelines. Step 6 requires steps 3 and 4 to complete but does not block on step 5.

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
GET /v1/contexts?limit=10000
```

The endpoint supports a `limit` query parameter (default: 20) controlling the maximum number of contexts returned. The UI passes `limit=10000` to ensure all contexts are returned — the default of 20 is insufficient when non-Kilroy contexts (e.g., Claude Code sessions) accumulate on the instance. The endpoint also supports a `tag` query parameter for server-side filtering: `GET /v1/contexts?tag=kilroy/...` returns only contexts whose `client_tag` matches the given value exactly. The UI does not use server-side tag filtering because the `run_id` portion of the Kilroy tag varies; instead it fetches all contexts and filters client-side by prefix (see Section 5.5).

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

Each context object includes a `client_tag` field (optional string) identifying the application that created it. Kilroy sets this to `kilroy/{run_id}`. The `is_live` field is `true` when the context has an active session writing to it; the UI uses this for stale pipeline detection (see Section 6.2). Additional fields (`title`, `labels`, `session_id`, `last_activity_at`) may be present but are unused by the UI.

### 5.3 Turn Response

```
GET /v1/contexts/{context_id}/turns?limit=100
```

Returns (turns are always ordered oldest-first — ascending by depth within the context's parent chain):

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
| `limit` | `64` | Maximum number of turns to return (parsed as u32; no server-enforced maximum). The UI uses at most 100 for polling and `headDepth + 1` for discovery. |
| `before_turn_id` | `0` | Pagination cursor. When `0` (default), returns the most recent turns. When set to a turn ID, returns turns older than that ID. Use `next_before_turn_id` from the previous response to fetch the next page. |
| `view` | `typed` | Response format: `typed` (decoded JSON), `raw` (msgpack), or `both` |

**Type registry dependency.** The default `view=typed` format requires every turn's `declared_type` to be registered in CXDB's type registry. For Kilroy turns, this means the `kilroy-attractor-v1` registry bundle (shown in the response's `meta.registry_bundle_id` field) must be published to the CXDB instance before the UI can fetch turns. If any single turn in a context references an unregistered type, the entire turn fetch request for that context fails (CXDB's type resolution is per-turn with no skip-on-error fallback). This can occur during development (before the registry bundle is published), after a version mismatch (newer Attractor types not in the bundle), or in forked contexts that inherit parent turns with non-Kilroy types. The polling algorithm handles this failure mode as a per-context error (see Section 6.1, step 4).

**Response fields:**

- `declared_type` — the type as written by the client when the turn was appended.
- `decoded_as` — the type after registry resolution. May differ from `declared_type` when `type_hint_mode` is `latest` or `explicit`. The UI uses `declared_type.type_id` for type matching (sufficient because Attractor types do not use version migration).
- `next_before_turn_id` — pagination cursor for fetching older turns. Set to the oldest turn's ID in the response; `null` when the response contains no turns. Pass this as the `before_turn_id` query parameter to get the next page. Note: a non-null value means the response was non-empty, not that older turns definitely exist — the definitive "no more pages" signal is `response.turns.length < limit`.
- `parent_turn_id` — the turn this was appended after (present but unused by the UI).

### 5.4 Turn Type IDs

| Type ID | Description | Key Data Fields |
|---------|-------------|-----------------|
| `com.kilroy.attractor.RunStarted` | First turn in a context (pipeline-level) | `graph_name`, `graph_dot`, `run_id` |
| `com.kilroy.attractor.Prompt` | LLM prompt sent to agent | `node_id`, `text` |
| `com.kilroy.attractor.ToolCall` | Agent invoked a tool | `node_id`, `tool_name`, `arguments_json` |
| `com.kilroy.attractor.ToolResult` | Tool result | `node_id`, `tool_name`, `output`, `is_error` |
| `com.kilroy.attractor.GitCheckpoint` | Git commit at node boundary | `node_id` (if present), `sha` |
| `com.kilroy.attractor.StageStarted` | Node execution began | `node_id` |
| `com.kilroy.attractor.StageFinished` | Node execution completed | `node_id` |
| `com.kilroy.attractor.StageFailed` | Node execution failed | `node_id` |
| `com.kilroy.attractor.ParallelBranchCompleted` | Parallel branch finished | `branch_key` |

Types with `node_id` are processed by the status derivation algorithm (Section 6.2). Types without `node_id` (RunStarted, ParallelBranchCompleted) are silently skipped via the `IF nodeId IS null` guard. GitCheckpoint may or may not carry `node_id` depending on context — the null guard handles both cases. These types are defined in the `kilroy-attractor-v1` registry bundle and their fields should be verified against the bundle if field-level details are needed beyond what is documented here.

### 5.5 Pipeline Discovery

CXDB is a generic context store with no first-class pipeline concept. The UI discovers which contexts belong to which pipeline by reading the `RunStarted` turn. When multiple CXDB instances are configured, the UI queries all of them and builds a unified mapping.

**Discovery algorithm:**

The algorithm has two phases: (1) identify Kilroy contexts using `client_tag`, and (2) fetch the `RunStarted` turn to extract `graph_name` and `run_id`.

Kilroy contexts are identified by their `client_tag`, which follows the format `kilroy/{run_id}`. The contexts endpoint supports server-side filtering via the `tag` query parameter, but since the `run_id` portion varies, the UI fetches all contexts and filters client-side by prefix. The context list request must include `limit=10000` to override the CXDB default of 20 — without this, instances with many non-Kilroy contexts (e.g., Claude Code sessions) may push Kilroy contexts outside the default 20-context window, causing pipeline discovery to silently miss them.

```
FUNCTION discoverPipelines(cxdbInstances, knownMappings):
    FOR EACH (index, instance) IN cxdbInstances:
        contexts = fetchContexts(index, limit=10000)

        FOR EACH context IN contexts:
            key = (index, context.context_id)
            IF key IN knownMappings:
                CONTINUE  -- already discovered (positive or negative)

            -- Phase 1: Filter by client_tag prefix
            IF context.client_tag IS null OR NOT context.client_tag.startsWith("kilroy/"):
                knownMappings[key] = null  -- not a Kilroy context
                CONTINUE

            -- Phase 2: Fetch RunStarted turn (first turn of the context)
            -- fetchFirstTurn may fail due to transient errors (non-200 response,
            -- type registry missing, instance temporarily unreachable). Distinguish
            -- between "confirmed non-RunStarted" and "unknown due to error."
            TRY:
                firstTurn = fetchFirstTurn(index, context.context_id, context.head_depth)
            CATCH fetchError:
                -- Transient failure: do NOT cache a null mapping.
                -- Leave the context unmapped so it is retried on the next poll cycle.
                CONTINUE

            IF firstTurn IS NOT null AND firstTurn.declared_type.type_id == "com.kilroy.attractor.RunStarted":
                graphName = firstTurn.data.graph_name
                runId = firstTurn.data.run_id
                knownMappings[key] = { graphName, runId }
            ELSE IF firstTurn IS null:
                -- Empty context (no turns yet). This can happen during early pipeline
                -- startup or transient CXDB lag. Do NOT cache a null mapping — leave
                -- unmapped so discovery retries on the next poll cycle until a turn appears.
                CONTINUE
            ELSE:
                knownMappings[key] = null  -- has kilroy tag but confirmed non-RunStarted first turn

    RETURN knownMappings
```

**Fetching the first turn.** CXDB returns turns oldest-first (ascending by position in the parent chain). The `before_turn_id` parameter paginates backward from a given turn ID. To reach the first turn of a context, the algorithm requests `headDepth + 1` turns to fetch the entire context in a single request:

```
FUNCTION fetchFirstTurn(cxdbIndex, contextId, headDepth):
    IF headDepth == 0:
        -- Context has at most one turn; limit=1 returns it if present.
        -- An empty context (just created, no turns yet) also has headDepth 0,
        -- so guard against an empty response.
        response = fetchTurns(cxdbIndex, contextId, limit=1)
        IF response.turns IS EMPTY:
            RETURN null
        RETURN response.turns[0]

    -- Fetch the entire context in one request.
    -- headDepth + 1 = total turn count. CXDB parses limit as u32 with no enforced maximum.
    response = fetchTurns(cxdbIndex, contextId, limit=headDepth + 1)
    IF response.turns IS EMPTY:
        RETURN null
    RETURN response.turns[0]  -- oldest turn (oldest-first ordering) = first turn
```

Since `fetchLimit = headDepth + 1` and CXDB imposes no limit maximum, the first turn is always fetched in a single request regardless of context depth. This runs once per context (results are cached). The `client_tag` prefix filter (Phase 1) ensures pagination only runs for Kilroy contexts, not for unrelated contexts that may share the CXDB instance.

The `graph_name` from the `RunStarted` turn is matched against the graph ID in each loaded DOT file (the identifier after `digraph` in the DOT source). Contexts whose `graph_name` matches the currently displayed pipeline are used for the status overlay — regardless of which CXDB instance they reside on.

The `RunStarted` turn also contains a `run_id` field (see Section 5.4 for the full field inventory) that uniquely identifies the pipeline run. All contexts belonging to the same run (e.g., parallel branches) share the same `run_id`. The discovery algorithm records both `graph_name` and `run_id` for each context.

**Caching.** The context-to-pipeline mapping is cached in memory, keyed by `(cxdb_index, context_id)`. Both positive results (RunStarted contexts mapped to a pipeline) and negative results (non-Kilroy contexts and confirmed non-RunStarted contexts stored as `null`) are cached. The first turn of a context is immutable — once a context is successfully classified, it is never re-fetched. Only newly appeared context IDs (and previously failed or empty fetches that were not cached) trigger discovery requests. The `client_tag` prefix filter prevents fetching turns for non-Kilroy contexts entirely. Two cases are left unmapped (not cached as `null`) and retried on subsequent polls: (a) when a `fetchFirstTurn` call fails due to a transient error (non-200 response, type registry miss, timeout), and (b) when `fetchFirstTurn` returns `null` (empty context with no turns yet — common during early pipeline startup or transient CXDB lag). This prevents both transient failures and premature classification of empty contexts from permanently classifying a valid Kilroy context as non-Kilroy.

**Multiple runs of the same pipeline.** When CXDB contains contexts from multiple runs of the same pipeline (same `graph_name`, different `run_id`), the UI uses only the most recent run. The most recent run is determined by the highest `created_at_unix_ms` among the `RunStarted` contexts for that pipeline. Contexts from older runs are ignored for status overlay purposes. This prevents stale data from a completed run from conflicting with an in-progress run.

**Cross-instance merging.** If contexts from the same run (same `run_id`) exist on multiple CXDB instances (e.g., parallel branches written to separate servers), their turns are merged into a single status map. The UI does not distinguish which CXDB instance a turn came from.

---

## 6. Status Overlay

### 6.1 Polling

The UI polls all configured CXDB instances every 3 seconds. Each poll cycle:

1. For each CXDB instance, fetch `GET /api/cxdb/{i}/v1/contexts?limit=10000` — get context lists. On success, store the response in `cachedContextLists[i]` (replacing any previous cached value). If an instance is unreachable (502), skip it, retain its per-context status maps from the last successful poll, and use `cachedContextLists[i]` as the context list for that instance in subsequent steps. This ensures that `lookupContext`, `determineActiveRuns`, and `checkPipelineLiveness` continue to function using the last known context data during transient outages — preserving active-run determination and liveness signals rather than losing them.
2. Run pipeline discovery for any new `(index, context_id)` pairs (Section 5.5)
3. **Determine active run per pipeline.** For each loaded pipeline, group discovered contexts by `run_id`. The active run is the one whose contexts have the highest `created_at_unix_ms` value. Contexts from non-active runs are excluded from steps 4–7. When the active `run_id` changes for a pipeline (a new run has started), reset all per-context status maps and `lastSeenTurnId` cursors for that pipeline's old-run contexts, and clear the per-pipeline turn cache (step 5) for that pipeline. This implements the "most recent run" rule described in Section 5.5. The context list data from step 1 must be retained (e.g., in a local variable) for use here, since the discovery mapping does not store `created_at_unix_ms`. The algorithm also maintains a `previousActiveRunIds` map (keyed by pipeline graph ID) across poll cycles to detect run changes.

**Active run determination pseudocode:**

```
FUNCTION determineActiveRuns(pipelines, knownMappings, contextLists, previousActiveRunIds):
    activeContextsByPipeline = {}

    FOR EACH pipeline IN pipelines:
        -- Collect discovered contexts for this pipeline with their run_id and created_at.
        -- knownMappings is keyed by (cxdb_index, context_id) from step 2.
        -- contextLists is the raw context list data retained from step 1.
        candidates = []
        FOR EACH ((index, contextId), mapping) IN knownMappings:
            IF mapping IS NOT null AND mapping.graphName == pipeline.graphId:
                contextInfo = lookupContext(contextLists, index, contextId)
                candidates.append({ index, contextId, runId: mapping.runId,
                                    createdAt: contextInfo.created_at_unix_ms })

        IF candidates IS EMPTY:
            activeContextsByPipeline[pipeline.graphId] = []
            CONTINUE

        -- Group by run_id, pick the run with the highest created_at among its contexts
        runGroups = groupBy(candidates, "runId")
        activeRunId = null
        highestCreatedAt = 0
        FOR EACH (runId, contexts) IN runGroups:
            maxCreatedAt = max(c.createdAt FOR c IN contexts)
            IF maxCreatedAt > highestCreatedAt:
                highestCreatedAt = maxCreatedAt
                activeRunId = runId

        -- Detect run change and reset stale state
        IF previousActiveRunIds[pipeline.graphId] IS NOT null
           AND previousActiveRunIds[pipeline.graphId] != activeRunId:
            resetPipelineState(pipeline.graphId)  -- clear per-context maps, cursors, turn cache

        previousActiveRunIds[pipeline.graphId] = activeRunId
        activeContextsByPipeline[pipeline.graphId] = runGroups[activeRunId]

    RETURN activeContextsByPipeline
```

The `lookupContext` helper finds the context object (from step 1's context list responses) by `(cxdb_index, context_id)` to access `created_at_unix_ms`. The `resetPipelineState` helper clears the per-context status maps, `lastSeenTurnId` cursors, and per-pipeline turn cache for all contexts that belonged to the old run. It also removes `knownMappings` entries whose `runId` matches the old run's `run_id`. These entries are no longer useful — they will never match the active run, and if the same context IDs appear in a future run with different `RunStarted` data, they will be re-discovered. Entries for the new run and entries with `null` mappings (negative caches) are retained.

**Pipeline liveness check.** After determining active runs, check whether each pipeline's active-run contexts have any live sessions. A pipeline is "live" if at least one of its active-run contexts has `is_live == true` in the context list response. This signal is used in step 6 for stale node detection.

```
FUNCTION checkPipelineLiveness(activeContexts, contextLists):
    -- A pipeline is "live" if ANY of its active-run contexts has is_live == true
    FOR EACH ctx IN activeContexts:
        contextInfo = lookupContext(contextLists, ctx.index, ctx.contextId)
        IF contextInfo.is_live == true:
            RETURN true
    RETURN false
```

4. For each context in the **active run** of **any loaded pipeline** (across all instances), fetch recent turns: `GET /api/cxdb/{i}/v1/contexts/{id}/turns?limit=100` (returns oldest-first). If a per-context turn fetch returns a non-200 response (e.g., 404/500 from a type registry miss, or any other server error), skip that context for this poll cycle: retain its cached turns and per-context status map from the last successful fetch, and continue polling. This prevents a single context's failure (such as an unregistered type in `view=typed` — see Section 5.3) from affecting other contexts or crashing the poll cycle. Turns are fetched for all pipelines, not just the active tab — this ensures per-context status maps stay current for inactive pipelines, preventing stale data on tab switch.
5. **Cache raw turns** — Store the raw turn arrays from step 4 in a per-pipeline turn cache, keyed by `(cxdb_index, context_id)`. This cache is replaced (not appended) on each successful fetch. When a CXDB instance is unreachable, its entries in the turn cache are retained from the previous successful fetch. The detail panel (Section 7.2) reads from this cache.
6. Run `updateContextStatusMap` per context (updating persistent per-context maps and advancing each context's `lastSeenTurnId` cursor), then `mergeStatusMaps` across **active-run** contexts for the **active pipeline**, then `applyErrorHeuristic` on the merged map using the per-context turn caches for the active pipeline, then `applyStaleDetection` using the pipeline liveness result from step 3 (Section 6.2). Per-context maps for inactive pipelines are also updated but their merged maps are not computed until the user switches to that tab. Per-context status maps from unreachable instances are included in the merge using their cached values.
7. Apply CSS classes to SVG nodes for the active pipeline (Section 6.3)

**Poll scheduling.** The poller uses `setTimeout` (not `setInterval`). After a poll cycle completes, the next poll is scheduled 3 seconds later. This prevents overlapping poll cycles when CXDB instances respond slowly — at most one poll cycle is in flight at any time. The effective interval is 3 seconds plus poll execution time.

The polling interval is constant. It does not adapt to pipeline activity or CXDB load. Requests to different CXDB instances within a single poll cycle are issued in parallel.

**Status caching on failure.** The UI retains per-context status maps from the last successful poll. When a CXDB instance is unreachable, its contexts' status maps are not discarded — they participate in the merge using cached values. This ensures that status is preserved (not reverted to "pending") when a CXDB instance goes down temporarily. Cached status maps are only replaced when fresh data is successfully fetched for that context.

**Turn fetch limit.** Each context poll fetches at most 100 recent turns (`limit=100`; CXDB returns turns oldest-first). This window may not contain lifecycle turns for nodes that completed early in a long-running pipeline. The persistent status map (Section 6.2) ensures completed nodes retain their status even when their lifecycle turns fall outside this window.

**Gap recovery.** After step 4, if any context's fetched turns do not reach back to `lastSeenTurnId`, the poller issues additional paginated requests using `before_turn_id` to fetch the missing turns until `lastSeenTurnId` is reached or `next_before_turn_id` is null. The gap detection condition is:

```
oldestFetched = turns[0].turn_id   -- oldest turn in the batch (oldest-first ordering)
IF lastSeenTurnId IS NOT null
   AND oldestFetched > lastSeenTurnId              -- batch doesn't reach our cursor
   AND response.next_before_turn_id IS NOT null:   -- response was non-empty (more turns may exist to paginate)
    -- Run gap recovery.
```

The condition uses `oldestFetched > lastSeenTurnId` (without `+ 1`) because CXDB allocates turn IDs from a global counter shared across all contexts on an instance. Within a single context's parent chain, turn IDs are monotonically increasing but **not consecutive** — gaps between intra-context turn IDs are normal and proportional to the number of concurrently active contexts. The `next_before_turn_id IS NOT null` guard prevents gap recovery when the response was empty (which indicates no turns exist before the cursor). Note that a non-null `next_before_turn_id` means the response contained at least one turn, not that older turns definitely exist — but in the gap recovery context, this is sufficient because if the batch contains any turns and doesn't reach `lastSeenTurnId`, there are older turns to fetch. Together, these conditions detect real gaps (the 100-turn fetch window doesn't include `lastSeenTurnId` and there are older turns to paginate) without false positives from sparse turn IDs.

**Gap recovery pseudocode:**

```
-- Gap recovery: fetch turns between lastSeenTurnId and the main batch
recoveredTurns = []
cursor = response.next_before_turn_id
WHILE cursor IS NOT null:
    gapResponse = fetchTurns(cxdbIndex, contextId, limit=100, before_turn_id=cursor)
    IF gapResponse.turns IS EMPTY:
        BREAK
    recoveredTurns = gapResponse.turns + recoveredTurns  -- prepend to maintain oldest-first
    -- Check if we've reached lastSeenTurnId
    oldestInGap = gapResponse.turns[0].turn_id  -- oldest turn in page (oldest-first ordering)
    IF oldestInGap <= lastSeenTurnId:
        BREAK
    cursor = gapResponse.next_before_turn_id

-- Prepend recovered turns to the main batch
turns = recoveredTurns + turns
```

This ensures lifecycle events (e.g., `StageFinished`) that occurred during a CXDB outage are not permanently lost. The gap recovery procedure runs at most once per context per poll cycle. Within the procedure, multiple paginated requests may be issued (one per 100 missed turns). The recovered turns are prepended (in oldest-first order) to the context's turn batch before step 5 caches them and step 6 processes them for status derivation.

### 6.2 Node Status Map

The status map associates each DOT node ID with an execution status. The status map is **persistent** — it accumulates across poll cycles rather than being recomputed from scratch. This prevents completed nodes from reverting to "pending" when their lifecycle turns fall outside the 100-turn fetch window.

```
TYPE NodeStatus:
    status                : "pending" | "running" | "complete" | "error" | "stale"
    lastTurnId            : String | null
    toolName              : String | null
    turnCount             : Integer
    errorCount            : Integer
    hasLifecycleResolution: Boolean
```

**Status map lifecycle:**

1. A new status map is initialized (all nodes "pending") when a pipeline is first displayed.
2. On each poll cycle, fetched turns are processed and node statuses are **promoted** within each context according to the per-context precedence `pending < running < complete < error`. Statuses are never demoted within a context. (Cross-context merging uses a different precedence where `running > complete` — see Section 6.2.)
3. The status map is **reset** (all nodes back to "pending") only when the active `run_id` changes — i.e., a new run of the same pipeline is detected (Section 5.5).

**Turn ID comparison.** CXDB turn IDs are numeric strings (e.g., `"6066"`). All turn ID comparisons in the UI — including the deduplication check, `lastSeenTurnId` tracking, and `lastTurnId` on `NodeStatus` — must use numeric ordering: `parseInt(turn.turn_id, 10)`. The `<=` operator on turn IDs in the pseudocode below denotes numeric comparison, not lexicographic string comparison. Lexicographic comparison breaks for IDs of different lengths (e.g., `"999" > "1000"` lexicographically).

**Status derivation algorithm (per context):**

The algorithm processes turns from a single CXDB context and promotes statuses in an existing per-context status map. When multiple contexts match the active pipeline (e.g., parallel branches), the algorithm runs independently per context and the results are merged (see below).

```
FUNCTION updateContextStatusMap(existingMap, dotNodeIds, turns, lastSeenTurnId):
    -- Initialize entries for any new node IDs not yet in the map
    FOR EACH nodeId IN dotNodeIds:
        IF nodeId NOT IN existingMap:
            existingMap[nodeId] = NodeStatus { status: "pending", turnCount: 0, errorCount: 0, hasLifecycleResolution: false }

    -- Per-context precedence: complete outranks running because within a single
    -- execution flow, a completed node must not regress to running. (The cross-context
    -- merge uses a different precedence where running outranks complete — see mergeStatusMaps.)
    CONTEXT_PRECEDENCE = { "error": 3, "complete": 2, "running": 1, "pending": 0 }

    -- Compute the newest turn ID across the entire batch (handles any ordering,
    -- including mixed-order batches produced by gap recovery prepending)
    newLastSeenTurnId = lastSeenTurnId
    FOR EACH turn IN turns:
        IF newLastSeenTurnId IS null OR turn.turn_id > newLastSeenTurnId:
            newLastSeenTurnId = turn.turn_id

    -- turns are oldest-first from the API; gap recovery may prepend older turns
    FOR EACH turn IN turns:
        -- Skip turns already processed in a previous poll cycle
        IF lastSeenTurnId IS NOT null AND turn.turn_id <= lastSeenTurnId:
            CONTINUE  -- skip this turn; batch may not be sorted, so don't break

        nodeId = turn.data.node_id
        typeId = turn.declared_type.type_id
        IF nodeId IS null OR nodeId NOT IN existingMap:
            CONTINUE

        -- Determine the status this turn implies
        newStatus = null
        IF typeId == "com.kilroy.attractor.StageFinished":
            newStatus = "complete"
            existingMap[nodeId].hasLifecycleResolution = true
        ELSE IF typeId == "com.kilroy.attractor.StageFailed":
            newStatus = "error"
            existingMap[nodeId].hasLifecycleResolution = true
        ELSE IF typeId == "com.kilroy.attractor.StageStarted":
            newStatus = "running"
        ELSE:
            -- Non-lifecycle turns: infer running
            newStatus = "running"

        -- Promote status. Lifecycle resolutions (StageFinished, StageFailed) are
        -- authoritative and unconditionally override status. Once a node has
        -- lifecycle resolution, only other lifecycle turns can modify its status.
        -- Non-lifecycle turns follow promotion-only (never demote).
        IF typeId == "com.kilroy.attractor.StageFinished"
           OR typeId == "com.kilroy.attractor.StageFailed":
            -- Lifecycle turns are authoritative: override any previous status
            existingMap[nodeId].status = newStatus
        ELSE IF NOT existingMap[nodeId].hasLifecycleResolution
           AND (newStatus == "error" OR CONTEXT_PRECEDENCE[newStatus] > CONTEXT_PRECEDENCE[existingMap[nodeId].status]):
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

    RETURN (existingMap, newLastSeenTurnId)
```

**Turn deduplication.** Each per-context status map tracks a `lastSeenTurnId` — the newest `turn_id` processed in the previous poll cycle. On each poll, the algorithm skips turns with `turn_id <= lastSeenTurnId`, processing only newly appended turns. Because gap recovery prepends older turns before the main batch (both segments are oldest-first but the combined batch has a discontinuity at the join point), the algorithm uses `CONTINUE` instead of `BREAK` to skip already-seen turns — it cannot assume strictly ascending order across the join. The `newLastSeenTurnId` cursor is computed as the maximum `turn_id` across the entire batch before the processing loop begins, ensuring it always advances to the newest turn regardless of batch ordering. This prevents `turnCount` and `errorCount` from being inflated by re-processing overlapping turns across poll cycles. The cursor is initialized to `null` (process all turns) when a context is first discovered, and resets to `null` when the active `run_id` changes.

**lastTurnId assignment.** The `lastTurnId` field on `NodeStatus` records the most recent turn for that node. It is updated whenever a turn's `turn_id` exceeds the stored value (using numeric comparison). Since turns arrive oldest-first, later encounters per node in the batch have higher turn IDs, and the max-comparison ensures `lastTurnId` always holds the newest turn ID. Across poll cycles, new turns always have higher IDs than previously stored values (due to deduplication), so `lastTurnId` correctly advances to reflect the latest activity for each node.

**Lifecycle turn precedence.** `StageFinished` and `StageFailed` are authoritative lifecycle signals. When processed, they set `hasLifecycleResolution = true` on the node and unconditionally override the current status — including any previous status. This handles two cases: (a) an agent encounters 3+ tool errors but then recovers and completes the node successfully, and (b) gap recovery prepends older turns before the main batch, where a `StageStarted` turn might appear after a `StageFinished` for the same node in the combined batch. Once a node has `hasLifecycleResolution = true`, only other lifecycle turns (`StageFinished`, `StageFailed`) can modify its status — non-lifecycle turns are ignored for that node. This prevents a `StageStarted` turn (processed after `StageFinished` due to batch ordering) from regressing a completed node back to running. The error loop heuristic (which runs post-merge) also skips nodes with `hasLifecycleResolution = true`.

**Error loop detection heuristic.** The heuristic runs as a post-merge step (see `applyErrorHeuristic` above), after `updateContextStatusMap` and `mergeStatusMaps` have produced the merged display map. It fires only for nodes that are "running" and have no lifecycle resolution (`hasLifecycleResolution == false`). For each such node, it examines each context's cached turns independently — if any single context has 3 consecutive recent errors for the node, the node is promoted to "error" in the merged map. This per-context scoping avoids cross-instance `turn_id` comparison: CXDB instances have independent turn ID counters with no temporal relationship, so sorting turns by `turn_id` across instances would produce arbitrary interleaving rather than temporal ordering. Within a single context, `turn_id` is monotonically increasing and safe to use for ordering. The `errorCount` field on `NodeStatus` remains as a display-only lifetime counter (shown in the detail panel) but is no longer used for heuristic decisions.

**Multi-context merging.** When multiple CXDB contexts match the active pipeline (e.g., parallel branches), the algorithm runs independently per context, producing one per-context status map. The per-context maps are then merged into a single display map using **merge precedence** (highest wins):

```
error > running > complete > pending
```

Note: the merge precedence intentionally differs from the per-context precedence (`error > complete > running > pending`). Within a single context, a completed node should never regress to running. But across contexts, `running > complete` because if one parallel branch is still running a node while another has completed it, the display should show "running" to indicate ongoing activity.

```
FUNCTION mergeStatusMaps(dotNodeIds, perContextMaps):
    MERGE_PRECEDENCE = { "error": 3, "running": 2, "complete": 1, "pending": 0 }
    merged = {}
    FOR EACH nodeId IN dotNodeIds:
        merged[nodeId] = NodeStatus { status: "pending", turnCount: 0, errorCount: 0, hasLifecycleResolution: false }
        -- Track lifecycle resolution across all contexts using AND semantics
        allContextsHaveLifecycleResolution = true
        anyContextHasNode = false
        FOR EACH contextMap IN perContextMaps:
            contextStatus = contextMap[nodeId]
            IF MERGE_PRECEDENCE[contextStatus.status] > MERGE_PRECEDENCE[merged[nodeId].status]:
                merged[nodeId].status = contextStatus.status
                merged[nodeId].toolName = contextStatus.toolName
                merged[nodeId].lastTurnId = contextStatus.lastTurnId
            merged[nodeId].turnCount += contextStatus.turnCount
            merged[nodeId].errorCount += contextStatus.errorCount
            -- Only consider contexts that have actually processed turns for this node
            IF contextStatus.status != "pending":
                anyContextHasNode = true
                IF NOT contextStatus.hasLifecycleResolution:
                    allContextsHaveLifecycleResolution = false
        -- hasLifecycleResolution is true only when ALL contexts that have processed
        -- turns for this node have lifecycle resolution. This prevents a completed
        -- branch from suppressing error/stale heuristics in a branch that is still
        -- actively failing.
        merged[nodeId].hasLifecycleResolution = anyContextHasNode AND allContextsHaveLifecycleResolution
    RETURN merged
```

This ensures that parallel branches each contribute their own "running" node, and a node that is "running" in one context but "complete" in another shows as "running." The `hasLifecycleResolution` flag uses AND semantics across contexts: the merged map sets `hasLifecycleResolution = true` only when ALL contexts that have processed turns for the node have lifecycle resolution. This prevents a branch that has completed a node from suppressing the error and stale heuristics for the same node in a different branch that is actively failing. Only contexts that have progressed beyond "pending" for the node participate in the AND — contexts that have not yet encountered the node do not prevent lifecycle resolution from being set. The per-context maps are persistent (accumulated across polls); the merged map is recomputed each poll cycle from the current per-context maps.

**Error loop heuristic (post-merge).** After merging per-context maps, the error loop heuristic runs once per pipeline per poll cycle against the merged map and the per-context turn caches. This architecture avoids two problems: (a) scoping the heuristic per-context prevents cross-instance `turn_id` comparison (CXDB instances have independent, monotonically-increasing turn ID counters with no temporal relationship), and (b) per-context maps are no longer contaminated with decisions based on other contexts' data.

```
FUNCTION applyErrorHeuristic(mergedMap, dotNodeIds, perContextCaches):
    -- For each running node without lifecycle resolution, check each context's
    -- cached turns independently. If ANY context shows 3 consecutive recent
    -- ToolResult errors for the node, flag it as "error" in the merged map.
    FOR EACH nodeId IN dotNodeIds:
        IF mergedMap[nodeId].status == "running"
           AND NOT mergedMap[nodeId].hasLifecycleResolution:
            FOR EACH contextTurns IN perContextCaches:
                recentTurns = getMostRecentToolResultsForNodeInContext(contextTurns, nodeId, count=3)
                IF recentTurns.length >= 3 AND ALL(turn.data.is_error == true FOR turn IN recentTurns):
                    mergedMap[nodeId].status = "error"
                    BREAK  -- one context with an error loop is sufficient
    RETURN mergedMap
```

The `getMostRecentToolResultsForNodeInContext` helper scans a single context's cached turns for `ToolResult` turns (i.e., turns whose `declared_type.type_id` is `com.kilroy.attractor.ToolResult`) matching the given `node_id`, collecting them sorted by `turn_id` descending (newest-first, which is safe for intra-context ordering since turn IDs are monotonically increasing within a single context), and returns the first `count` matches. Only `ToolResult` turns carry the `is_error` field (see Section 5.4); other turn types (Prompt, ToolCall, etc.) do not have this field, so including them would dilute the error detection window and prevent the heuristic from firing during typical error loops where turn types interleave as Prompt → ToolCall → ToolResult. This avoids the cross-instance `turn_id` ordering problem: turn IDs are only compared within the same CXDB instance and context, where they have a meaningful temporal relationship.

**Stale pipeline detection (post-merge).** After the error heuristic, the stale detection step runs if the pipeline has no live sessions. When all contexts for a pipeline's active run have `is_live == false` (no agent is writing to any of them), any node still showing as "running" without lifecycle resolution is reclassified as "stale." This detects the case where an agent process crashes mid-node — no `StageFinished` or `StageFailed` is written, and the node would otherwise display as "running" indefinitely.

```
FUNCTION applyStaleDetection(mergedMap, dotNodeIds, pipelineIsLive):
    IF pipelineIsLive:
        RETURN mergedMap  -- at least one session is active; no stale detection needed
    FOR EACH nodeId IN dotNodeIds:
        IF mergedMap[nodeId].status == "running"
           AND NOT mergedMap[nodeId].hasLifecycleResolution:
            mergedMap[nodeId].status = "stale"
    RETURN mergedMap
```

The `pipelineIsLive` flag is computed by `checkPipelineLiveness` in Section 6.1 step 3. Nodes with `hasLifecycleResolution == true` are not affected — their status is authoritative from lifecycle turns.

### 6.3 CSS Status Classes

After building the status map, the UI walks SVG `<g class="node">` elements and applies CSS classes:

| Status | CSS Class | Visual |
|--------|-----------|--------|
| `pending` | `node-pending` | Gray fill |
| `running` | `node-running` | Blue fill, pulsing animation |
| `complete` | `node-complete` | Green fill |
| `error` | `node-error` | Red fill |
| `stale` | `node-stale` | Orange/amber fill, no animation |

```css
.node-pending polygon, .node-pending ellipse, .node-pending path   { fill: #e0e0e0; }
.node-running polygon, .node-running ellipse, .node-running path   { fill: #90caf9; animation: pulse 1.5s infinite; }
.node-complete polygon, .node-complete ellipse, .node-complete path  { fill: #a5d6a7; }
.node-error polygon, .node-error ellipse, .node-error path        { fill: #ef9a9a; }
.node-stale polygon, .node-stale ellipse, .node-stale path        { fill: #ffcc80; }

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
| Choices | Outgoing edge labels via `GET /dots/{name}/edges` | Available choices for human gate nodes — labels of edges whose `source` matches this node's ID (see Section 3.2) |
| Goal Gate | DOT `goal_gate` attribute | Boolean flag — if `"true"`, this conditional node acts as a goal gate (displayed as a badge on the detail panel header). Goal gates use the same `diamond` shape as regular conditionals. |

### 7.2 CXDB Activity

The detail panel shows recent CXDB turns for the selected node. Turns are sourced from the per-pipeline turn cache (Section 6.1, step 5), filtered to those where `turn.data.node_id` matches the selected node's DOT ID.

**Context-grouped display.** When the selected node has matching turns across multiple contexts (e.g., parallel branches), turns are displayed grouped by context rather than interleaved. Each context's turns appear in a collapsible section labeled with the CXDB instance index and context ID (e.g., "CXDB-0 / Context 33"). Within each section, turns are displayed newest-first (the UI reverses the API's oldest-first order) by `turn_id` — this is safe because `turn_id` is monotonically increasing within a single context's parent chain (see Section 6.2). Sections are ordered by recency: for each context that has matching turns, compute the highest `turn_id` among its turns for the selected node. The context with the highest such `turn_id` appears first. This uses intra-context `turn_id` ordering (safe within a single context's parent chain). When contexts span multiple CXDB instances, sections from different instances are not interleaved by `turn_id` — CXDB instances have independent turn ID counters with no temporal relationship, so cross-instance `turn_id` comparison would produce arbitrary ordering rather than temporal ordering.

| Column | Source | Description |
|--------|--------|-------------|
| Type | `declared_type.type_id` | Turn type (ToolCall, ToolResult, Prompt) |
| Tool | `data.tool_name` | Tool invoked (e.g., `shell`, `write_file`) |
| Output | `data.output` | Truncated output (expandable) |
| Error | `data.is_error` | Highlighted if true |

Within each context section, turns are displayed newest-first (reversed from the API's oldest-first order for better UX — most recent activity at the top). The panel shows at most 20 turns per context section. If all of a node's turns have scrolled out of the 100-turn poll window (i.e., the node completed early and subsequent nodes have generated many turns), the detail panel shows the node's DOT attributes but displays "No recent CXDB activity" in place of the turn list. The node's status remains correct via the persistent status map (Section 6.2).

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

When all contexts for the active pipeline's active run have `is_live == false` and at least one node is "stale" (was "running" but the pipeline has no active sessions), the indicator shows a warning: **"Pipeline stalled — no active sessions."** This alerts the operator that the agent process may have crashed and no further progress is expected without intervention.

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

6. **Status is mutually exclusive.** Every node has exactly one status: `pending`, `running`, `complete`, `error`, or `stale`.

7. **Polling delay is constant at 3 seconds.** After each poll cycle completes, the next poll is scheduled 3 seconds later via `setTimeout`. At most one poll cycle is in flight at any time. The delay does not back off, speed up, or adapt.

8. **Unknown node IDs in CXDB are ignored.** If a turn references a `node_id` not in the loaded DOT file, the UI silently skips it.

9. **Pipeline scoping is strict.** The status overlay only uses CXDB contexts whose `RunStarted` turn's `graph_name` matches the active DOT file's graph ID. Turns from unrelated contexts never appear. This holds across all configured CXDB instances.

10. **Context-to-pipeline mapping is immutable once resolved.** Once a context is successfully mapped to a pipeline via its `RunStarted` turn (or confirmed as non-Kilroy with a `null` mapping), the mapping is never re-evaluated. The `RunStarted` turn does not change. Mappings are keyed by `(cxdb_index, context_id)`. Contexts whose discovery failed due to transient errors, and empty contexts (no turns yet), are not cached and are retried on subsequent polls until classification succeeds. Old-run mappings are removed by `resetPipelineState` when the active run changes (Section 6.1).

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
- [ ] `GET /dots/{name}/edges` returns parsed DOT edges with labels as JSON
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
- [ ] Nodes colored by status: gray (pending), blue/pulse (running), green (complete), red (error), orange (stale)
- [ ] Stale detection: nodes show orange when pipeline has no active sessions and node lacks lifecycle resolution
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
