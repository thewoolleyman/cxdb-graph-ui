# Final Review

## Task

Perform a final semantic review of the CXDB Graph UI implementation to ensure it meets all acceptance criteria from `.ai/spec.md`.

## Context

All deterministic gates (fmt, vet, build, tests, browser) have passed. This is the final semantic fidelity check before marking the pipeline complete.

## Files to Read

- `.ai/spec.md` — Complete specification and acceptance criteria
- `ui/main.go` — Go server implementation
- `ui/index.html` — Browser SPA implementation
- `ui/go.mod` — Module file
- `.ai/verify_browser.md` — Browser verification results (from previous stage)

## Files to Write

- `.ai/review_final.md` — Review findings

## What to Do

1. Verify all deliverables exist:
   - `ui/main.go`, `ui/index.html`, `ui/go.mod`

2. Check server implementation (spec Section 3):
   - **AC-1**: `--port`, `--cxdb` (repeatable), `--dot` (repeatable, required) CLI flags
   - **AC-2**: All 7 routes implemented: `GET /`, `/dots/{name}`, `/dots/{name}/nodes`, `/dots/{name}/edges`, `/api/cxdb/{index}/*`, `/api/dots`, `/api/cxdb/instances`
   - **AC-3**: DOT files read fresh on each request (no caching)
   - **AC-4**: `index.html` embedded via `//go:embed index.html`
   - **AC-5**: Startup rejects: duplicate base filenames, duplicate graph IDs, anonymous graphs, missing `--dot`
   - **AC-6**: DOT parser handles comment stripping, multi-line strings, `+` concatenation, escape decoding
   - **AC-7**: Node ID normalization (unquote, unescape, trim)
   - **AC-8**: Edge endpoint port stripping, chain expansion
   - **AC-9**: Standard library only — no external imports
   - **AC-10**: Prints `Kilroy Pipeline UI: http://127.0.0.1:{port}` on startup
   - **AC-11**: CXDB proxy strips `/api/cxdb/{index}` prefix and forwards remainder
   - **AC-12**: `/api/dots` returns filenames in `--dot` flag order

3. Check browser verification passed (previous stage):
   - **AC-22**: `.ai/verify_browser.md` exists and reports all checks passed
   - **AC-23**: Graphviz WASM loaded successfully (no stuck "Loading Graphviz...")
   - **AC-24**: SVG rendered with expected nodes, tabs showed correct graph IDs, node click opened detail panel
   - **AC-25**: No blocking JavaScript errors (CDN 404s, uncaught exceptions)

4. Check browser SPA (spec Sections 4–8):
   - **AC-13**: CDN URLs pinned to exact versions (esm.sh for wasm-graphviz, jsDelivr for msgpack)
   - **AC-14**: DOT rendered to SVG via `Graphviz.load()` + `gv.layout(dot, "svg", "dot")`
   - **AC-15**: Pipeline tabs from `/api/dots`, labeled with graph ID (fallback: filename)
   - **AC-16**: Tab labels use `textContent` (not innerHTML)
   - **AC-17**: Status poll every 3 seconds
   - **AC-18**: Node status classes: `node-pending`, `node-running`, `node-complete`, `node-error`, `node-stale`
   - **AC-19**: Pipeline discovery via RunStarted msgpack decode (base64 → bytes → `decode()`)
   - **AC-20**: Detail panel shows node attributes on click; user content via textContent/escaped HTML
   - **AC-21**: Graceful degradation when CXDB unreachable (graph still renders)

5. Write `.ai/review_final.md` with:
   - Section for each major component (server routes, DOT parsing, browser integration tests, browser rendering, status overlay, detail panel)
   - Pass/fail for each AC above
   - List any gaps with specific AC identifiers

6. If ANY acceptance criteria fail, set `failure_signature` to comma-separated sorted list of failed AC IDs (e.g. "AC-3,AC-7")

## Acceptance Checks

- All deliverables exist
- All acceptance criteria pass
- No critical gaps in functionality

## Status Contract

Write status JSON to `$KILROY_STAGE_STATUS_PATH` (absolute path). If unavailable, use `$KILROY_STAGE_STATUS_FALLBACK_PATH`.

Success: `{"status":"success"}`
Failure: `{"status":"fail","failure_reason":"semantic_fidelity_gap","failure_signature":"<comma-separated-failed-AC-IDs>","details":"<specific gaps>","failure_class":"deterministic"}`

**CRITICAL:** If multiple acceptance criteria fail, set `failure_signature` to a sorted comma-separated list (e.g. "AC-3,AC-7,AC-13").

Do not write nested `status.json` files after `cd`.
