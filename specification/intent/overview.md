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

## 2. Architecture

The system has two components: a Rust HTTP server and a browser-side single-page application.

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
│  Rust Server                                     │
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

**Why Rust.** Rust provides memory safety without garbage collection, a strong type system with algebraic data types (`Result<T, E>`, `Option<T>`) for railway-oriented error handling, and zero-cost abstractions. The server uses `axum` for HTTP routing and handlers, `tokio` for the async runtime, `hyper` as the underlying HTTP implementation, `clap` for CLI argument parsing, and `thiserror` for structured error types. Dependencies are declared in `server/Cargo.toml`. The application is built and run with `cargo build` / `cargo run` from the `server/` directory, or via top-level `make build` / `make run`.

**Why browser-side DOT rendering.** The `@hpcc-js/wasm-graphviz` library compiles Graphviz to WebAssembly and runs entirely in the browser. This avoids requiring the `dot` binary on the host, supports interactive SVG manipulation, and renders DOT changes without server restart.

**Why a proxy for CXDB.** CXDB's REST endpoints (contexts, turns) do not set CORS headers. The SSE endpoint (`/v1/events`) does set `Access-Control-Allow-Origin: *`, but the UI uses polling, not SSE (see `specification/constraints/non-goals.md`). The browser cannot fetch from a different origin for the REST endpoints. The server reverse-proxies `/api/cxdb/*` to CXDB, putting all requests on a single origin. When multiple CXDB instances are configured, the server proxies each under a numeric index (`/api/cxdb/0/*`, `/api/cxdb/1/*`, etc.).
