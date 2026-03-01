# CXDB Graph UI Spec — Critique v56 (sonnet)

**Critic:** sonnet (claude-sonnet-4-6)
**Date:** 2026-02-25

## Prior Context

v55-sonnet and v55-codex both found no MVP blockers. The specification has been stable for multiple cycles. No changes were made between v55 and v56 — the spec was unchanged.

---

## No MVP-blocking issues found

This critique was performed with a focused scope: identify only issues that would prevent a minimal MVP from being built — specifically, an implementation that can successfully serve the page and render a single-pipeline graph with status overlay.

The critical path for that MVP was examined end-to-end:

1. `go run ui/main.go --dot <path>` starts the server (Section 3.1, 3.3) — startup, argument parsing, error on missing `--dot`, and startup message are all specified.
2. Browser loads `index.html` via `GET /` (Section 3.2) — `//go:embed index.html` directive and the requirement that `index.html` reside at `ui/index.html` alongside `ui/main.go` are explicitly stated. The compile-time error for misplaced files is noted.
3. Browser fetches `/api/dots` and `/api/cxdb/instances` (Section 3.2, 4.5 step 2-3) — both endpoints are specified with response shapes.
4. Browser prefetches `/dots/{name}/nodes` and `/dots/{name}/edges` for all pipelines (Section 4.5 step 4) — prefetch is required, error handling on failure is specified.
5. Browser fetches the DOT file from `/dots/{name}` (Section 3.2) — serving, 404 for unregistered files, and fresh-read semantics are specified.
6. Browser loads `@hpcc-js/wasm-graphviz` from the pinned CDN URL (Section 4.1) — the URL, import syntax (`import { Graphviz } from "..."`), and `gv.layout(dotString, "svg", "dot")` call are all pinned and explicit.
7. SVG is injected and status overlay applied via CSS classes (Sections 4.2, 6.3) — the node matching algorithm and CSS class names/colors are specified.
8. Polling begins (Section 4.5 step 6, Section 6.1) — poll interval, discovery algorithm, and status derivation are fully specified.

All steps are covered with sufficient specificity for an implementer to build a working MVP.

**One observation (not a blocker):** Section 4.1.1 describes the msgpack library as providing "a `decode(Uint8Array)` function" but does not show the explicit import statement (e.g., `import { decode } from "..."`) the way Section 4.1 shows the full Graphviz import. An implementer can correctly infer the named export `decode` from the prose description. This is not a blocking gap — it is consistent with the library's published API and easily verified — but the explicit import form would match the level of specificity provided for Graphviz WASM. This is noted as a non-blocking observation only.

**Conclusion:** The specification is complete and consistent for the MVP scope. No blocking issues identified. The spec has been stable and thoroughly reviewed across many critique cycles, and this review confirms no new gaps have emerged.
