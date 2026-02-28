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
12. [Testing Requirements](#12-testing-requirements)

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
    │ :9110       │         │ :9111       │
    └─────────────┘         └─────────────┘
```

**Why Go.** Go is already a dependency in the Attractor/Kilroy ecosystem. The server uses only the standard library — no external packages. A minimal `go.mod` is required (Go 1.16+ defaults to module-aware mode and refuses to compile without one). The `go.mod` lives in `ui/` alongside `main.go` with module name `cxdb-graph-ui` and a minimum Go version matching the host toolchain (e.g., `go 1.21`). It runs with `go run ui/main.go`.

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
| `--cxdb` | URL (repeatable) | `http://127.0.0.1:9110` | CXDB HTTP API base URL. May be specified multiple times for multiple CXDB instances. |
| `--dot` | path (repeatable) | (required) | Path to a pipeline DOT file. May be specified multiple times. |

Both `--dot` and `--cxdb` are repeatable. The UI auto-discovers which CXDB instances contain contexts for which pipelines (Section 5.5). No manual pairing is required.

If no `--cxdb` flags are provided, the default (`http://127.0.0.1:9110`) is used as the sole instance. If no `--dot` flags are provided, the server exits with an error message and usage help.

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
  --cxdb http://127.0.0.1:9110 \
  --cxdb http://127.0.0.1:9111

# Custom CXDB address
go run ui/main.go --dot pipeline.dot --cxdb http://10.0.0.5:9110
```

The server prints the URL on startup: `Kilroy Pipeline UI: http://127.0.0.1:9030`

### 3.2 Routes

#### `GET /` — Dashboard

Serves `index.html` embedded in the binary via Go's `//go:embed` directive. The `main.go` file embeds `index.html` at compile time using `//go:embed index.html`, serving it from the embedded filesystem. This ensures the asset is always available regardless of the working directory — `go run ui/main.go` compiles the binary in a temp directory, so runtime file resolution relative to the source would fail. Returns 500 if the embed fails to load (should not happen in a correctly compiled binary).

**`index.html` file location.** The `//go:embed` directive resolves paths relative to the source file's package directory. Therefore `index.html` must reside at `ui/index.html`, co-located with `ui/main.go`. Placing `index.html` anywhere else (e.g., at the repository root) will cause a compile error: `pattern index.html: no matching files found`. Both files must be in the same directory (`ui/`).

#### `GET /dots/{name}` — DOT Files

Serves DOT files registered via `--dot` flags. The `{name}` is the base filename (e.g., `pipeline-alpha.dot`).

- The server builds a map from base filename to absolute path at startup. If two `--dot` flags resolve to the same base filename (e.g., `pipelines/alpha/pipeline.dot` and `pipelines/beta/pipeline.dot` both have basename `pipeline.dot`), the server exits with a non-zero code and prints an error identifying the conflicting paths. This prevents silent collisions where one pipeline becomes unreachable.
- **Graph ID uniqueness.** At startup, the server parses each DOT file to extract its graph ID. The server uses the same graph ID parsing and normalization logic as the browser (Section 4.4): the regex `/^\s*(strict\s+)?(di)?graph\s+("(?:[^"\\]|\\.)*"|\w+)/m` extracts the identifier, quoted IDs are unquoted (outer `"` stripped) and unescaped (internal `\"` → `"`, `\\` → `\`), leading/trailing whitespace is trimmed, and the result is the normalized graph ID. This is the same normalization applied to node IDs (see `/dots/{name}/nodes` below). The `strict` keyword prefix is optional and consumed but does not affect the extracted ID. If the regex does not match (e.g., anonymous graphs like `digraph { ... }` with no identifier after the keyword), the server rejects the DOT file at startup with a non-zero exit code and an error message stating that named graphs are required for pipeline discovery (since `RunStarted.data.graph_name` must match the graph ID). This ensures that the server's uniqueness check and the browser's pipeline discovery match `RunStarted.data.graph_name` against the same normalized value. If two DOT files share the same normalized graph ID, the server exits with a non-zero code and prints an error identifying the conflicting files and graph ID. Duplicate graph IDs would cause ambiguous pipeline discovery — both pipelines would match the same CXDB contexts, producing identical and misleading status overlays. This check mirrors the basename collision check and runs at startup alongside it.
- Only filenames registered via `--dot` are servable. Requests for unregistered names return 404.
- Files are read fresh on each request. DOT file regeneration is picked up without server restart. If the registered file cannot be read from disk (e.g., deleted after server startup, permission error), the server returns 500 with a plain-text error body describing the failure. The browser handles non-200 responses from `/dots/{name}` by displaying an error message in the graph area (replacing the SVG). Recovery is automatic — the file is re-read on every request, so restoring the file resolves the error on the next fetch (tab switch or initial load).

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
- **Named nodes only:** Global default blocks (`node [...]`, `edge [...]`, `graph [...]`) are excluded. Only named node definitions (e.g., `implement [shape=box, prompt="..."]`) are parsed. **Kilroy-generated DOT files always define `shape` explicitly on every node** (verified against actual Kilroy pipeline DOT files — e.g., `start [shape=Mdiamond]`, `implement [shape=box, ...]`, `check_fmt [shape=diamond]`). Default `node [...]` attributes are therefore not needed for `shape` resolution. If a node lacks an explicit `shape` attribute, the detail panel's Type field (Section 7.3) displays no type label rather than falling back to a Graphviz default. Supporting inherited default attributes is not required.
- **Subgraph scope:** Nodes defined inside `subgraph` blocks are included.
- **Escape sequences:** Quoted attribute values support these DOT escapes: `\"` → `"`, `\n` → newline, `\\` → `\`. Other escape sequences are passed through verbatim.
- **Comment handling:** The parser must strip DOT comments before parsing node and edge definitions: `//` line comments (from `//` to end of line, preserving the newline) and `/* */` block comments (from `/*` to the next `*/`). Comments inside double-quoted strings are not stripped — the parser must track whether it is inside a quoted string (with escape handling for `\"` and `\\`) and only recognize comment delimiters outside of strings. For example, `prompt="check http://example.com"` must not be treated as containing a line comment. An unterminated block comment (`/*` with no matching `*/`) is a parse error. An unterminated string (a `"` with no matching closing `"` before end of input) encountered during comment stripping is also a parse error. This matches Kilroy's `stripComments` function (`kilroy/internal/attractor/dot/comments.go`), which returns errors for both unterminated block comments (line 56) and unterminated strings (line 67), and preprocesses DOT source before lexing using the same rules. Kilroy-generated DOT files from the YAML-to-DOT compiler may not contain comments, but the "Generic pipeline support" principle (Section 1.2) means hand-edited or annotated DOT files commonly do.

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
{ "instances": ["http://127.0.0.1:9110", "http://127.0.0.1:9111"] }
```

### 3.3 Server Properties

- The server is stateless. It caches nothing. Every request reads from disk or proxies to CXDB.
- The server uses only Go standard library packages. No external dependencies. A minimal `go.mod` (module `cxdb-graph-ui`, no `require` directives) lives in `ui/` alongside `main.go` — required because Go 1.16+ operates in module-aware mode by default.
- The server binds to `0.0.0.0:{port}` (all interfaces).
- Requests to paths not matching any registered route return 404 with a plain-text body. The server does not serve directory listings, automatic redirects, or HTML error pages for unmatched routes.

---

## 4. DOT Rendering

### 4.1 Graphviz WASM

The browser loads `@hpcc-js/wasm-graphviz` from the esm.sh CDN at a pinned version:

```
https://esm.sh/@hpcc-js/wasm-graphviz@1.6.1
```

This URL serves a valid ES module (`export * from "/@hpcc-js/wasm-graphviz@1.6.1/es2022/wasm-graphviz.mjs"`) compatible with `<script type="module">` imports. The jsDelivr CDN URL (`dist/index.min.js`) for this package is a UMD bundle, not an ES module — importing it with `<script type="module">` would produce a `SyntaxError: The requested module does not provide an export named 'Graphviz'` error and block SVG rendering entirely. The esm.sh CDN handles the ESM transformation for this package.

This library compiles Graphviz to WebAssembly and exposes a `Graphviz` named export. The expected import and usage pattern is:

```javascript
import { Graphviz } from "https://esm.sh/@hpcc-js/wasm-graphviz@1.6.1";
const gv = await Graphviz.load();
const svg = gv.layout(dotString, "svg", "dot");
```

The UI calls `gv.layout(dotString, "svg", "dot")` with the raw DOT file content fetched from `/dots/{name}`. The resulting SVG is injected into the main content area.

If the Graphviz CDN is unreachable, the WASM module fails to load and the graph area displays an error message. The rest of the UI (tabs, connection indicator) still renders — this requires that CDN dependencies are loaded with import isolation (see Section 4.1.1) so that a failure in one dependency does not prevent the module from executing.

### 4.1.1 Browser Dependencies

The browser loads two CDN dependencies. Both are ES modules used in `index.html`:

**Import isolation.** To uphold the graceful degradation principle (Section 1.2), CDN dependencies must not share a single top-level `import` scope where one failure prevents all JavaScript from executing. The msgpack decoder — used only for CXDB pipeline discovery (`decodeFirstTurn`, Section 5.5) — must be loaded via dynamic `import()` with error handling, not as a top-level `import` statement. This ensures that if the msgpack CDN is unreachable or returns an error, DOT rendering, tab creation, and the connection indicator still function. The Graphviz WASM dependency may remain a top-level import since DOT rendering is the UI's primary function and cannot proceed without it. The recommended pattern for msgpack is a lazy singleton loaded on first use:

```javascript
let msgpackModule = null;
async function getMsgpack() {
    if (!msgpackModule) {
        msgpackModule = await import("https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/index.mjs");
    }
    return msgpackModule;
}
```

If the dynamic `import()` fails, `decodeFirstTurn` returns `null` for the affected context, and pipeline discovery falls back to retrying on the next poll cycle. DOT rendering and the rest of the UI are unaffected.

1. **Graphviz WASM** — `@hpcc-js/wasm-graphviz` at pinned version via esm.sh (documented above in Section 4.1). Used for DOT-to-SVG rendering.

2. **Msgpack decoder** — `@msgpack/msgpack` at a pinned CDN URL:

```
https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/index.mjs
```

The expected usage pattern is via the `getMsgpack()` lazy loader (see "Import isolation" above):

```javascript
const { decode } = await getMsgpack();
const payload = decode(uint8ArrayBytes);
```

This library provides a `decode(Uint8Array)` named export that decodes msgpack bytes into JavaScript objects. It is used exclusively by `decodeFirstTurn` (Section 5.5) to extract `graph_name` and `run_id` from the raw msgpack payload of `RunStarted` turns fetched with `view=raw`. It is not used during regular turn polling (`view=typed`), which returns pre-decoded JSON.

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

**CXDB `node_id` matching assumption.** The UI assumes that `turn.data.node_id` values from CXDB are already normalized — i.e., they match the normalized DOT node IDs produced by the server's `/nodes` endpoint and the SVG `<title>` text. No additional normalization (unquoting, unescaping, trimming) is applied to CXDB `node_id` values before comparison. This assumption holds for Kilroy-generated CXDB data because Kilroy's DOT parser normalizes node IDs during parsing (`dot/parser.go`), stores them as `model.Node.ID`, and passes `node.ID` directly to CXDB event functions (`cxdb_events.go`). The CXDB `node_id` is therefore already the normalized form. Non-Kilroy pipelines that emit raw (un-normalized) DOT identifiers as CXDB `node_id` values (e.g., including outer quotes or escape sequences) would not match. Supporting such pipelines would require normalizing CXDB `node_id` values, which is out of scope for the initial implementation.

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

**Graph ID extraction.** The browser extracts the graph ID from the DOT source when the file is first fetched, using a regex pattern that handles both `digraph` and `graph` keywords, optional `strict` prefix, and both quoted and unquoted names: `/^\s*(strict\s+)?(di)?graph\s+("(?:[^"\\]|\\.)*"|\w+)/m`. The `strict` keyword prefix, if present, is consumed but does not affect the extracted ID. If the name is quoted, the UI unquotes it (strips the outer `"` characters), unescapes internal sequences (`\"` → `"`, `\\` → `\`), and trims leading/trailing whitespace before using it as the graph ID. This normalization is identical to node ID normalization (Section 3.2, `/dots/{name}/nodes`). If the regex does not match (e.g., anonymous graphs like `digraph { ... }`), the tab falls back to the base filename. However, the server rejects anonymous graphs at startup (Section 3.2), so in normal operation the regex always matches. The filename fallback exists only for defensive robustness if the browser-side regex encounters an edge case the server's identical regex did not. Tabs initially display filenames (from the `/api/dots` response) and update to graph IDs as each DOT file is fetched and parsed. Pipeline discovery in Section 5.5 matches `RunStarted.data.graph_name` against the normalized (unquoted, unescaped) graph ID.

**HTML escaping.** Tab labels (whether graph IDs or filenames) must be rendered as text-only — via `textContent` assignment or explicit HTML entity escaping (`<` → `&lt;`, `>` → `&gt;`, `&` → `&amp;`, `"` → `&quot;`). Graph IDs are extracted from user-provided DOT files and may contain characters like `<`, `&`, or `"`. Rendering via `innerHTML` would allow HTML injection in the tab bar. This matches the detail panel escaping policy (Section 7.1).

Switching tabs fetches the DOT file fresh and re-renders the SVG. On every tab switch (or any event that refetches a DOT file), the UI also refetches `GET /dots/{name}/nodes` and `GET /dots/{name}/edges` to refresh cached node/edge metadata and updates `dotNodeIds` for that pipeline. This ensures that DOT file regeneration (new nodes, removed nodes, changed prompts, updated edge labels) is reflected in the status overlay, detail panel, and human-gate choices — not just the SVG rendering. When the node list changes, new nodes are initialized as "pending" in the per-context status maps, and removed nodes are dropped from the maps. If a cached merged status map exists for the newly selected pipeline (computed by the polling loop — Section 6.1, step 6, which merges status maps for all loaded pipelines on every poll cycle), it is immediately reapplied to the new SVG (after reconciling with the refreshed `dotNodeIds`). Otherwise, all nodes start as pending. The next poll cycle refreshes the status with live data. This avoids a gray flash when switching between tabs for pipelines that have already been polled.

**Tab-switch error handling.** If the `/dots/{name}/nodes` fetch fails during a tab switch — whether 400 (DOT parse error), 404, 500, or network error — the browser logs a warning and retains the previous `dotNodeIds` for that pipeline (or falls back to an empty set if no previous data exists). This ensures that cached status maps are not discarded spuriously due to transient errors. If the `/dots/{name}/edges` fetch fails, the browser retains the previous edge list for that pipeline (or uses an empty list if none exists), keeping the rest of the detail panel functional. These failure policies mirror the initialization prefetch rules (Section 4.5, Step 4) and align with the graceful-degradation principle (Section 1.2). The DOT file fetch itself (for SVG rendering) is handled independently — a DOT fetch failure displays the Graphviz error in the graph area but does not affect the cached status overlay.

### 4.5 Initialization Sequence

When the browser loads `index.html`, the following sequence executes:

1. **Load Graphviz WASM** — Import `@hpcc-js/wasm-graphviz` from CDN. During loading, the graph area shows "Loading Graphviz...".
2. **Fetch DOT file list** — `GET /api/dots` returns available DOT filenames (as a JSON object with a `dots` array). Build the tab bar.
3. **Fetch CXDB instance list** — `GET /api/cxdb/instances` returns configured CXDB URLs.
4. **Prefetch node IDs and edges for all pipelines** — For every DOT filename returned by `/api/dots`, fetch `GET /dots/{name}/nodes` to obtain `dotNodeIds` and `GET /dots/{name}/edges` to obtain the edge list for each pipeline. The `/nodes` prefetch ensures that background polling (step 6) can compute per-context status maps for all pipelines from the first poll cycle, not just the active tab. Without this, the holdout scenario "Switch between pipeline tabs" (which expects cached status to be immediately reapplied with no gray flash) cannot be satisfied. The `/edges` prefetch ensures that human gate choices (derived from outgoing edge labels — Section 7.1) are available for the initially rendered pipeline without requiring a tab switch. Without this, clicking a human gate node on the first pipeline would show no choices until the user switches away and back. **Error handling:** If any `/nodes` prefetch fails — whether 400 (DOT parse error), 404 (DOT file removed between `/api/dots` and `/nodes`), 500 (internal server error), or network error — the browser logs a warning and proceeds with an empty `dotNodeIds` set for that pipeline. If any `/edges` prefetch fails, the browser logs a warning and proceeds with an empty edge list for that pipeline. A failed prefetch must not block steps 5 or 6. The active tab still renders its SVG, and polling starts for all pipelines. The affected pipeline will have no status overlay (for `/nodes` failures) or no human gate choices (for `/edges` failures) until the next tab switch triggers a fresh fetch.
5. **Render first pipeline** — Fetch the first DOT file via `GET /dots/{name}`, render it as SVG.
6. **Start polling** — Trigger the first CXDB poll immediately (t=0). After each poll completes, schedule the next poll 3 seconds later via `setTimeout`. The first poll triggers pipeline discovery for all contexts.

Steps 2 and 3 run in parallel. Steps 4 and 5 require steps 1 and 2 to complete. Step 4 fetches node IDs and edges for all pipelines in parallel (both `/nodes` and `/edges` for each pipeline can be fetched concurrently). Step 5 may run concurrently with step 4's requests for non-first pipelines. Step 6 requires steps 3 and 4 to complete but does not block on step 5.

---

## 5. CXDB Integration

### 5.1 API Endpoints Consumed

The UI reads from CXDB HTTP APIs (default port 9110). All requests go through the server's `/api/cxdb/{index}/*` proxy, where `{index}` identifies the CXDB instance.

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
  "contexts": [],
  "total_count": 5,
  "elapsed_ms": 2,
  "query": "tag ^= \"kilroy/\""
}
```

Each context object in the `contexts` array contains: `context_id`, `head_turn_id`, `head_depth`, `created_at_unix_ms`, `is_live`, `client_tag` (from cached metadata), and `title` (from cached metadata). The CQL search response does **not** include `labels`, `session_id`, `last_activity_at`, `lineage`, `provenance`, `active_sessions`, or `active_tags` — the CQL endpoint builds lightweight context objects directly rather than calling the full `context_to_json` used by the context list endpoint. The absence of `labels` is significant for the metadata labels optimization (Section 5.5): since CQL search is the primary discovery path, the optimization cannot read `graph_name`/`run_id` from labels without per-context requests or a CXDB enhancement to include `labels` in CQL results. If the context lineage optimization (Section 5.5) is implemented in the future, the UI would need a separate context list request or individual context fetches for lineage data.

**`client_tag` resolution asymmetry.** The `client_tag` field is resolved differently between the two discovery endpoints:

- **CQL search**: `client_tag` comes from cached metadata only (extracted from the first turn's msgpack payload key 30, stored in `context_metadata_cache`). If metadata extraction has not yet occurred (context just created, first turn not yet appended or not yet processed), `client_tag` is absent from the context object.
- **Context list fallback**: `client_tag` comes from cached metadata first, then falls back to the active session's tag (`context_to_json`'s `.or_else` fallback to the active session's `client_tag`). This means `client_tag` is available for live contexts even before metadata extraction completes.

This difference means a context may appear in the fallback context list (with `client_tag` resolved from the active session) before it appears in CQL search results (which require cached metadata). The bootstrap lag note below covers the timing implications. An implementer testing with the context list fallback might observe `client_tag` appearing for all live contexts, then be surprised when switching to CQL to find it missing during the brief metadata extraction window for newly created contexts.

CQL results are sorted by `context_id` descending (most recent first), as implemented in CXDB's `store.rs`. Since CXDB allocates context IDs monotonically from a global counter, this is effectively equivalent to creation-time ordering. The context list fallback sorts by `created_at_unix_ms` descending — note that `created_at_unix_ms` on `ContextHead` is updated on every `append_turn` (`turn_store/mod.rs` lines 458-463), so this sort reflects the most recent *activity* time, not creation time. The `determineActiveRuns` algorithm (Section 6.1) does not depend on response ordering — it scans all candidates to find the maximum `context_id` — so this difference has no functional impact.

The CQL search endpoint also accepts an optional `limit` query parameter. When present, matching contexts are sorted by `context_id` descending and truncated to the specified count. The response's `total_count` field reflects the number of matching contexts **before** truncation — it may be larger than `contexts.length` when a `limit` is applied (CXDB's `store.rs` lines 389-392 compute `total_count` before `sorted_ids.truncate(limit)`). The UI omits `limit` to retrieve all Kilroy contexts, so `total_count == contexts.length` in normal operation. The discovery algorithm needs to see all contexts to determine the active run. Environments with hundreds of historical Kilroy runs will produce proportionally larger CQL search responses, but this is acceptable for the initial implementation — paginating CQL results would complicate discovery logic for a scenario that is not performance-critical at expected scale.

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

The fallback endpoint supports a `limit` query parameter (default: 20) controlling the maximum number of contexts returned. Contexts are returned in **descending order by `created_at_unix_ms`** (which reflects the most recent turn's timestamp, not the original context creation time — see `ContextHead.created_at_unix_ms` update semantics below), matching CXDB's `list_recent_contexts` implementation which sorts by `created_at_unix_ms` descending. The UI passes `limit=10000` to ensure all contexts are returned — the default of 20 is insufficient when non-Kilroy contexts (e.g., Claude Code sessions) accumulate on the instance.

**Fallback truncation risk.** The `limit=10000` value is a heuristic. If a CXDB instance accumulates more than 10,000 contexts over its lifetime (plausible on a shared development server running for weeks), the oldest contexts will be truncated from the response. Because contexts are ordered newest-first, this truncation affects the oldest contexts. Active Kilroy pipeline contexts are typically recent and unlikely to be truncated, but long-running pipelines on busy instances could be affected. The failure mode is silent: pipelines whose contexts are truncated will not be discovered, and no error is surfaced. This truncation risk is the primary reason to prefer CQL search.

The fallback endpoint also supports a `tag` query parameter for server-side filtering: `GET /v1/contexts?tag=kilroy/...` returns only contexts whose `client_tag` matches the given value exactly. The UI does not use server-side tag filtering because the `run_id` portion of the Kilroy tag varies; the CQL `^=` operator handles prefix matching instead. **Caution:** The `tag` query parameter filters AFTER the `limit` truncation. CXDB calls `list_recent_contexts(limit)` first (line 221), then applies `tag_filter` to the truncated result (lines 236-241). If 15,000 contexts exist and `limit=10000`, the oldest 5,000 are discarded before `tag` filtering runs. Matching contexts in the discarded tail are silently lost. This is an additional reason the UI uses client-side prefix filtering (for the fallback path) rather than server-side `tag` filtering — and why the CQL `^=` operator (which filters before response construction) is the preferred discovery path.

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

Each context object includes a `client_tag` field (optional string) identifying the application that created it. Kilroy sets this to `kilroy/{run_id}`. CXDB filters out empty-string `client_tag` values in the context list fallback endpoint — `context_to_json`'s `.filter(|t| !t.is_empty())` converts empty strings to `None`, which is omitted from the JSON response. The CQL search endpoint does not apply this filter (it reads directly from cached metadata), but `extract_context_metadata` stores whatever the msgpack payload contains, so an empty-string `client_tag` could theoretically appear in CQL results if the first turn's metadata key 1 is an empty string. In practice, Kilroy always sets a non-empty `client_tag` (`kilroy/{run_id}`), so this asymmetry has no functional impact. The `client_tag` field is either a non-empty string or absent (null) in normal operation. The UI's prefix filter need not check for empty strings. The `is_live` field is `true` when the context has an active session writing to it; the UI uses this for stale pipeline detection (see Section 6.2). Additional fields (`title`, `labels`, `session_id`, `last_activity_at`) may be present but are unused by the UI.

**`is_live` resolution.** The `is_live` field is resolved dynamically from CXDB's session tracker, not from a stored field. Both the CQL search endpoint (via `session_tracker.get_session_for_context(context_id)`, `is_live = session.is_some()`) and the context list fallback (`context_to_json`) resolve `is_live` identically. When a binary protocol session disconnects (agent exits or crashes), the session is immediately removed from the tracker (`metrics.rs` `disconnect_session`). The next HTTP request for that context sees `is_live: false` with no caching delay. This means stale detection (Section 6.2) can fire on the very first poll cycle after an agent crash — `is_live` transitions instantaneously, not gradually.

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
| `before_turn_id` | `0` | Pagination cursor. When `0` (default) or omitted, returns the most recent `limit` turns from the context head, in oldest-first order — both values are equivalent and delegate to CXDB's `get_last(context_id, limit)` internally (`turn_store/mod.rs` line 535-536). When set to a non-zero turn ID, returns turns older than that ID (walking backward via `parent_turn_id`), also in oldest-first order. Both code paths produce the same ordering (`results.reverse()` at the end). The `fetchFirstTurn` pseudocode (Section 5.5) uses `cursor = 0` as a sentinel meaning "start from head (no before_turn_id)" — this works because omitting the parameter and passing `0` are functionally identical. Use `next_before_turn_id` from the previous response to fetch the next page. **Context scoping note.** The `context_id` parameter verifies the context exists but does not scope the `before_turn_id` traversal. CXDB resolves `before_turn_id` from a global turn table (`turn_store/mod.rs` line 539-542: `self.turns.get(&before_turn_id)`) and walks `parent_turn_id` links without context boundary checks. This is why `fetchFirstTurn` (Section 5.5) correctly discovers the parent context's `RunStarted` turn for forked contexts — the parent chain naturally crosses context boundaries. The UI's pagination is safe because it uses `next_before_turn_id` from the same context's response chain. **Defensive note.** Because `before_turn_id` is resolved globally, callers must ensure that the cursor passed as `before_turn_id` originates from the same context's response chain. Mixing cursors across contexts produces silently incorrect results — the returned turns belong to the wrong context's parent chain. The gap recovery pseudocode (Section 6.1) maintains `lastSeenTurnId` per `(cxdb_index, context_id)` pair to prevent this. Implementers should assert that the cursor and context_id are from the same mapping. |
| `view` | `typed` | Response format: `typed` (decoded JSON), `raw` (msgpack), or `both` |
| `bytes_render` | `base64` | Raw payload encoding when `view=raw` or `view=both`: `base64` (response field: `bytes_b64`), `hex` (response field: `bytes_hex`), or `len_only` (response field: `bytes_len`, no payload data). The UI uses the default (`base64`) and accesses `bytes_b64`. This parameter has no effect when `view=typed`. |

**Type registry dependency.** The default `view=typed` format requires every turn's `declared_type` to be registered in CXDB's type registry. For Kilroy turns, this means the `kilroy-attractor-v1` registry bundle (shown in the response's `meta.registry_bundle_id` field) must be published to the CXDB instance before the UI can fetch turns. If any single turn in a context references an unregistered type, the entire turn fetch request for that context fails (CXDB's type resolution is per-turn with no skip-on-error fallback — `http/mod.rs` line 849-850: `registry.get_type_version(...).ok_or_else(|| StoreError::NotFound(...))`). This can occur during development (before the registry bundle is published), after a version mismatch (newer Attractor types not in the bundle), or in forked contexts that inherit parent turns with non-Kilroy types. The polling algorithm handles this failure mode as a per-context error (see Section 6.1, step 4).

**Permanent failure for forked contexts with non-Kilroy parents.** The forked-context case deserves special attention because it can cause **permanent** `view=typed` failures, not just transient ones. CXDB's `get_last` / `get_before` walks the parent chain across context boundaries (`turn_store/mod.rs`), so turns from the parent context are included in the child's response. If a Kilroy context was forked from a parent that contains turns with `cxdb.ConversationItem` types (e.g., from a Claude Code session or other non-Kilroy client), and the `cxdb.ConversationItem` registry bundle is not published on that CXDB instance, then `view=typed` fetches will fail for the child context every poll cycle — the parent turns are immutable and will always be in the response window until enough child turns are appended to push them out. This is distinct from the transient "registry not yet published" scenario. The per-context error handling (Section 6.1, step 4: skip and retain cache) handles the failure gracefully, but the context will not update until either the missing bundle is published or the non-Kilroy parent turns fall outside the fetch window.

**Blob-level failure scope.** CXDB loads payload blobs for all turns in the response window. The Store wrapper (`store.rs` lines 268-274 for `get_last`, lines 295-301 for `get_before`) calls `self.blob_store.get(&record.payload_hash)?` for each turn, using `?` error propagation with no per-turn skip. If any single payload blob is corrupted or missing (disk error, incomplete write), the entire request fails with 500 — even if the most recent turns are intact. The failure persists across poll cycles until the corrupted blob falls outside the 100-turn fetch window (as new turns are appended and the window slides forward). For slow-moving contexts, this could take hours. The per-context error handling (Section 6.1, step 4: skip and retain cache) mitigates this by preserving last-known status, but the context will not update until the blob is no longer in the window. This is a distinct failure mode from the type registry miss — blob corruption is less obvious because the 500 error does not indicate which specific blob failed.

**`view=raw` subsystem dependencies.** The `view=raw` parameter eliminates only the type registry dependency. The turn metadata store (which holds `declared_type_id` and `declared_type_version` — loaded via `self.turn_store.get_turn_meta(record.turn_id)?` at `turn_store/mod.rs` line 496-500) and the blob store (which holds the raw payload) are still accessed for every turn regardless of the `view` parameter. The `declared_type` fields are extracted from `TurnMeta` unconditionally before the view-dependent code path runs (`http/mod.rs` lines 807-808). If the turn metadata is corrupted or missing, the entire turn fetch fails with the same blast radius as blob corruption — `view=raw` does not reduce the number of CXDB subsystems involved. Failures in either subsystem are handled by the existing per-context error handling (Section 6.1, step 4).

**Response fields:**

- `declared_type` — the type as written by the client when the turn was appended.
- `decoded_as` — the type after registry resolution. May differ from `declared_type` when `type_hint_mode` is `latest` or `explicit`. The UI uses `declared_type.type_id` for type matching (sufficient because Attractor types do not use version migration).
- `next_before_turn_id` — pagination cursor for fetching older turns. Set to the oldest turn's ID in the response; `null` when the response contains no turns. Pass this as the `before_turn_id` query parameter to get the next page. Note: a non-null value means the response was non-empty, not that older turns definitely exist — the definitive "no more pages" signal is `response.turns.length < limit`.
- `parent_turn_id` — the turn this was appended after (present but unused by the UI).

### 5.4 Turn Type IDs

| Type ID | Description | Key Data Fields |
|---------|-------------|-----------------|
| `com.kilroy.attractor.RunStarted` | First turn in a context (pipeline-level) | `graph_name`, `run_id`, `graph_dot` (optional) |
| `com.kilroy.attractor.RunCompleted` | Pipeline run completed (pipeline-level) | `run_id`, `final_status`, `final_git_commit_sha`, `cxdb_context_id`, `cxdb_head_turn_id` |
| `com.kilroy.attractor.RunFailed` | Pipeline run failed (pipeline-level) | `run_id`, `reason`, `node_id` (optional), `git_commit_sha` |
| `com.kilroy.attractor.Prompt` | LLM prompt sent to agent | `node_id`, `text` |
| `com.kilroy.attractor.ToolCall` | Agent invoked a tool | `node_id` (optional per registry, always populated in practice), `tool_name`, `arguments_json`, `call_id` |
| `com.kilroy.attractor.ToolResult` | Tool result | `node_id` (optional per registry, always populated in practice), `tool_name`, `output`, `is_error`, `call_id` |
| `com.kilroy.attractor.AssistantMessage` | LLM response | `node_id` (optional), `text`, `model`, `input_tokens`, `output_tokens`, `tool_use_count` |
| `com.kilroy.attractor.GitCheckpoint` | Git commit at node boundary | `node_id`, `git_commit_sha`, `status` |
| `com.kilroy.attractor.CheckpointSaved` | Checkpoint saved to disk | `run_id`, `node_id` (optional), `checkpoint_path` |
| `com.kilroy.attractor.Artifact` | Build artifact produced | `node_id` (optional), `name`, `mime`, `content_hash` |
| `com.kilroy.attractor.BackendTraceRef` | LLM backend trace reference | `node_id` (optional), `provider`, `backend` |
| `com.kilroy.attractor.Blob` | Raw binary data | `bytes` |
| `com.kilroy.attractor.StageStarted` | Node execution began | `node_id`, `handler_type` (optional) |
| `com.kilroy.attractor.StageFinished` | Node execution completed | `node_id`, `status`, `preferred_label` (optional), `failure_reason` (optional), `notes` (optional), `suggested_next_ids` (optional, array) |
| `com.kilroy.attractor.StageFailed` | Node execution failed | `node_id`, `failure_reason`, `will_retry` (optional, boolean), `attempt` (optional) |
| `com.kilroy.attractor.StageRetrying` | Node about to retry | `node_id`, `attempt`, `delay_ms` (optional) |
| `com.kilroy.attractor.ParallelStarted` | Parallel execution began | `node_id`, `branch_count`, `join_policy`, `error_policy` |
| `com.kilroy.attractor.ParallelBranchStarted` | Single parallel branch began | `node_id`, `branch_key`, `branch_index` |
| `com.kilroy.attractor.ParallelBranchCompleted` | Parallel branch finished | `node_id`, `branch_key`, `branch_index`, `status`, `duration_ms` |
| `com.kilroy.attractor.ParallelCompleted` | All parallel branches finished | `node_id`, `success_count`, `failure_count`, `duration_ms` |
| `com.kilroy.attractor.InterviewStarted` | Human gate question posed | `node_id`, `question_text`, `question_type` |
| `com.kilroy.attractor.InterviewCompleted` | Human gate answer received | `node_id`, `answer_value`, `duration_ms` |
| `com.kilroy.attractor.InterviewTimeout` | Human gate timed out | `node_id`, `question_text`, `duration_ms` |

Types with `node_id` are processed by the status derivation algorithm (Section 6.2). Types without `node_id` (RunStarted, RunCompleted, Blob) are silently skipped via the `IF nodeId IS null` guard. RunFailed carries an optional `node_id` — when present, it participates in status derivation; when absent, it is skipped. GitCheckpoint, CheckpointSaved, Artifact, BackendTraceRef, and AssistantMessage may or may not carry `node_id` depending on context — the null guard handles both cases. These types are defined in the `kilroy-attractor-v1` registry bundle (in the Kilroy/Attractor codebase) and their fields should be verified against the bundle if field-level details are needed beyond what is documented here. The `optional` annotations in the table above match the registry bundle definition (e.g., `ToolCall.node_id` is `opt()` in the registry), not necessarily the current Kilroy emitting code (which always populates them in practice). Fields marked optional in the registry may be absent from turns emitted by future Kilroy versions or third-party Attractor implementations. The `IF nodeId IS null` guard in the status derivation algorithm (Section 6.2) handles all cases regardless of optionality.

**Field notes for specific turn types.** `GitCheckpoint.status` records the `StageStatus` (e.g., `"success"`, `"fail"`, `"retry"`) at the time the git checkpoint was made — it uses the same `StageStatus` value set as `StageFinished.status` (see `runtime/status.go`). This field does not affect UI rendering since `GitCheckpoint` falls through to the "Other/unknown" detail panel row, but operators examining raw turn data in CXDB will see it. `ToolCall.call_id` and `ToolResult.call_id` are a correlation ID linking a tool invocation round-trip: the same `call_id` appears in both the `ToolCall` turn and its corresponding `ToolResult` turn. For LLM-driven tool calls (CLI stream path), `call_id` is the Anthropic `tool_use` ID (e.g., `"toolu_abc"`). For tool gate invocations (`handlers.go`), it is a ULID generated at call time. For Codergen-routed calls (`codergen_router.go`), it is also a ULID. The `call_id` field is not rendered by the detail panel but is present in all real-world Kilroy `ToolCall` and `ToolResult` turns. `ParallelStarted.join_policy` and `ParallelStarted.error_policy` are string values from Kilroy's parallel handler configuration that describe how the parallel fan-out is coordinated — specifically which branches must complete and what happens on branch failure. These fields do not affect UI rendering since `ParallelStarted` falls through to the "Other/unknown" detail panel row, but they are operationally significant for operators debugging failing parallel nodes.

**Kilroy types vs. CXDB canonical types.** The `com.kilroy.attractor.*` types above are distinct from CXDB's own canonical conversation type (`cxdb.ConversationItem`, defined in `clients/go/types/conversation.go` in the CXDB repository). The CXDB types use an `item_type` discriminator with variants like `user_input`, `assistant_turn`, `tool_call`, `tool_result`, `system`, and `handoff` — they have no concept of `node_id`, `graph_name`, `run_id`, `StageStarted`, `StageFinished`, or `StageFailed`. The Kilroy types are defined in the Kilroy/Attractor codebase (not the CXDB codebase) and are published to CXDB via the registry bundle mechanism. An implementer cannot verify the Kilroy field tags or type IDs from the CXDB source alone — the canonical source for the `kilroy-attractor-v1` bundle definition is the Attractor repository. The `decodeFirstTurn` tags (tag 1 = `run_id`, tag 8 = `graph_name`) are documented inline in Section 5.5 and are stable within bundle version 1 per CXDB's versioning model (existing tags are never reassigned).

### 5.5 Pipeline Discovery

CXDB is a generic context store with no first-class pipeline concept. The UI discovers which contexts belong to which pipeline by reading the `RunStarted` turn. When multiple CXDB instances are configured, the UI queries all of them and builds a unified mapping.

**Discovery algorithm:**

The algorithm has two phases: (1) identify Kilroy contexts using `client_tag`, and (2) fetch the `RunStarted` turn to extract `graph_name` and `run_id`.

Kilroy contexts are identified by their `client_tag`, which follows the format `kilroy/{run_id}`. The UI uses the CQL search endpoint (Section 5.2) as the primary discovery mechanism, with a fallback to the full context list for older CXDB versions. On each discovery call, the UI first attempts `GET /v1/contexts/search?q=tag ^= "kilroy/"`. If the endpoint returns 404, the UI sets a per-instance `cqlSupported` flag to `false` and falls back to `GET /v1/contexts?limit=10000` with client-side prefix filtering. The `cqlSupported` flag is checked on subsequent polls to skip the CQL attempt — it is reset when the CXDB instance becomes unreachable and then reconnects (since the instance may have been upgraded). When using CQL search, the server returns only `kilroy/`-prefixed contexts, eliminating the need for client-side prefix filtering and the 10,000-context limit heuristic. When using the fallback, the context list request must include `limit=10000` to override the CXDB default of 20 — without this, instances with many non-Kilroy contexts (e.g., Claude Code sessions) may push Kilroy contexts outside the default 20-context window.

**CQL discovery limitation (until Kilroy implements key 30).** As documented in the "`client_tag` stability requirement" section below, Kilroy does not currently embed context metadata at key 30 in turn payloads. CQL search relies on this metadata for `client_tag` indexing. Until Kilroy implements key 30, CQL search returns zero Kilroy contexts even though they exist — the CQL endpoint returns a valid 200 response with an empty `contexts` array, so the `cqlSupported` flag remains `true`. To handle this, the `discoverPipelines` pseudocode includes a **supplemental context list fetch** that runs on every poll cycle when CQL is supported, regardless of whether CQL returned contexts. The supplemental fetch serves three roles: (1) when CQL returns empty results, it provides `kilroy/`-prefixed contexts via session-tag resolution for active sessions; (2) when CQL returns some contexts but misses others (mixed deployment — new runs have key 30 and appear in CQL, but legacy active runs or runs whose metadata extraction has not yet completed appear only in the supplemental list with a non-null session-resolved `client_tag`), it provides the missing kilroy-prefixed contexts; (3) regardless of CQL result count, it collects null-tag contexts (completed runs whose `client_tag` is permanently null after session disconnect) into the null-tag backlog for `fetchFirstTurn` processing. The third role is essential during mixed deployments — once Kilroy begins emitting key 30, new runs appear in CQL results while older legacy runs (key 30 absent, session disconnected) are invisible to CQL. Without running the supplemental fetch even when CQL returns data, those legacy contexts are never queued for the null-tag backlog and become permanently inaccessible. `kilroy/`-prefixed contexts from the supplemental list are **always** merged into `contexts` using a dedup set built from `context_id` values already present in the CQL results — this prevents duplicates whether CQL returned zero results or many. Null-tag contexts are always collected. See the "`client_tag` stability requirement" section for the underlying limitation and the required Kilroy-side change.

```
FUNCTION discoverPipelines(cxdbInstances, knownMappings, cqlSupported):
    FOR EACH (index, instance) IN cxdbInstances:
        -- Phase 1: Fetch Kilroy contexts (CQL search or fallback)
        -- supplementalNullTagCandidates collects null-tag contexts encountered during
        -- the supplemental context list fetch (runs on every CQL-supported poll cycle,
        -- not only when CQL is empty). These are merged into nullTagCandidates below
        -- for backlog processing so legacy completed runs are found in mixed deployments.
        supplementalNullTagCandidates = []
        IF cqlSupported[index] != false:
            TRY:
                searchResponse = fetchCqlSearch(index, 'tag ^= "kilroy/"')
                contexts = searchResponse.contexts
                cqlSupported[index] = true
                -- Always fetch the full context list as a supplemental pass, regardless
                -- of whether CQL returned contexts. This is necessary for three cases:
                -- (a) CQL returned zero contexts: Kilroy contexts may exist but lack key 30
                --     metadata (current default), so session-tag-resolved client_tags are
                --     the only way to find active runs. Merge them into `contexts`.
                -- (b) CQL returned some contexts (mixed deployment): new runs with key 30
                --     appear in CQL, but legacy active runs or runs whose metadata extraction
                --     has not yet completed appear only in the supplemental list with a
                --     non-null client_tag (session-tag resolution). Without this merge, those
                --     contexts are silently dropped — their client_tag is non-null so they
                --     are never queued for the null-tag backlog, making them permanently
                --     undiscovered even though the agent is actively running.
                -- (c) Any deployment: completed runs whose sessions disconnected (client_tag
                --     permanently null due to absent key 30) are invisible to CQL and cannot
                --     be matched by prefix; collecting them here feeds the null-tag backlog.
                -- Kilroy-prefixed contexts from supplemental are merged by dedup on
                -- context_id to avoid adding entries already present from CQL. Null-tag
                -- contexts are always collected for the null-tag backlog regardless.
                supplemental = fetchContexts(index, limit=10000)
                -- Build a set of context_ids already returned by CQL so we can
                -- deduplicate when merging supplemental kilroy-prefixed contexts.
                -- CQL and the full context list can overlap: new runs that have
                -- key 30 metadata appear in both. Legacy runs or partially-upgraded
                -- runs may appear only in the supplemental list (e.g., active sessions
                -- on Kilroy instances not yet emitting key 30, or contexts that CQL
                -- missed due to metadata extraction lag). Deduplication by context_id
                -- ensures these contexts are merged without doubling existing ones.
                cqlContextIds = SET(ctx.context_id FOR ctx IN contexts)
                FOR EACH ctx IN supplemental:
                    IF ctx.client_tag IS NOT null AND ctx.client_tag.startsWith("kilroy/"):
                        -- Append kilroy-prefixed contexts from the supplemental list
                        -- that are absent from CQL results. This covers:
                        -- (a) CQL returned empty (current default, no key 30): all
                        --     active Kilroy contexts come from supplemental via session-tag.
                        -- (b) CQL returned some contexts (mixed deployment): new runs with
                        --     key 30 appear in CQL; legacy active runs that lack key 30
                        --     (or whose metadata lag behind) appear only in supplemental.
                        --     Without this merge, those active runs remain undiscovered
                        --     even though their client_tag is visible via session resolution.
                        IF ctx.context_id NOT IN cqlContextIds:
                            contexts.append(ctx)
                            cqlContextIds.add(ctx.context_id)  -- prevent double-append
                    ELSE IF ctx.client_tag IS null:
                        -- Null-tag context from the supplemental fetch. This context
                        -- may be a completed Kilroy run whose session has disconnected
                        -- (client_tag permanently null because key 30 is absent and the
                        -- session fallback in context_to_json is no longer available).
                        -- We cannot filter by prefix here, so collect it for the
                        -- null-tag backlog. The (index, ctx.context_id) key will be
                        -- checked against knownMappings in the backlog processing block.
                        supplementalNullTagCandidates.append(ctx)
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

        -- Null-tag backlog: contexts whose client_tag is null from either discovery path.
        -- These may be completed Kilroy runs whose session disconnected (making
        -- client_tag permanently null because key 30 is absent and context_to_json's
        -- session fallback no longer resolves the tag). Two sources feed this backlog:
        -- (1) the supplemental context list fetch (runs every CQL-supported poll cycle,
        --     not only when CQL is empty), collected above into supplementalNullTagCandidates.
        --     Running supplemental even when CQL has results is essential for mixed
        --     deployments: CQL finds new runs with key 30 metadata, but older legacy
        --     runs (no key 30, session disconnected) are invisible to CQL and would
        --     be permanently stranded without the supplemental pass.
        -- (2) the full context list fallback (CQL not supported), collected in the
        --     main context loop below into nullTagCandidates directly.
        -- We attempt fetchFirstTurn for up to NULL_TAG_BATCH_SIZE of the newest such
        -- contexts per poll cycle, prioritised by descending context_id (newest first).
        -- Contexts that are confirmed Kilroy are cached normally; confirmed
        -- non-Kilroy or transient errors are handled by the logic below.
        -- knownMappings is checked again in the batch processing block to handle
        -- supplementalNullTagCandidates that were not filtered against knownMappings
        -- in the supplemental fetch loop above.
        NULL_TAG_BATCH_SIZE = 5
        nullTagCandidates = supplementalNullTagCandidates  -- seed from supplemental path

        FOR EACH context IN contexts:
            key = (index, context.context_id)
            IF key IN knownMappings:
                CONTINUE  -- already discovered (positive or negative)

            -- When using fallback (no CQL), apply client-side prefix filter.
            -- IMPORTANT: Only cache a null mapping when client_tag is PRESENT but
            -- does NOT start with "kilroy/". If client_tag is null (absent), the
            -- context is a candidate for the null-tag backlog (see below).
            -- Rationale: on older CXDB versions (precisely those that use this fallback
            -- path), client_tag is resolved from the active session via context_to_json's
            -- .or_else fallback. This means client_tag can be legitimately null in two
            -- situations: (1) immediately after context creation before the session
            -- registers the context in context_to_session (brief startup window), and
            -- (2) after the run finishes and the session disconnects (SessionTracker.
            -- unregister removes the context-to-session mapping). For historical runs
            -- on legacy CXDB (completed + session gone), client_tag is PERMANENTLY
            -- null — so simply doing CONTINUE here would prevent those runs from ever
            -- being discovered. Instead, we enqueue them into the null-tag backlog.
            IF cqlSupported[index] == false:
                IF context.client_tag IS NOT null AND NOT context.client_tag.startsWith("kilroy/"):
                    knownMappings[key] = null  -- confirmed non-Kilroy context (tag present but wrong prefix)
                    CONTINUE
                ELSE IF context.client_tag IS null:
                    nullTagCandidates.append(context)
                    CONTINUE  -- will be processed in the null-tag batch below

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

        -- Null-tag batch: attempt fetchFirstTurn for the newest N null-tag contexts.
        -- Sort descending by context_id (newest first — monotonic proxy for recency).
        -- This enables discovery of completed Kilroy runs on both CQL-enabled CXDB
        -- (supplemental path, post-disconnect) and legacy CXDB (fallback path).
        -- Note: contexts from the supplemental path (supplementalNullTagCandidates) were
        -- not filtered against knownMappings before being added; check here to avoid
        -- redundant fetchFirstTurn calls for already-cached contexts.
        -- IMPORTANT: iterate the full sorted list and use a counter (not a slice) to
        -- enforce the batch limit. Slicing to [0..NULL_TAG_BATCH_SIZE] before iteration
        -- causes starvation: once the first N contexts are cached in knownMappings they
        -- permanently occupy the top of the sorted list and the CONTINUE skips each of
        -- them, so contexts past index N-1 are never examined regardless of how many
        -- poll cycles pass.
        nullTagCandidates.sortByDescending(c => parseInt(c.context_id, 10))
        nullTagProcessed = 0
        FOR EACH context IN nullTagCandidates:
            IF nullTagProcessed >= NULL_TAG_BATCH_SIZE:
                BREAK
            key = (index, context.context_id)
            IF key IN knownMappings:
                CONTINUE  -- already cached (positive or negative); skip (does NOT count toward batch limit)
            TRY:
                firstTurn = fetchFirstTurn(index, context.context_id, context.head_depth)
                nullTagProcessed++  -- count against batch limit only when fetchFirstTurn is invoked
            CATCH fetchError:
                -- Transient failure: do NOT cache, retry next poll.
                -- Still counts against the batch limit (the fetch was attempted).
                nullTagProcessed++
                CONTINUE

            IF firstTurn IS NOT null AND firstTurn.declared_type.type_id == "com.kilroy.attractor.RunStarted":
                graphName = firstTurn.data.graph_name
                runId = firstTurn.data.run_id
                IF graphName IS null OR graphName == "":
                    knownMappings[key] = null  -- RunStarted but no graph_name; immutable, cache negative
                    CONTINUE
                knownMappings[key] = { graphName, runId }
            ELSE IF firstTurn IS null:
                -- Empty context. Leave unmapped, retry next poll.
                CONTINUE
            ELSE:
                -- First turn is not RunStarted → confirmed non-Kilroy.
                -- Cache null to avoid re-fetching.
                knownMappings[key] = null

    RETURN knownMappings
```

**Fetching the first turn.** CXDB returns turns oldest-first (ascending by position in the parent chain). The `before_turn_id` parameter paginates backward from a given turn ID. To reach the first turn of a context, the algorithm paginates backward from the head in bounded pages rather than fetching the entire context in a single request. This avoids O(headDepth) memory and latency costs — CXDB's `get_last` walks the parent chain sequentially, serializes every turn including decoded payloads, and transfers the entire response over HTTP. For deep contexts (headDepth in the tens of thousands), a single unbounded request could produce hundreds of megabytes of JSON, all of which would be discarded except the first turn.

**Using `view=raw` for discovery.** The `fetchFirstTurn` algorithm uses `view=raw` instead of the default `view=typed`. This eliminates the type registry dependency for pipeline discovery. The `declared_type` field (containing `type_id` and `type_version`) is present in both `view=raw` and `view=typed` responses — it comes from the turn metadata, not the type registry. For the `RunStarted` data fields (`graph_name`, `run_id`), `view=raw` returns the raw msgpack payload as base64-encoded bytes in the `bytes_b64` field. The UI decodes this client-side: base64-decode to bytes, then msgpack-decode to extract the known `RunStarted` fields. This avoids the bootstrap ordering problem where the type registry bundle has not yet been published when the UI first discovers a pipeline (the registry is typically published by the Kilroy runner at the start of the run). Without `view=raw`, `fetchFirstTurn` would fail for all contexts during the window between context creation and registry publication, delaying pipeline discovery by 1-3 poll cycles (3-9 seconds). The regular turn polling (Section 6.1 step 4) continues using the default `view=typed` for the status overlay, since those fields are more complex and benefit from server-side projection.

```
FUNCTION fetchFirstTurn(cxdbIndex, contextId, headDepth):
    IF headDepth == 0:
        -- If headDepth == 0, the first turn is either at the head or one hop
        -- away. For non-forked contexts, headDepth 0 means at most one turn.
        -- For forked contexts created from a depth-0 base turn (e.g., forking
        -- directly from RunStarted), headDepth starts at 0 but the context
        -- may later accumulate turns at depths 1, 2, ... — in that case,
        -- limit=1 returns the newest turn (via get_last), not depth-0.
        -- Guard: verify the returned turn has depth == 0. If not, fall through
        -- to the general pagination loop which handles arbitrary depths.
        --
        -- Note: head_depth is updated on every append_turn (turn_store/mod.rs).
        -- A context with head_depth == 0 has either zero appended turns (just
        -- created/forked) or exactly one turn at depth 0. The depth == 0 guard
        -- is defensive — in practice, get_last(limit=1) for a head_depth == 0
        -- context always returns either empty (no turns) or a depth-0 turn.
        -- Use view=raw to avoid type registry dependency.
        response = fetchTurns(cxdbIndex, contextId, limit=1, view="raw")
        IF response.turns IS EMPTY:
            RETURN null
        IF response.turns[0].depth == 0:
            RETURN decodeFirstTurn(response.turns[0])
        -- Fall through to pagination: the context was forked from depth-0
        -- but has accumulated its own turns, so depth-0 is not at the head.

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
    -- Implementations SHOULD log a warning here (e.g., "discovery deferred:
    -- context {contextId} exceeds MAX_PAGES pagination cap") so that operators
    -- can recognise when a context is consistently skipped due to unusual depth.
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
    -- modeldb_catalog_source (11), graph_dot (12). The graph_dot field
    -- (optional string) contains the full pipeline DOT source at run start
    -- time, available for future features (e.g., reconstructing the exact
    -- graph used for a historical run) but unused by the initial
    -- implementation. Only tags 1 and 8 are used by the UI.
    -- bytes_b64 is present because fetchFirstTurn omits the bytes_render parameter,
    -- defaulting to base64. If bytes_render were set to "hex" or "len_only", the
    -- response would use bytes_hex or bytes_len instead and this access would fail.
    bytes = base64Decode(rawTurn.bytes_b64)
    -- The @msgpack/msgpack library (pinned at 3.0.0-beta2) always decodes
    -- MessagePack maps to plain JavaScript objects, never Map instances.
    -- There is no `useMaps` or equivalent option in this library version.
    -- Integer keys in the msgpack payload are accepted by the default
    -- mapKeyConverter and are automatically coerced to string keys by
    -- JavaScript's object property semantics (e.g., payload[8] and
    -- payload["8"] resolve identically). No special decoder configuration
    -- is needed.
    -- If a different msgpack decoder is used in the future that returns
    -- Map objects, convert with Object.fromEntries(payload.entries())
    -- before field access.
    payload = msgpackDecode(bytes)
    -- Access fields by their string-encoded integer tag.
    -- Go's msgpack encoder produces string keys (e.g., "1" not 1).
    -- The || fallback handles both forms defensively.
    RETURN {
        declared_type: rawTurn.declared_type,
        data: { graph_name: payload["8"] || payload[8], run_id: payload["1"] || payload[1] }
    }
```

**Cross-context traversal for forked contexts.** The `fetchFirstTurn` pagination follows CXDB's parent chain via `parent_turn_id` links. For forked contexts (created for parallel branches), the parent chain extends across context boundaries — the child context's turns link back to the parent context's turns via the fork point's `parent_turn_id`. Walking to depth 0 therefore discovers the parent context's `RunStarted` turn, not a turn within the child context. This is correct because Kilroy's parallel branch contexts share the parent's `RunStarted` (same `graph_name`, same `run_id`) via the linked parent chain. CXDB's `get_before` implementation (`turn_store/mod.rs`) walks `parent_turn_id` without any context boundary check, confirming this cross-context traversal. If a future Kilroy version emits a new `RunStarted` in each forked child context, the pagination would still work (it would find the child's `RunStarted` at the child's depth-0 position), but the current behavior discovers the parent's `RunStarted` instead.

**Pagination cost.** In the worst case (headDepth = 5000), fetching the first turn requires 50 paginated requests of 100 turns each. For typical Kilroy contexts (headDepth < 1000), this completes in under 10 pages. The `client_tag` prefix filter (Phase 1) ensures pagination only runs for Kilroy contexts, not for unrelated contexts that may share the CXDB instance. Each page request transfers at most 100 turns worth of JSON (roughly 50–200 KB depending on payload size), avoiding the memory spike of a single unbounded request. The `MAX_PAGES` cap of 50 means contexts deeper than ~5000 turns are skipped for discovery; these are retried on subsequent polls in case the depth was a transient artifact. When a context repeatedly hits the pagination cap (i.e., returns `null` from `fetchFirstTurn` poll after poll due to depth, not due to transient network errors), implementations should emit a warning log to help operators diagnose the situation — the context will keep being retried but discovery will be permanently deferred until the context's head depth shrinks below the cap or a future HTTP endpoint exposes `get_first_turn` directly.

**Note on CXDB internals.** The CXDB turn store has a `get_first_turn` method that walks back from the head to find depth=0 directly, but this is not exposed via the HTTP API. If a future CXDB release adds an HTTP endpoint for fetching the first turn (or exposes the binary protocol's `GetRangeByDepth` over HTTP), the pagination approach here should be replaced with a single targeted request. This runs once per context (results are cached).

The `graph_name` from the `RunStarted` turn is matched against the normalized graph ID in each loaded DOT file (Section 4.4). The normalization rules (unquote, unescape, trim) apply to the DOT-side graph ID; the `graph_name` value from CXDB is compared as-is. In practice, Kilroy's DOT parser (`kilroy/internal/attractor/dot/parser.go`) only accepts unquoted graph identifiers (the `tokenIdent` lexer path), so `graph_name` in `RunStarted` is always an unquoted, unescaped identifier that matches the DOT graph ID without normalization mismatch. If a future Kilroy version supports quoted graph names in DOT files, both the Kilroy parser and the UI's normalization would need to produce the same unquoted value — but this is not a concern for the initial implementation. Contexts whose `graph_name` matches the currently displayed pipeline are used for the status overlay — regardless of which CXDB instance they reside on.

The `RunStarted` turn also contains a `run_id` field (see Section 5.4 for the full field inventory) that uniquely identifies the pipeline run. All contexts belonging to the same run (e.g., parallel branches) share the same `run_id`. The discovery algorithm records both `graph_name` and `run_id` for each context.

**Caching.** The context-to-pipeline mapping is cached in memory, keyed by `(cxdb_index, context_id)`. Both positive results (RunStarted contexts mapped to a pipeline) and negative results (non-Kilroy contexts and confirmed non-RunStarted contexts stored as `null`) are cached. The first turn of a context is immutable — once a context is successfully classified, it is never re-fetched. Only newly appeared context IDs (and previously failed or empty fetches that were not cached) trigger discovery requests. The `client_tag` prefix filter (whether server-side via CQL or client-side in the fallback path) prevents fetching turns for non-Kilroy contexts entirely. Three cases are left unmapped (not cached as `null`) and retried on subsequent polls: (a) when a `fetchFirstTurn` call fails due to a transient error (non-200 response, timeout), (b) when `fetchFirstTurn` returns `null` (empty context with no turns yet — common during early pipeline startup or transient CXDB lag), and (c) when `client_tag` is `null` — null-tag contexts are queued in the null-tag backlog (up to `NULL_TAG_BATCH_SIZE` = 5 per poll cycle, newest first by context_id) and subjected to `fetchFirstTurn`. This applies in both discovery paths: the CQL-empty supplemental path (CQL-enabled CXDB where Kilroy lacks key 30 and the session has disconnected) and the full context list fallback path (legacy CXDB without CQL). If `fetchFirstTurn` confirms the context is a Kilroy run (first turn is `RunStarted`), it is cached positively. If it confirms a non-Kilroy first turn, it is cached as `null`. If the fetch fails transiently, the context remains uncached and is retried in a future poll cycle. This mechanism enables discovery of completed Kilroy runs on both CQL-enabled and legacy CXDB deployments where `client_tag` is permanently `null` after session disconnect. This prevents transient failures, empty contexts, and transiently-missing tags from permanently classifying a valid Kilroy context as non-Kilroy.

**`client_tag` stability requirement and current limitation.** The `client_tag` prefix filter assumes `client_tag` is stable across polls. CXDB resolves `client_tag` with a fallback chain: first from stored metadata (extracted from the first turn's msgpack payload key 30), then from the active session's tag. If the first turn's payload does not include context metadata (key 30 is absent), the `client_tag` in the context list is only present while the session is active (`is_live == true`). Once the session disconnects, `client_tag` becomes `null`, and the UI's prefix filter would fail to match — permanently excluding the context from discovery if it has already been cached as non-Kilroy. **Kilroy must embed `client_tag` in the first turn's context metadata** (key 30) for reliable classification.

**Current state: Kilroy does NOT embed key 30.** As of the current Kilroy implementation, no component injects key 30 into turn payloads. Kilroy's `EncodeTurnPayload` (`msgpack_encode.go`) only emits tags defined in the `kilroy-attractor-v1` registry bundle (tags 1-12 for `RunStarted`). Tag 30 is not in the bundle. `BinaryClient.AppendTurn` (`binary_client.go`) writes raw msgpack payload bytes to the wire without injecting additional metadata. CXDB's binary protocol handler (`protocol/mod.rs`, `parse_append_turn`) passes the payload verbatim to the store. The key 30 / `context_metadata` convention is defined in CXDB's Go client types (`cxdb/clients/go/types/conversation.go` line 167: `ContextMetadata *ContextMetadata \`msgpack:"30"\``) as a client-side convention for `ConversationItem` users. Kilroy uses its own type system (`com.kilroy.attractor.*`) and does not use `ConversationItem`.

**Consequences for discovery:**

- **CQL search returns zero Kilroy contexts.** CXDB's CQL secondary indexes (`cql/indexes.rs`) are built from `context_metadata_cache`, which only has `client_tag` if `extract_context_metadata` (`store.rs`) found key 30 in the payload. Since Kilroy payloads lack key 30, the query `tag ^= "kilroy/"` returns zero results. The CQL-first discovery path produces empty results for all Kilroy contexts.

- **Context list fallback works only during active sessions.** The fallback endpoint resolves `client_tag` from the active session's tag via `context_to_json`'s `.or_else` fallback. This works while the Kilroy agent is connected. After session disconnect (`SessionTracker.unregister` in `metrics.rs` removes all context-to-session mappings), `client_tag` becomes `null` for all that run's contexts. Completed pipelines become undiscoverable on fresh page loads.

- **The UI's `knownMappings` cache and null-tag backlog mitigate this.** Once a context is discovered during an active session, it remains in the cache. For a fresh page load after pipeline completion (when `client_tag` is permanently null), the null-tag backlog mechanism (`NULL_TAG_BATCH_SIZE` = 5 per poll cycle, iterated with a counter over the full candidate list to prevent starvation) attempts `fetchFirstTurn` for unclassified null-tag contexts. This applies in both paths: for CQL-enabled CXDB (where the supplemental context list fetch — running on every CQL-supported poll cycle — collects null-tag contexts), and for legacy CXDB without CQL (where the full context list fallback returns null-tag contexts). Running the supplemental fetch on every poll cycle (not only when CQL is empty) is essential for mixed deployments where CQL finds new runs with key 30 but legacy completed runs have null `client_tag` and are invisible to CQL. Discovery completes within a bounded number of poll cycles proportional to the number of null-tag contexts divided by `NULL_TAG_BATCH_SIZE`.

**Required Kilroy-side change (prerequisite).** For reliable discovery — both CQL search and post-disconnect context list lookups — Kilroy must embed context metadata at key 30 in the first turn's payload. This can be done by: (a) adding a tag 30 field to the `RunStarted` type in the `kilroy-attractor-v1` registry bundle, or (b) wrapping the encoded payload in an outer map that includes key 30 alongside the registry-encoded data. Until this change is made, the context list fallback with session-tag resolution is the only reliable discovery path, limited to active sessions. The UI's existing `knownMappings` cache and the graceful-degradation principle (Section 1.2) ensure that pipelines discovered during an active session remain visible for the duration of the browser session.

**Fallback behavior until Kilroy implements key 30.** The `discoverPipelines` algorithm handles the current state via the supplemental context list fetch. The algorithm issues a supplemental `fetchContexts(index, limit=10000)` on every CQL-supported poll cycle regardless of whether CQL returned results. The supplemental fetch serves three roles:

1. **CQL returned zero results (current default, no key 30):** All Kilroy contexts have `client_tag` resolved from the active session's tag (`context_to_json`'s `.or_else` fallback). These appear in the supplemental fetch with non-null `kilroy/`-prefixed tags but are invisible to CQL. They are merged into `contexts` via dedup on `context_id`, enabling discovery of all active runs.

2. **CQL returned some results but missed others (mixed deployment):** Once Kilroy partially upgrades to emit key 30, new runs appear in CQL results while older active runs — whose key 30 metadata has not yet been extracted, or whose instances haven't been upgraded — appear only in the supplemental list with a non-null session-resolved `client_tag`. The old `IF contexts IS EMPTY` guard would silently drop these, making those runs permanently undiscovered even though their agents are running. The dedup-based merge ensures they are appended to `contexts` and reach Phase 2 discovery.

3. **Any deployment (null-tag backlog):** Completed runs whose sessions have disconnected — where `client_tag` becomes permanently `null` after session disconnect — are collected into `supplementalNullTagCandidates` on every supplemental pass. These are processed via the null-tag backlog: up to `NULL_TAG_BATCH_SIZE` = 5 per poll cycle (iterated with a counter over the full sorted list to prevent starvation) are subjected to `fetchFirstTurn`. This enables discovery of completed pipelines on CQL-enabled CXDB instances even after all sessions disconnect.

A fresh page load after all sessions disconnect will therefore discover completed pipelines within a bounded number of poll cycles, proportional to the number of null-tag contexts divided by `NULL_TAG_BATCH_SIZE`. The supplemental fetch adds one additional HTTP request per CXDB instance per poll cycle when CQL is supported, which is acceptable overhead given the graceful-degradation requirement.

**Metadata extraction asymmetry for forked contexts.** CXDB populates the `context_metadata_cache` via two paths: (1) on append, `maybe_cache_metadata` (`store.rs` lines 161-178) extracts metadata from the first turn appended to the context — for new contexts this is the depth-0 `RunStarted` turn, but for forked contexts this is the first turn appended to the child (at depth = base_depth + 1), which is an application turn (e.g., `StageStarted`, `Prompt`), not `RunStarted`; (2) on cache miss (e.g., after CXDB restart), `load_context_metadata` (`store.rs` lines 151-156) calls `get_first_turn(context_id)`, which walks the parent chain to depth=0 — crossing context boundaries for forked contexts and finding the parent's `RunStarted` turn. For forked contexts, these two paths extract metadata from **different turns** with potentially different payloads. The Go client types confirm the convention: `conversation.go` line 165 says "By convention, only included in the first turn (depth=1) of a context."

**Current state (key 30 absent).** Since Kilroy does not currently embed key 30 in any turn payload (see "`client_tag` stability requirement" above), neither extraction path finds `client_tag` metadata. `extract_context_metadata` returns `None` for `client_tag` regardless of which turn it examines. The asymmetry between the two extraction paths is structurally real but currently moot — both paths yield `None`.

**After Kilroy implements key 30.** Once Kilroy embeds `client_tag` in context metadata (key 30) of both the parent's `RunStarted` and the child's first appended turn, `maybe_cache_metadata` will find it on the hot path for forked contexts. After a CXDB restart, `load_context_metadata` will find the parent's `RunStarted` metadata instead, which also has `client_tag`. Both paths will produce the same `client_tag` value (`kilroy/{run_id}`) because Kilroy uses the same `run_id` for parent and child contexts. However, other metadata fields (`title`, `labels`) may differ between the two turns. This asymmetry would be invisible during normal operation but an implementer testing against a freshly-restarted CXDB might observe different CQL search results than against a long-running instance.

**Metadata labels optimization (not required for initial implementation).** The CXDB server extracts and caches metadata from the first turn of every context (key 30 of the msgpack payload), including `client_tag`, `title`, and `labels`. If Kilroy embeds `graph_name` and `run_id` in the context metadata labels (e.g., `["kilroy:graph=alpha_pipeline", "kilroy:run=01KJ7..."]`), the UI could read them from the context list response's `labels` field, eliminating all `fetchFirstTurn` pagination. However, the CQL search response (the primary discovery path) does not include `labels` — only the full context list endpoint does (Section 5.2). This means the optimization is incompatible with the CQL-first discovery path without one of: (a) falling back to the context list endpoint (losing CQL's scalability benefits), (b) making separate per-context requests to `GET /v1/contexts/{id}` which does return `labels`, (c) a CXDB enhancement to include `labels` in CQL search results, or (d) using server-side SSE subscription (non-goal #11) — the `ContextMetadataUpdated` SSE event carries `labels` (confirmed in CXDB's `events.rs` and `http/mod.rs`), so the Go proxy server could collect labels from these events and serve them without per-context HTTP requests, elegantly bypassing both the CQL limitation and per-context HTTP overhead. Option (d) is the most efficient workaround because it avoids polling entirely for metadata discovery, but it requires the server-side SSE infrastructure described in non-goal #11. This is a Kilroy-side change (not a CXDB change) that would simplify discovery significantly but requires solving the CQL `labels` gap. The pagination approach works correctly today and is used for the initial implementation.

**Context lineage optimization (not required for initial implementation).** CXDB tracks cross-context lineage via `ContextLinked` events. When a context is forked from another (e.g., for parallel branches), CXDB records `parent_context_id`, `root_context_id`, and `spawn_reason` in the context's provenance. The context list endpoint returns this data when `include_lineage=1` is passed. A future optimization could use lineage to skip `fetchFirstTurn` for child contexts: if a child's `parent_context_id` is already in `knownMappings`, the child inherits the parent's `graph_name`/`run_id` mapping. This would reduce discovery latency proportionally to the number of parallel branches. The current approach (fetching the first turn independently for each context) is correct but performs redundant work for forked contexts that share the same `RunStarted` data.

**Multiple runs of the same pipeline.** When CXDB contains contexts from multiple runs of the same pipeline (same `graph_name`, different `run_id`), the UI uses only the most recent run. The most recent run is determined by lexicographic comparison of `run_id` values across run groups — the run with the lexicographically greatest `run_id` is the active run. **Why `run_id` ULID lex order.** Kilroy generates `run_id` as a ULID (Universally Unique Lexicographically Sortable Identifier) using `github.com/oklog/ulid/v2` (`internal/attractor/engine/runid.go`): `ulid.New(ulid.Timestamp(t), entropy)` encodes the creation timestamp in the most significant 48 bits. Lexicographic order on ULIDs is therefore equivalent to time order: a lexicographically larger `run_id` means a more recently started run, regardless of which CXDB instance the contexts reside on. **Why not `context_id`.** CXDB's `context_id` is allocated from a per-instance monotonically increasing counter (`turn_store/mod.rs` lines 347-348) that starts at 1 and is independent on each CXDB server. When multiple CXDB instances are configured, the counter on each instance grows independently: CXDB-0 may have accumulated 550 contexts (an old run's `context_id`s are 500–550) while CXDB-1 has only 20 contexts (a newer run's `context_id`s are 12–20). Comparing `context_id` values across instances would incorrectly select CXDB-0's old run (higher counter) over CXDB-1's newer run (lower counter). `run_id` ULID comparison is immune to this because it encodes the wall-clock time of run creation, not a per-instance counter. **Why not `created_at_unix_ms`.** CXDB's `ContextHead.created_at_unix_ms` is updated on every `append_turn` (`turn_store/mod.rs` lines 458-463) — it reflects the most recent turn's timestamp, not the context's original creation time. Using `max(created_at_unix_ms)` for run selection would select the run with the most recent *activity*, not the most recently *created* run. This causes incorrect flips when an older run's context receives a late turn (e.g., a delayed parallel branch completing) after a newer run has started. Contexts from older runs are ignored for status overlay purposes. This prevents stale data from a completed run from conflicting with an in-progress run.

**Cross-instance merging.** If contexts from the same run (same `run_id`) exist on multiple CXDB instances (e.g., parallel branches written to separate servers), their turns are merged into a single status map. The UI does not distinguish which CXDB instance a turn came from.

---

## 6. Status Overlay

### 6.1 Polling

The UI polls all configured CXDB instances every 3 seconds. Each poll cycle:

1. For each CXDB instance, fetch Kilroy contexts using the CQL search endpoint or fallback (see Section 5.2 and 5.5's `discoverPipelines` for the CQL/fallback selection logic). On success, store the **discovery-effective context list** in `cachedContextLists[i]` (replacing any previous cached value). The discovery-effective list is: the merged list of CQL results plus any supplemental kilroy-prefixed contexts not already in CQL (deduplicated by `context_id`, per the `discoverPipelines` pseudocode in Section 5.5) when CQL is in use, or the full context list when using the fallback. This ensures that `cachedContextLists[i]` always reflects the same `contexts` array used for Phase 2 discovery in the current poll cycle — including supplemental contexts regardless of whether CQL returned results. In particular: when CQL returns empty results, the supplemental context list may discover active Kilroy contexts via session-tag resolution, and those contexts (with their `is_live` field) must be in `cachedContextLists[i]` for `lookupContext` and `checkPipelineLiveness` to find them; when CQL returns some results but misses others (mixed deployment — see Section 5.5, case (b)), the supplemental contexts merged into `contexts` must also be present in `cachedContextLists[i]`, otherwise `checkPipelineLiveness` will not find their `is_live` field and will misclassify active runs as stale. Without storing the full merged list, CQL-only polls would produce an incomplete `cachedContextLists[i]`, causing `applyStaleDetection` to flip running nodes to "stale" even though agents are actively working. If an instance is unreachable (502), skip it, retain its per-context status maps from the last successful poll, and use `cachedContextLists[i]` as the context list for that instance in subsequent steps. This ensures that `lookupContext`, `determineActiveRuns`, and `checkPipelineLiveness` continue to function using the last known context data during transient outages — preserving active-run determination and liveness signals rather than losing them.

   **`cqlSupported` flag reset on reconnection.** The UI tracks a per-instance `instanceReachable[i]` flag. On each poll step 1, before issuing any discovery request: if `instanceReachable[i]` was `false` in the previous cycle (the instance was unreachable), and the current attempt succeeds with a non-502 response, set `instanceReachable[i] = true` and reset `cqlSupported[i] = undefined` (allowing the next poll cycle to retry CQL). This reset is applied regardless of whether the instance was previously `cqlSupported[i] = false` (no CQL) or `cqlSupported[i] = true` (CQL worked but could be affected by an upgrade). The reset happens at reachability detection time — not inside the CQL path itself — so it applies whether the non-502 response comes from a CQL search, context list, or any other proxied request. If the current attempt returns 502, set `instanceReachable[i] = false` and skip the instance as before. In pseudocode:

   ```
   -- At the top of each poll cycle for instance[i]:
   currentlyReachable = (fetchContextsOrCql(i) does NOT return 502)
   IF NOT currentlyReachable:
       instanceReachable[i] = false
       SKIP instance i this cycle
   ELSE:
       IF instanceReachable[i] == false:
           -- Instance just reconnected after being unreachable.
           -- Reset cqlSupported so the next poll retries CQL
           -- (the instance may have been upgraded while down).
           cqlSupported[i] = undefined
       instanceReachable[i] = true
       -- proceed with discovery
   ```

   This ensures that an instance upgraded from non-CQL to CQL while unreachable will have CQL re-probed on the next poll after it comes back, rather than permanently skipping CQL based on a pre-outage 404.
2. Run pipeline discovery for any new `(index, context_id)` pairs (Section 5.5)
3. **Determine active run per pipeline.** For each loaded pipeline, group discovered contexts by `run_id`. The active run is the one with the lexicographically greatest `run_id` value — since `run_id` is a ULID with a 48-bit millisecond timestamp prefix, lexicographic max is equivalent to "most recently started run" and is safe across multiple CXDB instances (see Section 5.5 for the full explanation including why `context_id` cannot be used cross-instance and why `created_at_unix_ms` is also unsuitable). Contexts from non-active runs are excluded from steps 4–7. When the active `run_id` changes for a pipeline (a new run has started), reset all per-context status maps and `lastSeenTurnId` cursors for that pipeline's old-run contexts, and clear the per-pipeline turn cache (step 5) for that pipeline. This implements the "most recent run" rule described in Section 5.5. The algorithm also maintains a `previousActiveRunIds` map (keyed by pipeline graph ID) across poll cycles to detect run changes.

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
                   candidates.append({ index, contextId, runId: mapping.runId })

           IF candidates IS EMPTY:
               activeContextsByPipeline[pipeline.graphId] = []
               CONTINUE

           -- Group by run_id, pick the run with the lexicographically greatest
           -- run_id. run_id is a ULID (Universally Unique Lexicographically Sortable
           -- Identifier) generated at run start time with a 48-bit millisecond
           -- timestamp prefix (ulid.New(ulid.Timestamp(t), entropy) in
           -- internal/attractor/engine/runid.go). Lexicographic max of run_id is
           -- therefore equivalent to "most recently started run". This comparison
           -- is safe across CXDB instances because run_id is generated by Kilroy
           -- at launch time (not by CXDB), so it does not depend on any per-instance
           -- counter. In contrast, context_id is a per-instance monotonic counter
           -- that resets independently on each CXDB server — comparing context_id
           -- values across instances can incorrectly favour an old run on a
           -- high-counter instance over a newer run on a low-counter instance.
           runGroups = groupBy(candidates, "runId")
           activeRunId = null
           FOR EACH (runId, contexts) IN runGroups:
               IF activeRunId IS null OR runId > activeRunId:
                   -- ULID lexicographic comparison: larger string = later creation time
                   activeRunId = runId

           -- Detect run change and reset stale state
           IF previousActiveRunIds[pipeline.graphId] IS NOT null
              AND previousActiveRunIds[pipeline.graphId] != activeRunId:
               resetPipelineState(pipeline.graphId)  -- clear per-context status maps, cursors, turn cache for old run
               -- IMPORTANT: resetPipelineState does NOT remove old-run entries from
               -- knownMappings. Old-run contexts remain cached (with their graphName
               -- and runId) so that discoverPipelines skips them on future polls.
               -- Removing them would force expensive re-discovery (fetchFirstTurn)
               -- for every old-run context on every poll cycle. Since context IDs
               -- are monotonic and never recycled, retaining these mappings is safe.
               -- The determineActiveRuns algorithm naturally ignores old-run contexts
               -- because their runId will not match the new activeRunId.

           previousActiveRunIds[pipeline.graphId] = activeRunId
           activeContextsByPipeline[pipeline.graphId] = runGroups[activeRunId]

       RETURN activeContextsByPipeline
   ```

   The `lookupContext` helper finds the context object (from step 1's context list responses) by `(cxdb_index, context_id)` to access fields like `is_live`. The `resetPipelineState` helper clears the per-context status maps, `lastSeenTurnId` cursors, and per-pipeline turn cache for all contexts that belonged to the old run. It does **not** remove `knownMappings` entries for the old run — doing so would force expensive `fetchFirstTurn` re-discovery for every old-run context on every subsequent poll cycle. Old-run entries are harmless: the `determineActiveRuns` algorithm naturally ignores them because their `runId` does not match the current active run (which is selected by ULID lex max, not by `context_id`). CXDB context IDs are monotonically increasing integers allocated from a per-instance counter and are never reused within an instance, so old-run entries do not cause collisions within the `knownMappings` key space (which is always `(cxdb_index, context_id)`). Over time, old-run entries accumulate in `knownMappings` — this is acceptable because the number of entries is bounded by the total number of Kilroy contexts across all CXDB instances, which grows slowly. Entries with `null` mappings (negative caches for non-Kilroy contexts) are also retained.

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
6. Run `updateContextStatusMap` per context (updating persistent per-context maps and advancing each context's `lastSeenTurnId` cursor), then `mergeStatusMaps` across **active-run** contexts for **each loaded pipeline** (both active and inactive), then `applyErrorHeuristic` on each pipeline's merged map using the per-context turn caches, then `applyStaleDetection` using the pipeline liveness result from step 3 (Section 6.2). The merged map for each pipeline is cached as the pipeline's current display map. This ensures that when the user switches to an inactive tab, the cached merged map can be immediately applied to the SVG without recomputation, satisfying the "no gray flash" requirement (Section 4.4 and the "Switch between pipeline tabs" holdout scenario). Per-context status maps from unreachable instances are included in the merge using their cached values.
7. Apply CSS classes to SVG nodes for the active pipeline (Section 6.3)

**Poll scheduling.** The poller uses `setTimeout` (not `setInterval`). After a poll cycle completes, the next poll is scheduled 3 seconds later. This prevents overlapping poll cycles when CXDB instances respond slowly — at most one poll cycle is in flight at any time. The effective interval is 3 seconds plus poll execution time.

The polling interval is constant. It does not adapt to pipeline activity or CXDB load. Requests to different CXDB instances within a single poll cycle are issued in parallel.

**Status caching on failure.** The UI retains per-context status maps from the last successful poll. When a CXDB instance is unreachable, its contexts' status maps are not discarded — they participate in the merge using cached values. This ensures that status is preserved (not reverted to "pending") when a CXDB instance goes down temporarily. Cached status maps are only replaced when fresh data is successfully fetched for that context.

**Turn fetch limit.** Each context poll fetches at most 100 recent turns (`limit=100`; CXDB returns turns oldest-first). This window may not contain lifecycle turns for nodes that completed early in a long-running pipeline. The persistent status map (Section 6.2) ensures completed nodes retain their status even when their lifecycle turns fall outside this window.

**Gap recovery.** After step 4, if any context's fetched turns do not reach back to `lastSeenTurnId`, the poller issues additional paginated requests using `before_turn_id` to fetch the missing turns until `lastSeenTurnId` is reached or `next_before_turn_id` is null. The gap detection condition is:

```
oldestFetched = turns[0].turn_id   -- oldest turn in the batch (oldest-first ordering)
IF lastSeenTurnId IS NOT null
   AND numericTurnId(oldestFetched) > numericTurnId(lastSeenTurnId)  -- batch doesn't reach our cursor
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
    IF numericTurnId(oldestInGap) <= numericTurnId(lastSeenTurnId):
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

**Turn ID comparison.** CXDB turn IDs are numeric strings (e.g., `"6066"`). All turn ID comparisons in the UI — including the deduplication check, `lastSeenTurnId` tracking, `lastTurnId` on `NodeStatus`, gap recovery detection, and error heuristic sorting — must use numeric ordering: `parseInt(turn_id, 10)`. Lexicographic comparison breaks for IDs of different lengths (e.g., `"999" > "1000"` lexicographically). All pseudocode in this specification uses the `numericTurnId(id)` helper (equivalent to `parseInt(id, 10)`) to make numeric comparison explicit at every comparison site. This applies to gap recovery (Section 6.1), `updateContextStatusMap`, `mergeStatusMaps`, `applyErrorHeuristic`, and the detail panel's within-context sorting (Section 7.2).

**Status derivation algorithm (per context):**

The algorithm processes turns from a single CXDB context and promotes statuses in an existing per-context status map. When multiple contexts match the active pipeline (e.g., parallel branches), the algorithm runs independently per context and the results are merged (see below).

```
FUNCTION updateContextStatusMap(existingMap, dotNodeIds, turns, lastSeenTurnId):
    -- Prune entries for node IDs no longer in dotNodeIds (handles DOT file regeneration
    -- where nodes are removed). This prevents unbounded growth of per-context status maps
    -- and satisfies the Section 4.4 requirement that "removed nodes are dropped from the maps."
    FOR EACH nodeId IN keys(existingMap):
        IF nodeId NOT IN dotNodeIds:
            DELETE existingMap[nodeId]

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
        IF newLastSeenTurnId IS null OR numericTurnId(turn.turn_id) > numericTurnId(newLastSeenTurnId):
            newLastSeenTurnId = turn.turn_id

    -- turns are oldest-first from the API; gap recovery may prepend older turns
    FOR EACH turn IN turns:
        -- Skip turns already processed in a previous poll cycle
        IF lastSeenTurnId IS NOT null AND numericTurnId(turn.turn_id) <= numericTurnId(lastSeenTurnId):
            CONTINUE  -- skip this turn; batch may not be sorted, so don't break

        nodeId = turn.data.node_id
        typeId = turn.declared_type.type_id
        IF nodeId IS null OR nodeId NOT IN existingMap:
            CONTINUE

        -- Determine the status this turn implies
        newStatus = null
        IF typeId == "com.kilroy.attractor.StageFinished":
            existingMap[nodeId].hasLifecycleResolution = true
            IF turn.data.status == "fail":
                newStatus = "error"
            ELSE:
                newStatus = "complete"
        ELSE IF typeId == "com.kilroy.attractor.StageFailed":
            IF turn.data.will_retry == true:
                newStatus = "running"
                -- Do NOT set hasLifecycleResolution. The node is retrying, not terminally
                -- failed. A subsequent StageFinished or StageFailed (will_retry=false)
                -- will provide the authoritative resolution.
            ELSE:
                newStatus = "error"
                existingMap[nodeId].hasLifecycleResolution = true
        ELSE IF typeId == "com.kilroy.attractor.RunFailed":
            newStatus = "error"
            existingMap[nodeId].hasLifecycleResolution = true
        ELSE IF typeId == "com.kilroy.attractor.StageStarted":
            newStatus = "running"
        ELSE:
            -- Non-lifecycle turns: infer running
            newStatus = "running"

        -- Promote status. Lifecycle resolutions (StageFinished, terminal StageFailed)
        -- are authoritative and unconditionally override status. Once a node has
        -- lifecycle resolution, only other lifecycle turns can modify its status.
        -- Non-lifecycle turns follow promotion-only (never demote).
        -- StageFailed with will_retry=true is NOT a lifecycle resolution — it sets
        -- "running" status and follows the non-lifecycle promotion path, allowing
        -- the retry to proceed visually as a running node.
        IF typeId == "com.kilroy.attractor.StageFinished"
           OR (typeId == "com.kilroy.attractor.StageFailed" AND turn.data.will_retry != true)
           OR typeId == "com.kilroy.attractor.RunFailed":
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
           OR numericTurnId(turn.turn_id) > numericTurnId(existingMap[nodeId].lastTurnId):
            existingMap[nodeId].lastTurnId = turn.turn_id

    RETURN (existingMap, newLastSeenTurnId)
```

**Turn deduplication.** Each per-context status map tracks a `lastSeenTurnId` — the newest `turn_id` processed in the previous poll cycle. On each poll, the algorithm skips turns with `turn_id <= lastSeenTurnId`, processing only newly appended turns. Because gap recovery prepends older turns before the main batch (both segments are oldest-first but the combined batch has a discontinuity at the join point), the algorithm uses `CONTINUE` instead of `BREAK` to skip already-seen turns — it cannot assume strictly ascending order across the join. The `newLastSeenTurnId` cursor is computed as the maximum `turn_id` across the entire batch before the processing loop begins, ensuring it always advances to the newest turn regardless of batch ordering. This prevents `turnCount` and `errorCount` from being inflated by re-processing overlapping turns across poll cycles. The cursor is initialized to `null` (process all turns) when a context is first discovered, and resets to `null` when the active `run_id` changes.

**lastTurnId assignment.** The `lastTurnId` field on `NodeStatus` records the most recent turn for that node. It is updated whenever a turn's `turn_id` exceeds the stored value (using numeric comparison). Since turns arrive oldest-first, later encounters per node in the batch have higher turn IDs, and the max-comparison ensures `lastTurnId` always holds the newest turn ID. Across poll cycles, new turns always have higher IDs than previously stored values (due to deduplication), so `lastTurnId` correctly advances to reflect the latest activity for each node.

**Lifecycle turn precedence.** `StageFinished`, `StageFailed`, and `RunFailed` are authoritative lifecycle signals. When processed, they set `hasLifecycleResolution = true` on the node and unconditionally override the current status — including any previous status. `RunFailed` is a pipeline-level failure event that carries an optional `node_id` — when present and non-empty, it marks the node as "error" (red). Kilroy's `cxdbRunFailed` always includes a `node_id` key, but the value may be an empty string if the run fails before entering any node (e.g., during graph initialization — see `persistFatalOutcome` in `engine.go`). An empty `node_id` passes the `IF nodeId IS null` guard but is filtered by the `IF nodeId NOT IN existingMap` guard, so it does not affect any node's status. `StageFinished` checks the `data.status` field: if `status == "fail"`, the node is set to "error" (red); otherwise it is set to "complete" (green). This ensures that a node which finished with a terminal failure (e.g., `StageFinished { status: "fail" }` followed by `RunFailed`) displays as red, not green. The `status` field has five canonical values (`"success"`, `"partial_success"`, `"retry"`, `"fail"`, `"skipped"` — from Kilroy's `StageStatus` enum in `runtime/status.go`) and may also contain custom routing values (e.g., `"process"`, `"done"`, `"port"`, `"needs_dod"`) used for multi-way conditional branching (see `ParseStageStatus` in `runtime/status.go` lines 31-39, and `custom_outcome_routing_test.go`). All values are treated as "complete" except `"fail"`. The UI must not assume a closed set of status values — the `status == "fail"` check is the only branch that matters. This handles three cases: (a) an agent encounters 3+ tool errors but then recovers and completes the node successfully, (b) gap recovery prepends older turns before the main batch, where a `StageStarted` turn might appear after a `StageFinished` for the same node in the combined batch, and (c) a node terminates with `StageFinished { status: "fail" }` and should display as error, not complete. Once a node has `hasLifecycleResolution = true`, only other lifecycle turns (`StageFinished`, `StageFailed`, `RunFailed`) can modify its status — non-lifecycle turns are ignored for that node. This prevents a `StageStarted` turn (processed after `StageFinished` due to batch ordering) from regressing a completed node back to running. The error loop heuristic (which runs post-merge) also skips nodes with `hasLifecycleResolution = true`.

**Error loop detection heuristic.** The heuristic runs as a post-merge step (see `applyErrorHeuristic` above), after `updateContextStatusMap` and `mergeStatusMaps` have produced the merged display map. It fires only for nodes that are "running" and have no lifecycle resolution (`hasLifecycleResolution == false`). For each such node, it examines each context's cached turns independently — if any single context has 3 consecutive recent errors for the node, the node is promoted to "error" in the merged map. This per-context scoping avoids cross-instance `turn_id` comparison: CXDB instances have independent turn ID counters with no temporal relationship, so sorting turns by `turn_id` across instances would produce arbitrary interleaving rather than temporal ordering. Within a single context, `turn_id` is monotonically increasing and safe to use for ordering. The `errorCount` field on `NodeStatus` is an internal-only lifetime counter used for diagnostics (e.g., logging, debugging) but is **not displayed** in the detail panel UI. The same applies to `turnCount` and `toolName` on `NodeStatus` — these are internal bookkeeping fields used by the status derivation and merge algorithms, not rendered in the detail panel. The detail panel's CXDB Activity section (Section 7.2) shows individual turn rows sourced from the turn cache, not aggregated counters from `NodeStatus`.

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

The `getMostRecentToolResultsForNodeInContext` helper scans a single context's cached turns for `ToolResult` turns (i.e., turns whose `declared_type.type_id` is `com.kilroy.attractor.ToolResult`) matching the given `node_id`, collecting them sorted by `numericTurnId(turn_id)` descending (newest-first, which is safe for intra-context ordering since turn IDs are monotonically increasing within a single context), and returns the first `count` matches. Only `ToolResult` turns carry the `is_error` field (see Section 5.4); other turn types (Prompt, ToolCall, etc.) do not have this field, so including them would dilute the error detection window and prevent the heuristic from firing during typical error loops where turn types interleave as Prompt → ToolCall → ToolResult. This avoids the cross-instance `turn_id` ordering problem: turn IDs are only compared within the same CXDB instance and context, where they have a meaningful temporal relationship.

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

**SVG element coverage.** The CSS selectors (`polygon`, `ellipse`, `path`) cover all ten node shapes in the Kilroy shape vocabulary (Section 7.3). Most shapes (`Mdiamond`, `Msquare`, `box`, `diamond`, `parallelogram`, `hexagon`, `component`, `tripleoctagon`, `house`) render as `<polygon>`. `circle` renders as `<ellipse>`. `doublecircle` renders as two nested `<ellipse>` elements — the CSS selectors match both, coloring the entire node correctly. No shapes render as elements outside the `polygon`/`ellipse`/`path` set.

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
| Prompt | DOT `prompt` attribute | Full prompt text, scrollable, whitespace-preserved (`white-space: pre-wrap`) |
| Tool Command | DOT `tool_command` attribute | Shell command for tool gate nodes, whitespace-preserved (`white-space: pre-wrap`) |
| Question | DOT `question` attribute | Human gate question text, whitespace-preserved (`white-space: pre-wrap`) |
| Choices | Outgoing edge labels via `GET /dots/{name}/edges` | Available choices for human gate nodes — labels of edges whose `source` matches this node's ID (see Section 3.2) |
| Goal Gate | DOT `goal_gate` attribute | Boolean flag — if `"true"`, this conditional node acts as a goal gate (displayed as a badge on the detail panel header). Goal gates use the same `diamond` shape as regular conditionals. |

**HTML escaping.** All DOT attribute values rendered in the detail panel (Node ID, Prompt, Tool Command, Question, Choices edge labels, and Goal Gate badge labels) must be HTML-escaped before DOM insertion — either via `textContent` assignment or explicit entity escaping (`<` → `&lt;`, `>` → `&gt;`, `&` → `&amp;`, `"` → `&quot;`). DOT files are user-provided inputs; unescaped rendering via `innerHTML` or string interpolation into HTML would allow injection of arbitrary markup. This applies to all text fields from the `/dots/{name}/nodes` and `/dots/{name}/edges` responses.

### 7.2 CXDB Activity

The detail panel shows recent CXDB turns for the selected node. Turns are sourced from the per-pipeline turn cache (Section 6.1, step 5), filtered to those where `turn.data.node_id` matches the selected node's DOT ID.

**Context-grouped display.** When the selected node has matching turns across multiple contexts (e.g., parallel branches), turns are displayed grouped by context rather than interleaved. Each context's turns appear in a collapsible section labeled with the CXDB instance index and context ID (e.g., "CXDB-0 / Context 33"). Within each section, turns are displayed newest-first (the UI reverses the API's oldest-first order) by `turn_id` — this is safe because `turn_id` is monotonically increasing within a single context's parent chain (see Section 6.2). Sections are ordered using a two-level sort: first by CXDB instance index (lower index first), then by highest `turn_id` among the context's matching turns (descending — most recent first). This groups contexts by instance, where `turn_id` comparison is meaningful (monotonically increasing within a single instance), and uses a stable, deterministic ordering across instances. CXDB instances have independent turn ID counters with no temporal relationship, so cross-instance `turn_id` comparison is not attempted.

| Column | Source | Description |
|--------|--------|-------------|
| Type | `declared_type.type_id` | Turn type (ToolCall, ToolResult, Prompt, etc.) |
| Tool | `data.tool_name` | Tool invoked (e.g., `shell`, `write_file`) — blank for non-tool turns |
| Output | varies by type (see mapping below) | Truncated content (expandable). Rendered with `white-space: pre-wrap` to preserve newlines, indentation, and runs of whitespace. Truncation is applied after HTML-escaping. |
| Error | `data.is_error` | Highlighted if true — only applicable to ToolResult |

**Per-type rendering.** The Output column content varies by turn type:

| Turn Type | Output Column | Tool Column | Error Column |
|-----------|--------------|-------------|--------------|
| `Prompt` | `data.text` | blank | blank |
| `ToolCall` | `data.arguments_json` | `data.tool_name` | blank |
| `ToolResult` | `data.output` | `data.tool_name` | `data.is_error` (highlighted if true) |
| `AssistantMessage` | `data.text` | `data.model` | blank |
| `StageStarted` | "Stage started" + (if `data.handler_type` is non-empty: ": {`data.handler_type`}") | blank | blank |
| `StageFinished` | "Stage finished: {`data.status`}" + (if `data.preferred_label` is non-empty: " — {`data.preferred_label`}") + (if `data.failure_reason` is non-empty: "\n{`data.failure_reason`}") + (if `data.notes` is non-empty: "\n{`data.notes`}") + (if `data.suggested_next_ids` is non-empty: "\nNext: {comma-joined `data.suggested_next_ids`}") | blank | highlighted if `data.status` is `"fail"` |
| `StageFailed` | `data.failure_reason` + (if `data.will_retry == true`: " (will retry, attempt {`data.attempt`})") + (if `data.will_retry != true` and `data.attempt` is present and > 0: " (attempt {`data.attempt`})") | blank | highlighted (only if `data.will_retry != true`) |
| `StageRetrying` | "Retrying (attempt {`data.attempt`}" + (if `data.delay_ms` is present and > 0: ", delay {formatted_delay}") + ")" where `formatted_delay` uses the `formatMilliseconds` helper (see below) | blank | blank |
| `RunCompleted` | `data.final_status` | blank | blank |
| `RunFailed` | `data.reason` | blank | highlighted |
| `InterviewStarted` | `data.question_text` + (if `data.question_type` is non-empty: " [{`data.question_type`}]") | blank | blank |
| `InterviewCompleted` | `data.answer_value` + (if `data.duration_ms` is present and > 0: " (waited {formatted_duration})") | blank | blank |
| `InterviewTimeout` | `data.question_text` | blank | highlighted ("timeout") |
| Other/unknown | "[unsupported turn type]" (placeholder) | blank | blank |

**`formatMilliseconds` helper.** The `formatted_delay` (used by `StageRetrying`) and `formatted_duration` (used by `InterviewCompleted`) both use the same millisecond-to-human-readable conversion: if `ms >= 1000`, display as `{ms / 1000}s` — one decimal place if not a whole number, no decimal if it is (e.g., 1500 → "1.5s", 2000 → "2s", 60000 → "60s"). If `ms < 1000`, display as `{ms}ms` (e.g., 250 → "250ms", 1 → "1ms"). Values of 0 are excluded by the guard (`> 0`) before calling this helper.

**Tool gate turns.** Tool gate nodes (shape=parallelogram) produce `ToolCall` and `ToolResult` turns with `tool_name: "shell"`, the same turn types used by LLM task nodes. Kilroy's `ToolHandler` (`handlers.go` lines 536-549 and 621-652) runs the shell command and emits these turns with the command in `ToolCall.arguments_json` and stdout/stderr in `ToolResult.output`, where `is_error` reflects the exit code. No special rendering is needed — the standard per-type rendering handles tool gate turns identically to LLM task tool turns.

**Custom routing values in `StageFinished`.** For conditional nodes using custom routing outcomes (e.g., `"process"`, `"done"`, `"needs_dod"`), the `data.status` and `data.preferred_label` fields may contain the same value. The rendering displays both as-is — no deduplication is applied. For example, a conditional node with `status: "process"` and `preferred_label: "process"` displays as: "Stage finished: process — process".

**Pipeline-level turns without `node_id`.** The detail panel filters turns to those where `turn.data.node_id` matches the selected node's DOT ID. Pipeline-level turns that lack a `node_id` field — specifically `RunCompleted` (which carries only `run_id` and `final_status` — see Section 5.4) — will never match any node's filter and therefore never appear in the per-node detail panel. The `RunCompleted` row in the table above is included for completeness and documents the intended rendering *if* a `RunCompleted` turn were ever displayed, but it is unreachable in practice. `RunFailed`, by contrast, always includes a `node_id` field (Kilroy's `cxdbRunFailed` always passes one), though the value may be an empty string if the run fails before entering any node — in that case the `node_id` filter excludes it from all per-node detail panels. When `node_id` is a valid DOT node ID, the turn does appear in the detail panel for the failed node. Other pipeline-level turns without `node_id` (`CheckpointSaved`, `Artifact`, `Blob`, `BackendTraceRef`) fall through to the "Other/unknown" row but are similarly excluded by the `node_id` filter.

This mapping ensures all turn types that may appear in the turn cache render meaningfully. The high-value additions are: `AssistantMessage` (shows model name and LLM response text — a high-frequency turn type critical for the "mission control" use case), `InterviewStarted`/`InterviewCompleted`/`InterviewTimeout` (human gate interaction events — `InterviewStarted` includes `question_type` to distinguish gate modes, `InterviewCompleted` includes `duration_ms` to show how long the pipeline waited for human input), `StageRetrying` (shows retry attempt count and backoff delay), and `RunCompleted`/`RunFailed` (pipeline-level lifecycle events). `StageFailed` now renders `failure_reason` instead of a generic label. The remaining low-value types (`Artifact`, `Blob`, `BackendTraceRef`, `CheckpointSaved`, `GitCheckpoint`, `ParallelStarted`, `ParallelBranchStarted`, `ParallelBranchCompleted`, `ParallelCompleted`) fall through to the "Other/unknown" row — they carry no user-facing content beyond what is already reflected in the status overlay. The `StageStarted` lifecycle turn displays its `handler_type` field (e.g., "Stage started: codergen", "Stage started: tool", "Stage started: wait.human") to help operators identify what kind of execution is beginning — particularly useful for conditional nodes with `TypeOverride` that use a different handler than their shape would suggest. The `handler_type` value comes from Kilroy's `resolvedHandlerType` function (`cxdb_events.go` line 72, `handlers.go` lines 174-182). `StageFinished` renders its `status`, `preferred_label`, `failure_reason`, `notes`, and `suggested_next_ids` fields because these carry substantive operator-facing information: `status` distinguishes success from failure (a node with `status: "fail"` displays as red/error in the overlay), `preferred_label` shows which edge the pipeline chose at a conditional node, `failure_reason` explains why a node failed, `notes` provides a concise handler-generated summary of what happened during node execution (e.g., "applied workaround for flaky test", "retried 2 times before success") — the only narrative record beyond the raw tool call/result stream, and `suggested_next_ids` shows which downstream nodes the pipeline selected (useful for understanding branching decisions at conditional/routing nodes). Both `notes` and `suggested_next_ids` are always emitted by Kilroy's `cxdbStageFinished` (`cxdb_events.go` lines 87-88) but may be empty. `StageRetrying` renders `delay_ms` alongside `attempt` to show the backoff delay between retry attempts — this helps operators judge whether a persistent failure (escalating delays) warrants intervention.

**Kilroy-side truncation.** Kilroy truncates three high-frequency text fields at the source before appending to CXDB: `AssistantMessage.text`, `ToolCall.arguments_json`, and `ToolResult.output` are each capped at 8,000 characters by the Kilroy engine (`cli_stream_cxdb.go` lines 46, 66, 87). The UI's client-side truncation (below) operates within this limit for these fields. Expanding a truncated turn row via "Show more" shows at most 8,000 characters for these fields, not the full original content (e.g., a complete LLM response may exceed 8,000 characters but only the truncated version reaches CXDB). **`Prompt.text` is NOT truncated** — `cxdbPrompt` in `cxdb_events.go` passes the full assembled LLM prompt directly to CXDB without calling `truncate`. Prompt text commonly ranges from 5,000 to 50,000+ characters for complex LLM tasks. Other text fields (`StageFailed.failure_reason`, `RunFailed.reason`, `InterviewStarted.question_text`) are also not truncated at the Kilroy side but are typically short. The client-side Output column truncation (500 characters / 8 lines) handles visual presentation for all fields regardless of source-side truncation. An implementer should not assume all text values fit within 8,000 characters — `Prompt.text` in particular may be significantly larger.

**Prompt expansion behavior.** Because `Prompt.text` is not truncated at the source, clicking "Show more" on a `Prompt` turn expands to the full prompt text — which may be 50,000+ characters. Implementations must handle this gracefully. The required behavior is to apply the same 8,000-character secondary cap on expansion for `Prompt` turns as for `AssistantMessage`, `ToolCall`, and `ToolResult` turns. When a `Prompt` turn is capped at 8,000 characters on expansion, the UI must display a disclosure note (e.g., "(truncated to 8,000 characters — full prompt available in CXDB)") so the operator knows the content is not complete. This cap prevents unbounded DOM growth and maintains consistent UX across all expandable turn types. Implementations that expand `Prompt` turns without a secondary cap are not spec-compliant — the combination of an unbounded prompt (no source-side truncation) and a no-cap expansion would inject tens of thousands of characters into a single DOM element, creating visible layout and performance issues.

**Truncation and expansion.** The Output column truncates content to the first 500 characters or 8 lines, whichever limit is reached first. Truncation is applied after HTML-escaping and before rendering in the `white-space: pre-wrap` container. When content is truncated, a "Show more" toggle appears inline below the visible excerpt. Clicking "Show more" expands the row to display the full content (still whitespace-preserved) and changes the toggle to "Show less" to re-collapse. Each turn row has its own independent expand/collapse state. Line breaks in the visible truncated excerpt are preserved (truncation does not collapse whitespace). Fixed-label outputs (lifecycle turns, unknown types) are never truncated.

Within each context section, turns are displayed newest-first (reversed from the API's oldest-first order for better UX — most recent activity at the top). All `turn_id` comparisons used for ordering within the detail panel — both within-context sorting and cross-context section ordering — must be numeric (`parseInt(turn_id, 10)`), consistent with Section 6.2. Lexicographic comparison breaks for IDs of different digit lengths (e.g., `"999" > "1000"` lexicographically). The panel shows at most 20 turns per context section. If all of a node's turns have scrolled out of the 100-turn poll window (i.e., the node completed early and subsequent nodes have generated many turns), the detail panel shows the node's DOT attributes but displays "No recent CXDB activity" in place of the turn list. The node's status remains correct via the persistent status map (Section 6.2).

### 7.3 Shape-to-Type Label Mapping

| Shape | Display Label |
|-------|--------------|
| `Mdiamond` | Start |
| `circle` | Start |
| `Msquare` | Exit |
| `doublecircle` | Exit |
| `box` | LLM Task |
| `diamond` | Conditional |
| `parallelogram` | Tool Gate |
| `hexagon` | Human Gate |
| `component` | Parallel |
| `tripleoctagon` | Parallel Fan-in |
| `house` | Stack Manager Loop |
| *(any other)* | LLM Task (default) |

The table above reflects all ten shapes in Kilroy's `shapeToType` function (`kilroy/internal/attractor/engine/handlers.go`). `circle` is an alternative start shape (rendered as `<ellipse>` in SVG) and `doublecircle` is an alternative exit shape (rendered as two nested `<ellipse>` elements). `component`, `tripleoctagon`, and `house` are all rendered as `<polygon>` in SVG. The default row matches Kilroy's `default` case, which returns `"codergen"` (mapped to "LLM Task" in the UI) for any unrecognized shape — this ensures the UI handles DOT files with unexpected shapes gracefully.

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

**HTML escaping.** CXDB URLs displayed in the indicator (e.g., in the "CXDB unreachable" state or the hover tooltip for partial connectivity) must be rendered as text-only — via `textContent` assignment or explicit HTML entity escaping. CXDB URLs come from command-line `--cxdb` flags and may contain query parameters with `&` or other characters that would be interpreted as HTML if inserted via `innerHTML`. This matches the tab label (Section 4.4) and detail panel (Section 7.1) escaping policies.

### 8.3 Interaction

- **Click node:** Opens detail panel for that node
- **Click outside panel or close button:** Closes detail panel
- **Click pipeline tab:** Switches to that pipeline's DOT file, re-renders SVG
- **Browser zoom (Ctrl+scroll):** Zooms the SVG natively

---

## 9. Invariants

**Graph Rendering**

1. **Every DOT node appears in the SVG.** The UI does not filter, hide, or skip nodes. The graph is rendered as-is by Graphviz WASM.

2. **SVG rendering is deterministic.** The same DOT input always produces the same SVG layout. Node positions are determined entirely by Graphviz, not by the UI.

3. **Graph renders without CXDB.** If CXDB is unreachable, the graph renders with all nodes in pending (gray) state. CXDB is an overlay, not a prerequisite.

4. **DOT files are never modified.** The UI reads DOT files. It never writes to them.

   **Status Overlay**

5. **Status is derived from CXDB turns, never fabricated.** A node's status is determined primarily by lifecycle turns (`StageStarted` → running, `StageFinished` with `status != "fail"` → complete, `StageFinished` with `status == "fail"` → error, terminal `StageFailed` → error). A `StageFailed` with `will_retry: true` sets status to "running" (not "error") and does not count as lifecycle resolution — the node is actively retrying. When lifecycle turns are absent, a heuristic fallback infers status from turn activity. The UI does not infer status beyond what the turn data provides.

6. **Status is mutually exclusive.** Every node has exactly one status: `pending`, `running`, `complete`, `error`, or `stale`.

7. **Polling delay is constant at 3 seconds.** After each poll cycle completes, the next poll is scheduled 3 seconds later via `setTimeout`. At most one poll cycle is in flight at any time. The delay does not back off, speed up, or adapt.

8. **Unknown node IDs in CXDB are ignored.** If a turn references a `node_id` not in the loaded DOT file, the UI silently skips it.

9. **Pipeline scoping is strict.** The status overlay only uses CXDB contexts whose `RunStarted` turn's `graph_name` matches the active DOT file's graph ID. Turns from unrelated contexts never appear. This holds across all configured CXDB instances.

10. **Context-to-pipeline mapping is immutable once resolved and never removed.** Once a context is successfully mapped to a pipeline via its `RunStarted` turn (or confirmed as non-Kilroy with a `null` mapping), the mapping is never re-evaluated or deleted. The `RunStarted` turn does not change. Mappings are keyed by `(cxdb_index, context_id)`. Contexts whose discovery failed due to transient errors, and empty contexts (no turns yet), are not cached and are retried on subsequent polls until classification succeeds. Old-run mappings are retained in `knownMappings` even after `resetPipelineState` clears per-context status maps, cursors, and turn caches — this prevents expensive re-discovery (`fetchFirstTurn`) for old-run contexts on every poll cycle. The `determineActiveRuns` algorithm naturally ignores old-run contexts because their `runId` does not match the current active run.

11. **CXDB instances are polled independently.** A single unreachable CXDB instance does not prevent polling of other instances. The connection indicator shows per-instance status.

    **Server**

12. **The server is stateless.** It caches nothing. Every DOT request reads from disk. Every CXDB request is proxied in real time.

13. **Only registered DOT files are servable.** The `/dots/` endpoint serves only files registered via `--dot` flags. Unregistered filenames return 404.

14. **CXDB proxy is transparent.** Requests and responses are forwarded without modification.

    **Detail Panel**

15. **Content is displayed verbatim with whitespace preserved.** Prompt text, tool commands, and CXDB output are shown as-is (with HTML escaping for XSS prevention) in containers styled with `white-space: pre-wrap`. This preserves newlines, indentation, and runs of whitespace. The UI does not summarize or reformat.

   **API Contract**

16. **`/edges` expands chain syntax.** A DOT edge chain `a -> b -> c [label="x"]` is expanded into two independent edges: `(a, b, "x")` and `(b, c, "x")`. No direct edge from `a` to `c` is emitted. Each segment inherits the label from the chain's attribute block. This invariant is verified at the API layer (Go test or curl), not via the UI.

17. **`/edges` strips port suffixes.** Port syntax (`node_id:port` or `node_id:port:compass`) in edge endpoints is stripped: `a:out -> b:in` produces edge `{source: "a", target: "b", label: null}`. This invariant is verified at the API layer.

18. **Parse errors produce 400 with a JSON error body.** An unterminated block comment (`/*` without matching `*/`) or an unterminated string literal (`"` without a closing `"`) in a DOT file causes both `/dots/{name}/nodes` and `/dots/{name}/edges` to return HTTP 400 with a JSON body of the form `{"error": "DOT parse error: ..."}`. This invariant is verified at the API layer.

19. **Comments in DOT source are stripped before parsing; comments inside quoted strings are preserved.** A URL such as `http://example.com` inside a quoted attribute value is not treated as a line comment. This invariant is verified at the API layer.

   **Client-Side Logic**

20. **Discovery state machine behavior is verified by JavaScript unit tests, not by UI tests.** The following client-side behaviors require direct JS-level testing (mocking CXDB API responses and inspecting internal state) and cannot be reliably verified through Playwright DOM inspection alone:
    - `fetchFirstTurn` pagination and `MAX_PAGES` cap
    - `knownMappings` caching and null-entry semantics
    - `determineActiveRuns` ULID-based run selection
    - Gap recovery (`lastSeenTurnId` cursor, `MAX_GAP_PAGES` bound)
    - Error loop detection scoped per context
    - `cqlSupported` flag lifecycle (set, reset on reconnect, fallback path)
    - `NULL_TAG_BATCH_SIZE` batch limiting
    - Supplemental context list dedup merge
    - `cachedContextLists` population for liveness checks

    This invariant establishes the testing layer boundary: these behaviors belong in a JS unit test suite that imports the discovery module directly, not in the Playwright UI test skill.

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

11. **No DOT rendering from CXDB.** Although `RunStarted.graph_dot` embeds the pipeline DOT source at run start time (Section 5.4), the UI reads DOT files from disk via `--dot` flags. This enables: (a) viewing the pipeline graph before any CXDB data exists (e.g., while composing the pipeline), (b) reflecting live DOT file regeneration without requiring a new CXDB run, and (c) rendering pipelines that have never been executed. The `graph_dot` field is available for future features (e.g., historical run reconstruction showing the exact graph used for a past run) but is not used for graph rendering.

12. **No browser-side SSE event streaming.** CXDB exposes a `/v1/events` Server-Sent Events endpoint for real-time push notifications (e.g., `TurnAppended`, `ContextCreated`). The browser uses polling instead for simplicity — no persistent connection management, simpler error recovery, and 3-second latency is sufficient for the "mission control" use case. Note: the Go proxy server could optionally subscribe to CXDB's SSE endpoint server-side (using the Go client's `SubscribeEvents` function with automatic reconnection) to reduce discovery latency — e.g., immediately triggering discovery when a `ContextCreated` event with a `kilroy/`-prefixed `client_tag` arrives, without waiting for the next poll cycle. CXDB emits both `ContextCreated` (when the context is created, with `client_tag` from the session) and `ContextMetadataUpdated` (when the first turn's metadata is extracted, with `client_tag`, `title`, and `labels` from the payload — confirmed in `events.rs` lines 27-36 and the Go client's `ContextMetadataUpdatedEvent` at `clients/go/events.go` lines 19-25). The `ContextMetadataUpdated` event is the more reliable trigger for discovery because it fires after the metadata cache and CQL secondary indexes are populated — meaning a CQL search issued after receiving this event is guaranteed to find the context. A `ContextCreated`-based trigger could race with metadata extraction, requiring a fallback poll if CQL does not yet return the context. This is not required for the initial implementation but is a lower-complexity design point than browser-side SSE, since the browser's polling architecture remains unchanged.

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
- [ ] All node shapes render correctly (Mdiamond, Msquare, box, diamond, parallelogram, hexagon, circle, doublecircle, component, tripleoctagon, house — see Section 7.3 for the full shape-to-type mapping)
- [ ] Pipeline tabs switch between loaded DOT files

