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
Makefile                        ← top-level build targets
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
│   ├── integration.rs          ← server integration tests
│   └── browser.rs              ← browser smoke tests (#[cfg(feature = "browser")])
└── assets/
    └── index.html              ← embedded frontend SPA
specification/                  ← spec files (unchanged location)
factory/                        ← factory config (unchanged location)
```

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
5. `index.html` is embedded at compile time from `server/assets/`
6. Workspace `Cargo.toml` at repo root with `resolver = "2"`

**Configuration pattern (cxdb alignment).** A `Config` struct in `server/src/config.rs` uses `clap` derive macros to parse CLI arguments (`--dot`, `--cxdb`, `--port`). The `Config` struct is passed into the server builder as the single source of truth for all runtime configuration — no scattered CLI argument access throughout the codebase.

### 3.4 Makefile

A top-level `Makefile` serves as the canonical entry point for all build, test, and development operations, matching `cxdb`'s naming conventions:

| Target | Command | Description |
|--------|---------|-------------|
| `build` | `cd server && cargo build` | Debug build |
| `release` | `cd server && cargo build --release` | Release build |
| `test` | `cd server && cargo test` | Run all unit and integration tests |
| `test-browser` | `cd server && cargo test --features browser -- --test-threads=1` | Run browser integration tests |
| `clippy` | `cd server && cargo clippy -- -D warnings` | Lint with Clippy (enforces ROP lints) |
| `fmt` | `cd server && cargo fmt` | Format code |
| `fmt-check` | `cd server && cargo fmt --check` | Check formatting without modifying |
| `check` | `cd server && cargo check` | Fast type-check without codegen |
| `clean` | `cd server && cargo clean` | Remove build artifacts |
| `run` | `cd server && cargo run --` | Run the server (pass args after `--`) |
| `precommit` | `make fmt-check && make clippy && make test` | Pre-commit validation gate |

### 3.5 CI Workflow

A GitHub Actions CI workflow at `.github/workflows/rust.yml` runs on push and PR to `main`, matching `cxdb`'s structure:

1. **Build** — `cargo build` (from `server/`)
2. **Test** — `cargo test` (from `server/`)
3. **Clippy** — `cargo clippy -- -D warnings` (from `server/`, enforces ROP lints)
4. **Format** — `cargo fmt --check` (from `server/`)

All four gates must pass. A failure in any gate blocks merge. The CI workflow may call Makefile targets or run raw Cargo commands — either is acceptable as long as the gates match the `precommit` targets exactly.
