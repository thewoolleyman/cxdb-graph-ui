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

Serves `index.html` embedded in the binary via Go's `//go:embed` directive. The `main.go` file embeds `index.html` at compile time using `//go:embed index.html`, serving it from the embedded filesystem. This ensures the asset is always available regardless of the working directory — `go run ui/main.go` compiles the binary in a temp directory, so runtime file resolution relative to the source would fail. Returns 500 if the embed fails to load (should not happen in a correctly compiled binary).

#### `GET /dots/{name}` — DOT Files

Serves DOT files registered via `--dot` flags. The `{name}` is the base filename (e.g., `pipeline-alpha.dot`).

- The server builds a map from base filename to absolute path at startup. If two `--dot` flags resolve to the same base filename (e.g., `pipelines/alpha/pipeline.dot` and `pipelines/beta/pipeline.dot` both have basename `pipeline.dot`), the server exits with a non-zero code and prints an error identifying the conflicting paths. This prevents silent collisions where one pipeline becomes unreachable.
- **Graph ID uniqueness.** At startup, the server parses each DOT file to extract its graph ID (the identifier after `digraph`). The server uses the same graph ID parsing and normalization logic as the browser (Section 4.4): the regex `/(di)?graph\s+("(?:[^"\\]|\\.)*"|\w+)/` extracts the identifier, quoted IDs are unquoted (outer `"` stripped) and unescaped (internal `\"` sequences resolved), and the result is the normalized graph ID. This ensures that the server's uniqueness check and the browser's pipeline discovery match `RunStarted.data.graph_name` against the same normalized value. If two DOT files share the same normalized graph ID, the server exits with a non-zero code and prints an error identifying the conflicting files and graph ID. Duplicate graph IDs would cause ambiguous pipeline discovery — both pipelines would match the same CXDB contexts, producing identical and misleading status overlays. This check mirrors the basename collision check and runs at startup alongside it.
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