### CXDB Integration

- [ ] UI polls CXDB every 3 seconds
- [ ] Pipeline discovery via `RunStarted` turn's `graph_name` field
- [ ] Context-to-pipeline mapping is cached (no redundant discovery requests)
- [ ] Status derived from StageStarted/StageFinished/StageFailed lifecycle turns when present (StageFailed with will_retry=true sets running, not error; StageFinished with status="fail" sets error, not complete)
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
- [ ] Pipeline tab labels and CXDB indicator text are HTML-escaped (text-only rendering)

---

## 12. Testing Requirements

The implementation requires three distinct testing layers. All three layers must pass before the implementation is considered complete.

### 12.1 Go Unit Tests — Server Layer

**Coverage target: 100% line and branch coverage** for all Go code in `ui/`.

**Tooling:**
```bash
go test -cover -coverprofile=coverage.out ./...
go tool cover -func=coverage.out
```

**Scope:** All server handlers (`handleRoot`, `handleDots`, `handleAPIDots`, `handleAPICXDB`), DOT parsing functions (`parseNodes`, `parseEdges`, `extractGraphID`, `stripComments`, `parseAttrList`, `parseDotToken`, `parseAttrValue`), startup validation (duplicate basenames, duplicate graph IDs, anonymous graphs, missing `--dot`), and the CXDB proxy logic.

