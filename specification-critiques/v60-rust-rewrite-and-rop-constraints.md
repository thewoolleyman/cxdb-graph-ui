# Critique v61 — Rewrite Application from Go to Rust with Railway-Oriented Programming Constraints

**Author:** rust-rewrite
**Date:** 2026-03-01

## Severity: CRITICAL

## Summary

The CXDB Graph UI application is being rewritten from Go to Rust. This is a full replacement — all existing code will be deleted and recreated by the factory. No existing Go code will be reused. The specification must be updated to describe a standard idiomatic Rust application from scratch, not a port of the Go codebase. All Go-specific conventions (directory layout, tooling, idioms, module structure) must be replaced with standard Rust equivalents. A new constraint document must enforce railway-oriented programming (ROP) patterns via `Result<T, E>` throughout the codebase.

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

**3. A unified application error type.** Define an `AppError` enum (or equivalent) using `thiserror` for all application-level errors. The enum must have variants covering: DOT parse errors, file I/O errors, CXDB proxy errors, CLI validation errors, HTTP handler errors, and embedding/asset errors. Each variant must carry enough context for actionable error messages. Implement `From` conversions for upstream error types (`std::io::Error`, `hyper::Error`, etc.) so that `?` works transparently across error boundaries.

**4. A type alias `AppResult<T> = Result<T, AppError>`.** All application functions that can fail should return `AppResult<T>` for consistency.

**5. No `unwrap()` or `expect()` in non-test code.** These methods panic on failure, breaking the railway pattern. They are permitted only in test code (`#[cfg(test)]` modules) and in `main()` for top-level fatal errors where the program should exit. Enforced via Clippy lints.

**6. No `panic!()` in non-test code.** Explicit panics are forbidden outside test modules. Enforced via Clippy lints.

**7. Clippy lint enforcement.** The following lints must be set to `deny` in the project's `Cargo.toml` under `[lints.clippy]`:

```toml
[lints.clippy]
unwrap_used = "deny"
expect_used = "deny"
panic = "deny"
unwrap_in_result = "deny"
```

These lints are enforced at compile time. Code that uses `unwrap()`, `expect()`, or `panic!()` outside of test modules will fail the `cargo clippy` gate.

**8. HTTP handlers must not panic.** All HTTP request handlers must return structured error responses (appropriate HTTP status codes with JSON error bodies) rather than panicking. A handler that encounters an error must propagate it via `Result` to an error-handling layer (e.g., an `axum` error handler or `IntoResponse` impl on `AppError`) that produces the correct HTTP response.

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
- Dependencies are declared in `Cargo.toml`. The application is built and run with `cargo build` / `cargo run`.

### Command references

- All instances of `go run ui/main.go` → `cargo run --`
- "A minimal `go.mod`" → remove entirely (Cargo.toml is described elsewhere)
- "module name `cxdb-graph-ui`" → remove or replace with "crate name `cxdb-graph-ui`"
- Any reference to `go.mod`, `go.sum`, Go module-aware mode → remove

---

## Issue #3: Update `specification/intent/server.md` — Replace Go with idiomatic Rust

**Severity: CRITICAL**

- "Go standard library packages. No external dependencies." → Replace with the Rust dependency set: `axum`, `tokio`, `hyper`, `clap`, `thiserror`, `serde`/`serde_json`, `tower-http` (for proxy/middleware). Rust does not have a "no external dependencies" culture — the crate ecosystem is the standard way to build applications.
- "A minimal `go.mod` (module `cxdb-graph-ui`, no `require` directives) lives in `ui/` alongside `main.go`" → "A `Cargo.toml` at the project root defines the crate name, edition, dependencies, and lint configuration."
- Remove all references to Go module-aware mode, `go.mod` location, `main.go` location.
- "The server uses only Go standard library packages" → "The server uses idiomatic Rust crates from crates.io."

---

