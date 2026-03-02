# CXDB Graph UI Spec — Critique v60 (rust-rewrite) Acknowledgement

Applied all 16 issues from the Rust rewrite critique as a single coordinated revision. The specification now describes a Rust application following `cxdb` repo conventions with railway-oriented programming constraints. All Go-specific content has been replaced with idiomatic Rust equivalents across `specification/intent/`, `specification/constraints/`, `specification/contracts/`, and `holdout-scenarios/`.

## Issue #1: Create `specification/constraints/railway-oriented-programming-requirements.md`

**Status: Applied to specification**

Created the new constraint file with all 10 ROP requirements (Result types, `?` operator, AppError enum, AppResult alias, no unwrap/expect/panic in non-test code, Clippy lint enforcement, HTTP handler error handling, CXDB proxy error propagation, structured DOT parse errors). Also incorporated Issue #12's Rust idioms (naming, formatting, dependencies, async, serialization, testing) into the same file under a "Rust Idioms" section.

Changes:
- `specification/constraints/railway-oriented-programming-requirements.md`: Created with all ROP and Rust idiom requirements
- `specification/constraints/README.md`: Added row for the new file, updated testing-requirements description from "Go" to "Rust"

## Issue #2: Update `specification/intent/overview.md` — Replace Go with idiomatic Rust

**Status: Applied to specification**

Replaced "Go HTTP server" with "Rust HTTP server" in architecture section, replaced architecture diagram label "Go Server (main.go)" with "Rust Server", replaced entire "Why Go" paragraph with "Why Rust" covering memory safety, algebraic data types, and the Rust dependency set (axum, tokio, hyper, clap, thiserror). Removed go.mod/module references. Updated CXDB proxy paragraph to remove "Go" qualifier.

Changes:
- `specification/intent/overview.md`: Architecture diagram, "Why Rust" paragraph, CXDB proxy description

## Issue #3: Update `specification/intent/server.md` — Replace Go with idiomatic Rust

**Status: Applied to specification**

Replaced "Go standard library packages" with Rust crate ecosystem description. Replaced go.mod/main.go references with Cargo.toml/workspace description.

Changes:
- `specification/intent/server.md`: Section 3.2 Server Properties

## Issue #4: Update `specification/contracts/server-api.md` — Replace Go with idiomatic Rust

**Status: Applied to specification**

Updated CLI section from `go run ui/main.go` to `cargo run --` with `make run` alternative. Replaced all example commands. Replaced `//go:embed` section with `include_str!()`/`rust-embed` description. Updated `index.html` file location from `ui/` to `server/assets/`. Updated contract description in README.md from "Go server" to "Rust server".

Changes:
- `specification/contracts/server-api.md`: CLI section, examples, GET / route (embed mechanism and file location)
- `specification/contracts/README.md`: Updated "Go server" to "Rust server" in table

## Issue #5: Update `specification/constraints/testing-requirements.md` — Replace Go with idiomatic Rust

**Status: Applied to specification**

Complete rewrite of the testing requirements document. Section 12.1 now describes Rust unit tests with cargo tarpaulin/llvm-cov, `#[cfg(test)]` modules, snake_case function names, make precommit enforcement. Section 12.2 updated index.html path from `ui/` to `server/assets/`. Section 12.3 replaced chromedp with Rust browser testing crates, replaced go test commands with cargo test --features browser, replaced httptest.NewServer with tokio TcpListener + axum in-process server. Section 12.5 updated "Go tests" to "Rust tests".

Changes:
- `specification/constraints/testing-requirements.md`: Full rewrite of all sections

## Issue #6: Update `specification/constraints/definition-of-done.md` — Replace Go with idiomatic Rust

**Status: Applied to specification**

Replaced `go run` with `cargo run --` / `make run`. Replaced browser test command. Added new "Code Quality (ROP Enforcement)" section with 7 checklist items. Added new "Rust Idioms" section with 4 checklist items.

Changes:
- `specification/constraints/definition-of-done.md`: Full rewrite with Rust commands, ROP and idioms sections

## Issue #7: Update `specification/constraints/invariants.md` — minor language references

**Status: Applied to specification**

Replaced all instances of "API layer (Go test or curl)" with "API layer (Rust test or curl)" in invariants 16, 17, 18, 19.

Changes:
- `specification/constraints/invariants.md`: Four instances of "Go test" → "Rust test"