**Must run without** a live CXDB instance or browser. The test suite belongs in `ui/main_test.go` using `package main` so unexported parsing functions are directly testable.

**Enforcement:** The `script/smoke-test-suite-fast` script runs `go test ./...` and must pass before any commit is landed. Once the Go codebase has a test suite, coverage enforcement is added to the fast suite.

### 12.2 JavaScript Unit Tests — Client Logic Layer

**Coverage target: 100% line and branch coverage** for all JavaScript in `ui/index.html`.

**Pre-requisite:** JavaScript logic must be extracted from inline `<script>` tags into importable ES modules before this layer can be implemented. The inline-script constraint of the "No build toolchain" principle (Section 1.2) applies to the deployed artifact, not to the development and test workflow — the source can be modular ES modules that are inlined (or concatenated) as part of a simple build step.

**Tooling:** Vitest with V8 coverage provider:
```bash
vitest run --coverage --coverage.provider=v8 --coverage.100
```

**Scope:** The behaviors listed in Invariant 20 (Section 9) must each have unit tests that inject mock CXDB API responses and assert on internal state transitions. This is the only practical way to verify these behaviors — Playwright DOM inspection cannot observe intermediate state such as which endpoint was called, how many times, or what was cached.

**Must run without** a live server, browser, or CXDB instance.

