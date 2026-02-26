# Final Review — CXDB Graph UI

Date: 2026-02-26
Reviewer: Kilroy AI (automated semantic review)

---

## Summary

All deliverables exist. All 21 acceptance criteria pass. No gaps detected.

---

## Deliverables Checklist

| File | Exists |
|---|---|
| `ui/main.go` | ✅ |
| `ui/index.html` | ✅ |
| `ui/go.mod` | ✅ |

`ui/go.mod` declares module `cxdb-graph-ui` with `go 1.21` — no `require` directives.

---

## Section 1 — Server Routes

### AC-1: CLI flags (`--port`, `--cxdb`, `--dot`)
**PASS.** `main.go` defines all three flags:
- `--port` (int, default 9030)
- `--cxdb` via `multiFlag` (repeatable, defaults to `http://127.0.0.1:9110` if not given)
- `--dot` via `multiFlag` (repeatable, required — exits with error if absent)

### AC-2: All 7 routes implemented
**PASS.** Routes registered in `main()`:
1. `GET /` — `handleRoot` → serves `index.html`
2. `GET /dots/{name}` — `handleDots` with empty suffix → raw DOT file
3. `GET /dots/{name}/nodes` — `handleDots` with suffix `nodes` → JSON node attrs
4. `GET /dots/{name}/edges` — `handleDots` with suffix `edges` → JSON edge list
5. `GET /api/cxdb/{index}/*` — `handleAPICXDB` → reverse proxy
6. `GET /api/dots` — `handleAPIDots` → JSON dots list
7. `GET /api/cxdb/instances` — `handleAPICXDB` with path == `/api/cxdb/instances` → JSON instances

### AC-3: DOT files read fresh on each request (no caching)
**PASS.** `handleDots` calls `os.ReadFile(dotPath)` on every request. No in-memory caching of file content. The `dotsByName` map stores paths only, not file contents.

### AC-4: `index.html` embedded via `//go:embed index.html`
**PASS.** Line 17–18 of `main.go`:
```go
//go:embed index.html
var indexHTML []byte
```
Served from `handleRoot`. Both `main.go` and `index.html` live in `ui/`.

### AC-5: Startup validation (duplicate filenames, duplicate graph IDs, anonymous graphs, missing `--dot`)
**PASS.**
- Missing `--dot`: exits with error + usage (lines 72–76)
- Duplicate base filenames: detected via `nameToPath` map, exits with descriptive error (lines 94–97)
- Anonymous graphs (no named graph ID): `extractGraphID` returns error if regex doesn't match (line 293), exits at startup
- Duplicate graph IDs: detected via `graphIDToPath` map, exits with descriptive error (lines 116–120)

