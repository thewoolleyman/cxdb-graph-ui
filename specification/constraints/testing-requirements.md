# Testing Requirements

The implementation requires four distinct testing layers. All four layers must pass before the implementation is considered complete.

## 12.1 Rust Unit Tests — Server Layer

**Coverage target: 100% line and branch coverage** for all Rust code in `server/`.

**Tooling:**
```bash
cargo tarpaulin --out html --fail-under 100
```
or:
```bash
cargo llvm-cov --fail-under-lines 100
```

**Scope:** All server handlers (`handle_root`, `handle_dots`, `handle_api_dots`, `handle_api_cxdb`), DOT parsing functions (`parse_nodes`, `parse_edges`, `extract_graph_id`, `strip_comments`, `parse_attr_list`, `parse_dot_token`, `parse_attr_value`), startup validation (duplicate basenames, duplicate graph IDs, anonymous graphs, missing `--dot`), and the CXDB proxy logic.

**Must run without** a live CXDB instance or browser. Unit tests live in `#[cfg(test)] mod tests` blocks within each module, giving direct access to private functions. Integration tests live in `server/tests/`.

**Enforcement:** `make test` runs `cargo test` and must pass before any commit is landed. The Clippy gate (`cargo clippy -- -D warnings`) enforces the ROP lints from `specification/constraints/railway-oriented-programming-requirements.md`. `make precommit` runs `make fmt-check && make clippy && make test`.

## 12.2 JavaScript Unit Tests — Client Logic Layer

**Coverage target: 100% line and branch coverage** for all JavaScript in `server/assets/index.html`.

**Pre-requisite:** JavaScript logic must be extracted from inline `<script>` tags into importable ES modules before this layer can be implemented. The inline-script constraint of the "No build toolchain" principle (Section 1.2) applies to the deployed artifact, not to the development and test workflow — the source can be modular ES modules that are inlined (or concatenated) as part of a simple build step.

**Tooling:** Vitest with V8 coverage provider:
```bash
vitest run --coverage --coverage.provider=v8 --coverage.100
```

**Scope:** The behaviors listed in Invariant 20 (Section 9) must each have unit tests that inject mock CXDB API responses and assert on internal state transitions. This is the only practical way to verify these behaviors — Playwright DOM inspection cannot observe intermediate state such as which endpoint was called, how many times, or what was cached.

**Must run without** a live server, browser, or CXDB instance.

## 12.3 Browser Integration Tests — Smoke Layer

**Purpose:** Verify that the assembled application actually loads and renders in a real browser. This layer catches CDN failures, WASM initialization errors, and module-level import breakages that unit tests cannot detect.

**Tooling:** `headless_chrome`, `chromiumoxide`, or `fantoccini` (Rust crates for headless browser testing). Tests live in the Rust integration test suite (`server/tests/` directory) and require no Node.js or external test runner.

```bash
cargo test --features browser -- --test-threads=1
```

**Feature flag isolation:** Tests use `#[cfg(feature = "browser")]` so that the fast unit test suite (`cargo test`) is unaffected. Browser tests run only when explicitly invoked with `--features browser`.

**In-process server:** Tests bind to `127.0.0.1:0` with `tokio::net::TcpListener` and run the `axum` server in-process, eliminating external process management. A fixture DOT file is used as the `--dot` input.

**Minimum required assertions:**
- The page loads without JavaScript errors that block module execution
- Graphviz WASM initializes (the "Loading Graphviz..." message disappears)
- An SVG element is present in the DOM containing expected node IDs from the fixture DOT file
- Pipeline tabs render with correct graph IDs
- Clicking a node opens the detail panel

**CDN dependency validation:** Because the tests load the actual `index.html` with its CDN imports, any broken CDN URL causes the module to fail to load, which causes the SVG assertion to timeout and fail. This directly prevents the class of bug seen in v58 (broken msgpack CDN URL).

**Pipeline integration:** A dedicated pipeline gate (e.g., `verify_browser`) runs the browser test command after `verify_tests`. This keeps the fast unit test loop clean while ensuring browser rendering is verified before `review_final`.

**Enforcement:** `make test-browser` runs `cargo test --features browser -- --test-threads=1` and must pass before a pipeline run is considered successful.

## 12.4 Playwright UI Tests — Integration Layer

**Scope:** Visual rendering, DOM structure, user interactions, network error handling, and CXDB status overlay (with mock CXDB via Playwright request routing).

**What Playwright tests:** SVG rendered from DOT, tab labels match graph IDs, node colors match expected status, detail panel content, HTML escaping (no XSS), DOT file changes picked up on tab switch, CXDB unreachable states.

**What Playwright does NOT test:** Internal JS state machine steps, API JSON format details (edge chain structure, port stripping, parse error body shape), server startup behavior (exit codes, stderr messages). These are covered by Sections 12.1 and 12.2 respectively.

**Mock CXDB:** Status overlay scenarios use Playwright's request routing (`page.route`) to intercept `/api/cxdb/*` requests and return fixture JSON responses without a live CXDB instance. Fixture responses are stored in `.claude/skills/run-holdout-scenarios/fixtures/mock-cxdb/`.

**Server startup scenarios** (no `--dot` flag, duplicate basenames, duplicate graph IDs, anonymous graph) are tested via Bash subprocess in the same skill: run the binary, capture exit code and stderr, assert on expected values.

## 12.5 Testing Layer Boundaries

The following table maps scenario categories to their required testing layer:

| Scenario Category | Testing Layer |
|---|---|
| DOT Rendering — visual (SVG shapes, tab labels, HTML escaping) | Playwright (12.4) |
| DOT Rendering — API contract (edge chain JSON, port stripping, parse error bodies) | Rust tests (12.1) |
| Application loads and renders (CDN deps, WASM init, SVG output) | Browser integration (12.3) |
| CXDB Status Overlay (node colors, pulsing, stale detection) | Playwright + mock CXDB (12.4) |
| Pipeline Discovery state machine (ULID selection, gap recovery, CQL flag, etc.) | JS unit tests (12.2) |
| Detail Panel — visual (panel opens, content rendered) | Playwright (12.4) |
| Detail Panel — CXDB turn format (StageStarted/Finished/Failed output strings) | JS unit tests (12.2) |
| CXDB Connection Handling (unreachable → message, partial connectivity indicator) | Playwright + mock CXDB (12.4) |
| Server startup validation (exit code, error messages) | Bash subprocess (12.4 skill) |
| Server API format (`/api/dots`, `/api/cxdb/instances`, `/dots/{name}` 404) | Rust tests (12.1) |
