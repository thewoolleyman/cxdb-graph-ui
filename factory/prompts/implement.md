# Implement CXDB Graph UI

## Task

**CRITICAL: Read `.ai/postmortem_latest.md` first if it exists.**
- If postmortem exists: This is a REPAIR iteration. Fix only the specific gaps/failures identified. Do not regenerate working code.
- If postmortem absent: This is a FRESH implementation. Execute the specification from scratch.

Implement the CXDB Graph UI per the specification under `specification/` (intent, contracts, and constraints).

## Context

The CXDB Graph UI is a local web dashboard that renders Attractor pipeline DOT files as interactive SVG graphs with real-time execution status from CXDB. It has two components:

1. **`ui/main.go`** — A Go HTTP server (standard library only) that serves the SPA, DOT files, parsed node/edge data, and proxies CXDB API requests.
2. **`ui/index.html`** — A browser SPA (single HTML file, inline CSS/JS, no build toolchain) that renders DOT → SVG via Graphviz WASM and overlays CXDB execution state onto graph nodes.
3. **`ui/go.mod`** — Minimal Go module file (module name: `cxdb-graph-ui`, no external dependencies).

## Files to Read

**ALWAYS READ FIRST:**
- `.ai/postmortem_latest.md` — If present, this is a repair iteration. Read this BEFORE reading anything else.

**Then read the full specification:**
- All files under `specification/intent/` — Overview, architecture, server, DOT rendering, CXDB integration, status overlay, detail panel, UI layout
- All files under `specification/constraints/` — Invariants, non-goals, definition of done, testing requirements
- All files under `specification/contracts/` — Server API (downstream) and CXDB API (upstream)

**If repair iteration, also read the files mentioned in the postmortem.**

## Files to Write

- `ui/go.mod` — Go module file: `module cxdb-graph-ui` with Go version matching host toolchain (1.21+), no require directives
- `ui/main.go` — Go HTTP server
- `ui/index.html` — Browser SPA

## What to Do

**If `.ai/postmortem_latest.md` exists:**
1. Read postmortem first — understand what failed
2. Read only the specific files mentioned in the postmortem
3. Make surgical fixes to address the identified failures
4. Do NOT regenerate modules that are working
5. Do NOT change code that isn't related to the failure

**If postmortem absent (fresh implementation):**

### ui/go.mod
- Module name: `cxdb-graph-ui`
- Go version: `go 1.21` (or match host toolchain version)
- No `require` directives — standard library only

### ui/main.go
Implement all routes per `specification/contracts/server-api.md`:
- `GET /` — Serve embedded `index.html` via `//go:embed index.html`
- `GET /dots/{name}` — Serve registered DOT files (read fresh each request)
- `GET /dots/{name}/nodes` — Return JSON map of node ID → attributes (shape, class, prompt, tool_command, question, goal_gate)
- `GET /dots/{name}/edges` — Return JSON array of edges (source, target, label)
- `GET /api/cxdb/{index}/*` — Reverse-proxy to the corresponding CXDB instance
- `GET /api/dots` — Return JSON list of registered DOT filenames (ordered)
- `GET /api/cxdb/instances` — Return JSON list of CXDB URLs

CLI flags:
- `--port` (int, default 9030)
- `--cxdb` (repeatable string, default `http://127.0.0.1:9110`)
- `--dot` (repeatable string, required)

Startup checks (exit non-zero on violation):
- At least one `--dot` flag required
- No duplicate base filenames across `--dot` paths
- No duplicate graph IDs across registered DOT files (parse graph ID using regex from `specification/contracts/server-api.md`; reject anonymous graphs)

DOT parsing (`specification/contracts/server-api.md`):
- Strip `//` line comments and `/* */` block comments (per spec comment-stripping rules)
- Parse node attributes: quoted and unquoted values, `+` string concatenation, multi-line quoted strings, escape decoding (`\"` → `"`, `\n` → newline, `\\` → `\`)
- Parse edge statements: `->` chains expanded, port syntax stripped, same attribute parsing rules
- Normalize node/edge IDs: strip outer quotes, resolve escape sequences, trim whitespace

Server properties:
- Bind to `0.0.0.0:{port}`
- Print `Kilroy Pipeline UI: http://127.0.0.1:{port}` on startup
- Stateless — no caching
- Standard library only — no imports outside `go` standard library

### ui/index.html
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

- `ui/go.mod` exists with module `cxdb-graph-ui`, no require directives
- `ui/main.go` compiles with `go build ./...` from `ui/`
- `ui/main.go` passes `go vet ./...` from `ui/`
- `ui/index.html` exists co-located with `ui/main.go`
- All 7 routes implemented
- DOT parser handles comments, multi-line strings, `+` concatenation, escape sequences
- Startup rejects duplicate basenames, duplicate graph IDs, anonymous graphs
- No external Go packages imported (standard library only)
- CDN URLs pinned to exact versions from spec

## Status Contract

Write status JSON to `$KILROY_STAGE_STATUS_PATH` (absolute path). If unavailable, use `$KILROY_STAGE_STATUS_FALLBACK_PATH`.

Success: `{"status":"success"}`
Failure: `{"status":"fail","failure_reason":"<reason>","details":"<details>","failure_class":"deterministic"}`
Retry (transient): `{"status":"retry","failure_reason":"<reason>","details":"<details>","failure_class":"transient_infra"}`

Do not write nested `status.json` files after `cd`.