**Node ID normalization.** Node IDs returned by `/nodes` (as JSON keys) and `/edges` (as `source`/`target` values) are normalized to match the SVG `<title>` text that Graphviz produces and the `node_id` values in CXDB turns. The normalization rules are: quoted DOT identifiers have their outer `"` characters stripped and internal escape sequences resolved (`\"` → `"`, `\\` → `\`), and leading/trailing whitespace is trimmed. This is the same approach used for graph ID normalization (Section 4.4). The normalized node ID is the canonical key used for: `dotNodeIds` sets, status map keys, detail panel lookup, and edge `source`/`target` values. **Scope limitation:** Kilroy-generated DOT files use only unquoted, alphanumeric node IDs (e.g., `implement`, `check_fmt`). The normalization handles quoted IDs for correctness, but the UI does not need to support arbitrary Unicode or whitespace-containing node IDs.

The server parses node attribute blocks from the DOT source. Parsing rules:

- **Attribute syntax:** Both quoted (`key="value"`) and unquoted (`key=value`) attribute values are supported.
- **String concatenation:** Quoted values support the DOT `+` concatenation operator: `prompt="first part" + "second part"` is equivalent to `prompt="first partsecond part"` (fragments are joined with no separator, per DOT semantics). The parser must handle `+` between consecutive quoted strings within an attribute value.
- **Multi-line quoted values:** Quoted attribute values may span literal newlines. A value that begins with `"` extends to the next unescaped `"`, regardless of intervening newlines. A line-by-line parser is insufficient — the parser must handle multi-line strings.
- **Named nodes only:** Global default blocks (`node [...]`, `edge [...]`, `graph [...]`) are excluded. Only named node definitions (e.g., `implement [shape=box, prompt="..."]`) are parsed.
- **Subgraph scope:** Nodes defined inside `subgraph` blocks are included.
- **Escape sequences:** Quoted attribute values support these DOT escapes: `\"` → `"`, `\n` → newline, `\\` → `\`. Other escape sequences are passed through verbatim.

The file is read fresh on each request. Returns 404 if the DOT file is not registered. Returns 400 with a JSON error body (`{"error": "DOT parse error: ..."}`) if the DOT file has invalid syntax that prevents node attribute parsing. The browser handles a 400 from `/nodes` by continuing with an empty `dotNodeIds` set for that pipeline — the SVG error message from Graphviz WASM (Section 4.1) is still displayed, polling proceeds, and status maps for that pipeline remain empty until the DOT file is fixed and the tab is re-selected.

#### `GET /dots/{name}/edges` — DOT Edge List

Returns a JSON array of edges parsed from the named DOT file. Each edge includes the source node, target node, and label (if present).

```json
[
  { "source": "check_goal", "target": "implement", "label": "fail" },
  { "source": "check_goal", "target": "done", "label": "pass" },
  { "source": "implement", "target": "check_fmt", "label": null }
]
```

The server parses edge statements from the DOT source (`source -> target` syntax). Edge labels come from the `label` attribute in the edge's attribute block (e.g., `check_goal -> done [label="pass"]`). Edges without a `label` attribute have `label: null`. Edges inside `subgraph` blocks are included. **Edge attribute parsing reuses the same rules as node attribute parsing** (Section 3.2, `/dots/{name}/nodes`): quoted and unquoted values, `+` concatenation of quoted fragments, multi-line quoted strings, and the same escape decoding (`\"` → `"`, `\n` → newline, `\\` → `\`). This ensures human-gate choices and edge labels are decoded correctly even when labels contain whitespace, escaped characters, or multi-line content.

**DOT edge subset.** The parser supports only the edge constructs used in Kilroy-generated DOT files:

- **Simple edges:** `node_id -> node_id` with an optional attribute block. This is the primary form.
- **Edge chains:** `a -> b -> c` is expanded into two edges: `(a, b)` and `(b, c)`. Each segment inherits the attribute block from the chain statement (e.g., `a -> b -> c [label="x"]` produces two edges both with `label: "x"`).
- **Node IDs** in edge statements are normalized using the same rules as `/nodes` (see above): quoted IDs are unquoted and unescaped, whitespace is trimmed.
- **Ports are stripped:** If an endpoint uses port syntax (`node_id:port` or `node_id:port:compass`), the port suffix is stripped and only the base `node_id` is used as `source` or `target`. This ensures edge endpoints match the node IDs in `/nodes` and the SVG `<title>` elements.
- **Subgraph endpoints** (e.g., `subgraph cluster_x { ... } -> node_id`) are not supported. Edges must reference named nodes directly. Kilroy-generated DOT files do not use subgraph endpoints.

The file is read fresh on each request. Returns 404 if the DOT file is not registered. Returns 400 with a JSON error body (`{"error": "DOT parse error: ..."}`) if the DOT file has invalid syntax that prevents edge parsing. The browser handles a 400 from `/edges` by continuing with an empty edge list for that pipeline — human gate choices will be unavailable in the detail panel until the DOT file is fixed.

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

Returns a JSON object with a `dots` array containing the available DOT filenames (registered via `--dot` flags), **in the same order as the `--dot` flags were provided on the command line**. This ordering is deterministic and must be preserved — the server must use an ordered data structure (e.g., a slice, not a map) for DOT file registration. The browser uses this order for tab rendering and selects the first entry as the initial pipeline. This is a server-generated response used by the browser to build pipeline tabs.

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

### 4.1.1 Browser Dependencies

The browser loads two CDN dependencies. Both are ES modules imported via `<script type="module">` in `index.html`:

1. **Graphviz WASM** — `@hpcc-js/wasm-graphviz` at pinned version (documented above in Section 4.1). Used for DOT-to-SVG rendering.

2. **Msgpack decoder** — `@msgpack/msgpack` at a pinned CDN URL:

```
https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/mod.min.mjs
```

This library provides a `decode(Uint8Array)` function that decodes msgpack bytes into JavaScript objects. It is used exclusively by `decodeFirstTurn` (Section 5.5) to extract `graph_name` and `run_id` from the raw msgpack payload of `RunStarted` turns fetched with `view=raw`. It is not used during regular turn polling (`view=typed`), which returns pre-decoded JSON.

**Base64 decoding** uses the browser's built-in `atob()` function combined with a `Uint8Array` conversion — no additional library is needed:

```javascript
function base64ToBytes(b64) {
    const binary = atob(b64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
}
```

No other CDN dependencies are required. All other functionality (DOM manipulation, fetch, SVG interaction) uses browser built-in APIs.

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

**Graph ID extraction.** The browser extracts the graph ID from the DOT source when the file is first fetched, using a regex pattern that handles both `digraph` and `graph` keywords, and both quoted and unquoted names: `/(di)?graph\s+("(?:[^"\\]|\\.)*"|\w+)/`. If the name is quoted, the UI unquotes it (strips the outer `"` characters) and unescapes internal `\"` sequences before using it as the graph ID. If the regex does not match (e.g., unusual formatting or anonymous graphs), the tab falls back to the base filename. Tabs initially display filenames (from the `/api/dots` response) and update to graph IDs as each DOT file is fetched and parsed. Pipeline discovery in Section 5.5 matches `RunStarted.data.graph_name` against the normalized (unquoted, unescaped) graph ID.

Switching tabs fetches the DOT file fresh and re-renders the SVG. On every tab switch (or any event that refetches a DOT file), the UI also refetches `GET /dots/{name}/nodes` and `GET /dots/{name}/edges` to refresh cached node/edge metadata and updates `dotNodeIds` for that pipeline. This ensures that DOT file regeneration (new nodes, removed nodes, changed prompts, updated edge labels) is reflected in the status overlay, detail panel, and human-gate choices — not just the SVG rendering. When the node list changes, new nodes are initialized as "pending" in the per-context status maps, and removed nodes are dropped from the maps. If a cached status map exists for the newly selected pipeline (from a previous poll cycle), it is immediately reapplied to the new SVG (after reconciling with the refreshed `dotNodeIds`). Otherwise, all nodes start as pending. The next poll cycle refreshes the status with live data. This avoids a gray flash when switching between tabs for pipelines that have already been polled.

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
| `/api/cxdb/{i}/v1/contexts/search?q={cql}` | GET | CQL search for contexts on CXDB instance `i` (primary discovery) |
| `/api/cxdb/{i}/v1/contexts` | GET | List all contexts on CXDB instance `i` (fallback discovery) |
| `/api/cxdb/{i}/v1/contexts/{id}/turns?limit={n}&before_turn_id={id}` | GET | Fetch turns for a context on instance `i` |

### 5.2 Context Discovery Endpoints

**Primary: CQL search.** CXDB provides a CQL (Context Query Language) search endpoint at `GET /v1/contexts/search?q={cql}` that supports server-side prefix filtering via the `^=` (starts with) operator:

```
GET /v1/contexts/search?q=tag ^= "kilroy/"
```

This returns only contexts whose `client_tag` starts with `"kilroy/"`, using CXDB's secondary indexes (`tag_sorted` B-tree in `server/src/cql/indexes.rs`) for efficient server-side filtering. The CQL search response has a different shape from the context list response:

```json
{
  "contexts": [ ... ],
  "total_count": 5,
  "elapsed_ms": 2,
  "query": "tag ^= \"kilroy/\""
}
```

Each context object in the `contexts` array contains: `context_id`, `head_turn_id`, `head_depth`, `created_at_unix_ms`, `is_live`, `client_tag` (from cached metadata), and `title` (from cached metadata). The CQL search response does **not** include `labels`, `session_id`, `last_activity_at`, `lineage`, `provenance`, `active_sessions`, or `active_tags` — the CQL endpoint builds lightweight context objects directly rather than calling the full `context_to_json` used by the context list endpoint. The absence of `labels` is significant for the metadata labels optimization (Section 5.5): since CQL search is the primary discovery path, the optimization cannot read `graph_name`/`run_id` from labels without per-context requests or a CXDB enhancement to include `labels` in CQL results. If the context lineage optimization (Section 5.5) is implemented in the future, the UI would need a separate context list request or individual context fetches for lineage data.

CQL results are sorted by `context_id` descending (most recent first), as implemented in CXDB's `store.rs`. Since CXDB allocates context IDs monotonically from a global counter, this is effectively equivalent to creation-time ordering. The context list fallback sorts by `created_at_unix_ms` descending. The `determineActiveRuns` algorithm (Section 6.1) does not depend on response ordering — it scans all candidates to find the maximum `created_at_unix_ms` — so this difference has no functional impact.

The CQL search endpoint also accepts an optional `limit` query parameter. When present, matching contexts are sorted by `context_id` descending and truncated to the specified count. The UI omits `limit` to retrieve all Kilroy contexts, since the discovery algorithm needs to see all contexts to determine the active run. Environments with hundreds of historical Kilroy runs will produce proportionally larger CQL search responses, but this is acceptable for the initial implementation — paginating CQL results would complicate discovery logic for a scenario that is not performance-critical at expected scale.

**CQL error response.** When a CQL query is malformed, the endpoint returns 400 with a JSON error body:

```json
{
  "error": "Parse error: unexpected token at position 5",
  "error_type": "ParseError",
  "position": 5,
  "field": null
}
```

This is distinct from 404 (CQL not supported) and network errors (instance unreachable). A 400 means CQL is supported but the query was rejected. Since the UI's query (`tag ^= "kilroy/"`) is hardcoded and correct, a 400 is unlikely in practice but could occur against a misconfigured proxy or incompatible CQL version. The `discoverPipelines` pseudocode (Section 5.5) handles this case explicitly.

**CQL search bootstrap lag.** CQL secondary indexes are built from cached metadata, which is extracted from the first turn's msgpack payload. A newly created context may not appear in CQL search results until its first turn is appended and metadata is extracted. The context list fallback resolves `client_tag` from the active session as well (via `context_to_json`'s session-tag fallback), so it can discover contexts earlier. This race window is typically sub-second (the time between context creation and first turn append) and does not affect the UI's behavior — the context would be discovered on the next poll cycle after metadata extraction. No code change is needed; this is a documentation note for completeness.