## Issue #4: Update `specification/contracts/server-api.md` — Replace Go with idiomatic Rust

**Severity: CRITICAL**

This file has the most Go-specific content. Every reference must be updated.

### CLI section
- `go run ui/main.go [OPTIONS]` → `cargo run -- [OPTIONS]`
- All example commands: replace `go run ui/main.go` with `cargo run --`
- Startup message: "Kilroy Pipeline UI: http://127.0.0.1:9030" — unchanged (behavior, not implementation)

### Route: `GET /` — Dashboard
- "Go's `//go:embed` directive" → Rust's `include_str!()` macro or the `rust-embed` crate
- "The `main.go` file embeds `index.html` at compile time using `//go:embed index.html`, serving it from the embedded filesystem" → "The binary embeds `index.html` at compile time using `include_str!()` or `rust-embed`, serving it from the embedded data"
- "`go run ui/main.go` compiles the binary in a temp directory, so runtime file resolution relative to the source would fail" → "`include_str!()` resolves paths relative to the source file at compile time, so the embedded content is always available regardless of the working directory at runtime"
- "`ui/index.html` must reside at `ui/index.html`, co-located with `ui/main.go`" → "`index.html` must reside at a path reachable by the `include_str!()` macro relative to the embedding source file (typically at the crate root or in a known asset directory)"
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
- "The test suite belongs in `ui/main_test.go` using `package main` so unexported parsing functions are directly testable" → "Unit tests live in `#[cfg(test)] mod tests` blocks within each module, giving direct access to private functions. Integration tests live in `tests/`."
- "`script/smoke-test-suite-fast` runs `go test ./...`" → runs `cargo test` and `cargo clippy -- -D warnings`
- The Clippy gate is critical — it enforces the ROP lints from Issue #1

### Section 12.2: JavaScript Unit Tests
- If the single-HTML-file frontend approach is retained, this section stands as-is. Note that the v60 critique's concerns about JS test pipeline enforcement remain valid independently of the Rust rewrite.

### Section 12.3: Browser Integration Tests
- "`chromedp` (pure Go, headless Chrome via DevTools Protocol)" → `headless_chrome`, `chromiumoxide`, or `fantoccini` (Rust crates for headless browser testing)
- "Tests live within the Go test suite and require no Node.js" → "Tests live in the Rust integration test suite (`tests/` directory) and require no Node.js"
- "`go test -tags browser`" → `cargo test --features browser` (Cargo feature flags for test isolation)
- "`//go:build browser`" → `#[cfg(feature = "browser")]`
- "In-process server: `httptest.NewServer`" → bind to `127.0.0.1:0` with `tokio::net::TcpListener` and run the `axum` server in-process
- "`go test -tags browser -count=1 -timeout 120s ./ui/...`" → `cargo test --features browser -- --test-threads=1` (with a timeout mechanism appropriate to the test harness)
- "`script/smoke-test-suite-slow`" → update command to the Cargo equivalent

### Section 12.5: Testing Layer Boundaries
- All references to "Go tests (12.1)" → "Rust tests (12.1)"

---

## Issue #6: Update `specification/constraints/definition-of-done.md` — Replace Go with idiomatic Rust

**Severity: CRITICAL**

### Core Functionality
- "`go run ui/main.go --dot <path>` starts the server" → "`cargo run -- --dot <path>` starts the server"

### Testing
- "Browser integration tests pass (`go test -tags browser -count=1 -timeout 120s ./ui/...`)" → "`cargo test --features browser -- --test-threads=1`"

### New section: Code Quality (ROP Enforcement)
Add a new section:
- [ ] All fallible functions return `Result<T, E>` — no panics in non-test code
- [ ] `AppError` enum covers all error categories with `thiserror` derives
- [ ] `AppResult<T>` type alias is used consistently across modules
- [ ] Clippy ROP lints (`unwrap_used`, `expect_used`, `panic`, `unwrap_in_result`) are set to `deny` in `Cargo.toml`
- [ ] `cargo clippy -- -D warnings` passes with zero warnings
- [ ] `cargo fmt --check` passes (standard Rust formatting)

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
- Any `script/smoke-test-suite-fast` or `script/smoke-test-suite-slow` commands must reference Cargo

