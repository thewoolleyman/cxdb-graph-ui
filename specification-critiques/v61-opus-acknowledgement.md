# CXDB Graph UI Spec — Critique v61 (opus) Acknowledgement

Applied all 17 issues from the frontend architecture critique as a single coordinated revision. The specification now describes a modern frontend stack aligned with cxdb conventions: Vite + React 18, TypeScript (strict), Tailwind CSS v3, pnpm v9, ESLint, and Playwright + Vitest testing. The single-file SPA with CDN dependencies has been replaced with a `frontend/` directory containing a proper build toolchain. The Rust server now embeds multi-file build output via `include_dir` instead of `include_str!()`.

## Issue #1: "No build toolchain" design principle contradicts cxdb conventions — replace with modern frontend stack

**Status: Applied to specification**

Replaced the "No build toolchain" principle in Section 1.2 with "cxdb-aligned frontend toolchain" describing Vite + React 18, TypeScript (strict), Tailwind CSS v3, and pnpm v9. Updated the architecture diagram in Section 2 to show "React SPA, built by Vite" and "bundled" instead of "CDN". Adopted the Vite + React recommendation over Next.js since cxdb-graph-ui is a single-page dashboard with no routing needs.

Changes:
- `specification/intent/overview.md`: Section 1.2 design principle, Section 2 architecture diagram, "Why browser-side DOT rendering" paragraph

## Issue #2: All JavaScript must be TypeScript with strict mode

**Status: Applied to specification**

TypeScript with `strict: true` is now required via the frontend toolchain specification. The `tsconfig.json` configuration is specified in the project layout. TypeScript interfaces for major data structures are specified as part of the `frontend/src/types/` directory. Code examples in Sections 4.1 and 4.1.1 updated to TypeScript syntax.

Changes:
- `specification/intent/overview.md`: Section 1.2 mentions TypeScript
- `specification/intent/server.md`: Section 3.3 project layout includes `tsconfig.json` and `types/` directory
- `specification/intent/dot-rendering.md`: Code examples updated to TypeScript

## Issue #3: Frontend must use pnpm for package management

**Status: Applied to specification**

pnpm v9 is specified as the package manager. `frontend/package.json` and `frontend/pnpm-lock.yaml` are in the project layout. Makefile targets added: `ui-install`, `ui-build`, `ui-dev`, `ui-lint`, `ui-test-unit`, `ui-test-e2e`. CI workflow specifies `pnpm install --frozen-lockfile`.

Changes:
- `specification/intent/server.md`: Section 3.3 project layout, Section 3.4 Makefile targets, Section 3.5 CI workflow

## Issue #4: CSS must use Tailwind CSS v3

**Status: Applied to specification**

Tailwind CSS v3 is specified with `tailwind.config.ts`, `postcss.config.mjs`, and a `cn()` utility in `frontend/src/lib/utils.ts`. The SVG status overlay CSS classes remain as global CSS rules in `globals.css` using Tailwind's `@layer` directive (since SVG elements are generated at runtime by Graphviz WASM, not authored in JSX). Status colors specified as Tailwind custom colors.

Changes:
- `specification/intent/server.md`: Section 3.3 project layout includes Tailwind config files
- `specification/intent/status-overlay.md`: Section 6.3 CSS rules wrapped in `@layer components` with Tailwind context

## Issue #5: Frontend must use React 18 with component architecture

**Status: Applied to specification**

React 18 component architecture specified with the full component tree, hooks, lib, and types directory structure matching cxdb's organization pattern. Conventions specified: named exports, barrel files, `@/` path alias, `import type {}`, `useCallback`, `useRef`, `data-testid` attributes. Separation of pure logic (in `lib/`) from React hooks (in `hooks/`) specified as critical for testability.

Changes:
- `specification/intent/server.md`: Section 3.3 project layout with full `frontend/src/` tree and conventions
- `specification/intent/overview.md`: Architecture diagram references "React SPA"

