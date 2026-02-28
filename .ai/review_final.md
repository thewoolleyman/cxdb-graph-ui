# Final Review — CXDB Graph UI Implementation

**Date:** 2026-02-28  
**Reviewer:** Kilroy attractor agent (review_final node)  
**Scope:** Semantic fidelity against `.ai/spec.md` acceptance criteria

---

## Deliverables Check

| File | Exists |
|------|--------|
| `ui/main.go` | ✅ Yes |
| `ui/index.html` | ✅ Yes |
| `ui/go.mod` | ✅ Yes (module `cxdb-graph-ui`, go 1.21, no external requires) |

---

## AC-by-AC Review

### AC-1: CLI flags (`--port`, `--cxdb` repeatable, `--dot` repeatable, required)
**PASS**  
- `--port` integer flag with default 9030 ✅  
- `--cxdb` uses `multiFlag` type (repeatable) ✅  
- `--dot` uses `multiFlag` type (repeatable) ✅  
- Missing `--dot` exits with error + usage ✅  
- Missing `--cxdb` defaults to `http://127.0.0.1:9110` ✅

### AC-2: All 7 routes implemented
**PASS**  
Routes registered:
- `GET /` → `handleRoot` ✅  
- `GET /dots/{name}` → `handleDots` (suffix "") ✅  
- `GET /dots/{name}/nodes` → `handleDots` (suffix "nodes") ✅  
- `GET /dots/{name}/edges` → `handleDots` (suffix "edges") ✅  
- `GET /api/cxdb/{index}/*` → `handleAPICXDB` (proxy path) ✅  
- `GET /api/dots` → `handleAPIDots` ✅  
- `GET /api/cxdb/instances` → `handleAPICXDB` (instances path) ✅

### AC-3: DOT files read fresh on each request (no caching)
**PASS**  
`handleDots` calls `os.ReadFile(dotPath)` on every request. No in-memory cache of file contents. Startup reads only validate graph ID; runtime always reads fresh. ✅

### AC-4: `index.html` embedded via `//go:embed index.html`
**PASS**  
Line 17: `//go:embed index.html` with `var indexHTML []byte`. Both `main.go` and `index.html` reside in `ui/`. ✅

### AC-5: Startup rejects duplicate base filenames, duplicate graph IDs, anonymous graphs, missing `--dot`
**PASS**  
- Missing `--dot`: exits with error ✅  
- Duplicate base filenames: checked via `nameToPath` map, exits ✅  
- Anonymous graphs (no named graph ID): `extractGraphID` returns error if regex doesn't match ✅  
- Duplicate graph IDs: checked via `graphIDToPath` map, exits ✅

### AC-6: DOT parser handles comment stripping, multi-line strings, `+` concatenation, escape decoding
**PASS**  
- `stripComments` handles `//` line comments and `/* */` block comments, with quoted-string tracking ✅  
- Multi-line quoted values: `parseDotToken` reads until closing `"` without line restrictions ✅  
- `+` concatenation: `parseAttrValue` loops on `+` operator ✅  
- Escape decoding: `unescapeDotString` handles `\"`, `\\`, `\n`, others pass-through ✅  
- Unterminated string/block comment → error ✅

### AC-7: Node ID normalization (unquote, unescape, trim)
**PASS**  
`normalizeID` strips outer `"`, calls `unescapeDotString`, trims whitespace. Applied to all node IDs. ✅

### AC-8: Edge endpoint port stripping, chain expansion
**PASS**  
- `stripPort` strips `:port` suffix from node IDs ✅  
- `parseEdges` builds `chain` slice and emits one edge per segment with inherited label ✅

### AC-9: Standard library only — no external imports
**PASS**  
`go.mod` has no `require` directives. Imports in `main.go`: `embed`, `encoding/json`, `flag`, `fmt`, `io`, `net/http`, `net/url`, `os`, `path/filepath`, `regexp`, `strings` — all stdlib. ✅

### AC-10: Prints `Kilroy Pipeline UI: http://127.0.0.1:{port}` on startup
**PASS**  
Line 130: `fmt.Printf("Kilroy Pipeline UI: http://127.0.0.1:%d\n", port)` ✅

### AC-11: CXDB proxy strips `/api/cxdb/{index}` prefix and forwards remainder
**PASS**  
`handleAPICXDB` strips `/api/cxdb/` prefix, extracts `{index}`, then appends `subPath` to the CXDB base URL. Query string is forwarded via `proxyURL.RawQuery = r.URL.RawQuery`. ✅

### AC-12: `/api/dots` returns filenames in `--dot` flag order
**PASS**  
`dotEntries` is a slice built in flag order. `handleAPIDots` iterates `dotEntries` (not the map) to produce the ordered list. ✅

### AC-13: CDN URLs pinned to exact versions (esm.sh for wasm-graphviz, jsDelivr for msgpack)
**PASS**  
Line 300: `https://esm.sh/@hpcc-js/wasm-graphviz@1.6.1` ✅  
Line 301: `https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/mod.min.mjs` ✅  
Both are `<script type="module">` ES module imports. ✅

### AC-14: DOT rendered to SVG via `Graphviz.load()` + `gv.layout(dot, "svg", "dot")`
**PASS**  
`init()` calls `gv = await Graphviz.load()`. `renderSVG` calls `gv.layout(dotSrc, "svg", "dot")`. ✅

### AC-15: Pipeline tabs from `/api/dots`, labeled with graph ID (fallback: filename)
**PASS**  
`buildTabs` initializes tab labels to filename. `switchPipeline` fetches DOT, calls `normalizeGraphId`, then `updateTabLabel(name, gid)` to update to graph ID. Fallback (failed fetch) keeps filename. ✅