CQL search eliminates two problems that the context list fallback has: (1) the `limit=10000` heuristic and its truncation risk — CQL returns all matching contexts regardless of total context count, and (2) client-side prefix filtering — the server handles it, reducing payload size and client complexity.

**Fallback: context list.** If the CQL search endpoint returns 404 (indicating an older CXDB version that lacks CQL support), the UI falls back to the full context list:

```
GET /v1/contexts?limit=10000
```

The fallback endpoint supports a `limit` query parameter (default: 20) controlling the maximum number of contexts returned. Contexts are returned in **descending order by creation time** (newest first), matching CXDB's `list_recent_contexts` implementation which sorts by `created_at_unix_ms` descending. The UI passes `limit=10000` to ensure all contexts are returned — the default of 20 is insufficient when non-Kilroy contexts (e.g., Claude Code sessions) accumulate on the instance.

**Fallback truncation risk.** The `limit=10000` value is a heuristic. If a CXDB instance accumulates more than 10,000 contexts over its lifetime (plausible on a shared development server running for weeks), the oldest contexts will be truncated from the response. Because contexts are ordered newest-first, this truncation affects the oldest contexts. Active Kilroy pipeline contexts are typically recent and unlikely to be truncated, but long-running pipelines on busy instances could be affected. The failure mode is silent: pipelines whose contexts are truncated will not be discovered, and no error is surfaced. This truncation risk is the primary reason to prefer CQL search.

