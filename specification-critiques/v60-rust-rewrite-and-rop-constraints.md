# Critique v61 — Rewrite Application from Go to Rust with Railway-Oriented Programming Constraints

**Author:** rust-rewrite
**Date:** 2026-03-01

## Severity: CRITICAL

## Summary

The CXDB Graph UI application is being rewritten from Go to Rust. This is a full replacement — all existing code will be deleted and recreated by the factory. No existing Go code will be reused. The specification must be updated to describe a standard idiomatic Rust application from scratch, not a port of the Go codebase. All Go-specific conventions (directory layout, tooling, idioms, module structure) must be replaced with standard Rust equivalents. A new constraint document must enforce railway-oriented programming (ROP) patterns via `Result<T, E>` throughout the codebase.

The Rust rewrite must follow the conventions and repo layout established by the upstream `cxdb` repository — the canonical Rust+JS project in this ecosystem. This ensures consistency across the CXDB platform: shared Makefile target names, matching CI structure, compatible `lib.rs` + `main.rs` separation, and the same `server/` subdirectory pattern.

This critique covers issues that must be applied as a single coordinated revision across `specification/intent/`, `specification/constraints/`, and `specification/contracts/`.

**Scope note:** Changes in this critique touch files outside `specification/intent/`. The constraints and contracts directories must also be updated — the language change affects testing requirements, definition of done, invariants, and the server API contract.

**Guiding principle:** The specification must describe a Rust application that looks like it was always a Rust application. No Go artifacts, naming conventions, or structural patterns should survive. When this critique says "replace X with Y," the result should read as though X never existed — not as a mechanical find-and-replace with Go ghosts.

---

## Issue #1: Create `specification/constraints/railway-oriented-programming-requirements.md`

**Severity: CRITICAL**

A new constraint file must be created at `specification/constraints/railway-oriented-programming-requirements.md`. This file does not exist yet and must be created from scratch.

### Required content for the new file

The file must specify the following requirements:

**1. All fallible operations must return `Result<T, E>`.** Every function that can fail — I/O, parsing, network requests, CLI argument validation, DOT parsing, CXDB proxy operations — must return `Result`. No function may silently swallow errors or use `Option` where `Result` is semantically correct.

**2. Error propagation via the `?` operator.** The `?` operator is the primary mechanism for propagating errors up the call stack. This gives railway-oriented semantics: each `?` is a potential branch to the error track. Combinator-style chaining (`.map()`, `.and_then()`, `.map_err()`) is permitted where it improves readability but is not required over `?`.

**3. A unified application error type.** Define an `AppError` enum (or equivalent) using `thiserror` for all application-level errors. The enum must have variants covering: DOT parse errors, file I/O errors, CXDB proxy errors, CLI validation errors, HTTP handler errors, and embedding/asset errors. Each variant must carry enough context for actionable error messages. Implement `From` conversions for upstream error types (`std::io::Error`, `hyper::Error`, etc.) so that `?` works transparently across error boundaries. This follows the same pattern as `cxdb`'s `StoreError` enum in `server/src/error.rs`.

**4. A type alias `AppResult<T> = Result<T, AppError>`.** All application functions that can fail should return `AppResult<T>` for consistency. This mirrors `cxdb`'s `pub type Result<T> = std::result::Result<T, StoreError>` pattern.

**5. No `unwrap()` or `expect()` in non-test code.** These methods panic on failure, breaking the railway pattern. They are permitted only in test code (`#[cfg(test)]` modules) and in `main()` for top-level fatal errors where the program should exit. Enforced via Clippy lints.

**6. No `panic!()` in non-test code.** Explicit panics are forbidden outside test modules. Enforced via Clippy lints.

**7. Clippy lint enforcement.** The following lints must be set to `deny` in the server crate's `Cargo.toml` under `[lints.clippy]`:

```toml
[lints.clippy]
unwrap_used = "deny"
expect_used = "deny"
panic = "deny"
unwrap_in_result = "deny"
```

These lints are enforced at compile time. Code that uses `unwrap()`, `expect()`, or `panic!()` outside of test modules will fail the `cargo clippy` gate.

**8. HTTP handlers must not panic.** All HTTP request handlers must return structured error responses (appropriate HTTP status codes with JSON error bodies) rather than panicking. A handler that encounters an error must propagate it via `Result` to an error-handling layer that maps `AppError` variants to HTTP status codes — the same pattern `cxdb` uses to map `StoreError` variants to 404/422/500.

