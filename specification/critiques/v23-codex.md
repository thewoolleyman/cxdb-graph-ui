# CXDB Graph UI Spec — Critique v23 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-24

## Prior Context

The v22 acknowledgements note that DOT regeneration now refreshes cached node/edge metadata and the server’s graph ID parsing was aligned with the browser’s normalization logic. This critique focuses on remaining implementability gaps around asset resolution and error handling paths.

---

## Issue #1: Server does not specify how index.html is located when running from repo root

### The problem

Section 3.2 says `GET /` serves `index.html` “from the same directory as `main.go`,” while the CLI examples and holdout scenarios assume `go run ui/main.go` is invoked from the repo root. In Go, the runtime does not provide a reliable “source directory” for `main.go` (the compiled binary is in a temp dir during `go run`). Without a clear rule, an implementation could incorrectly look in the current working directory, in the temp binary directory, or in the process executable path, causing `GET /` to 404 despite following the documented CLI usage.

### Suggestion

Specify the exact resolution strategy for `index.html` (and other static assets): e.g., “serve `ui/index.html` relative to the current working directory,” or “embed `index.html` via `//go:embed` and serve from the embedded filesystem.” Align the guidance with the documented invocation `go run ui/main.go` so a correct implementation is unambiguous.

---

## Issue #2: DOT parse failures for /nodes and /edges are not specified and can break initialization

### The problem

The spec defines error handling for Graphviz layout failures (Section 4.1) but does not specify how the server should respond when parsing DOT for `/dots/{name}/nodes` or `/dots/{name}/edges` fails. The initialization sequence requires prefetching `/nodes` for all pipelines before polling starts (Section 4.5). If a DOT file has invalid syntax (holdout scenario “DOT file with syntax error”), node/edge parsing may fail and the UI may never reach the polling step or may crash when metadata fetches reject. The current spec does not define whether these endpoints should return a 4xx/5xx with a payload, whether the UI should tolerate failures and continue, or how stale metadata should be handled in this error path.

### Suggestion

Define the server response for DOT parse errors on `/nodes` and `/edges` (e.g., 400 with a JSON error message) and the browser’s fallback behavior (e.g., continue rendering the SVG error message, skip metadata for that pipeline, and allow polling to proceed with an empty `dotNodeIds` set). This ensures the “DOT file with syntax error” scenario does not inadvertently block the rest of the UI lifecycle.