The fallback endpoint also supports a `tag` query parameter for server-side filtering: `GET /v1/contexts?tag=kilroy/...` returns only contexts whose `client_tag` matches the given value exactly. The UI does not use server-side tag filtering because the `run_id` portion of the Kilroy tag varies; the CQL `^=` operator handles prefix matching instead.

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
| `limit` | `64` | Maximum number of turns to return (parsed as u32; no server-enforced maximum). The UI uses 100 for polling and discovery pagination. |
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
| `com.kilroy.attractor.RunStarted` | First turn in a context (pipeline-level) | `graph_name`, `run_id` |
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

Kilroy contexts are identified by their `client_tag`, which follows the format `kilroy/{run_id}`. The UI uses the CQL search endpoint (Section 5.2) as the primary discovery mechanism, with a fallback to the full context list for older CXDB versions. On each discovery call, the UI first attempts `GET /v1/contexts/search?q=tag ^= "kilroy/"`. If the endpoint returns 404, the UI sets a per-instance `cqlSupported` flag to `false` and falls back to `GET /v1/contexts?limit=10000` with client-side prefix filtering. The `cqlSupported` flag is checked on subsequent polls to skip the CQL attempt — it is reset when the CXDB instance becomes unreachable and then reconnects (since the instance may have been upgraded). When using CQL search, the server returns only `kilroy/`-prefixed contexts, eliminating the need for client-side prefix filtering and the 10,000-context limit heuristic. When using the fallback, the context list request must include `limit=10000` to override the CXDB default of 20 — without this, instances with many non-Kilroy contexts (e.g., Claude Code sessions) may push Kilroy contexts outside the default 20-context window.

```
FUNCTION discoverPipelines(cxdbInstances, knownMappings, cqlSupported):
    FOR EACH (index, instance) IN cxdbInstances:
        -- Phase 1: Fetch Kilroy contexts (CQL search or fallback)
        IF cqlSupported[index] != false:
            TRY:
                searchResponse = fetchCqlSearch(index, 'tag ^= "kilroy/"')
                contexts = searchResponse.contexts
                cqlSupported[index] = true
            CATCH httpError:
                IF httpError.status == 404:
                    cqlSupported[index] = false
                    contexts = fetchContexts(index, limit=10000)  -- fallback
                ELSE IF httpError.status == 400:
                    -- CQL is supported but the query was rejected. Log the error
                    -- for debugging. Do NOT set cqlSupported[index] = false (CQL works,
                    -- the query just failed). Skip this instance for this poll cycle.
                    logWarning("CQL query error on instance " + index + ": " + httpError.body.error)
                    CONTINUE
                ELSE:
                    CONTINUE  -- instance unreachable, skip
        ELSE:
            contexts = fetchContexts(index, limit=10000)

        FOR EACH context IN contexts:
            key = (index, context.context_id)
            IF key IN knownMappings:
                CONTINUE  -- already discovered (positive or negative)

            -- When using fallback (no CQL), apply client-side prefix filter
            IF cqlSupported[index] == false:
                IF context.client_tag IS null OR NOT context.client_tag.startsWith("kilroy/"):
                    knownMappings[key] = null  -- not a Kilroy context
                    CONTINUE

            -- Phase 2: Fetch RunStarted turn (first turn of the context)
            -- fetchFirstTurn may fail due to transient errors (non-200 response,
            -- instance temporarily unreachable, msgpack decode failure). Distinguish
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
                -- Guard against null or empty graph_name. The registry bundle
                -- marks graph_name as optional, so a valid RunStarted can have
                -- graph_name absent or empty. Such a context can never match
                -- any pipeline. Cache it as null (same as non-Kilroy) since
                -- the first turn is immutable — retrying would not help.
                IF graphName IS null OR graphName == "":
                    knownMappings[key] = null
                    CONTINUE
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

**Fetching the first turn.** CXDB returns turns oldest-first (ascending by position in the parent chain). The `before_turn_id` parameter paginates backward from a given turn ID. To reach the first turn of a context, the algorithm paginates backward from the head in bounded pages rather than fetching the entire context in a single request. This avoids O(headDepth) memory and latency costs — CXDB's `get_last` walks the parent chain sequentially, serializes every turn including decoded payloads, and transfers the entire response over HTTP. For deep contexts (headDepth in the tens of thousands), a single unbounded request could produce hundreds of megabytes of JSON, all of which would be discarded except the first turn.

**Using `view=raw` for discovery.** The `fetchFirstTurn` algorithm uses `view=raw` instead of the default `view=typed`. This eliminates the type registry dependency for pipeline discovery. The `declared_type` field (containing `type_id` and `type_version`) is present in both `view=raw` and `view=typed` responses — it comes from the turn metadata, not the type registry. For the `RunStarted` data fields (`graph_name`, `run_id`), `view=raw` returns the raw msgpack payload as base64-encoded bytes in the `bytes_b64` field. The UI decodes this client-side: base64-decode to bytes, then msgpack-decode to extract the known `RunStarted` fields. This avoids the bootstrap ordering problem where the type registry bundle has not yet been published when the UI first discovers a pipeline (the registry is typically published by the Kilroy runner at the start of the run). Without `view=raw`, `fetchFirstTurn` would fail for all contexts during the window between context creation and registry publication, delaying pipeline discovery by 1-3 poll cycles (3-9 seconds). The regular turn polling (Section 6.1 step 4) continues using the default `view=typed` for the status overlay, since those fields are more complex and benefit from server-side projection.

```
FUNCTION fetchFirstTurn(cxdbIndex, contextId, headDepth):
    IF headDepth == 0:
        -- Context has at most one turn; limit=1 returns it if present.
        -- An empty context (just created, no turns yet) also has headDepth 0,
        -- so guard against an empty response.
        -- Use view=raw to avoid type registry dependency.
        response = fetchTurns(cxdbIndex, contextId, limit=1, view="raw")
        IF response.turns IS EMPTY:
            RETURN null
        RETURN decodeFirstTurn(response.turns[0])

    -- Paginate backward from the head in bounded pages.
    -- Each page fetches up to PAGE_SIZE turns (100). Check whether the page
    -- contains a turn with depth == 0 (the first turn). If not, continue
    -- paginating using before_turn_id. Cap at MAX_PAGES (50) to prevent
    -- runaway pagination for extremely deep contexts.
    -- Use view=raw to avoid type registry dependency.
    PAGE_SIZE = 100
    MAX_PAGES = 50
    cursor = 0  -- 0 means "start from head" (no before_turn_id)

    FOR page = 1 TO MAX_PAGES:
        IF cursor == 0:
            response = fetchTurns(cxdbIndex, contextId, limit=PAGE_SIZE, view="raw")
        ELSE:
            response = fetchTurns(cxdbIndex, contextId, limit=PAGE_SIZE, before_turn_id=cursor, view="raw")

        IF response.turns IS EMPTY:
            RETURN null

        -- Turns are oldest-first. Check if depth=0 is in this page.
        IF response.turns[0].depth == 0:
            RETURN decodeFirstTurn(response.turns[0])

        -- The oldest turn in this page is not depth=0. Continue paginating.
        cursor = response.turns[0].turn_id  -- oldest turn's ID becomes the next before_turn_id
        -- CXDB's get_before walks backward from before_turn_id's parent,
        -- so the next page will contain turns older than this one.

    -- Exceeded MAX_PAGES without finding depth=0.
    -- This context is too deep for first-turn discovery. Return null so it
    -- is retried on subsequent polls (not cached as a negative result).
    RETURN null

