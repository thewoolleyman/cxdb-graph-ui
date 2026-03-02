# CXDB Graph UI Spec — Critique v61 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-03-02

## Prior Context

The v60 critique drove a comprehensive Go-to-Rust rewrite of the specification. All 16 issues were addressed: the spec now describes a Rust server (axum/tokio/clap/thiserror) with railway-oriented programming constraints, `cxdb` repo layout conventions (workspace Cargo.toml, `server/` subdirectory, lib.rs + main.rs separation), Makefile targets, and CI workflow. The Go `ui/` directory was deleted and replaced with `server/assets/index.html`.

This critique focuses on the **frontend architecture** — the browser-side SPA that currently lives as a single inline HTML file (`server/assets/index.html`). The `cxdb` repository (the canonical Rust+JS project in this ecosystem) uses a modern frontend toolchain: Next.js 14, TypeScript (strict), React 18, Tailwind CSS v3, pnpm, Playwright, and ESLint. The cxdb-graph-ui spec must be aligned with these established conventions for consistency, maintainability, and testability.

---

## Issue #1: "No build toolchain" design principle contradicts cxdb conventions — replace with modern frontend stack

### The problem

Section 1.2 states: "**No build toolchain.** The frontend is a single HTML file with inline CSS and JavaScript. External dependencies are loaded from CDN. There is no npm, no bundler, no TypeScript, no framework."

Non-goal #8 reiterates: "**No JS build toolchain.** No npm, webpack, bundler, TypeScript, or framework. A single HTML file with CDN imports."

This directly contradicts the cxdb repo's established frontend architecture, which uses Next.js 14 (App Router, static export), TypeScript with `strict: true`, pnpm v9, Tailwind CSS v3, ESLint, and React 18 with hooks-based components. The v60 critique aligned the server-side with cxdb conventions; the frontend must follow suit.