### 12.3 Playwright UI Tests — Integration Layer

**Scope:** Visual rendering, DOM structure, user interactions, network error handling, and CXDB status overlay (with mock CXDB via Playwright request routing).

**What Playwright tests:** SVG rendered from DOT, tab labels match graph IDs, node colors match expected status, detail panel content, HTML escaping (no XSS), DOT file changes picked up on tab switch, CXDB unreachable states.

**What Playwright does NOT test:** Internal JS state machine steps, API JSON format details (edge chain structure, port stripping, parse error body shape), server startup behavior (exit codes, stderr messages). These are covered by Sections 12.1 and 12.2 respectively.

**Mock CXDB:** Status overlay scenarios use Playwright's request routing (`page.route`) to intercept `/api/cxdb/*` requests and return fixture JSON responses without a live CXDB instance. Fixture responses are stored in `.claude/skills/run-holdout-scenarios/fixtures/mock-cxdb/`.

**Server startup scenarios** (no `--dot` flag, duplicate basenames, duplicate graph IDs, anonymous graph) are tested via Bash subprocess in the same skill: run the binary, capture exit code and stderr, assert on expected values.

### 12.4 Testing Layer Boundaries

The following table maps scenario categories to their required testing layer:

| Scenario Category | Testing Layer |
|---|---|
| DOT Rendering — visual (SVG shapes, tab labels, HTML escaping) | Playwright (12.3) |
| DOT Rendering — API contract (edge chain JSON, port stripping, parse error bodies) | Go tests (12.1) |
| CXDB Status Overlay (node colors, pulsing, stale detection) | Playwright + mock CXDB (12.3) |
| Pipeline Discovery state machine (ULID selection, gap recovery, CQL flag, etc.) | JS unit tests (12.2) |
| Detail Panel — visual (panel opens, content rendered) | Playwright (12.3) |
| Detail Panel — CXDB turn format (StageStarted/Finished/Failed output strings) | JS unit tests (12.2) |
| CXDB Connection Handling (unreachable → message, partial connectivity indicator) | Playwright + mock CXDB (12.3) |
| Server startup validation (exit code, error messages) | Bash subprocess (12.3 skill) |
| Server API format (`/api/dots`, `/api/cxdb/instances`, `/dots/{name}` 404) | Go tests (12.1) |
