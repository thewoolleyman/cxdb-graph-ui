# CXDB Graph UI Spec — Critique v50 (sonnet) Acknowledgement

Issue #1 was valid and applied. The spec previously claimed "no `go.mod`, no external packages" in Section 2, which directly contradicts how Go has worked since 1.16. Verified against the kilroy project source: kilroy's own `go.mod` (`module github.com/danshapiro/kilroy`, `go 1.25`) confirms the module-aware mode requirement, and kilroy's use of `//go:embed` directives in multiple source files (`internal/agent/prompt_assets.go`, `cmd/kilroy/prompt_assets.go`, `internal/attractor/engine/prompt_assets.go`) demonstrates that `//go:embed` — the same directive the spec requires in `ui/main.go` — requires a `go.mod` in the module tree. The spec was corrected in two places: Section 2's architecture rationale and Section 3.3's server properties list.

## Issue #1: `go.mod` omission blocks `go run` on modern Go

**Status: Applied to specification**

The critique is correct. Go 1.16+ defaults to module-aware mode and will refuse to compile any `.go` file — including `go run ui/main.go` — without a `go.mod` somewhere in the directory tree. The spec's claim that "no `go.mod`" is needed was wrong and would block any implementer on a modern Go toolchain.

Verified against kilroy source:
- `/Users/cwoolley/workspace/kilroy/go.mod`: kilroy uses `module github.com/danshapiro/kilroy`, `go 1.25`, with external `require` entries. This confirms the project is entirely module-aware and that `//go:embed` (used extensively in kilroy) works within that module root.
- The `cxdb-graph-ui` server will be a standalone tool in a `ui/` directory, not a subdirectory of the kilroy module. A separate `go.mod` in `ui/` is the right approach — placing it at the kilroy repo root would require adding it as a dependency of kilroy, which is undesirable.
- The spec uses `//go:embed index.html` in `ui/main.go`, which requires the `go.mod` to be at `ui/` or a parent. Since the server is standalone, `ui/go.mod` is the appropriate location.

The module name `cxdb-graph-ui` is appropriate for a standalone tool (no import path required since no other module imports it). No `require` directives are needed since the server uses only the standard library. The minimum Go version should be specified as `go 1.21` or later (the `//go:embed` directive requires Go 1.16+; `1.21` is a reasonable baseline for a new project and matches what the critique example used).

Changes:
- `specification/cxdb-graph-ui-spec.md` Section 2 ("Why Go"): Removed "no `go.mod`" claim. Now reads: "The server uses only the standard library — no external packages. A minimal `go.mod` is required (Go 1.16+ defaults to module-aware mode and refuses to compile without one). The `go.mod` lives in `ui/` alongside `main.go` with module name `cxdb-graph-ui` and a minimum Go version matching the host toolchain (e.g., `go 1.21`). It runs with `go run ui/main.go`."
- `specification/cxdb-graph-ui-spec.md` Section 3.3 ("Server Properties"): Updated "No external dependencies" bullet to add: "A minimal `go.mod` (module `cxdb-graph-ui`, no `require` directives) lives in `ui/` alongside `main.go` — required because Go 1.16+ operates in module-aware mode by default."

## Not Addressed (Out of Scope)

- None. The single issue was valid and fully addressed.
