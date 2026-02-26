# CXDB Graph UI Spec — Critique v55 (sonnet)

**Critic:** sonnet (claude-sonnet-4-6)
**Date:** 2026-02-25

## Prior Context

v54-codex found no MVP blockers. The only change from that cycle was adding a `SHOULD log a warning` note and prose extension in Section 5.5 for the `fetchFirstTurn` pagination cap scenario. The specification has been stable for several cycles.

---

## No MVP-blocking issues found

This critique was performed with a focused scope: identify only issues that would prevent a minimal MVP from being built — specifically, an implementation that can successfully serve the page and render a single-pipeline graph with status overlay.

The critical path for that MVP is:

1. `go run ui/main.go --dot <path>` starts the server (Section 3.1, 3.3)
2. Browser loads `index.html` via `GET /` (Section 3.2 — `//go:embed` directive and file layout at `ui/index.html` are clearly specified)
3. Browser fetches `/api/dots` to build the tab bar (Section 3.2)
4. Browser fetches the DOT file from `/dots/{name}` (Section 3.2)
5. Browser loads `@hpcc-js/wasm-graphviz` from the pinned CDN URL (Section 4.1 — URL, import pattern, and `gv.layout()` call are fully specified)
6. SVG is rendered into the main content area
7. Polling begins, contexts discovered, status overlay applied

All steps in this path are covered with sufficient specificity. No external packages are needed beyond the Go standard library for the server. The CDN URL and import pattern for Graphviz WASM are pinned and correct. The `//go:embed` directive and file co-location requirement (`ui/index.html` alongside `ui/main.go`) are explicitly stated. The initialization sequence (Section 4.5) specifies step ordering and parallelism clearly.

The routing conflict between `GET /api/cxdb/instances` and `GET /api/cxdb/{i}/*` is a real implementation concern (Go's standard `net/http.ServeMux` does not support path variables, so the implementer must write custom dispatch), but it is not a specification gap — an implementer with Go experience handles this routinely, and the two routes are clearly distinguished in the spec. No confusion about which requests go where.

**Conclusion:** The specification is complete and consistent for the MVP scope. No blocking issues identified.