**9. Graceful error propagation in the CXDB proxy.** Proxy errors (upstream unreachable, timeout, malformed response) must be caught and returned as HTTP 502 with a descriptive error body, not as panics or unwrapped connection errors.

**10. DOT parsing errors must be structured.** Parse failures must return typed error variants (e.g., `AppError::DotParse { source, line, detail }`) that carry enough context for the 400 JSON error response specified in the server API contract.

### Update `specification/constraints/README.md`

Add a row to the constraints README table:

| File | Description |
|------|-------------|
| [railway-oriented-programming-requirements.md](railway-oriented-programming-requirements.md) | Railway-oriented programming enforcement: Result types, error propagation, Clippy lints, no-panic policy |

---

## Issue #2: Update `specification/intent/overview.md` — Replace Go with idiomatic Rust

**Severity: CRITICAL**

All Go-specific content in `overview.md` must be replaced with idiomatic Rust equivalents. The result must read as a Rust-native design document.

### Section 2 Architecture

- Architecture diagram: "Go Server (main.go)" → "Rust Server"
- "Go HTTP server" → "Rust HTTP server"

### "Why Go" → "Why Rust"

Replace the entire "Why Go" paragraph. The new paragraph should state:

- Rust provides memory safety without garbage collection, a strong type system with algebraic data types (`Result<T, E>`, `Option<T>`) for railway-oriented error handling, and zero-cost abstractions.
- The server uses `axum` for HTTP routing and handlers, `tokio` for the async runtime, `hyper` as the underlying HTTP implementation, `clap` for CLI argument parsing, and `thiserror` for structured error types.
- Dependencies are declared in `server/Cargo.toml`. The application is built and run with `cargo build` / `cargo run` from the `server/` directory, or via top-level `make build` / `make run`.

### Command references

- All instances of `go run ui/main.go` → `cargo run --` (from `server/`) or `make run`
- "A minimal `go.mod`" → remove entirely (Cargo.toml is described elsewhere)
- "module name `cxdb-graph-ui`" → remove or replace with "crate name `cxdb-graph-ui`"
- Any reference to `go.mod`, `go.sum`, Go module-aware mode → remove

---

## Issue #3: Update `specification/intent/server.md` — Replace Go with idiomatic Rust

**Severity: CRITICAL**

- "Go standard library packages. No external dependencies." → Replace with the Rust dependency set: `axum`, `tokio`, `hyper`, `clap`, `thiserror`, `serde`/`serde_json`, `tower-http` (for proxy/middleware). Rust does not have a "no external dependencies" culture — the crate ecosystem is the standard way to build applications.
- "A minimal `go.mod` (module `cxdb-graph-ui`, no `require` directives) lives in `ui/` alongside `main.go`" → "A `server/Cargo.toml` defines the crate name, edition, dependencies, and lint configuration. A workspace `Cargo.toml` at the repo root declares the `server` member."
- Remove all references to Go module-aware mode, `go.mod` location, `main.go` location.
- "The server uses only Go standard library packages" → "The server uses idiomatic Rust crates from crates.io."

---

## Issue #4: Update `specification/contracts/server-api.md` — Replace Go with idiomatic Rust

**Severity: CRITICAL**

This file has the most Go-specific content. Every reference must be updated.

### CLI section
- `go run ui/main.go [OPTIONS]` → `cargo run -- [OPTIONS]` (from `server/`) or `make run`
- All example commands: replace `go run ui/main.go` with `cargo run --`
- Startup message: "Kilroy Pipeline UI: http://127.0.0.1:9030" — unchanged (behavior, not implementation)

### Route: `GET /` — Dashboard
- "Go's `//go:embed` directive" → Rust's `include_str!()` macro or the `rust-embed` crate
- "The `main.go` file embeds `index.html` at compile time using `//go:embed index.html`, serving it from the embedded filesystem" → "The binary embeds `index.html` at compile time using `include_str!()` or `rust-embed`, serving it from the embedded data"
- "`go run ui/main.go` compiles the binary in a temp directory, so runtime file resolution relative to the source would fail" → "`include_str!()` resolves paths relative to the source file at compile time, so the embedded content is always available regardless of the working directory at runtime"
- "`ui/index.html` must reside at `ui/index.html`, co-located with `ui/main.go`" → "`index.html` must reside at a path reachable by the `include_str!()` macro relative to the embedding source file (typically in `server/assets/`)"
- Remove the paragraph about `//go:embed` path resolution and compile errors — replace with equivalent Rust context

