# Implement CXDB Graph UI

## Task

**CRITICAL: Read `.ai/postmortem_latest.md` first if it exists.**
- If postmortem exists: This is a REPAIR iteration. Fix only the specific gaps/failures identified. Do not regenerate working code.
- If postmortem absent: This is a FRESH implementation. Execute the specification from scratch.

Implement the CXDB Graph UI per the specification under `specification/` (intent, contracts, and constraints).

## Context

The CXDB Graph UI is a local web dashboard that renders Attractor pipeline DOT files as interactive SVG graphs with real-time execution status from CXDB. It has two components:

1. **`server/`** — A Rust HTTP server using axum/tokio that serves the SPA, DOT files, parsed node/edge data, and proxies CXDB API requests. All fallible operations return `Result<T, E>` with railway-oriented error handling (see `specification/constraints/railway-oriented-programming-requirements.md`).
2. **`server/assets/index.html`** — A browser SPA (single HTML file, inline CSS/JS, no build toolchain) that renders DOT → SVG via Graphviz WASM and overlays CXDB execution state onto graph nodes.

## Files to Read

**ALWAYS READ FIRST:**
- `.ai/postmortem_latest.md` — If present, this is a repair iteration. Read this BEFORE reading anything else.

**Then read the full specification:**
- All files under `specification/intent/` — Overview, architecture, server, DOT rendering, CXDB integration, status overlay, detail panel, UI layout
- All files under `specification/constraints/` — Invariants, non-goals, definition of done, testing requirements, ROP requirements
- All files under `specification/contracts/` — Server API (downstream) and CXDB API (upstream)

**If repair iteration, also read the files mentioned in the postmortem.**

## Files to Write

### Workspace root
- `Cargo.toml` — Workspace manifest: `[workspace] resolver = "2"` with `members = ["server"]`
- `Makefile` — Top-level build targets per `specification/intent/server.md` Section 3.4

### server/
- `server/Cargo.toml` — Crate manifest with dependencies (axum, tokio, hyper, clap, thiserror, serde, serde_json, tower-http) and `[lints.clippy]` enforcing ROP (unwrap_used = "deny", expect_used = "deny", panic = "deny", unwrap_in_result = "deny")
- `server/src/main.rs` — Thin binary entry point: CLI parsing via clap, Config construction, server startup, graceful shutdown
- `server/src/lib.rs` — Library crate declaring all public modules
- `server/src/error.rs` — `AppError` enum (thiserror), `AppResult<T>` type alias, `From` impls for upstream errors
- `server/src/config.rs` — `Config` struct with clap derives for `--dot`, `--cxdb`, `--port`
- `server/src/server.rs` — axum router, all route handlers returning `impl IntoResponse`
- `server/src/dot_parser.rs` — DOT file parsing (nodes, edges, comments, graph ID extraction, normalization)
- `server/src/cxdb_proxy.rs` — CXDB reverse proxy handler
- `server/assets/index.html` — Browser SPA

## What to Do

**If `.ai/postmortem_latest.md` exists:**
1. Read postmortem first — understand what failed
2. Read only the specific files mentioned in the postmortem
3. Make surgical fixes to address the identified failures
4. Do NOT regenerate modules that are working
5. Do NOT change code that isn't related to the failure

**If postmortem absent (fresh implementation):**

### Workspace root
- `Cargo.toml` with `[workspace]` section
- `Makefile` with targets: build, release, test, test-browser, clippy, fmt, fmt-check, check, clean, run, precommit

### server/Cargo.toml
- Crate name: `cxdb-graph-ui`
- Edition: `2021`
- Dependencies: axum, tokio (features: full), hyper, clap (features: derive), thiserror, serde (features: derive), serde_json, tower-http (features: as needed for proxy)
- `[lints.clippy]` section with ROP lints set to "deny"

### server/src/error.rs
- `AppError` enum with variants for: DotParse, FileIo, CxdbProxy, CliValidation, HttpHandler, Embed
- Each variant carries context for actionable error messages
- `From` impls for `std::io::Error`, `hyper::Error`, etc.
- `impl IntoResponse for AppError` mapping variants to HTTP status codes
- `pub type AppResult<T> = Result<T, AppError>;`

### server/src/config.rs
- `Config` struct with clap derives for `--port` (u16, default 9030), `--cxdb` (Vec<String>, default ["http://127.0.0.1:9110"]), `--dot` (Vec<PathBuf>, required)
- Startup validation: at least one --dot, no duplicate basenames, no duplicate graph IDs, no anonymous graphs

