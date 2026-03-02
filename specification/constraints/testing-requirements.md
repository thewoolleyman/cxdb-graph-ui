# Testing Requirements

The implementation requires three distinct testing layers. All three layers must pass before the implementation is considered complete.

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

**Enforcement:** `make test` runs `cargo test` and must pass before any commit is landed. The Clippy gate (`cargo clippy -- -D warnings`) enforces the ROP lints from `specification/constraints/railway-oriented-programming-requirements.md`. `make precommit` runs `make fmt-check && make clippy && make test && make ui-lint && make ui-test-unit`.

## 12.2 TypeScript Unit Tests — Client Logic Layer

**Coverage target: 100% line and branch coverage** for all TypeScript in `frontend/src/lib/`.

**Tooling:** Vitest with V8 coverage provider:
```bash
cd frontend && pnpm test:unit
```
which runs:
```bash
vitest run --coverage --coverage.provider=v8 --coverage.100
```

**Scope:** All pure logic in `frontend/src/lib/` — the 9 discovery behaviors from Invariant 20, plus status derivation, merging, error heuristic, stale detection, gap recovery, and turn formatting. The TypeScript module structure in `frontend/src/lib/` is directly importable by Vitest — no extraction step is needed.

The behaviors listed in Invariant 20 (Section 9) must each have unit tests that inject mock CXDB API responses and assert on internal state transitions. This is the only practical way to verify these behaviors — Playwright DOM inspection cannot observe intermediate state such as which endpoint was called, how many times, or what was cached.

**Must run without** a live server, browser, or CXDB instance.

**Enforcement:** `make ui-test-unit` runs `cd frontend && pnpm test:unit`. Added to `make precommit`.

## 12.3 Playwright E2E Tests — Integration Layer

**Purpose:** Verify the fully assembled application in a real browser: WASM initialization, SVG rendering, React component behavior, user interactions, network error handling, and CXDB status overlay (with mock CXDB via Playwright request routing). This replaces both the previous Rust browser smoke tests (no longer needed with bundled npm packages — CDN URL breakage is impossible) and the previous Playwright UI tests into a single comprehensive E2E layer.

**Tooling:**
```bash
cd frontend && pnpm test:e2e
```
which runs Playwright tests in `frontend/tests/*.spec.ts`.

**Scope:** Visual rendering, DOM structure, user interactions, network error handling, and CXDB status overlay.

**What Playwright tests:** Application loads and WASM initializes, SVG rendered from DOT, tab labels match graph IDs, node colors match expected status, detail panel content, HTML escaping (no XSS), DOT file changes picked up on tab switch, CXDB unreachable states, `data-testid` attribute coverage.

**What Playwright does NOT test:** Internal TypeScript state machine steps, API JSON format details (edge chain structure, port stripping, parse error body shape), server startup behavior (exit codes, stderr messages). These are covered by Sections 12.1 and 12.2 respectively.

**Test infrastructure (cxdb conventions):**
- Tests in `frontend/tests/*.spec.ts`
- Custom fixtures extending `test` with server spawning (build Rust binary in `global-setup.ts`, spawn per-test)
- `page.route()` for CXDB mock responses (fixture responses in test utils)
- `data-testid` attributes as test selectors (see Section 12.6)
- Workers: 1 (sequential — each test spawns its own server instance)

**Mock CXDB:** Status overlay scenarios use Playwright's request routing (`page.route`) to intercept `/api/cxdb/*` requests and return fixture JSON responses without a live CXDB instance.

**Server startup scenarios** (no `--dot` flag, duplicate basenames, duplicate graph IDs, anonymous graph) are tested via Bash subprocess in the same Playwright test suite or via a separate test file: run the binary, capture exit code and stderr, assert on expected values.

**Enforcement:** `make ui-test-e2e` runs `cd frontend && pnpm test:e2e`.

## 12.4 Testing Layer Boundaries

The following table maps scenario categories to their required testing layer:

| Scenario Category | Testing Layer |
|---|---|
| DOT Rendering — visual (SVG shapes, tab labels, HTML escaping) | Playwright E2E (12.3) |
| DOT Rendering — API contract (edge chain JSON, port stripping, parse error bodies) | Rust tests (12.1) |
| Application loads and renders (WASM init, SVG output, React mount) | Playwright E2E (12.3) |
| CXDB Status Overlay (node colors, pulsing, stale detection) | Playwright E2E + mock CXDB (12.3) |
| Pipeline Discovery state machine (ULID selection, gap recovery, CQL flag, etc.) | TypeScript unit tests (12.2) |
| Detail Panel — visual (panel opens, content rendered) | Playwright E2E (12.3) |
| Detail Panel — CXDB turn format (StageStarted/Finished/Failed output strings) | TypeScript unit tests (12.2) |
| CXDB Connection Handling (unreachable → message, partial connectivity indicator) | Playwright E2E + mock CXDB (12.3) |
| Server startup validation (exit code, error messages) | Bash subprocess (12.3) |
| Server API format (`/api/dots`, `/api/cxdb/instances`, `/dots/{name}` 404) | Rust tests (12.1) |

## 12.5 ESLint Configuration

The frontend uses ESLint for TypeScript and React code quality enforcement, matching cxdb's conventions:

```json
{
  "extends": [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended",
    "plugin:react-hooks/recommended"
  ],
  "parser": "@typescript-eslint/parser"
}
```

**Enforcement:** `pnpm lint` is added to `make precommit` (via `make ui-lint`) and to the CI `frontend.yml` workflow.

## 12.6 `data-testid` Convention

All interactive and assertable DOM elements must have `data-testid` attributes for Playwright test selectors. Required selectors:

| Element | `data-testid` Value |
|---------|-------------------|
| Tab container | `tab-bar` |
| Individual pipeline tab | `tab-{graphId}` |
| SVG graph container | `graph-area` |
| Detail panel sidebar | `detail-panel` |
| CXDB status indicator | `connection-indicator` |
| Individual turn in detail panel | `turn-row-{turnId}` |
| Loading message | `loading-message` |
| Error display area | `error-message` |

This follows the `data-testid` convention (widely adopted by React Testing Library and Playwright) and ensures Playwright tests do not rely on brittle CSS class selectors or text content matching.