### Route: `GET /dots/{name}` — DOT Files
- Any reference to Go-specific parsing or function names (`parseNodes`, `parseEdges`, etc.) should use generic descriptions or Rust-style naming (`parse_nodes`, `parse_edges` — snake_case)

### General
- All function/method names that appear in Go style (camelCase: `handleRoot`, `handleDots`, `handleAPIDots`, `handleAPICXDB`, `stripComments`, `parseDotToken`, `parseAttrList`, `parseAttrValue`) → Rust snake_case equivalents (`handle_root`, `handle_dots`, `handle_api_dots`, `handle_api_cxdb`, `strip_comments`, `parse_dot_token`, `parse_attr_list`, `parse_attr_value`) or remove specific function names in favor of behavioral descriptions

---

## Issue #5: Update `specification/constraints/testing-requirements.md` — Replace Go with idiomatic Rust

**Severity: CRITICAL**

The entire testing requirements document must be rewritten for Rust tooling and conventions.

### Section 12.1: Rust Unit Tests — Server Layer
- Title: "Go Unit Tests — Server Layer" → "Rust Unit Tests — Server Layer"
- Coverage target: 100% line and branch coverage — unchanged
- Tooling: replace `go test -cover -coverprofile=coverage.out ./...` and `go tool cover -func=coverage.out` with:
  ```bash
  cargo tarpaulin --out html --fail-under 100
  ```
  or:
  ```bash
  cargo llvm-cov --fail-under-lines 100
  ```
- Scope: same behaviors, but reference Rust module names (snake_case) not Go function names
- "The test suite belongs in `ui/main_test.go` using `package main` so unexported parsing functions are directly testable" → "Unit tests live in `#[cfg(test)] mod tests` blocks within each module, giving direct access to private functions. Integration tests live in `server/tests/`."
- "`script/smoke-test-suite-fast` runs `go test ./...`" → runs `make test` (which runs `cargo test` and `cargo clippy -- -D warnings`)
- The Clippy gate is critical — it enforces the ROP lints from Issue #1

### Section 12.2: JavaScript Unit Tests
- If the single-HTML-file frontend approach is retained, this section stands as-is. Note that the v60 critique's concerns about JS test pipeline enforcement remain valid independently of the Rust rewrite.

### Section 12.3: Browser Integration Tests
- "`chromedp` (pure Go, headless Chrome via DevTools Protocol)" → `headless_chrome`, `chromiumoxide`, or `fantoccini` (Rust crates for headless browser testing)
- "Tests live within the Go test suite and require no Node.js" → "Tests live in the Rust integration test suite (`server/tests/` directory) and require no Node.js"
- "`go test -tags browser`" → `cargo test --features browser` (Cargo feature flags for test isolation)
- "`//go:build browser`" → `#[cfg(feature = "browser")]`
- "In-process server: `httptest.NewServer`" → bind to `127.0.0.1:0` with `tokio::net::TcpListener` and run the `axum` server in-process
- "`go test -tags browser -count=1 -timeout 120s ./ui/...`" → `cargo test --features browser -- --test-threads=1` (with a timeout mechanism appropriate to the test harness)
- "`script/smoke-test-suite-slow`" → update command to the Cargo equivalent or `make test-browser`

### Section 12.5: Testing Layer Boundaries
- All references to "Go tests (12.1)" → "Rust tests (12.1)"

---

## Issue #6: Update `specification/constraints/definition-of-done.md` — Replace Go with idiomatic Rust

**Severity: CRITICAL**

### Core Functionality
- "`go run ui/main.go --dot <path>` starts the server" → "`cargo run -- --dot <path>` (from `server/`) or `make run` starts the server"

### Testing
- "Browser integration tests pass (`go test -tags browser -count=1 -timeout 120s ./ui/...`)" → "`cargo test --features browser -- --test-threads=1`" or `make test-browser`

### New section: Code Quality (ROP Enforcement)
Add a new section:
- [ ] All fallible functions return `Result<T, E>` — no panics in non-test code
- [ ] `AppError` enum covers all error categories with `thiserror` derives
- [ ] `AppResult<T>` type alias is used consistently across modules
- [ ] Clippy ROP lints (`unwrap_used`, `expect_used`, `panic`, `unwrap_in_result`) are set to `deny` in `Cargo.toml`
- [ ] `cargo clippy -- -D warnings` passes with zero warnings
- [ ] `cargo fmt --check` passes (standard Rust formatting)
- [ ] `make precommit` passes (runs fmt-check, clippy, test)