### server/src/server.rs
Implement all routes per `specification/contracts/server-api.md`:
- `GET /` — Serve embedded `index.html` via `include_str!()`
- `GET /dots/{name}` — Serve registered DOT files (read fresh each request via `tokio::fs::read_to_string`)
- `GET /dots/{name}/nodes` — Return JSON map of node ID → attributes (shape, class, prompt, tool_command, question, goal_gate)
- `GET /dots/{name}/edges` — Return JSON array of edges (source, target, label)
- `GET /api/cxdb/{index}/*` — Reverse-proxy to the corresponding CXDB instance
- `GET /api/dots` — Return JSON list of registered DOT filenames (ordered)
- `GET /api/cxdb/instances` — Return JSON list of CXDB URLs

Server properties:
- Bind to `0.0.0.0:{port}` via `tokio::net::TcpListener`
- Print `Kilroy Pipeline UI: http://127.0.0.1:{port}` on startup
- Stateless — no caching
- All handlers return `Result` or `impl IntoResponse` — no panics

### server/src/dot_parser.rs
DOT parsing (`specification/contracts/server-api.md`):
- Strip `//` line comments and `/* */` block comments (per spec comment-stripping rules)
- Parse node attributes: quoted and unquoted values, `+` string concatenation, multi-line quoted strings, escape decoding (`\"` → `"`, `\n` → newline, `\\` → `\`)
- Parse edge statements: `->` chains expanded, port syntax stripped, same attribute parsing rules
- Normalize node/edge IDs: strip outer quotes, resolve escape sequences, trim whitespace
- All parse functions return `AppResult<T>` — parse errors produce `AppError::DotParse` with context

### server/assets/index.html
Implement the full SPA per the intent specification (Sections 4–8):

**CDN imports (pinned versions, ES modules):**
```html
<script type="module">
import { Graphviz } from "https://esm.sh/@hpcc-js/wasm-graphviz@1.6.1";
import { decode } from "https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/mod.min.mjs";
```

**Pipeline tabs** (Section 4.4):
- Fetch `/api/dots` on load, render a tab per DOT file
- Tab label: graph ID extracted from DOT source, fallback to filename
- Tab labels rendered via `textContent` (no innerHTML — XSS prevention)

**DOT rendering** (Section 4.1):
- Fetch DOT content from `/dots/{name}`, render SVG via `Graphviz.load()` then `gv.layout(dot, "svg", "dot")`
- Inject resulting SVG into main content area

**Status overlay** (Sections 4.2, 5, 6):
- Poll CXDB every 3 seconds via `/api/cxdb/{index}/v1/contexts` and `/api/cxdb/{index}/v1/contexts/{id}/turns`
- Match turns to pipeline by `RunStarted.data.graph_name` == normalized graph ID
- Color SVG nodes by status: pending/running/complete/error/stale
- Apply `data-status` attribute and CSS class to each `<g class="node">` element

**Pipeline discovery** (Section 5.5):
- Fetch `/api/cxdb/instances` to get all CXDB indices
- For each CXDB, fetch `/v1/contexts` and find the most recent context whose `RunStarted` turn has `graph_name` matching the current pipeline's graph ID
- Decode `RunStarted` turn using msgpack (`view=raw`, base64 decode, `decode()`)

**Detail panel** (Section 7):
- Click on a node → show its CXDB turns in a sidebar panel
- Display node type (from `shape`), class, prompt, tool_command, question, edges
- All user-supplied content rendered via `textContent` or explicit HTML escaping

**Connection indicator** (Section 8):
- Show connection status to CXDB

## Acceptance Checks

- `Cargo.toml` (workspace root) and `server/Cargo.toml` exist and are valid
- `Makefile` exists with required targets
- `cargo build` succeeds from `server/`
- `cargo clippy -- -D warnings` passes (enforces ROP: no unwrap/expect/panic outside tests)
- `cargo fmt --check` passes
- `cargo test` passes
- `server/assets/index.html` exists
- All 7 routes implemented
- DOT parser handles comments, multi-line strings, `+` concatenation, escape sequences
- Startup rejects duplicate basenames, duplicate graph IDs, anonymous graphs
- CDN URLs pinned to exact versions from spec

## Status Contract

Write status JSON to `$KILROY_STAGE_STATUS_PATH` (absolute path). If unavailable, use `$KILROY_STAGE_STATUS_FALLBACK_PATH`.

Success: `{"status":"success"}`
Failure: `{"status":"fail","failure_reason":"<reason>","details":"<details>","failure_class":"deterministic"}`
Retry (transient): `{"status":"retry","failure_reason":"<reason>","details":"<details>","failure_class":"transient_infra"}`

Do not write nested `status.json` files after `cd`.
