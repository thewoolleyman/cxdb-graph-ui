# Server API (Downstream Contract)

This document defines the HTTP API surface of the CXDB Graph UI server — the contract between the Rust server and the browser SPA.

---

## Command-Line Interface

```
cargo run -- [OPTIONS]
```

Run from the `server/` directory, or use `make run` from the repo root.

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--port` | integer | `9030` | TCP port for the UI server |
| `--cxdb` | URL (repeatable) | `http://127.0.0.1:9110` | CXDB HTTP API base URL. May be specified multiple times for multiple CXDB instances. |
| `--dot` | path (repeatable) | (required) | Path to a pipeline DOT file. May be specified multiple times. |

Both `--dot` and `--cxdb` are repeatable. The UI auto-discovers which CXDB instances contain contexts for which pipelines (Section 5.5). No manual pairing is required.

If no `--cxdb` flags are provided, the default (`http://127.0.0.1:9110`) is used as the sole instance. If no `--dot` flags are provided, the server exits with an error message and usage help.

**Examples:**

```bash
# Single pipeline, default CXDB (from server/ directory)
cargo run -- --dot /path/to/pipeline-alpha.dot

# Or using the Makefile from repo root
make run -- --dot /path/to/pipeline-alpha.dot

# Multiple pipelines, single CXDB
cargo run -- \
  --dot /path/to/pipeline-alpha.dot \
  --dot /path/to/pipeline-beta.dot \
  --dot /path/to/pipeline-gamma.dot

# Multiple pipelines, multiple CXDB instances
cargo run -- \
  --dot /path/to/pipeline-alpha.dot \
  --dot /path/to/pipeline-beta.dot \
  --cxdb http://127.0.0.1:9110 \
  --cxdb http://127.0.0.1:9111

# Custom CXDB address
cargo run -- --dot pipeline.dot --cxdb http://10.0.0.5:9110
```

The server prints the URL on startup: `Kilroy Pipeline UI: http://127.0.0.1:9030`

---

## Routes

### `GET /` — Dashboard

Serves `index.html` embedded in the binary at compile time using `include_str!()` or the `rust-embed` crate, serving it from the embedded data. The `include_str!()` macro resolves paths relative to the source file at compile time, so the embedded content is always available regardless of the working directory at runtime. Returns 500 if the embed fails to load (should not happen in a correctly compiled binary).

**`index.html` file location.** `index.html` must reside at a path reachable by the `include_str!()` macro relative to the embedding source file (typically in `server/assets/`). The embedding source file and the asset must be within the same crate.

### `GET /dots/{name}` — DOT Files

Serves DOT files registered via `--dot` flags. The `{name}` is the base filename (e.g., `pipeline-alpha.dot`).

- The server builds a map from base filename to absolute path at startup. If two `--dot` flags resolve to the same base filename (e.g., `pipelines/alpha/pipeline.dot` and `pipelines/beta/pipeline.dot` both have basename `pipeline.dot`), the server exits with a non-zero code and prints an error identifying the conflicting paths. This prevents silent collisions where one pipeline becomes unreachable.
- **Graph ID uniqueness.** At startup, the server parses each DOT file to extract its graph ID. The server uses the same graph ID parsing and normalization logic as the browser (Section 4.4): the regex `/^\s*(strict\s+)?(di)?graph\s+("(?:[^"\\]|\\.)*"|\w+)/m` extracts the identifier, quoted IDs are unquoted (outer `"` stripped) and unescaped (internal `\"` → `"`, `\\` → `\`), leading/trailing whitespace is trimmed, and the result is the normalized graph ID. This is the same normalization applied to node IDs (see `/dots/{name}/nodes` below). The `strict` keyword prefix is optional and consumed but does not affect the extracted ID. If the regex does not match (e.g., anonymous graphs like `digraph { ... }` with no identifier after the keyword), the server rejects the DOT file at startup with a non-zero exit code and an error message stating that named graphs are required for pipeline discovery (since `RunStarted.data.graph_name` must match the graph ID). This ensures that the server's uniqueness check and the browser's pipeline discovery match `RunStarted.data.graph_name` against the same normalized value. If two DOT files share the same normalized graph ID, the server exits with a non-zero code and prints an error identifying the conflicting files and graph ID. Duplicate graph IDs would cause ambiguous pipeline discovery — both pipelines would match the same CXDB contexts, producing identical and misleading status overlays. This check mirrors the basename collision check and runs at startup alongside it.
- Only filenames registered via `--dot` are servable. Requests for unregistered names return 404.
- Files are read fresh on each request. DOT file regeneration is picked up without server restart. If the registered file cannot be read from disk (e.g., deleted after server startup, permission error), the server returns 500 with a plain-text error body describing the failure. The browser handles non-200 responses from `/dots/{name}` by displaying an error message in the graph area (replacing the SVG). Recovery is automatic — the file is re-read on every request, so restoring the file resolves the error on the next fetch (tab switch or initial load).

### `GET /dots/{name}/nodes` — DOT Node Attributes

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

### `GET /dots/{name}/edges` — DOT Edge List

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

### `GET /api/cxdb/{index}/*` — CXDB Reverse Proxy

Each `--cxdb` flag registers a CXDB instance at a zero-based index. The proxy route includes the index to disambiguate instances.

- `/api/cxdb/0/v1/contexts` → first `--cxdb` URL + `/v1/contexts`
- `/api/cxdb/1/v1/contexts` → second `--cxdb` URL + `/v1/contexts`

The server strips `/api/cxdb/{index}` and forwards the remainder to the corresponding CXDB base URL.

- Request and response bodies are passed through unmodified.
- No header injection, body rewriting, or caching.
- If a CXDB instance is unreachable, returns 502 Bad Gateway for that index.
- Index out of range returns 404.

### `GET /api/dots` — DOT File List

Returns a JSON object with a `dots` array containing the available DOT filenames (registered via `--dot` flags), **in the same order as the `--dot` flags were provided on the command line**. This ordering is deterministic and must be preserved — the server must use an ordered data structure (e.g., a slice, not a map) for DOT file registration. The browser uses this order for tab rendering and selects the first entry as the initial pipeline. This is a server-generated response used by the browser to build pipeline tabs.

```json
{ "dots": ["pipeline-alpha.dot", "pipeline-beta.dot"] }
```

### `GET /api/cxdb/instances` — CXDB Instance List

The browser fetches `/api/cxdb/instances` to get the list of configured CXDB URLs and their indices. This is a server-generated JSON response, not proxied:

```json
{ "instances": ["http://127.0.0.1:9110", "http://127.0.0.1:9111"] }
```
