# CXDB Graph UI Spec — Critique v50 (sonnet)

**Critic:** sonnet (claude-sonnet-4-6)
**Date:** 2026-02-25

## Prior Context

The v49 critique (codex) identified that the null-tag backlog was only activated for the legacy CQL-fallback path, leaving CQL-enabled CXDB instances unable to rediscover completed runs after session disconnect. Both issues were applied: `supplementalNullTagCandidates` was introduced to seed the null-tag backlog from the supplemental fetch path, and a new holdout scenario was added for the CQL-empty / null-tag / post-disconnect case.

---

**Note:** Per the user's instruction, this critique focuses exclusively on issues that would block building a minimal MVP capable of serving the page and rendering a single-pipeline graph. Issues unrelated to that goal are not raised.

---

## Issue #1: `go.mod` omission blocks `go run` on modern Go

### The problem

Section 2 states: "The server uses only the standard library — no `go.mod`, no external packages. It runs with `go run main.go`."

This is incorrect for Go 1.16 and later (the current default). In module-aware mode (the default since Go 1.16), `go run ui/main.go` requires a `go.mod` file somewhere in the directory tree. Without one, Go produces a fatal error:

```
go: go.mod file not found in current directory or any parent directory;
    see 'go help modules'
```

An implementer following the spec and omitting `go.mod` will be unable to run the server at all. The fix is simple — a minimal `go.mod` requires only two lines:

```
module cxdb-graph-ui

go 1.21
```

But the spec explicitly says not to create one, which directly contradicts how modern Go works. This is a hard blocker for the MVP.

### Suggestion

Remove the "no `go.mod`" claim and specify that a minimal `go.mod` is required. The spec should state the module name (e.g., `cxdb-graph-ui` or `github.com/kilroy/cxdb-graph-ui`) and a minimum Go version. The `go.mod` file should live in the `ui/` directory alongside `main.go` (since the spec says `go run ui/main.go` and `//go:embed index.html` with `index.html` collocated with `main.go`). Alternatively, if the intention is for `ui/` to be a subdirectory of a larger monorepo that already has a `go.mod` at its root, the spec should state that explicitly. Either way, the current "no `go.mod`" claim must be corrected to unblock implementers.

=== CRITIQUE SKILL COMPLETE ===
WARNING: If you are executing this skill as part of a loop (e.g., spec:critique-revise-loop), you are NOT done. Return to the loop protocol now and execute the next step. Check the loop's exit criteria before stopping.
=== END CRITIQUE SKILL ===