FUNCTION decodeFirstTurn(rawTurn):
    -- Extract declared_type (available in both raw and typed views)
    typeId = rawTurn.declared_type.type_id
    IF typeId != "com.kilroy.attractor.RunStarted":
        RETURN { declared_type: rawTurn.declared_type, data: null }

    -- Decode the raw msgpack payload to extract graph_name and run_id.
    -- The raw payload uses integer tags as map keys (not field names).
    -- Go's msgpack encoder produces string-encoded integer keys (e.g., the
    -- string "1" instead of the integer 1). CXDB's key_to_tag function
    -- (store.rs, projection/mod.rs) handles both forms. The browser-side
    -- decoder must do the same: for each map key, try parseInt if it is a
    -- string, or use the integer directly.
    --
    -- RunStarted field tags (from kilroy-attractor-v1 bundle, version 1):
    --   Tag 1: run_id (string)
    --   Tag 8: graph_name (string, optional)
    -- These tags are stable within bundle version 1. CXDB's type registry
    -- versioning model ensures existing tags are never reassigned — new
    -- bundle versions add fields with new tags. The full RunStarted v1
    -- field inventory is: run_id (1), timestamp_ms (2), repo_path (3),
    -- base_sha (4), run_branch (5), logs_root (6), worktree_dir (7),
    -- graph_name (8), goal (9), modeldb_catalog_sha256 (10),
    -- modeldb_catalog_source (11). Only tags 1 and 8 are used by the UI.
    bytes = base64Decode(rawTurn.bytes_b64)
    payload = msgpackDecode(bytes)
    -- Access fields by their integer tag (or string-encoded integer key).
    -- The || fallback handles both string-encoded integer keys (Go's
    -- msgpack encoder) and integer keys (other encoders).
    RETURN {
        declared_type: rawTurn.declared_type,
        data: { graph_name: payload["8"] || payload[8], run_id: payload["1"] || payload[1] }
    }