### New section: Rust Idioms
- [ ] Code follows standard Rust naming conventions (snake_case functions/variables, CamelCase types, SCREAMING_SNAKE_CASE constants)
- [ ] Public API types derive standard traits (`Debug`, `Clone`, `Serialize`/`Deserialize` where appropriate)
- [ ] Async code uses `tokio` runtime with `axum` handlers returning `impl IntoResponse`
- [ ] No `unsafe` code without explicit justification

---

## Issue #7: Update `specification/constraints/invariants.md` — minor language references

**Severity: MINOR**

- Invariants 16, 17, 18, 19 reference "API layer (Go test or curl)" → "API layer (Rust test or curl)"
- No other Go-specific references in invariants

---

## Issue #8: Update `specification/constraints/non-goals.md` — Go proxy reference

**Severity: MINOR**

Non-goal #12 references "the Go proxy server" and "the Go client's `SubscribeEvents` function":
- "the Go proxy server" → "the server" or "the Rust proxy server"
- "the Go client's `SubscribeEvents` function" — this refers to the upstream CXDB Go client library, not this application. Clarify that this is an upstream reference, not a reference to this application's implementation.

---

## Issue #9: Update `specification/contracts/cxdb-upstream.md` — minor internal references

**Severity: MINOR**

This file describes the upstream CXDB API contract. Most Go references are about CXDB's own codebase or the CXDB Go client library — those are external and should not change. However:

- Any reference to "the Go server" or "the Go proxy" that refers to THIS application must be updated to "the server" or "the Rust server"
- References to CXDB's own Go client (`clients/go/`) are external descriptions of upstream behavior and remain unchanged

---

## Issue #10: Update pipeline tooling references

**Severity: MAJOR**

Wherever the specification references factory pipeline tool gates or validation commands, update:

- `go vet ./...` → `cargo clippy -- -D warnings`
- `go test ./...` → `cargo test`
- `go build ./...` → `cargo build`
- Any `script/smoke-test-suite-fast` or `script/smoke-test-suite-slow` commands must reference the Makefile targets (`make test`, `make test-browser`)

---

## Issue #11: Adopt `cxdb` repo layout — `server/` subdirectory with workspace Cargo.toml

**Severity: CRITICAL**

The existing Go project uses a `ui/` directory containing `main.go`, `main_test.go`, `go.mod`, and `index.html`. This is a Go convention. The Rust rewrite must follow the repo layout established by the upstream `cxdb` repository — the canonical Rust+JS project in this ecosystem.

All existing code will be deleted. The factory will create a Rust project following `cxdb`'s structural conventions. The specification must not reference `ui/` as the code directory, `main.go`, `main_test.go`, `go.mod`, or any other Go artifacts.

### Repo layout matching `cxdb` conventions

The `cxdb` repository places its Rust server in a `server/` subdirectory with a workspace `Cargo.toml` at the repo root. The CXDB Graph UI must follow this same pattern:

