## 3. Server

The server exposes a CLI with `--port`, `--cxdb` (repeatable), and `--dot` (repeatable) flags, and serves 7 HTTP routes: `GET /` (dashboard), `GET /dots/{name}` (DOT files), `GET /dots/{name}/nodes` (parsed node attributes), `GET /dots/{name}/edges` (parsed edge list), `GET /api/cxdb/{index}/*` (CXDB reverse proxy), `GET /api/dots` (DOT file list), and `GET /api/cxdb/instances` (CXDB instance list).

**For complete CLI flag definitions, route specifications, request/response formats, and DOT parsing rules, see [`specification/contracts/server-api.md`](../contracts/server-api.md).**

### 3.2 Server Properties

- The server is stateless. It caches nothing. Every request reads from disk or proxies to CXDB.
- The server uses idiomatic Rust crates from crates.io: `axum`, `tokio`, `hyper`, `clap`, `thiserror`, `serde`/`serde_json`, `tower-http` (for proxy/middleware). A `server/Cargo.toml` defines the crate name, edition, dependencies, and lint configuration. A workspace `Cargo.toml` at the repo root declares the `server` member.
- The server binds to `0.0.0.0:{port}` (all interfaces).
- Requests to paths not matching any registered route return 404 with a plain-text body. The server does not serve directory listings, automatic redirects, or HTML error pages for unmatched routes.

### 3.3 Project Layout

The Rust server follows the repo layout established by the upstream `cxdb` repository — the canonical Rust+JS project in this ecosystem. This ensures consistency across the CXDB platform: shared Makefile target names, matching CI structure, compatible `lib.rs` + `main.rs` separation, and the same `server/` subdirectory pattern.

```
Cargo.toml                      ← workspace root: [workspace] members = ["server"]
Makefile                        ← top-level build targets (Rust + frontend)
frontend/
├── package.json                ← pnpm project (name, scripts, dependencies)
├── pnpm-lock.yaml              ← locked dependency versions (committed to VCS)
├── tsconfig.json               ← TypeScript config (strict)
├── vite.config.ts              ← Vite config (React plugin, build output to server/assets/)
├── tailwind.config.ts          ← Tailwind CSS config (status colors, animations)
├── postcss.config.mjs          ← PostCSS config (tailwindcss + autoprefixer)
├── .eslintrc.json              ← ESLint config
├── playwright.config.ts        ← Playwright config
├── vitest.config.ts            ← Vitest config for unit tests
├── src/
│   ├── main.tsx                ← Vite entry point
│   ├── components/
│   │   ├── TabBar.tsx          ← pipeline tabs
│   │   ├── GraphViewer.tsx     ← SVG graph area (Graphviz WASM rendering)
│   │   ├── DetailPanel.tsx     ← right sidebar (DOT attributes + CXDB turns)
│   │   ├── ConnectionIndicator.tsx ← CXDB status indicator
│   │   ├── StatusOverlay.tsx   ← CSS class application to SVG nodes
│   │   ├── TurnRow.tsx         ← individual turn in detail panel
│   │   └── index.ts            ← barrel exports
│   ├── hooks/
│   │   ├── useGraphviz.ts      ← Graphviz WASM loading and rendering
│   │   ├── useCxdbPoller.ts    ← CXDB polling loop (3-second interval)
│   │   ├── useDiscovery.ts     ← pipeline discovery state machine
│   │   ├── useStatusMap.ts     ← status derivation and merging
│   │   └── index.ts            ← barrel exports
│   ├── lib/
│   │   ├── api.ts              ← fetch wrappers for server API
│   │   ├── discovery.ts        ← pipeline discovery logic (pure functions)
│   │   ├── status.ts           ← status derivation algorithms (pure functions)
│   │   ├── dot-parser.ts       ← client-side graph ID extraction
│   │   ├── msgpack.ts          ← msgpack decoding for RunStarted
│   │   └── utils.ts            ← cn(), formatMilliseconds(), etc.
│   ├── types/
│   │   └── index.ts            ← NodeStatus, KnownMapping, TurnResponse, etc.
│   └── app/
│       ├── page.tsx            ← main dashboard layout
│       └── globals.css         ← Tailwind directives + SVG status classes
└── tests/
    ├── fixtures.ts             ← Playwright test fixtures
    ├── global-setup.ts         ← Build Rust server before tests
    ├── utils/
    │   ├── server.ts           ← Spawn/stop Rust server
    │   └── assertions.ts       ← Reusable page assertions
    ├── graph-rendering.spec.ts
    ├── status-overlay.spec.ts
    ├── detail-panel.spec.ts
    ├── connection-handling.spec.ts
    └── server-startup.spec.ts
server/
├── Cargo.toml                  ← crate manifest (name, edition, deps, [lints.clippy])
├── Cargo.lock                  ← locked dependency versions (committed to VCS)
├── src/
│   ├── main.rs                 ← binary entry point: CLI parsing, server startup
│   ├── lib.rs                  ← declares all pub modules (cxdb pattern)
│   ├── error.rs                ← AppError enum, AppResult<T> type alias, From impls
│   ├── config.rs               ← CLI config struct (from clap), startup validation
│   ├── server.rs               ← axum router, route handlers
│   ├── dot_parser.rs           ← DOT file parsing (nodes, edges, comments, normalization)
│   └── cxdb_proxy.rs           ← CXDB reverse proxy handler
├── tests/
│   └── integration.rs          ← server integration tests
└── assets/                     ← Vite build output (gitignored, populated by pnpm build)
    ├── index.html
    └── assets/
        ├── index-[hash].js
        ├── index-[hash].css
        └── wasm-graphviz-[hash].wasm
specification/                  ← spec files (unchanged location)
factory/                        ← factory config (unchanged location)
```