### AC-16: Tab labels use `textContent` (not innerHTML)
**PASS**  
`buildTabs`: `tab.textContent = name` ✅  
`updateTabLabel`: `tab.textContent = label` ✅

### AC-17: Status poll every 3 seconds
**PASS**  
`POLL_INTERVAL_MS = 3000`. `pollCycle` calls `await doPoll()` then `setTimeout(pollCycle, POLL_INTERVAL_MS)`. At most one cycle in flight at a time. ✅

### AC-18: Node status classes: `node-pending`, `node-running`, `node-complete`, `node-error`, `node-stale`
**PASS**  
`STATUS_CLASSES = ["node-pending","node-running","node-complete","node-error","node-stale"]`. `applyStatusToSVG` removes all, adds `"node-" + status`. CSS defines all 5 with colors and pulse animation for running. ✅

### AC-19: Pipeline discovery via RunStarted msgpack decode (base64 → bytes → `decode()`)
**PASS**  
`decodeFirstTurn`: calls `base64ToBytes(rawTurn.bytes_b64)`, then `decode(bytes)` (msgpack), extracts `graph_name` and `run_id`. `base64ToBytes` uses `atob` + `Uint8Array`. ✅

### AC-20: Detail panel shows node attributes on click; user content via textContent/escaped HTML
**PASS**  
`openDetailPanel` → `renderDetailPanel`. Panel shows node ID, type, class, status, prompt, tool_command, question, goal_gate, edges/choices, CXDB turns. All user-sourced content goes through `esc()` (HTML entity escaping) before being set via `innerHTML` inside `parts.join("")`. `detail-title` uses `textContent`. ✅

### AC-21: Graceful degradation when CXDB unreachable (graph still renders)
**PASS**  
SVG rendering happens from the DOT file independently of CXDB. CXDB failures return `null` from `fetchKilroyContexts`, which is handled in `doPoll` without throwing. `pollCycle` catches errors via try/catch. CXDB indicator shows error state but graph remains. ✅

---

## Component Reviews

### Server Routes
All 7 routes implemented correctly. Route matching uses `http.NewServeMux` with `/dots/` prefix handler that dispatches on suffix. `/api/cxdb/` dispatches on whether path is `/api/cxdb/instances` or a numeric-index proxy path. Returns correct 404 for unregistered names and out-of-range indices. Returns 502 when upstream CXDB unreachable.

### DOT Parsing
Comment stripping, multi-line string handling, `+` concatenation, and escape decoding are all implemented. The parser correctly excludes global attribute blocks (`node`, `edge`, `graph`, `subgraph`, `strict`, `digraph` keywords filtered via `isKeyword`). Port stripping for edge endpoints is present. Chain expansion emits N-1 edges for N-node chains with inherited label. Graph ID extraction uses the specified regex.

**Potential concern (not a spec failure):** `skipToStatementEnd` stops at `}` without consuming it (returns `pos` not `pos+1`), which is intentional to avoid consuming the closing brace of the graph body. This is correct behavior.

### Browser DOT Rendering
Graphviz WASM loaded via esm.sh CDN. DOT fetched from `/dots/{name}`. SVG injected into `#graph-area`. Click handlers attached to `g.node` elements using `<title>` text as node ID. Status applied by toggling CSS classes.

### CXDB Integration / Status Overlay
Discovery via `fetchFirstTurn` + msgpack decode. `knownMappings` cache with immutable entries once classified (null for non-Kilroy). `determineActiveRuns` uses ULID lexicographic comparison for newest run. Status derived from `StageStarted`/`StageFinished`/`StageFailed`/`RunFailed` turns. `StageFailed` with `will_retry=true` → running (not error). `StageFinished` with `status="fail"` → error. Stale detection marks running nodes as stale when pipeline has no live sessions. Merge precedence: error > running > complete > pending.

### Detail Panel
Opens on node click, closes on close button. Shows DOT attributes and CXDB turns. Turn output truncated to 500 chars/8 lines (short view) with "Show more" toggle expanding to 8000 chars (secondary cap). Prompt turns subject to same 8000-char secondary cap with truncation note. Turn rows sorted newest-first. Up to 20 turns per context section. Shows "No recent CXDB activity" when no turns found.

---

## Summary

| AC | Result |
|----|--------|
| AC-1  | ✅ PASS |
| AC-2  | ✅ PASS |
| AC-3  | ✅ PASS |
| AC-4  | ✅ PASS |
| AC-5  | ✅ PASS |
| AC-6  | ✅ PASS |
| AC-7  | ✅ PASS |
| AC-8  | ✅ PASS |
| AC-9  | ✅ PASS |
| AC-10 | ✅ PASS |
| AC-11 | ✅ PASS |
| AC-12 | ✅ PASS |
| AC-13 | ✅ PASS |
| AC-14 | ✅ PASS |
| AC-15 | ✅ PASS |
| AC-16 | ✅ PASS |
| AC-17 | ✅ PASS |
| AC-18 | ✅ PASS |
| AC-19 | ✅ PASS |
| AC-20 | ✅ PASS |
| AC-21 | ✅ PASS |

**All 21 acceptance criteria pass.** No gaps identified.

---

## Verdict

**PASS** — Implementation is complete and semantically faithful to the specification. All deliverables exist, all routes are implemented, the DOT parser handles the required syntax features, the browser SPA implements the full CXDB discovery/polling/status/detail pipeline, and all security (HTML escaping, no path traversal) and resilience (graceful CXDB degradation) requirements are met.