```
Cargo.toml                      ← workspace root: [workspace] members = ["server"]
Makefile                        ← top-level build targets (see Issue #13)
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

### `lib.rs` + `main.rs` separation (cxdb pattern)

The `cxdb` server uses a critical pattern: `lib.rs` declares all public modules, and `main.rs` is a thin binary entry point that imports from the library crate. This separation is required because:

1. **Testability.** Integration tests in `tests/` can only import the library crate (`use cxdb_graph_ui::*`), not the binary. Without `lib.rs`, integration tests cannot access any server internals.
2. **Consistency.** This is the standard Cargo convention for binary crates that need both a runnable binary and a testable library surface.

**`src/lib.rs`** must declare all modules:
```rust
pub mod config;
pub mod cxdb_proxy;
pub mod dot_parser;
pub mod error;
pub mod server;
```

**`src/main.rs`** imports from the library crate and runs the server. It should be a thin entry point — CLI parsing, config construction, server startup, and graceful shutdown. No business logic.

### Workspace `Cargo.toml` at repo root

Following `cxdb`'s pattern, a workspace `Cargo.toml` at the repo root declares the `server` member:

```toml
[workspace]
resolver = "2"
members = ["server"]
```

This allows `cargo build` / `cargo test` from the repo root to work, while keeping the server crate self-contained in `server/`.

### Module organization conventions (cxdb pattern)

Following `cxdb`'s conventions:
- Simple modules are single files (e.g., `error.rs`, `config.rs`)
- Complex modules that need internal submodules use the subdirectory + `mod.rs` pattern (e.g., `dot_parser/mod.rs` if it grows to need submodules like `dot_parser/lexer.rs`)
- Each module subdirectory may contain a `README.md` explaining its design (as `cxdb` does for `cql/`, `protocol/`, etc.)

### Shared state pattern (cxdb pattern)

`cxdb` passes shared state through `Arc<RwLock<>>` and `Arc<Mutex<>>` wrappers. If the graph-ui server needs shared state (e.g., parsed DOT file cache, configuration), it should follow the same pattern rather than inventing an alternative.

### Key conventions

- `server/src/` for all application source — Cargo default, non-negotiable
- `server/tests/` for integration tests (tests that exercise the public API or the running server)
- Unit tests in `#[cfg(test)] mod tests` blocks within each `src/*.rs` module
- `server/assets/` for static files embedded at compile time — keeps `src/` clean
- `server/Cargo.toml` defines the crate; workspace `Cargo.toml` at repo root
- `server/Cargo.lock` committed to version control (this is a binary/application, not a library)

**This layout is prescriptive for directory names (`server/`, `src/`, `tests/`, `Cargo.toml`, `lib.rs`) but illustrative for module decomposition.** The factory may split or merge modules (e.g., combine `server.rs` and `cxdb_proxy.rs`, or split `dot_parser.rs` into submodules) as long as the result follows Cargo conventions and meets all specification requirements. The non-negotiable structural requirements are:
1. Rust code lives in `server/` (not `ui/` or repo root), matching `cxdb`'s layout
2. `lib.rs` declares all public modules; `main.rs` is a thin entry point
3. `error.rs` (or an equivalent module) defines the unified error type
4. `server/Cargo.toml` includes `[lints.clippy]` ROP enforcement
5. `index.html` is embedded at compile time from `server/assets/`
6. Workspace `Cargo.toml` at repo root with `resolver = "2"`

### Specification file updates for project layout

Every specification file that references the old `ui/` directory or Go file paths must be updated:
- `ui/main.go` → `server/src/main.rs`
- `ui/main_test.go` → `#[cfg(test)]` blocks in `server/src/*.rs` or `server/tests/*.rs`
- `ui/go.mod` → `server/Cargo.toml`
- `ui/index.html` → `server/assets/index.html`
- "lives in `ui/` alongside `main.go`" → "lives in the `server/` crate"
- "`go run ui/main.go`" → "`cargo run`" (from `server/`) or `make run`

---

## Issue #12: Enforce idiomatic Rust beyond ROP

**Severity: MAJOR**