**Frontend directory.** The `frontend/` directory at the repo root contains the React SPA source, matching cxdb's frontend organization pattern. Vite builds static assets into `server/assets/`, which the Rust server embeds at compile time via the `include_dir` crate. The `server/assets/` directory is gitignored — it is a build artifact, not a source directory.

**Frontend conventions (cxdb alignment):**
- Named exports throughout, barrel `index.ts` files for each directory
- `@/` path alias for internal imports (configured in `tsconfig.json` and `vite.config.ts`)
- `import type {}` for type-only imports
- `useCallback` with stable deps for render optimization
- `useRef` for mutable poll state (timers, abort controllers, cached maps)
- `data-testid` attributes on all interactive elements for Playwright test selectors

**Separation of pure logic from React hooks.** The `frontend/src/lib/` directory contains pure TypeScript functions (discovery, status derivation, merging, gap recovery, error heuristic) that are directly importable by Vitest without React. The `frontend/src/hooks/` directory contains React hooks that orchestrate these pure functions with React lifecycle and state management. This separation is critical for testability — the pure logic modules are the primary target of the Vitest unit test suite (Section 12.2).

**`lib.rs` + `main.rs` separation (cxdb pattern).** `lib.rs` declares all public modules, and `main.rs` is a thin binary entry point that imports from the library crate. This separation is required because integration tests in `tests/` can only import the library crate (`use cxdb_graph_ui::*`), not the binary. `main.rs` should contain only CLI parsing, config construction, server startup, and graceful shutdown — no business logic.

**Workspace `Cargo.toml` at repo root.** Following `cxdb`'s pattern:

```toml
[workspace]
resolver = "2"
members = ["server"]
```

This allows `cargo build` / `cargo test` from the repo root to work, while keeping the server crate self-contained in `server/`.

