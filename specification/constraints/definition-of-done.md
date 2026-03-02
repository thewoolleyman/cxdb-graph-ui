# Definition of Done

## Core Functionality

- [ ] `cargo run -- --dot <path>` (from `server/`) or `make run` starts the server and prints the URL
- [ ] Multiple `--dot` flags register multiple pipelines
- [ ] `GET /` serves the dashboard (Vite-built assets embedded via `include_dir`)
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

## CXDB Integration

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

## Detail Panel

- [ ] Clicking a node opens the detail panel
- [ ] Panel shows DOT attributes: node ID, type, prompt, tool_command, question
- [ ] Panel shows recent CXDB turns: type, tool name, output, error flag
- [ ] Panel closes on click-outside or close button

## Resilience

- [ ] Graph renders when CXDB is unreachable
- [ ] CXDB status resumes automatically when CXDB becomes reachable
- [ ] DOT file changes are picked up on tab switch (no server restart needed)
- [ ] DOT syntax errors display an error message instead of crashing

## Frontend

- [ ] `pnpm build` (from `frontend/`) produces valid output in `server/assets/` without errors
- [ ] `pnpm lint` passes with zero warnings
- [ ] TypeScript compilation (`tsc --noEmit`) passes with zero errors
- [ ] Vitest unit tests pass (`pnpm test:unit`) with coverage thresholds met
- [ ] Playwright E2E tests pass (`pnpm test:e2e`)
- [ ] All interactive elements have `data-testid` attributes
- [ ] React components follow hooks-based architecture (no class components)
- [ ] Named exports throughout, barrel `index.ts` files for each directory
- [ ] `@/` path alias used for all internal imports

## Testing

- [ ] Playwright E2E tests pass (`make ui-test-e2e`)
- [ ] Application loads, Graphviz WASM initializes, and SVG renders with expected node IDs
- [ ] Pipeline tabs render and node click opens detail panel

## Code Quality (ROP Enforcement)

- [ ] All fallible functions return `Result<T, E>` — no panics in non-test code
- [ ] `AppError` enum covers all error categories with `thiserror` derives
- [ ] `AppResult<T>` type alias is used consistently across modules
- [ ] Clippy ROP lints (`unwrap_used`, `expect_used`, `panic`, `unwrap_in_result`) are set to `deny` in `Cargo.toml`
- [ ] `cargo clippy -- -D warnings` passes with zero warnings
- [ ] `cargo fmt --check` passes (standard Rust formatting)
- [ ] `make precommit` passes (runs fmt-check, clippy, test)

## Rust Idioms

- [ ] Code follows standard Rust naming conventions (snake_case functions/variables, CamelCase types, SCREAMING_SNAKE_CASE constants)
- [ ] Public API types derive standard traits (`Debug`, `Clone`, `Serialize`/`Deserialize` where appropriate)
- [ ] Async code uses `tokio` runtime with `axum` handlers returning `impl IntoResponse`
- [ ] No `unsafe` code without explicit justification

## Security

- [ ] `/dots/` only serves files registered via `--dot` (no path traversal)
- [ ] All user-sourced content in the detail panel is HTML-escaped
- [ ] Pipeline tab labels and CXDB indicator text are HTML-escaped (text-only rendering)