The ROP constraint (Issue #1) covers error handling. The specification should also enforce broader Rust idioms to prevent the factory from writing Go-in-Rust. Add to the constraints (either in the ROP file or a separate `rust-idioms.md`):

**Naming conventions:**
- Functions, methods, variables, modules: `snake_case`
- Types, traits, enums: `CamelCase`
- Constants and statics: `SCREAMING_SNAKE_CASE`
- Enforced by `cargo fmt` and Clippy's naming lints

**Formatting:**
- `cargo fmt --check` must pass. No manual formatting decisions — `rustfmt` is authoritative.
- Add to the pipeline as a tool gate alongside `cargo clippy`.

**Dependency management:**
- All dependencies declared in `server/Cargo.toml` with minimum version constraints
- `server/Cargo.lock` committed to version control
- No vendored dependencies unless required for offline builds (not applicable here)

**Async conventions:**
- All I/O-bound operations (HTTP handlers, file reads for DOT serving, CXDB proxy requests) are async
- `tokio` is the async runtime
- `axum` handlers are async functions returning `impl IntoResponse`
- No `block_on` or synchronous I/O inside async contexts

**Serialization:**
- JSON serialization/deserialization via `serde` and `serde_json`
- API response types derive `Serialize`; request types derive `Deserialize`
- No manual JSON string construction

**Testing:**
- `#[cfg(test)]` for unit test modules within source files
- `server/tests/` directory for integration tests
- `#[tokio::test]` for async test functions
- Feature-gated browser tests via `#[cfg(feature = "browser")]`
- Integration tests use `tempfile::tempdir()` for filesystem isolation (cxdb pattern)

---

## Issue #13: Add a Makefile with standard targets (cxdb convention)

**Severity: MAJOR**

The `cxdb` repository uses a top-level `Makefile` as the canonical entry point for all build, test, and development operations. The CXDB Graph UI must follow this convention. Developers working across both repos should find the same target names with the same semantics.

### Required Makefile targets

The following targets must be defined, matching `cxdb`'s naming conventions:

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

### Why this matters

- **Discoverability.** `make` + tab completion shows all available operations. New contributors don't need to learn Cargo flags.
- **Consistency.** `make precommit` in `cxdb-graph-ui` does the same thing as `make precommit` in `cxdb` — format check, Clippy, test.
- **Pipeline integration.** Factory pipeline tool gates reference Makefile targets, not raw Cargo commands. This decouples the pipeline from Cargo-specific flag details.
- **Abstraction.** The `server/` subdirectory layout means raw `cargo` commands need `cd server &&` or `--manifest-path`. The Makefile hides this.

---

## Issue #14: Add CI workflow for Rust (cxdb convention)

**Severity: MAJOR**

The `cxdb` repository uses GitHub Actions CI workflows that trigger on push/PR to `main`. The CXDB Graph UI must add an equivalent Rust CI workflow following the same structure.

### Required workflow: `.github/workflows/rust.yml`

The workflow must run on push and PR to `main`, and include these jobs (matching `cxdb`'s `rust.yml`):

1. **Build** — `cargo build` (from `server/`)
2. **Test** — `cargo test` (from `server/`)
3. **Clippy** — `cargo clippy -- -D warnings` (from `server/`, enforces ROP lints)
4. **Format** — `cargo fmt --check` (from `server/`)

All four gates must pass. A failure in any gate blocks merge.

### Relationship to Makefile

The CI workflow may call Makefile targets (`make build`, `make test`, etc.) or run raw Cargo commands. Either approach is acceptable as long as the gates match the `precommit` targets exactly.

---

## Issue #15: Integration test conventions (cxdb pattern)

**Severity: MAJOR**

Integration tests must follow `cxdb`'s established patterns:

### Test file organization

Integration tests live in `server/tests/*.rs`. Each file is a separate test binary compiled by Cargo. Following `cxdb`'s convention:

- `server/tests/integration.rs` — end-to-end server tests (start server, make HTTP requests, verify responses)
- `server/tests/dot_parser.rs` — DOT parsing integration tests with real `.dot` fixture files
- `server/tests/browser.rs` — browser smoke tests (feature-gated)

### Test isolation (cxdb pattern)

- Use `tempfile::tempdir()` for any test that needs filesystem state (DOT file directories, temporary configs). This is `cxdb`'s standard pattern — no test writes to fixed paths.
- Add `tempfile` as a `[dev-dependencies]` entry in `server/Cargo.toml`.
- Each test function creates its own isolated directory. No shared mutable state between tests.

### Import pattern

Integration tests import from the library crate:
```rust
use cxdb_graph_ui::server::build_router;
use cxdb_graph_ui::config::Config;
use cxdb_graph_ui::error::AppResult;
```

This is why the `lib.rs` + `main.rs` separation (Issue #11) is non-negotiable — without it, integration tests cannot import server internals.

---

## Issue #16: Configuration pattern (cxdb alignment)

**Severity: MINOR**

The `cxdb` server reads configuration from environment variables via `Config::from_env()`. The CXDB Graph UI currently uses CLI arguments (`--dot`, `--cxdb`, `--port`). CLI arguments are appropriate for this application (it's a developer tool, not a long-running service), but the config struct pattern should match:

- Define a `Config` struct in `server/src/config.rs`
- Use `clap` derive macros to parse CLI arguments into the struct
- Pass the `Config` struct into the server builder — do not scatter CLI argument access throughout the codebase
- The `Config` struct should be the single source of truth for all runtime configuration

This ensures the same architectural separation `cxdb` achieves with `Config::from_env()`: configuration is parsed once at startup and threaded through as a typed struct, not accessed ad-hoc.

---

## Relationship to Other Critiques

- **v58** (failed holdout scenarios) and **v59** (browser smoke tests): These remain valid. Browser integration tests and holdout scenario validation apply regardless of the server implementation language.