**Module organization conventions (cxdb pattern).** Simple modules are single files (e.g., `error.rs`, `config.rs`). Complex modules that need internal submodules use the subdirectory + `mod.rs` pattern. The layout is prescriptive for directory names (`server/`, `src/`, `tests/`, `Cargo.toml`, `lib.rs`) but illustrative for module decomposition — the factory may split or merge modules as long as the result follows Cargo conventions and meets all specification requirements. The non-negotiable structural requirements are:
1. Rust code lives in `server/` (not `ui/` or repo root), matching `cxdb`'s layout
2. `lib.rs` declares all public modules; `main.rs` is a thin entry point
3. `error.rs` (or an equivalent module) defines the unified error type
4. `server/Cargo.toml` includes `[lints.clippy]` ROP enforcement
5. `server/assets/` is embedded at compile time via the `include_dir` crate (populated by `pnpm build` in `frontend/`)
6. Workspace `Cargo.toml` at repo root with `resolver = "2"`
7. Frontend source lives in `frontend/` with its own `package.json`, `tsconfig.json`, and build config
8. `server/assets/` is gitignored (build artifact, not source)

**Configuration pattern (cxdb alignment).** A `Config` struct in `server/src/config.rs` uses `clap` derive macros to parse CLI arguments (`--dot`, `--cxdb`, `--port`). The `Config` struct is passed into the server builder as the single source of truth for all runtime configuration — no scattered CLI argument access throughout the codebase.

### 3.4 Makefile

A top-level `Makefile` serves as the canonical entry point for all build, test, and development operations, matching `cxdb`'s naming conventions:

| Target | Command | Description |
|--------|---------|-------------|
| `build` | `cd server && cargo build` | Debug build (Rust only) |
| `release` | `cd server && cargo build --release` | Release build (Rust only) |
| `build-all` | `make ui-build && make build` | Full build: frontend then Rust (embeds assets) |
| `test` | `cd server && cargo test` | Run all Rust unit and integration tests |
| `clippy` | `cd server && cargo clippy -- -D warnings` | Lint with Clippy (enforces ROP lints) |
| `fmt` | `cd server && cargo fmt` | Format Rust code |
| `fmt-check` | `cd server && cargo fmt --check` | Check Rust formatting without modifying |
| `check` | `cd server && cargo check` | Fast Rust type-check without codegen |
| `clean` | `cd server && cargo clean` | Remove Rust build artifacts |
| `run` | `cd server && cargo run --` | Run the server (pass args after `--`) |
| `ui-install` | `cd frontend && pnpm install` | Install frontend dependencies |
| `ui-build` | `cd frontend && pnpm build` | Build frontend (output to server/assets/) |
| `ui-dev` | `cd frontend && pnpm dev` | Start frontend dev server (hot-reload) |
| `ui-lint` | `cd frontend && pnpm lint` | Lint TypeScript/React code |
| `ui-test-unit` | `cd frontend && pnpm test:unit` | Run Vitest unit tests |
| `ui-test-e2e` | `cd frontend && pnpm test:e2e` | Run Playwright E2E tests |
| `precommit` | `make fmt-check && make clippy && make test && make ui-lint && make ui-test-unit` | Pre-commit validation gate |

### 3.5 CI Workflow

Two GitHub Actions CI workflows run on push and PR to `main`, matching `cxdb`'s structure:

**`.github/workflows/rust.yml`** — Rust gates:

1. **Build** — `cargo build` (from `server/`)
2. **Test** — `cargo test` (from `server/`)
3. **Clippy** — `cargo clippy -- -D warnings` (from `server/`, enforces ROP lints)
4. **Format** — `cargo fmt --check` (from `server/`)

**`.github/workflows/frontend.yml`** — Frontend gates (Node.js 20, pnpm 9):

1. **Build** — `pnpm install --frozen-lockfile && pnpm build` (from `frontend/`)
2. **Lint** — `pnpm install --frozen-lockfile && pnpm lint` (from `frontend/`)
3. **Unit tests** — `pnpm install --frozen-lockfile && pnpm test:unit` (from `frontend/`)
4. **E2E tests** — Build Rust server, install Playwright browsers, run `pnpm test:e2e` (from `frontend/`)

All gates in both workflows must pass. A failure in any gate blocks merge. The CI workflows may call Makefile targets or run raw commands — either is acceptable as long as the gates match the `precommit` targets exactly.
