# Railway-Oriented Programming Requirements

All Rust code in the server crate must follow railway-oriented programming (ROP) patterns via `Result<T, E>`. These requirements are enforced at compile time via Clippy lints and at review time via code quality gates.

## 1. All fallible operations must return `Result<T, E>`

Every function that can fail — I/O, parsing, network requests, CLI argument validation, DOT parsing, CXDB proxy operations — must return `Result`. No function may silently swallow errors or use `Option` where `Result` is semantically correct.

## 2. Error propagation via the `?` operator

The `?` operator is the primary mechanism for propagating errors up the call stack. This gives railway-oriented semantics: each `?` is a potential branch to the error track. Combinator-style chaining (`.map()`, `.and_then()`, `.map_err()`) is permitted where it improves readability but is not required over `?`.

## 3. A unified application error type

Define an `AppError` enum (or equivalent) using `thiserror` for all application-level errors. The enum must have variants covering: DOT parse errors, file I/O errors, CXDB proxy errors, CLI validation errors, HTTP handler errors, and embedding/asset errors. Each variant must carry enough context for actionable error messages. Implement `From` conversions for upstream error types (`std::io::Error`, `hyper::Error`, etc.) so that `?` works transparently across error boundaries. This follows the same pattern as `cxdb`'s `StoreError` enum in `server/src/error.rs`.

## 4. A type alias `AppResult<T> = Result<T, AppError>`

All application functions that can fail should return `AppResult<T>` for consistency. This mirrors `cxdb`'s `pub type Result<T> = std::result::Result<T, StoreError>` pattern.

## 5. No `unwrap()` or `expect()` in non-test code

These methods panic on failure, breaking the railway pattern. They are permitted only in test code (`#[cfg(test)]` modules) and in `main()` for top-level fatal errors where the program should exit. Enforced via Clippy lints.

## 6. No `panic!()` in non-test code

Explicit panics are forbidden outside test modules. Enforced via Clippy lints.

## 7. Clippy lint enforcement

The following lints must be set to `deny` in the server crate's `Cargo.toml` under `[lints.clippy]`:

```toml
[lints.clippy]
unwrap_used = "deny"
expect_used = "deny"
panic = "deny"
unwrap_in_result = "deny"
```

These lints are enforced at compile time. Code that uses `unwrap()`, `expect()`, or `panic!()` outside of test modules will fail the `cargo clippy` gate.

## 8. HTTP handlers must not panic

All HTTP request handlers must return structured error responses (appropriate HTTP status codes with JSON error bodies) rather than panicking. A handler that encounters an error must propagate it via `Result` to an error-handling layer that maps `AppError` variants to HTTP status codes — the same pattern `cxdb` uses to map `StoreError` variants to 404/422/500.

## 9. Graceful error propagation in the CXDB proxy

Proxy errors (upstream unreachable, timeout, malformed response) must be caught and returned as HTTP 502 with a descriptive error body, not as panics or unwrapped connection errors.

## 10. DOT parsing errors must be structured

Parse failures must return typed error variants (e.g., `AppError::DotParse { source, line, detail }`) that carry enough context for the 400 JSON error response specified in the server API contract.

## Rust Idioms

Beyond ROP, the following Rust idioms are enforced:

### Naming conventions

- Functions, methods, variables, modules: `snake_case`
- Types, traits, enums: `CamelCase`
- Constants and statics: `SCREAMING_SNAKE_CASE`
- Enforced by `cargo fmt` and Clippy's naming lints

### Formatting

- `cargo fmt --check` must pass. No manual formatting decisions — `rustfmt` is authoritative.
- Added to the pipeline as a tool gate alongside `cargo clippy`.

### Dependency management

- All dependencies declared in `server/Cargo.toml` with minimum version constraints
- `server/Cargo.lock` committed to version control
- No vendored dependencies unless required for offline builds (not applicable here)

### Async conventions

- All I/O-bound operations (HTTP handlers, file reads for DOT serving, CXDB proxy requests) are async
- `tokio` is the async runtime
- `axum` handlers are async functions returning `impl IntoResponse`
- No `block_on` or synchronous I/O inside async contexts

### Serialization

- JSON serialization/deserialization via `serde` and `serde_json`
- API response types derive `Serialize`; request types derive `Deserialize`
- No manual JSON string construction

### Testing

- `#[cfg(test)]` for unit test modules within source files
- `server/tests/` directory for integration tests
- `#[tokio::test]` for async test functions
- Feature-gated browser tests via `#[cfg(feature = "browser")]`
- Integration tests use `tempfile::tempdir()` for filesystem isolation (cxdb pattern)