---

## Issue #11: Standard Rust project layout

**Severity: CRITICAL**

The existing Go project uses a `ui/` directory containing `main.go`, `main_test.go`, `go.mod`, and `index.html`. This is a Go convention. The Rust rewrite must use standard Rust project layout conventions.

All existing code will be deleted. The factory will create a standard Rust project at the repository root (or an appropriate subdirectory — see below). The specification must not reference `ui/` as the code directory, `main.go`, `main_test.go`, `go.mod`, or any other Go artifacts.

### Standard Rust crate layout

The specification must describe the project structure using standard Cargo conventions:

```
Cargo.toml                  ← crate manifest (name, edition, dependencies, [lints.clippy])
Cargo.lock                  ← locked dependency versions (committed to VCS)
src/
├── main.rs                 ← entry point, CLI parsing, server startup
├── error.rs                ← AppError enum, AppResult<T> type alias, From impls
├── server.rs               ← axum router, route handlers
├── dot_parser.rs           ← DOT file parsing (nodes, edges, comments, normalization)
├── cxdb_proxy.rs           ← CXDB reverse proxy handler
└── config.rs               ← CLI config struct (from clap), startup validation
tests/
├── integration.rs          ← server integration tests
└── browser.rs              ← browser smoke tests (feature-gated: #[cfg(feature = "browser")])
assets/
└── index.html              ← embedded frontend SPA
```

**Key conventions:**
- `src/` for all application source — this is Cargo's default and non-negotiable
- `tests/` for integration tests (tests that exercise the public API or the running server)
- Unit tests in `#[cfg(test)] mod tests` blocks within each `src/*.rs` module
- `assets/` (or similar) for static files embedded at compile time — keeps `src/` clean
- `Cargo.toml` at the crate root, not nested in a subdirectory
- `Cargo.lock` committed to version control (this is a binary/application, not a library)

**This layout is prescriptive for directory names (`src/`, `tests/`, `Cargo.toml`) but illustrative for module decomposition.** The factory may split or merge modules (e.g., combine `server.rs` and `cxdb_proxy.rs`, or split `dot_parser.rs` into submodules) as long as the result follows Cargo conventions and meets all specification requirements. The non-negotiable structural requirements are:
1. `src/` contains all application source (not `ui/` or any other custom name)
2. `error.rs` (or an equivalent module) defines the unified error type and is importable by all other modules
3. `Cargo.toml` is at the project root with `[lints.clippy]` ROP enforcement
4. `index.html` is embedded at compile time from a known location

### Specification file updates for project layout

Every specification file that references the old `ui/` directory or Go file paths must be updated:
- `ui/main.go` → `src/main.rs`
- `ui/main_test.go` → `#[cfg(test)]` blocks in `src/*.rs` or `tests/*.rs`
- `ui/go.mod` → `Cargo.toml`
- `ui/index.html` → `assets/index.html` (or `src/` — wherever the embed macro references)
- "lives in `ui/` alongside `main.go`" → "lives at the crate root"
- "`go run ui/main.go`" → "`cargo run`" (Cargo knows where `src/main.rs` is)

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
- All dependencies declared in `Cargo.toml` with minimum version constraints
- `Cargo.lock` committed to version control
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
- `tests/` directory for integration tests
- `#[tokio::test]` for async test functions
- Feature-gated browser tests via `#[cfg(feature = "browser")]`

---

## Relationship to Other Critiques

- **v58** (failed holdout scenarios) and **v59** (browser smoke tests): These remain valid. Browser integration tests and holdout scenario validation apply regardless of the server implementation language.