```

**Cross-context traversal for forked contexts.** The `fetchFirstTurn` pagination follows CXDB's parent chain via `parent_turn_id` links. For forked contexts (created for parallel branches), the parent chain extends across context boundaries — the child context's turns link back to the parent context's turns via the fork point's `parent_turn_id`. Walking to depth 0 therefore discovers the parent context's `RunStarted` turn, not a turn within the child context. This is correct because Kilroy's parallel branch contexts share the parent's `RunStarted` (same `graph_name`, same `run_id`) via the linked parent chain. CXDB's `get_before` implementation (`turn_store/mod.rs`) walks `parent_turn_id` without any context boundary check, confirming this cross-context traversal. If a future Kilroy version emits a new `RunStarted` in each forked child context, the pagination would still work (it would find the child's `RunStarted` at the child's depth-0 position), but the current behavior discovers the parent's `RunStarted` instead.

**Pagination cost.** In the worst case (headDepth = 5000), fetching the first turn requires 50 paginated requests of 100 turns each. For typical Kilroy contexts (headDepth < 1000), this completes in under 10 pages. The `client_tag` prefix filter (Phase 1) ensures pagination only runs for Kilroy contexts, not for unrelated contexts that may share the CXDB instance. Each page request transfers at most 100 turns worth of JSON (roughly 50–200 KB depending on payload size), avoiding the memory spike of a single unbounded request. The `MAX_PAGES` cap of 50 means contexts deeper than ~5000 turns are skipped for discovery; these are retried on subsequent polls in case the depth was a transient artifact.

**Note on CXDB internals.** The CXDB turn store has a `get_first_turn` method that walks back from the head to find depth=0 directly, but this is not exposed via the HTTP API. If a future CXDB release adds an HTTP endpoint for fetching the first turn (or exposes the binary protocol's `GetRangeByDepth` over HTTP), the pagination approach here should be replaced with a single targeted request. This runs once per context (results are cached).

The `graph_name` from the `RunStarted` turn is matched against the graph ID in each loaded DOT file (the identifier after `digraph` in the DOT source). Contexts whose `graph_name` matches the currently displayed pipeline are used for the status overlay — regardless of which CXDB instance they reside on.

The `RunStarted` turn also contains a `run_id` field (see Section 5.4 for the full field inventory) that uniquely identifies the pipeline run. All contexts belonging to the same run (e.g., parallel branches) share the same `run_id`. The discovery algorithm records both `graph_name` and `run_id` for each context.

**Caching.** The context-to-pipeline mapping is cached in memory, keyed by `(cxdb_index, context_id)`. Both positive results (RunStarted contexts mapped to a pipeline) and negative results (non-Kilroy contexts and confirmed non-RunStarted contexts stored as `null`) are cached. The first turn of a context is immutable — once a context is successfully classified, it is never re-fetched. Only newly appeared context IDs (and previously failed or empty fetches that were not cached) trigger discovery requests. The `client_tag` prefix filter (whether server-side via CQL or client-side in the fallback path) prevents fetching turns for non-Kilroy contexts entirely. Two cases are left unmapped (not cached as `null`) and retried on subsequent polls: (a) when a `fetchFirstTurn` call fails due to a transient error (non-200 response, timeout), and (b) when `fetchFirstTurn` returns `null` (empty context with no turns yet — common during early pipeline startup or transient CXDB lag). This prevents both transient failures and premature classification of empty contexts from permanently classifying a valid Kilroy context as non-Kilroy.

**`client_tag` stability requirement.** The `client_tag` prefix filter assumes `client_tag` is stable across polls. CXDB resolves `client_tag` with a fallback chain: first from stored metadata (extracted from the first turn's msgpack payload key 30), then from the active session's tag. If the first turn's payload does not include context metadata (key 30 is absent), the `client_tag` in the context list is only present while the session is active (`is_live == true`). Once the session disconnects, `client_tag` becomes `null`, and the UI's prefix filter would fail to match — permanently excluding the context from discovery if it has already been cached as non-Kilroy. **Kilroy must embed `client_tag` in the first turn's context metadata** (key 30) for reliable classification. This is the expected integration pattern and is likely already the case, but the spec states this requirement explicitly rather than treating `client_tag` as an opaque stable field.

**Metadata labels optimization (not required for initial implementation).** The CXDB server extracts and caches metadata from the first turn of every context (key 30 of the msgpack payload), including `client_tag`, `title`, and `labels`. If Kilroy embeds `graph_name` and `run_id` in the context metadata labels (e.g., `["kilroy:graph=alpha_pipeline", "kilroy:run=01KJ7..."]`), the UI could read them from the context list response's `labels` field, eliminating all `fetchFirstTurn` pagination. However, the CQL search response (the primary discovery path) does not include `labels` — only the full context list endpoint does (Section 5.2). This means the optimization is incompatible with the CQL-first discovery path without one of: (a) falling back to the context list endpoint (losing CQL's scalability benefits), (b) making separate per-context requests to `GET /v1/contexts/{id}` which does return `labels`, (c) a CXDB enhancement to include `labels` in CQL search results, or (d) using server-side SSE subscription (non-goal #11) — the `ContextMetadataUpdated` SSE event carries `labels` (confirmed in CXDB's `events.rs` and `http/mod.rs`), so the Go proxy server could collect labels from these events and serve them without per-context HTTP requests, elegantly bypassing both the CQL limitation and per-context HTTP overhead. Option (d) is the most efficient workaround because it avoids polling entirely for metadata discovery, but it requires the server-side SSE infrastructure described in non-goal #11. This is a Kilroy-side change (not a CXDB change) that would simplify discovery significantly but requires solving the CQL `labels` gap. The pagination approach works correctly today and is used for the initial implementation.

**Context lineage optimization (not required for initial implementation).** CXDB tracks cross-context lineage via `ContextLinked` events. When a context is forked from another (e.g., for parallel branches), CXDB records `parent_context_id`, `root_context_id`, and `spawn_reason` in the context's provenance. The context list endpoint returns this data when `include_lineage=1` is passed. A future optimization could use lineage to skip `fetchFirstTurn` for child contexts: if a child's `parent_context_id` is already in `knownMappings`, the child inherits the parent's `graph_name`/`run_id` mapping. This would reduce discovery latency proportionally to the number of parallel branches. The current approach (fetching the first turn independently for each context) is correct but performs redundant work for forked contexts that share the same `RunStarted` data.

**Multiple runs of the same pipeline.** When CXDB contains contexts from multiple runs of the same pipeline (same `graph_name`, different `run_id`), the UI uses only the most recent run. The most recent run is determined by the highest `created_at_unix_ms` among the `RunStarted` contexts for that pipeline. Contexts from older runs are ignored for status overlay purposes. This prevents stale data from a completed run from conflicting with an in-progress run.

**Cross-instance merging.** If contexts from the same run (same `run_id`) exist on multiple CXDB instances (e.g., parallel branches written to separate servers), their turns are merged into a single status map. The UI does not distinguish which CXDB instance a turn came from.

---

## 6. Status Overlay

### 6.1 Polling

The UI polls all configured CXDB instances every 3 seconds. Each poll cycle:

1. For each CXDB instance, fetch Kilroy contexts using the CQL search endpoint or fallback (see Section 5.2 and 5.5's `discoverPipelines` for the CQL/fallback selection logic). On success, store the response contexts in `cachedContextLists[i]` (replacing any previous cached value). If an instance is unreachable (502), skip it, retain its per-context status maps from the last successful poll, and use `cachedContextLists[i]` as the context list for that instance in subsequent steps. This ensures that `lookupContext`, `determineActiveRuns`, and `checkPipelineLiveness` continue to function using the last known context data during transient outages — preserving active-run determination and liveness signals rather than losing them.
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

The `lookupContext` helper finds the context object (from step 1's context list responses) by `(cxdb_index, context_id)` to access `created_at_unix_ms`. The `resetPipelineState` helper clears the per-context status maps, `lastSeenTurnId` cursors, and per-pipeline turn cache for all contexts that belonged to the old run. It also removes `knownMappings` entries whose `runId` matches the old run's `run_id`. These entries are removed for memory hygiene: old-run entries will never match the active run and would accumulate indefinitely across successive runs. (CXDB context IDs are monotonically increasing integers allocated from a global counter and are never reused, so there is no risk of a future context reusing an old ID.) Entries for the new run and entries with `null` mappings (negative caches) are retained.

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
-- Bounded to MAX_GAP_PAGES (10) to prevent a long outage from blocking the poller.
MAX_GAP_PAGES = 10
recoveredTurns = []
cursor = response.next_before_turn_id
pagesFetched = 0
WHILE cursor IS NOT null AND pagesFetched < MAX_GAP_PAGES:
    gapResponse = fetchTurns(cxdbIndex, contextId, limit=100, before_turn_id=cursor)
    pagesFetched = pagesFetched + 1
    IF gapResponse.turns IS EMPTY:
        BREAK
    recoveredTurns = gapResponse.turns + recoveredTurns  -- prepend to maintain oldest-first
    -- Check if we've reached lastSeenTurnId
    oldestInGap = gapResponse.turns[0].turn_id  -- oldest turn in page (oldest-first ordering)
    IF oldestInGap <= lastSeenTurnId:
        BREAK
    cursor = gapResponse.next_before_turn_id

-- If the page limit was hit before reaching lastSeenTurnId, advance the cursor
-- to the oldest recovered turn. Some intermediate turns are lost, but the persistent
-- status map ensures statuses are never demoted, and the next poll's 100-turn window
-- will contain the most recent state.
IF pagesFetched >= MAX_GAP_PAGES AND cursor IS NOT null:
    lastSeenTurnId = recoveredTurns[0].turn_id  -- oldest recovered turn becomes new cursor

-- Prepend recovered turns to the main batch
turns = recoveredTurns + turns
```