### AC-6: DOT parser handles comment stripping, multi-line strings, `+` concatenation, escape decoding
**PASS.**
- Comment stripping: `stripComments()` handles `//` line comments (skips to EOL, preserves newline) and `/* */` block comments, correctly tracking quoted string state and returning errors for unterminated block comments or strings.
- Multi-line quoted values: `parseDotToken` reads quoted strings character-by-character handling `\"` and `\\` escapes, spanning newlines naturally.
- `+` concatenation: `parseAttrValue` loops with `+` detection, appending fragments.
- Escape decoding: `unescapeDotString` handles `\"` → `"`, `\\` → `\`, `\n` → newline, others passed verbatim.

### AC-7: Node ID normalization (unquote, unescape, trim)
**PASS.** `normalizeID()`: trims whitespace, strips outer quotes if present, calls `unescapeDotString()` on the inner content. Applied consistently to node IDs in `parseNodes` and `parseEdges`.

### AC-8: Edge endpoint port stripping, chain expansion
**PASS.**
- Port stripping: `stripPort()` trims everything after `:` from a node ID.
- Chain expansion: `parseEdges` accumulates chain nodes in a slice and emits one `edge` per consecutive pair, each inheriting the same attribute block.

### AC-9: Standard library only — no external imports
**PASS.** `go.mod` has no `require` directives. `main.go` imports: `embed`, `encoding/json`, `flag`, `fmt`, `io`, `net/http`, `net/url`, `os`, `path/filepath`, `regexp`, `strings` — all standard library.

### AC-10: Startup message format
**PASS.** Line 130: `fmt.Printf("Kilroy Pipeline UI: http://127.0.0.1:%d\n", port)` matches spec exactly.

### AC-11: CXDB proxy strips `/api/cxdb/{index}` prefix
**PASS.** `handleAPICXDB` strips `/api/cxdb/` prefix, extracts numeric index, uses `subPath` (remainder after index) as the forwarded path. Query string is forwarded via `proxyURL.RawQuery = r.URL.RawQuery`.

### AC-12: `/api/dots` returns filenames in `--dot` flag order
**PASS.** `dotEntries` is a slice (ordered by flag insertion order), `handleAPIDots` iterates it sequentially to build the names array. Deterministic ordering preserved.

---

## Section 2 — Browser SPA

### AC-13: CDN URLs pinned to exact versions
**PASS.** `index.html` lines 300–301:
```javascript
import { Graphviz } from "https://esm.sh/@hpcc-js/wasm-graphviz@1.6.1";
import { decode } from "https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/mod.min.mjs";
```
Both are pinned to exact versions as required by the spec (Section 4.1 and 4.1.1).

### AC-14: DOT rendered via `Graphviz.load()` + `gv.layout(dot, "svg", "dot")`
**PASS.** `init()` calls `gv = await Graphviz.load()`. `renderSVG()` calls `svg = gv.layout(dotSrc, "svg", "dot")`. The resulting SVG is injected into `#graph-area`.

### AC-15: Pipeline tabs from `/api/dots`, labeled with graph ID (fallback: filename)
**PASS.** `init()` fetches `/api/dots`, builds tabs via `buildTabs()` initially using the filename. After rendering DOT, `normalizeGraphId(dotSrc)` extracts the graph ID and `updateTabLabel(name, gid)` updates the tab text with the graph ID. Filename is the fallback if DOT fetch fails.

### AC-16: Tab labels use `textContent` (not innerHTML)
**PASS.** `buildTabs()` uses `tab.textContent = name`. `updateTabLabel()` uses `tab.textContent = label`. No `innerHTML` assignment for tab labels.

### AC-17: Status poll every 3 seconds
**PASS.** `POLL_INTERVAL_MS = 3000`. After each `doPoll()` completes (or errors), `setTimeout(pollCycle, POLL_INTERVAL_MS)` schedules the next cycle. At most one poll cycle in flight at a time.

### AC-18: Node status classes: `node-pending`, `node-running`, `node-complete`, `node-error`, `node-stale`
**PASS.** `STATUS_CLASSES = ["node-pending","node-running","node-complete","node-error","node-stale"]`. `applyStatusToSVG()` removes all status classes then adds `"node-" + status`. CSS rules for all five classes defined in `<style>`. `@keyframes pulse` applied to `node-running`. Colors match spec (gray/pending, blue-pulse/running, green/complete, red/error, orange/stale).

### AC-19: Pipeline discovery via RunStarted msgpack decode (base64 → bytes → `decode()`)
**PASS.** `decodeFirstTurn()` calls `base64ToBytes(rawTurn.bytes_b64)` then `decode(bytes)` (using `@msgpack/msgpack`). Extracts `graph_name` from `payload["8"] ?? payload[8]` and `run_id` from `payload["1"] ?? payload[1]`. `fetchFirstTurn()` fetches via `?view=raw` to get raw bytes. `knownMappings` caches the result.

### AC-20: Detail panel shows node attributes on click; user content via textContent/escaped HTML
**PASS.**
- `openDetailPanel(nodeId)` called on node click, populates `#detail-panel`.
- All user-sourced content (node IDs, attr values, turn output, etc.) is passed through `esc()` before HTML insertion. `detail-title` uses `titleEl.textContent = nodeId`. `esc()` replaces `&`, `<`, `>`, `"` with HTML entities.
- DOT attributes (prompt, tool_command, question, goal_gate) displayed in `.detail-value` containers with `white-space: pre-wrap`.
- CXDB turns displayed in a table with truncation/expand functionality (500 chars / 8 lines short, 8000 chars expanded, with truncation note).
- Close via close button or click-outside (SVG background click).