The single-file approach has caused measurable problems in previous pipeline runs: broken CDN URLs (v58), inability to unit test client logic without a complex extraction step (Section 12.2's "pre-requisite" for ES module extraction), and no type safety for the complex CXDB integration logic.

### Suggestion

Replace the "No build toolchain" principle in Section 1.2 with: "**cxdb-aligned frontend toolchain.** The frontend uses the same build tools as the cxdb repository: Vite + React 18, TypeScript (strict mode), Tailwind CSS v3, and pnpm v9. The build produces static assets served by the Rust server."

Remove non-goal #8 entirely, or replace it with: "**No server-side rendering.** The frontend is a statically-built SPA. No SSR, no ISR, no server components."

**Framework choice — Vite + React instead of Next.js.** The cxdb repo uses Next.js App Router with `output: 'export'` for static site generation. Since cxdb-graph-ui is a single-page dashboard with no routing, no SSR, no API routes, and no dynamic pages, Next.js adds unnecessary complexity. Vite + React is the lighter option that still aligns with cxdb's conventions on TypeScript, Tailwind, pnpm, ESLint, React, and Playwright. The build output (`dist/`) is a set of static files the Rust server can serve.

Update the architecture diagram in Section 2 to show `frontend/` as the source, `frontend/dist/` as the build output, and the Rust server serving the built assets.

---

## Issue #2: All JavaScript must be TypeScript with strict mode

### The problem

The spec uses plain JavaScript throughout — all code examples in Sections 4, 5, 6, and 7 are untyped. The cxdb repo uses TypeScript with `strict: true`, `isolatedModules: true`, and `bundler` module resolution. The complex CXDB integration logic (pipeline discovery, status derivation, gap recovery, error heuristics) would benefit enormously from static typing — the discovery state machine has ~15 distinct data types (`knownMappings`, `NodeStatus`, context lists, turn responses, CQL responses) that are currently specified only as prose.

### Suggestion

Add a new constraint to the spec requiring TypeScript with `strict: true`. Specify a `tsconfig.json` matching cxdb's conventions:

```json
{
  "compilerOptions": {
    "strict": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "isolatedModules": true,
    "paths": { "@/*": ["./src/*"] }
  }
}
```

Define TypeScript interfaces for all the major data structures currently described only in pseudocode: `NodeStatus`, `KnownMapping`, `PipelineState`, `CxdbContextEntry`, `CqlSearchResponse`, `TurnResponse`, etc. These types serve as both documentation and compile-time correctness checks.

Update all code examples in the spec to use TypeScript syntax with type annotations where they add clarity (function signatures, state declarations).

---

## Issue #3: Frontend must use pnpm for package management

### The problem

The spec has no package management — dependencies are loaded from CDNs. The cxdb repo uses pnpm v9 with `pnpm-lock.yaml` and `pnpm install --frozen-lockfile` in CI. Without a package manager, there is no reproducible dependency resolution, no lock file, and no way to audit or update dependencies systematically.

### Suggestion

The spec should require:
- `frontend/package.json` with all dependencies declared
- `frontend/pnpm-lock.yaml` committed to VCS
- `pnpm install --frozen-lockfile` in CI
- Makefile targets: `ui-install` (`cd frontend && pnpm install`), `ui-build` (`cd frontend && pnpm build`), `ui-dev` (`cd frontend && pnpm dev`), `ui-lint` (`cd frontend && pnpm lint`), `ui-test` (`cd frontend && pnpm test`)

---

## Issue #4: CSS must use Tailwind CSS v3

### The problem

The spec uses inline CSS within the single HTML file (Section 6.3 defines raw CSS rules for status classes). The cxdb repo uses Tailwind CSS v3 with a custom theme system, PostCSS, and `cn()` utility for class merging. The inline CSS approach is inconsistent with cxdb's patterns and makes styling harder to maintain.

### Suggestion

Replace the inline CSS approach with Tailwind CSS v3. The status overlay colors (pending=gray, running=blue, complete=green, error=red, stale=orange) should be defined as Tailwind custom colors or CSS variables applied via Tailwind utilities. The pulsing animation for "running" nodes should be a Tailwind custom animation (matching cxdb's `breathe` and `glow-pulse` animation patterns).

Specify the following config files:
- `frontend/tailwind.config.ts` — with custom status colors and animations
- `frontend/postcss.config.mjs` — tailwindcss + autoprefixer
- A `cn()` utility in `frontend/src/lib/utils.ts` (matching cxdb's pattern)

Note: The SVG status overlay CSS (Section 6.3) targets SVG elements injected by Graphviz WASM. These are DOM elements that Tailwind utility classes cannot be applied to directly (since the SVG is generated at runtime, not authored in JSX). The status CSS classes (`.node-pending`, `.node-running`, etc.) should remain as global CSS rules in a `globals.css` file, defined using Tailwind's `@layer` directive. This is the same pattern cxdb uses for its `globals.css` (Tailwind directives + CSS custom properties).

---

## Issue #5: Frontend must use React 18 with component architecture

### The problem

The spec uses vanilla JavaScript DOM manipulation throughout. The cxdb repo uses React 18 with hooks-based components, `'use client'` directives, `useCallback` for render optimization, and `useRef` for mutable values. The cxdb-graph-ui dashboard has clear component boundaries (tab bar, graph viewer, detail panel, connection indicator) that map naturally to React components.

### Suggestion

Specify a React 18 component architecture for the frontend. The component tree should follow cxdb's organization pattern:

```
frontend/src/
  components/
    TabBar.tsx            — pipeline tabs
    GraphViewer.tsx       — SVG graph area (Graphviz WASM rendering)
    DetailPanel.tsx       — right sidebar (DOT attributes + CXDB turns)
    ConnectionIndicator.tsx — CXDB status indicator
    StatusOverlay.tsx     — CSS class application to SVG nodes
    TurnRow.tsx           — individual turn in detail panel
    index.ts              — barrel exports
  hooks/
    useGraphviz.ts        — Graphviz WASM loading and rendering
    useCxdbPoller.ts      — CXDB polling loop (3-second interval)
    useDiscovery.ts       — pipeline discovery state machine
    useStatusMap.ts       — status derivation and merging
    index.ts              — barrel exports
  lib/
    api.ts                — fetch wrappers for server API
    discovery.ts          — pipeline discovery logic (pure functions)
    status.ts             — status derivation algorithms (pure functions)
    dot-parser.ts         — client-side graph ID extraction
    msgpack.ts            — msgpack decoding for RunStarted
    utils.ts              — cn(), formatMilliseconds(), etc.
  types/
    index.ts              — NodeStatus, KnownMapping, TurnResponse, etc.
  app/
    page.tsx              — main dashboard layout
    globals.css           — Tailwind directives + SVG status classes
```

Follow cxdb's conventions:
- Named exports throughout, barrel `index.ts` files
- `@/` path alias for internal imports
- `import type {}` for type-only imports
- `useCallback` with stable deps for render optimization
- `useRef` for mutable poll state (timers, abort controllers, cached maps)
- `data-*` attributes on all interactive elements for Playwright test selectors

The separation of **pure logic** (in `lib/`) from **React hooks** (in `hooks/`) is critical for testability — discovery, status derivation, and merging logic can be unit tested without React.

---

## Issue #6: CDN dependencies must become npm packages

### The problem

Section 4.1.1 specifies two CDN dependencies loaded at runtime:
- `@hpcc-js/wasm-graphviz@1.6.1` from esm.sh
- `@msgpack/msgpack@3.0.0-beta2` from jsdelivr

With a proper build toolchain, CDN loading is unnecessary and harmful: it introduces runtime failure modes (CDN unreachable, CDN serving stale/wrong version), prevents tree-shaking, provides no TypeScript types, and has already caused bugs (v58 broken msgpack CDN URL).

### Suggestion

Both dependencies should be installed as npm packages via pnpm and imported normally in TypeScript:

```typescript
import { Graphviz } from "@hpcc-js/wasm-graphviz";
import { decode } from "@msgpack/msgpack";
```

The build tool (Vite) handles bundling, tree-shaking, and WASM asset management. The `@hpcc-js/wasm-graphviz` package includes TypeScript types and properly loads its WASM binary via Vite's asset handling.

Remove all CDN URL references from Sections 4.1, 4.1.1, and the import isolation pattern. The "import isolation" concept (Section 4.1.1) becomes a standard dynamic `import()` in TypeScript — which Vite handles natively.

Update the graceful degradation principle: instead of "CDN unreachable," the failure mode becomes "WASM load error" (which is still possible and should be handled, but is less likely with bundled assets).

Remove the browser integration test layer (Section 12.3) rationale about "CDN dependency validation" — with bundled packages, broken URLs are impossible.

---

## Issue #7: Testing architecture must be simplified to match cxdb — Playwright + Vitest

### The problem

The spec defines 4 testing layers:
1. Rust unit tests (12.1) — appropriate, keep
2. JavaScript unit tests via Vitest (12.2) — currently specifies extraction from inline scripts
3. Browser integration tests via Rust headless_chrome (12.3) — unnecessary with proper frontend toolchain
4. Playwright UI tests (12.4) — appropriate, keep

The cxdb repo uses only Playwright for all frontend testing (no Vitest, no Rust browser tests). However, the cxdb-graph-ui's discovery state machine and status derivation logic genuinely need unit testing — Playwright cannot observe internal state transitions. The right approach is:

### Suggestion

Simplify to 3 testing layers:

**Layer 1 — Rust unit tests (keep as-is).** `cargo test`, 100% coverage for server code.

**Layer 2 — TypeScript unit tests via Vitest.** With the frontend now in TypeScript with proper modules (Issue #5), the "pre-requisite" in Section 12.2 about extracting JS from inline scripts is eliminated. The pure logic modules in `lib/` (discovery, status derivation, merging, gap recovery, error heuristic) are directly importable and testable. Update Section 12.2:
- Tooling: `vitest run --coverage` with V8 provider
- Scope: All pure logic in `frontend/src/lib/` — the 9 discovery behaviors from Invariant 20, plus status derivation, merging, error heuristic, and stale detection
- Must run without a browser, server, or CXDB instance
- Add `ui-test-unit` Makefile target: `cd frontend && pnpm test:unit`

**Layer 3 — Playwright E2E tests (replaces both 12.3 and 12.4).** The Rust `headless_chrome` browser smoke tests (12.3) are unnecessary because:
- With bundled npm packages, CDN URL breakage is impossible
- Playwright tests already verify that the app loads, WASM initializes, SVG renders, tabs work, and node click opens the panel
- Maintaining a separate Rust browser test suite doubles the browser testing surface with no additional coverage

Follow cxdb's Playwright conventions:
- Tests in `frontend/tests/*.spec.ts`
- Custom fixtures extending `test` with server spawning (build Rust binary in `global-setup.ts`, spawn per-test)
- `page.route()` for CXDB mock responses
- `data-*` attributes as test selectors
- Workers: 1 (sequential)
- Add `ui-test-e2e` Makefile target: `cd frontend && pnpm test:e2e`

Remove Section 12.3 entirely. Update Section 12.5 (Testing Layer Boundaries) to reflect the simplified layers. Remove the `make test-browser` target from Section 3.4. Remove the `server/tests/browser.rs` file from Section 3.3's layout.

---

## Issue #8: Frontend must live in its own `frontend/` directory

### The problem

The spec places the entire frontend in `server/assets/index.html` — a single file embedded in the Rust binary via `include_str!()`. With a proper build toolchain, the frontend is a separate project with its own `package.json`, `tsconfig.json`, build config, test config, and source tree.

### Suggestion

Add a `frontend/` directory at the repo root (matching cxdb's pattern). Update Section 3.3 (Project Layout) to show:

```
Cargo.toml                      ← workspace root
Makefile                        ← top-level build targets (Rust + frontend)
frontend/
├── package.json                ← pnpm project (name, scripts, dependencies)
├── pnpm-lock.yaml              ← locked dependency versions
├── tsconfig.json               ← TypeScript config (strict)
├── vite.config.ts              ← Vite config (React plugin, build output to server/assets/)
├── tailwind.config.ts          ← Tailwind CSS config
├── postcss.config.mjs          ← PostCSS config
├── .eslintrc.json              ← ESLint config
├── playwright.config.ts        ← Playwright config
├── src/
│   ├── components/             ← React components
│   ├── hooks/                  ← Custom React hooks
│   ├── lib/                    ← Pure utility modules
│   ├── types/                  ← TypeScript type definitions
│   ├── app/
│   │   ├── page.tsx            ← Main dashboard page
│   │   └── globals.css         ← Tailwind + SVG status classes
│   └── main.tsx                ← Vite entry point
├── tests/
│   ├── fixtures.ts             ← Playwright test fixtures
│   ├── global-setup.ts         ← Build Rust server before tests
│   ├── utils/
│   │   ├── server.ts           ← Spawn/stop Rust server
│   │   └── assertions.ts       ← Reusable page assertions
│   ├── graph-rendering.spec.ts
│   ├── status-overlay.spec.ts
│   ├── detail-panel.spec.ts
│   ├── connection-handling.spec.ts
│   └── server-startup.spec.ts
└── vitest.config.ts            ← Vitest config for unit tests
server/
├── Cargo.toml
├── src/
│   ├── main.rs
│   ├── lib.rs
│   ├── ...
├── tests/
│   └── integration.rs
└── assets/                     ← Vite build output (gitignored, built by `pnpm build`)
    ├── index.html
    ├── assets/
    │   ├── index-[hash].js
    │   ├── index-[hash].css
    │   └── wasm-graphviz-[hash].wasm
```

**Key design decision: Vite builds into `server/assets/`.** The Rust server's `include_str!()` approach no longer works for a multi-file build output (JS, CSS, WASM, HTML). Two options:

1. **`include_dir!()` macro** (via the `include_dir` crate): Embeds the entire `server/assets/` directory at compile time. The Rust binary is self-contained. Requires `pnpm build` before `cargo build`.
2. **Runtime file serving**: The Rust server serves files from a `--assets` directory at runtime (defaulting to `server/assets/`). Simpler for development (`pnpm dev` + `cargo run` work independently), but the binary is no longer self-contained.

Recommend option 1 for production (matching the current `include_str!()` intent) with a `--dev` flag that serves from the filesystem for development workflow. This is the same pattern used by Rust web frameworks like `leptos` and `dioxus`.

Update the Makefile to add a `build-all` target that runs `pnpm build` then `cargo build`.

---

## Issue #9: Factory pipeline must add frontend build, lint, and test gates

### The problem

The factory pipeline (`factory/pipeline-config.yaml`) only has gates for Rust tooling: `cargo fmt`, `cargo clippy`, `cargo build`, `cargo test`. There are no gates for frontend build (`pnpm build`), frontend lint (`pnpm lint`), or frontend tests (`pnpm test`). A factory run could produce Rust code that compiles and passes Rust tests but has TypeScript compilation errors, ESLint violations, or failing frontend tests.

### Suggestion

Add frontend gates to the pipeline config after the Rust gates:

```
verify_tests → fix_ui_lint → verify_ui_lint → check_ui_lint
             → verify_ui_build → check_ui_build
             → verify_ui_tests → check_ui_tests
             → verify_browser (Playwright E2E) → review_final
```

Gate commands:
- `fix_ui_lint`: `cd frontend && pnpm lint --fix`
- `verify_ui_lint`: `cd frontend && pnpm lint`
- `verify_ui_build`: `cd frontend && pnpm build` (also validates TypeScript)
- `verify_ui_tests`: `cd frontend && pnpm test:unit` (Vitest unit tests)
- `verify_browser`: Updated to run `cd frontend && pnpm test:e2e` (Playwright) instead of the current MCP-based browser verification

Update `factory/prompts/implement.md` to include the frontend architecture, component structure, TypeScript types, and build workflow. Update `factory/prompts/review_final.md` to check frontend code quality alongside Rust code.

Update `script/build.sh`, `script/setup.sh`, and `script/smoke-test-suite-full` to include frontend build and test steps.

---

## Issue #10: Holdout scenarios and skills must be updated for the new architecture

### The problem

The holdout scenarios (`holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`) and the verify-run-holdout-scenarios skill assume a single-file SPA with CDN dependencies. Multiple scenarios reference CDN-specific behavior (e.g., "Msgpack CDN failure does not block DOT rendering"), inline CSS classes, and single-file structure.

### Suggestion

Update the holdout scenarios:
- Remove or rewrite the "Msgpack CDN failure" scenario — with bundled packages, CDN failures are not a failure mode. Replace with a WASM load failure scenario.
- Add scenarios for frontend build: `pnpm build` produces valid output, `pnpm lint` passes, TypeScript compilation succeeds.
- Update "Render a pipeline graph" to reference React component rendering, not raw DOM manipulation.
- Add a scenario for dev workflow: `pnpm dev` + `cargo run` work together for hot-reload development.

Update the verify-run-holdout-scenarios skill:
- Update SKILL.md to reference Playwright tests in `frontend/tests/` instead of MCP browser automation.
- Update fixture paths if they move.

---

## Issue #11: ESLint configuration required

### The problem

The spec does not mention JavaScript/TypeScript linting. The cxdb repo uses ESLint with the `next/core-web-vitals` ruleset. Without linting, there is no automated code quality enforcement for the frontend.

### Suggestion

Specify ESLint configuration for the frontend. Since we're using Vite (not Next.js), use `eslint-config-react-app` or a custom config with `@typescript-eslint/recommended` and `eslint-plugin-react-hooks`:

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

Add `pnpm lint` to the CI workflow and the `make precommit` target.

---

## Issue #12: `data-*` test selector convention must be specified

### The problem

The cxdb repo uses `data-*` attributes on DOM elements as Playwright test selectors (e.g., `[data-context-debugger]`, `[data-debug-event-list]`). This convention is not mentioned in the spec. Without it, Playwright tests will rely on brittle CSS class selectors or text content matching.

### Suggestion

Add a testing convention to Section 12 (or to the new frontend architecture section) requiring `data-testid` attributes on all interactive and assertable elements. Define the required selectors:

- `data-testid="tab-bar"` — tab container
- `data-testid="tab-{graphId}"` — individual pipeline tab
- `data-testid="graph-area"` — SVG graph container
- `data-testid="detail-panel"` — detail panel sidebar
- `data-testid="connection-indicator"` — CXDB status indicator
- `data-testid="turn-row-{turnId}"` — individual turn in detail panel
- `data-testid="loading-message"` — "Loading Graphviz..." indicator
- `data-testid="error-message"` — error display area

This follows the `data-testid` convention (widely adopted by React Testing Library and Playwright) rather than cxdb's `data-*` custom attributes, since cxdb-graph-ui has no domain-specific attribute needs.

---

## Issue #13: CI workflow must include frontend jobs

### The problem

Section 3.5 defines a CI workflow (`rust.yml`) with only Rust gates (build, test, clippy, format). There are no CI jobs for frontend build, lint, or tests.

### Suggestion

Add a `frontend.yml` CI workflow (matching cxdb's pattern) with separate jobs:
- `build`: `pnpm install --frozen-lockfile && pnpm build`
- `lint`: `pnpm install --frozen-lockfile && pnpm lint`
- `test-unit`: `pnpm install --frozen-lockfile && pnpm test:unit`
- `test-e2e`: Build Rust server, install Playwright browsers, run `pnpm test:e2e`

Node.js 20, pnpm 9, matching cxdb's CI configuration.

Update the `make precommit` target in Section 3.4 to also run frontend lint and unit tests: `make fmt-check && make clippy && make test && make ui-lint && make ui-test-unit`.

---

## Issue #14: Definition of Done must include frontend criteria

### The problem

The Definition of Done (`specification/constraints/definition-of-done.md`) only references `cargo` commands and Rust-specific criteria. There are no checklist items for frontend build, lint, TypeScript compilation, or frontend tests.

### Suggestion

Add a "Frontend" section to the Definition of Done:

```markdown
## Frontend

- [ ] `pnpm build` produces valid output in `server/assets/` without errors
- [ ] `pnpm lint` passes with zero warnings
- [ ] TypeScript compilation (`tsc --noEmit`) passes with zero errors
- [ ] Vitest unit tests pass with coverage thresholds met
- [ ] Playwright E2E tests pass
- [ ] All interactive elements have `data-testid` attributes
- [ ] React components follow hooks-based architecture (no class components)
- [ ] Named exports throughout, barrel `index.ts` files for each directory
- [ ] `@/` path alias used for all internal imports
```

---

## Issue #15: Rust server asset serving strategy must be updated for multi-file build output

### The problem

Section 3.2 and the server-api contract (`GET /`) specify `include_str!("../assets/index.html")` for embedding the frontend. With a build toolchain producing multiple files (HTML, JS, CSS, WASM, source maps), `include_str!()` is insufficient.

### Suggestion

Update `GET /` route specification in `specification/contracts/server-api.md`:

For production: use the `include_dir` crate to embed the entire `server/assets/` directory at compile time. The route handler serves files from the embedded directory with correct MIME types. `GET /` returns `index.html`, and `GET /assets/*` returns the hashed build artifacts.

For development: a `--dev` flag on the CLI causes the server to serve files from the filesystem path `server/assets/` (or a configurable `--assets-dir`) instead of the embedded copy. This enables hot-reload during development.

Update the project layout (Section 3.3) to show `server/assets/` as a build output directory (gitignored) rather than a source directory.

Add `include_dir` to the server's `Cargo.toml` dependencies.

---

## Issue #16: Invariant 20 and Section 12.2 must be updated for TypeScript module testing

### The problem

Invariant 20 says "Discovery state machine behavior is verified by JavaScript unit tests." Section 12.2's pre-requisite says "JavaScript logic must be extracted from inline `<script>` tags into importable ES modules." Both assume the single-file SPA architecture.

### Suggestion

Update Invariant 20: "Discovery state machine behavior is verified by **TypeScript** unit tests, not by UI tests. The pure logic modules in `frontend/src/lib/` (discovery, status derivation, merging, gap recovery) are directly importable by Vitest."

Update Section 12.2: Remove the pre-requisite paragraph entirely (the TypeScript module structure is the source of truth — there is no extraction step). Update the scope to reference `frontend/src/lib/discovery.ts`, `frontend/src/lib/status.ts`, etc. Update the tooling to `pnpm test:unit`.

---

## Issue #17: The `server/assets/index.html` stub must be removed or replaced

### The problem

The git status shows `server/` as an untracked directory containing `server/assets/index.html` — a stub from the previous Go implementation that was deleted in the v60 commit but the `server/` directory was re-created with just this HTML file. With the frontend now being a built artifact, this file should not be a manually-authored source file.

### Suggestion

Delete `server/assets/index.html` from version control. Add `server/assets/` to `.gitignore` (it will be populated by `pnpm build`). The frontend source lives in `frontend/src/` and the build output goes to `server/assets/`.

Alternatively, if the Rust build must work without running `pnpm build` first (e.g., for CI jobs that only test Rust code), include a minimal placeholder `index.html` in the source tree that says "Frontend not built. Run `pnpm build` in frontend/ first." This prevents `include_dir!()` from failing at compile time when `server/assets/` is empty.