This ensures lifecycle events (e.g., `StageFinished`) that occurred during a CXDB outage are not permanently lost. The gap recovery procedure runs at most once per context per poll cycle. Within the procedure, up to `MAX_GAP_PAGES` (10) paginated requests are issued (one per 100 turns, covering up to 1,000 missed turns). This bounds recovery time: a context with thousands of accumulated turns during a long outage will recover the most recent 1,000 turns and advance the cursor, rather than blocking the entire poll cycle with dozens of sequential HTTP requests. The tradeoff is that intermediate turns beyond the 1,000-turn window are lost — but because statuses are never demoted (Section 6.2), any promotions from lost turns are not critical. The next poll cycle's 100-turn window contains the most recent state. The recovered turns are prepended (in oldest-first order) to the context's turn batch before step 5 caches them and step 6 processes them for status derivation.

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

**Error heuristic window limitation.** The turn cache is replaced (not appended) on each successful fetch (Section 6.1, step 5). The error heuristic therefore only detects errors visible in the current 100-turn fetch window. If 3 error ToolResults span across two poll cycles — for example, 2 errors in the previous poll's window and 1 in the current window — only the current window's turns are available, and the heuristic would not fire. This means slow error loops (where errors are spaced more than ~100 turns apart across all turn types in the context) will not trigger the heuristic. This is acceptable for the initial implementation: the heuristic targets rapid error loops where the agent retries the same failing command in quick succession, producing many ToolResult turns per poll window. Slow error loops (one error every few minutes with hundreds of intervening turns) are an atypical pattern that is better addressed by lifecycle turns (`StageFailed`) or operator observation.

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