### AC-21: Graceful degradation when CXDB unreachable
**PASS.**
- `pollCycle()` wraps `doPoll()` in try/catch, always schedules next poll.
- Per-instance reachability tracked in `instanceReachable`. Failed instance does not block others.
- `cachedContextLists` retains last successful fetch per instance.
- SVG graph renders entirely from DOT file (no CXDB dependency). Nodes default to `pending` (gray) without CXDB data.
- CXDB indicator reflects unreachable state via "CXDB unreachable" + red dot with URLs in tooltip (all via `textContent` — HTML-safe).

---

## Section 3 — Additional Spec Requirements Verified

- **Shape-to-type mapping (AC-18 adjacent):** `SHAPE_TO_TYPE` in JS covers all 11 shapes from spec Section 7.3 plus default fallback (`"LLM Task"` via `SHAPE_TO_TYPE[shape] ?? "LLM Task"`).
- **Stale detection:** `applyStaleDetection()` marks `running` nodes without lifecycle resolution as `stale` when `pipelineIsLive` is false. Warning banner rendered.
- **Multiple runs:** `determineActiveRuns()` groups by `runId`, selects max ULID (lexicographically newest), calls `resetPipelineState` on run change.
- **Parallel branch merging:** `mergeStatusMaps()` uses `MERGE_PRECEDENCE` (error > running > complete > pending) across per-context maps.
- **Turn numeric ordering:** All `turn_id` comparisons use `numId()` (`parseInt(id, 10)`).
- **StageFailed with will_retry:** Sets status to `"running"`, does NOT set `hasLifecycleResolution`.
- **`/api/cxdb/instances` HTML escaping:** `updateCXDBIndicator` sets `tooltip.textContent` (not innerHTML) for URLs.
- **Server binds to `0.0.0.0`:** Confirmed line 129.
- **404 for unregistered DOT files:** `handleDots` returns `http.NotFound` if name not in `dotsByName`.
- **502 for unreachable CXDB:** `handleAPICXDB` returns `http.StatusBadGateway` on proxy error.

---

## Acceptance Criteria Results

| AC | Description | Result |
|---|---|---|
| AC-1 | CLI flags | ✅ PASS |
| AC-2 | All 7 routes | ✅ PASS |
| AC-3 | DOT read fresh on each request | ✅ PASS |
| AC-4 | index.html embedded via go:embed | ✅ PASS |
| AC-5 | Startup validation | ✅ PASS |
| AC-6 | DOT parser (comments, multiline, concat, escapes) | ✅ PASS |
| AC-7 | Node ID normalization | ✅ PASS |
| AC-8 | Edge port stripping + chain expansion | ✅ PASS |
| AC-9 | Standard library only | ✅ PASS |
| AC-10 | Startup message | ✅ PASS |
| AC-11 | CXDB proxy prefix stripping | ✅ PASS |
| AC-12 | `/api/dots` flag order preserved | ✅ PASS |
| AC-13 | CDN URLs pinned | ✅ PASS |
| AC-14 | Graphviz.load() + gv.layout() | ✅ PASS |
| AC-15 | Tabs from /api/dots, labeled with graph ID | ✅ PASS |
| AC-16 | Tab labels via textContent | ✅ PASS |
| AC-17 | 3-second poll interval | ✅ PASS |
| AC-18 | Node status CSS classes | ✅ PASS |
| AC-19 | RunStarted msgpack decode | ✅ PASS |
| AC-20 | Detail panel with HTML-escaped user content | ✅ PASS |
| AC-21 | Graceful degradation when CXDB unreachable | ✅ PASS |

---

## Conclusion

**All 21 acceptance criteria pass.** The implementation is semantically complete and faithful to the specification. No gaps or regressions detected.