## Issue #6: CDN dependencies must become npm packages

**Status: Applied to specification**

Both `@hpcc-js/wasm-graphviz` and `@msgpack/msgpack` are now specified as npm packages installed via pnpm and imported as standard TypeScript modules. All CDN URL references removed from Sections 4.1 and 4.1.1. The "import isolation" concept simplified — msgpack still uses lazy dynamic `import()` for graceful degradation but as a bundled module, not a CDN fetch. Graphviz WASM loading described as Vite-managed asset.

Changes:
- `specification/intent/dot-rendering.md`: Sections 4.1 and 4.1.1 completely rewritten for npm packages

## Issue #7: Testing architecture must be simplified to match cxdb — Playwright + Vitest

**Status: Applied to specification**

Simplified from 4 testing layers to 3: (1) Rust unit tests (unchanged), (2) TypeScript unit tests via Vitest (updated from JavaScript, removed extraction pre-requisite), (3) Playwright E2E tests (replaces both browser integration tests and previous Playwright layer). Removed Section 12.3 (browser integration tests) entirely — with bundled npm packages, CDN URL breakage is impossible, and Playwright tests cover all browser-level assertions. Removed `test-browser` Makefile target and `browser.rs` from project layout. Removed `#[cfg(feature = "browser")]` from ROP requirements. Updated Section 12.5 testing layer boundaries.

Changes:
- `specification/constraints/testing-requirements.md`: Complete rewrite — 3 layers, new section numbering
- `specification/intent/server.md`: Section 3.3 layout (removed `browser.rs`), Section 3.4 Makefile (removed `test-browser`, added frontend targets)
- `specification/constraints/railway-oriented-programming-requirements.md`: Removed feature-gated browser tests line

## Issue #8: Frontend must live in its own `frontend/` directory

**Status: Applied to specification**

Added `frontend/` directory at repo root with full project structure: `package.json`, `tsconfig.json`, `vite.config.ts`, `tailwind.config.ts`, `postcss.config.mjs`, `.eslintrc.json`, `playwright.config.ts`, `vitest.config.ts`, and the `src/` and `tests/` trees. Vite builds into `server/assets/` (gitignored). `include_dir` crate embeds the build output at compile time. `--dev` flag specified for development workflow. `make build-all` target runs `pnpm build` then `cargo build`. Non-negotiable structural requirements updated to include frontend directory and gitignored assets.

Changes:
- `specification/intent/server.md`: Section 3.3 project layout completely rewritten with `frontend/` tree
- `specification/contracts/server-api.md`: `GET /` route rewritten for `include_dir` and multi-file serving

## Issue #9: Factory pipeline must add frontend build, lint, and test gates

**Status: Applied to factory pipeline**

Updated `factory/pipeline-config.yaml` with frontend gate nodes: `verify_ui_install`, `verify_ui_build`, `verify_ui_lint`, `verify_ui_test_unit` (with corresponding `check_*` diamonds). Replaced `verify_browser` (LLM-driven browser check) with deterministic `verify_e2e` gate running `pnpm test:e2e`. Frontend gates run before Rust build (since `include_dir` embeds `server/assets/`). Updated `goal`, `graph_goal`, `rules`, and `required_gates` to reflect React SPA architecture. Deleted `factory/prompts/verify_browser.md` (absorbed useful parts into `review_final.md`). Updated `implement.md` and `review_final.md` prompts for the new frontend architecture.

## Issue #10: Holdout scenarios and skills must be updated for the new architecture

**Status: Applied to specification and holdout scenarios**

Updated holdout scenarios: replaced "Msgpack CDN failure" scenario with "WASM load failure" scenario. Updated "Render a pipeline graph" to reference React SPA and Vite-bundled WASM. Added 4 new frontend build scenarios (build produces valid output, lint passes, unit tests pass, dev workflow with hot-reload). The verify-run-holdout-scenarios skill update is deferred to implementation time since it depends on the actual Playwright test file paths.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Replaced CDN scenario, updated rendering scenario, added Frontend Build section