**Context-grouped display.** When the selected node has matching turns across multiple contexts (e.g., parallel branches), turns are displayed grouped by context rather than interleaved. Each context's turns appear in a collapsible section labeled with the CXDB instance index and context ID (e.g., "CXDB-0 / Context 33"). Within each section, turns are displayed newest-first (the UI reverses the API's oldest-first order) by `turn_id` — this is safe because `turn_id` is monotonically increasing within a single context's parent chain (see Section 6.2). Sections are ordered using a two-level sort: first by CXDB instance index (lower index first), then by highest `turn_id` among the context's matching turns (descending — most recent first). This groups contexts by instance, where `turn_id` comparison is meaningful (monotonically increasing within a single instance), and uses a stable, deterministic ordering across instances. CXDB instances have independent turn ID counters with no temporal relationship, so cross-instance `turn_id` comparison is not attempted.

| Column | Source | Description |
|--------|--------|-------------|
| Type | `declared_type.type_id` | Turn type (ToolCall, ToolResult, Prompt, etc.) |
| Tool | `data.tool_name` | Tool invoked (e.g., `shell`, `write_file`) — blank for non-tool turns |
| Output | varies by type (see mapping below) | Truncated content (expandable) |
| Error | `data.is_error` | Highlighted if true — only applicable to ToolResult |

**Per-type rendering.** The Output column content varies by turn type:

| Turn Type | Output Column | Tool Column | Error Column |
|-----------|--------------|-------------|--------------|
| `Prompt` | `data.text` | blank | blank |
| `ToolCall` | `data.arguments_json` | `data.tool_name` | blank |
| `ToolResult` | `data.output` | `data.tool_name` | `data.is_error` (highlighted if true) |
| `StageStarted` | "Stage started" (fixed label) | blank | blank |
| `StageFinished` | "Stage finished" (fixed label) | blank | blank |
| `StageFailed` | "Stage failed" (fixed label) | blank | blank |
| Other/unknown | "[unsupported turn type]" (placeholder) | blank | blank |

This mapping ensures all turn types that may appear in the turn cache render meaningfully. Lifecycle turns (StageStarted, StageFinished, StageFailed) use fixed labels since their data fields (node_id, timestamp_ms, status) are already reflected in the node status overlay and do not need detailed rendering.

Within each context section, turns are displayed newest-first (reversed from the API's oldest-first order for better UX — most recent activity at the top). All `turn_id` comparisons used for ordering within the detail panel — both within-context sorting and cross-context section ordering — must be numeric (`parseInt(turn_id, 10)`), consistent with Section 6.2. Lexicographic comparison breaks for IDs of different digit lengths (e.g., `"999" > "1000"` lexicographically). The panel shows at most 20 turns per context section. If all of a node's turns have scrolled out of the 100-turn poll window (i.e., the node completed early and subsequent nodes have generated many turns), the detail panel shows the node's DOT attributes but displays "No recent CXDB activity" in place of the turn list. The node's status remains correct via the persistent status map (Section 6.2).

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

11. **No browser-side SSE event streaming.** CXDB exposes a `/v1/events` Server-Sent Events endpoint for real-time push notifications (e.g., `TurnAppended`, `ContextCreated`). The browser uses polling instead for simplicity — no persistent connection management, simpler error recovery, and 3-second latency is sufficient for the "mission control" use case. Note: the Go proxy server could optionally subscribe to CXDB's SSE endpoint server-side (using the Go client's `SubscribeEvents` function with automatic reconnection) to reduce discovery latency — e.g., immediately triggering discovery when a `ContextCreated` event with a `kilroy/`-prefixed `client_tag` arrives, without waiting for the next poll cycle. This is not required for the initial implementation but is a lower-complexity design point than browser-side SSE, since the browser's polling architecture remains unchanged.

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