## Issue #8: Update `specification/constraints/non-goals.md` — Go proxy reference

**Status: Applied to specification**

Updated non-goal #12 to replace "the Go proxy server" and "the Go client's `SubscribeEvents` function" with language-neutral references that clarify the upstream CXDB Go client is an external dependency, not this application's implementation.

Changes:
- `specification/constraints/non-goals.md`: Non-goal #12 proxy/SSE paragraph

## Issue #9: Update `specification/contracts/cxdb-upstream.md` — minor internal references

**Status: Not addressed**

Searched for "the Go server" and "the Go proxy" references to this application in cxdb-upstream.md. Found none — all Go references in that file describe CXDB's own Go codebase or the upstream CXDB Go client library, which are external and should remain unchanged.

## Issue #10: Update pipeline tooling references

**Status: Applied to specification**

All pipeline tooling references updated as part of Issues #5 and #6. `go vet` → `cargo clippy`, `go test` → `cargo test`, `go build` → `cargo build`, script references → Makefile targets (`make test`, `make test-browser`, `make precommit`).

Changes:
- `specification/constraints/testing-requirements.md`: All tooling commands
- `specification/constraints/definition-of-done.md`: All tooling commands

## Issue #11: Adopt `cxdb` repo layout — `server/` subdirectory with workspace Cargo.toml

**Status: Applied to specification**

Added Section 3.3 "Project Layout" to server.md with the complete repo layout diagram, lib.rs + main.rs separation, workspace Cargo.toml, module organization conventions, and the 6 non-negotiable structural requirements. Updated all file path references across the specification: `ui/main.go` → `server/src/main.rs`, `ui/main_test.go` → `#[cfg(test)]` blocks, `ui/go.mod` → `server/Cargo.toml`, `ui/index.html` → `server/assets/index.html`.

Changes:
- `specification/intent/server.md`: New Section 3.3 with full layout
- `specification/contracts/server-api.md`: Updated embed location from `ui/` to `server/assets/`
- `specification/constraints/testing-requirements.md`: All file path references
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: All `go run ui/main.go` → `cargo run --`

## Issue #12: Enforce idiomatic Rust beyond ROP

**Status: Applied to specification**

Incorporated into the ROP requirements file (Issue #1) under a "Rust Idioms" section covering naming conventions, formatting, dependency management, async conventions, serialization, and testing patterns. Also added "Rust Idioms" checklist to definition-of-done.md.

Changes:
- `specification/constraints/railway-oriented-programming-requirements.md`: "Rust Idioms" section
- `specification/constraints/definition-of-done.md`: "Rust Idioms" checklist

## Issue #13: Add a Makefile with standard targets (cxdb convention)

**Status: Applied to specification**

Added Section 3.4 "Makefile" to server.md with the complete target table (build, release, test, test-browser, clippy, fmt, fmt-check, check, clean, run, precommit).

Changes:
- `specification/intent/server.md`: New Section 3.4

## Issue #14: Add CI workflow for Rust (cxdb convention)

**Status: Applied to specification**

Added Section 3.5 "CI Workflow" to server.md describing the `.github/workflows/rust.yml` requirements (build, test, clippy, format gates).

Changes:
- `specification/intent/server.md`: New Section 3.5

## Issue #15: Integration test conventions (cxdb pattern)

**Status: Applied to specification**

Incorporated into Section 3.3 (Project Layout — the repo layout shows `server/tests/` with integration.rs, dot_parser.rs, and browser.rs), the testing-requirements.md rewrite (Section 12.1 references `server/tests/` and `tempfile::tempdir()`), and the ROP requirements file's testing section (integration tests use `tempfile::tempdir()` for filesystem isolation).

Changes:
- `specification/intent/server.md`: Section 3.3 layout diagram and lib.rs explanation
- `specification/constraints/testing-requirements.md`: Section 12.1 test organization
- `specification/constraints/railway-oriented-programming-requirements.md`: Testing section

## Issue #16: Configuration pattern (cxdb alignment)

**Status: Applied to specification**

Added Config struct description to Section 3.3 of server.md, specifying the `clap` derive macro pattern and single-source-of-truth principle.

Changes:
- `specification/intent/server.md`: Section 3.3 "Configuration pattern" paragraph

## Not Addressed (Out of Scope)

- **Issue #9 (cxdb-upstream.md)**: No changes needed — all Go references in that file describe the upstream CXDB codebase, not this application.
