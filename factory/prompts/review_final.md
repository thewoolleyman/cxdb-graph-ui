# Final Review

## Task

Perform a final semantic review of the CXDB Graph UI implementation to ensure it meets all acceptance criteria from the specification.

## Context

All deterministic gates (fmt, clippy, build, tests, frontend build, lint, unit tests, E2E tests) have passed. This is the final semantic fidelity check before marking the pipeline complete.

## Files to Read

**Read the full specification:**
- All files under `specification/intent/` — Overview, architecture, server, DOT rendering, CXDB integration, status overlay, detail panel, UI layout
- All files under `specification/constraints/` — Invariants, non-goals, definition of done, testing requirements, ROP requirements
- All files under `specification/contracts/` — Server API (downstream) and CXDB API (upstream)

**Read the Rust implementation:**
- `server/Cargo.toml` — Crate manifest (dependencies, lint config)
- `server/src/main.rs` — Binary entry point
- `server/src/lib.rs` — Module declarations
- `server/src/error.rs` — Error types
- `server/src/config.rs` — CLI config
- `server/src/server.rs` — Route handlers
- `server/src/dot_parser.rs` — DOT parsing
- `server/src/cxdb_proxy.rs` — CXDB proxy
- `Cargo.toml` — Workspace root
- `Makefile` — Build targets

**Read the frontend implementation:**
- `frontend/package.json` — Dependencies and scripts
- `frontend/tsconfig.json` — TypeScript config (verify strict: true)
- `frontend/vite.config.ts` — Build config (verify output to server/assets/)
- `frontend/src/` — React components, hooks, lib, types
- `frontend/tests/` — Playwright E2E and Vitest unit tests

## Files to Write

- `.ai/review_final.md` — Review findings

## What to Do

1. Verify all deliverables exist:
   - `Cargo.toml` (workspace root), `server/Cargo.toml`, `Makefile`
   - `server/src/main.rs`, `server/src/lib.rs`, `server/src/error.rs`, `server/src/config.rs`, `server/src/server.rs`, `server/src/dot_parser.rs`, `server/src/cxdb_proxy.rs`
   - `frontend/package.json`, `frontend/tsconfig.json`, `frontend/vite.config.ts`
   - `frontend/src/` component tree

2. Check ROP enforcement (spec `specification/constraints/railway-oriented-programming-requirements.md`):
   - **AC-R1**: `[lints.clippy]` in `server/Cargo.toml` denies `unwrap_used`, `expect_used`, `panic`, `unwrap_in_result`
   - **AC-R2**: `AppError` enum exists with thiserror derives and covers all error categories
   - **AC-R3**: `AppResult<T>` type alias used consistently
   - **AC-R4**: No `unwrap()`, `expect()`, or `panic!()` in non-test code
   - **AC-R5**: HTTP handlers return structured error responses (not panics)

3. Check server implementation (spec Section 3):
   - **AC-1**: `--port`, `--cxdb` (repeatable), `--dot` (repeatable, required) CLI flags via clap
   - **AC-2**: All routes implemented: `GET /`, `/assets/*`, `/dots/{name}`, `/dots/{name}/nodes`, `/dots/{name}/edges`, `/api/cxdb/{index}/*`, `/api/dots`, `/api/cxdb/instances`
   - **AC-3**: DOT files read fresh on each request (no caching)
   - **AC-4**: Frontend build output embedded via `include_dir` from `server/assets/`
   - **AC-5**: Startup rejects: duplicate base filenames, duplicate graph IDs, anonymous graphs, missing `--dot`
   - **AC-6**: DOT parser handles comment stripping, multi-line strings, `+` concatenation, escape decoding
   - **AC-7**: Node ID normalization (unquote, unescape, trim)
   - **AC-8**: Edge endpoint port stripping, chain expansion
   - **AC-9**: lib.rs + main.rs separation (main.rs is thin entry point)
   - **AC-10**: Prints `Kilroy Pipeline UI: http://127.0.0.1:{port}` on startup
   - **AC-11**: CXDB proxy strips `/api/cxdb/{index}` prefix and forwards remainder
   - **AC-12**: `/api/dots` returns filenames in `--dot` flag order

4. Check frontend implementation:
   - **AC-13**: TypeScript strict mode enabled (`strict: true` in tsconfig.json)
   - **AC-14**: DOT rendered to SVG via Graphviz WASM (npm package, bundled by Vite)
   - **AC-15**: Pipeline tabs from `/api/dots`, labeled with graph ID (fallback: filename)
   - **AC-16**: Tab labels use `textContent` (not innerHTML)
   - **AC-17**: Status poll every 3 seconds
   - **AC-18**: Node status classes: `node-pending`, `node-running`, `node-complete`, `node-error`, `node-stale`
   - **AC-19**: Pipeline discovery via RunStarted msgpack decode (base64 → bytes → `decode()`)
   - **AC-20**: Detail panel shows node attributes on click; user content via textContent/escaped HTML
   - **AC-21**: Graceful degradation when CXDB unreachable (graph still renders)

5. Perform visual browser verification (smoke test):
   - Start the server with fixture DOT files from `holdout-scenarios/fixtures/`
   - Navigate to `http://127.0.0.1:9030` using Playwright MCP browser tools
   - **AC-22**: Page loads without stuck "Loading" state
   - **AC-23**: SVG pipeline graph visible with labeled nodes and edges
   - **AC-24**: Multiple tabs visible matching DOT file graph IDs
   - **AC-25**: Node click opens detail panel
   - **AC-26**: No blocking JavaScript errors (check `browser_console_messages` level "error"; ignore favicon 404)
   - Kill the server process after verification

6. Check frontend tooling:
   - **AC-27**: `frontend/package.json` has correct scripts (build, lint, test:unit, test:e2e)
   - **AC-28**: ESLint configured with TypeScript and React rules
   - **AC-29**: Vite builds to `../server/assets/`
   - **AC-30**: React components follow conventions: named exports, `data-testid` attributes, `@/` path alias

7. Write `.ai/review_final.md` with:
   - Section for each major component (ROP compliance, server routes, DOT parsing, frontend components, status overlay, detail panel, browser verification)
   - Pass/fail for each AC above
   - List any gaps with specific AC identifiers

8. If ANY acceptance criteria fail, set `failure_signature` to comma-separated sorted list of failed AC IDs (e.g. "AC-3,AC-7")

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