## Issue #11: ESLint configuration required

**Status: Applied to specification**

ESLint configuration specified with `eslint:recommended`, `@typescript-eslint/recommended`, and `react-hooks/recommended` rulesets. Added to CI workflow (`pnpm lint`), Makefile (`ui-lint`), and `make precommit` target. `.eslintrc.json` in the project layout.

Changes:
- `specification/constraints/testing-requirements.md`: New Section 12.5 ESLint Configuration
- `specification/intent/server.md`: Section 3.3 layout includes `.eslintrc.json`, Section 3.4 `ui-lint` target, Section 3.5 CI lint gate

## Issue #12: `data-*` test selector convention must be specified

**Status: Applied to specification**

Added `data-testid` convention with the full required selector table. Uses the `data-testid` convention (widely adopted by React Testing Library and Playwright) rather than custom `data-*` attributes.

Changes:
- `specification/constraints/testing-requirements.md`: New Section 12.6 `data-testid` Convention

## Issue #13: CI workflow must include frontend jobs

**Status: Applied to specification**

Added `.github/workflows/frontend.yml` CI workflow with build, lint, unit test, and E2E test jobs. Node.js 20, pnpm 9, matching cxdb's CI configuration.

Changes:
- `specification/intent/server.md`: Section 3.5 CI Workflow expanded with frontend.yml

## Issue #14: Definition of Done must include frontend criteria

**Status: Applied to specification**

Added "Frontend" section to the Definition of Done with 9 checklist items covering build, lint, TypeScript compilation, tests, `data-testid` attributes, React conventions, named exports, and path aliases. Updated Testing section to reference Playwright E2E instead of browser integration tests.

Changes:
- `specification/constraints/definition-of-done.md`: New "Frontend" section, updated "Testing" section

## Issue #15: Rust server asset serving strategy must be updated for multi-file build output

**Status: Applied to specification**

Updated `GET /` route specification to use `include_dir` crate for embedding the entire `server/assets/` directory. Specified `GET /assets/*` for hashed build artifacts with correct MIME types. Added `--dev` flag for development workflow (serves from filesystem). Added `make build-all` target. Updated project layout to show `server/assets/` as gitignored build output with hashed artifacts.

Changes:
- `specification/contracts/server-api.md`: `GET /` route completely rewritten
- `specification/intent/server.md`: Section 3.3 layout shows build output structure, Section 3.4 `build-all` target
- `specification/constraints/definition-of-done.md`: Updated `GET /` checklist item

## Issue #16: Invariant 20 and Section 12.2 must be updated for TypeScript module testing

**Status: Applied to specification**

Updated Invariant 20 from "JavaScript unit tests" to "TypeScript unit tests" with reference to `frontend/src/lib/` modules and Vitest. Updated Section 12.2 from "JavaScript Unit Tests" to "TypeScript Unit Tests" — removed the extraction pre-requisite entirely (the TypeScript module structure is the source of truth), updated scope to reference `frontend/src/lib/` modules, updated tooling to `pnpm test:unit`.

Changes:
- `specification/constraints/invariants.md`: Invariant 20 reworded for TypeScript and Vitest
- `specification/constraints/testing-requirements.md`: Section 12.2 rewritten

## Issue #17: The `server/assets/index.html` stub must be removed or replaced

**Status: Applied to specification**

The project layout now shows `server/assets/` as a gitignored build output directory populated by `pnpm build`. The specification notes that an optional minimal placeholder `index.html` may be committed to prevent `include_dir!()` from failing on a fresh clone before the first `pnpm build`. The actual deletion of the stub file is an implementation action, not a specification change — the spec now correctly describes the target state.

Changes:
- `specification/intent/server.md`: Section 3.3 layout shows `server/assets/` as build output
- `specification/contracts/server-api.md`: `GET /` route describes build dependency and placeholder option

## Not Addressed (Out of Scope)

None — all 17 issues addressed.
