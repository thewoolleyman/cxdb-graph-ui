# CXDB Graph UI Spec — Critique v53 (sonnet)

**Critic:** sonnet (claude-sonnet-4-6)
**Date:** 2026-02-25

## Prior Context

The v52 cycle addressed two issues from the codex critic: (1) a cross-instance active-run selection bug where `context_id` comparison across CXDB instances with independent counters could select an old run on a high-counter instance over a newer run on a low-counter instance — fixed by switching to `run_id` ULID lexicographic comparison; and (2) a prose/pseudocode contradiction where the "CQL discovery limitation" paragraph described the old behavior of only merging supplemental contexts when CQL returned empty, while the pseudocode correctly performed dedup-based merging regardless of CQL result count — fixed by rewriting the prose. The v52-sonnet critique confirmed no MVP-blocking issues. The task for this critique is to identify only issues that would block a minimal MVP from being built — one that successfully serves the page and renders a single-pipeline graph.

---

## No MVP-Blocking Issues Found

After reviewing the full specification against the holdout scenarios with focus on the minimal critical path — (1) start the Go server with `go run ui/main.go --dot <path>`, (2) serve `index.html` via `GET /`, and (3) render a single-pipeline DOT graph as SVG in the browser — no blocking issues were identified.

The critical path is completely specified:

**Go server startup:**
- File layout (`ui/main.go`, `ui/index.html`, `ui/go.mod`) is explicit in Sections 2 and 3.2.
- `//go:embed index.html` directive and its requirement that `index.html` co-locate with `main.go` in `ui/` is explicitly specified in Section 3.2, including the compile error that results from misplacement.
- The `go.mod` content (module `cxdb-graph-ui`, no `require` directives, minimum Go version matching host toolchain) is specified in Sections 2 and 3.3.
- `--dot` required flag, `--port` defaulting to 9030, `--cxdb` defaulting to `http://127.0.0.1:9010` are all specified in Section 3.1.
- Startup error on missing `--dot` is specified in Section 3.1.
- Server binding to `0.0.0.0:{port}` is specified in Section 3.3.

**Route coverage for MVP:**
- `GET /` serving embedded `index.html`: Section 3.2.
- `GET /dots/{name}` serving raw DOT content: Section 3.2.
- `GET /api/dots` returning JSON with dot filenames in flag order: Section 3.2.
- `GET /api/cxdb/instances` returning JSON with CXDB URLs: Section 3.2.
- `GET /dots/{name}/nodes` and `GET /dots/{name}/edges`: Section 3.2.
- `GET /api/cxdb/{i}/*` reverse proxy: Section 3.2.

**Browser-side rendering:**
- CDN URL for `@hpcc-js/wasm-graphviz` is pinned to `https://esm.sh/@hpcc-js/wasm-graphviz@1.6.1` with explicit rationale for why esm.sh is required (not jsDelivr): Section 4.1.
- Exact JS call `gv.layout(dotString, "svg", "dot")` is specified: Section 4.1.
- Initialization sequence steps and their dependencies are specified: Section 4.5.
- SVG node identification via `<title>` element: Section 4.2.
- CSS status classes and colors: Section 6.3.

**CXDB polling and status overlay:**
- Poll scheduling via `setTimeout` at 3 seconds: Section 6.1.
- Pipeline discovery algorithm with `fetchFirstTurn` and `decodeFirstTurn`: Section 5.5.
- `@msgpack/msgpack` CDN URL pinned at `https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/mod.min.mjs`: Section 4.1.1.
- `base64ToBytes` helper specified inline: Section 4.1.1.
- Status derivation algorithm: Section 6.2.
- Graceful degradation when CXDB is unreachable (graph renders with all nodes pending): Invariant 3, Section 9.

**DOT parser (for `/nodes` and `/edges`):**
- While the DOT parser specification is detailed, an implementer failing `/nodes` or `/edges` requests does not block graph rendering — the spec explicitly states that a 400 from `/nodes` causes the browser to proceed with an empty `dotNodeIds` set and a failed `/edges` proceeds with an empty edge list (Section 4.5, step 4 error handling). Graph rendering (step 5) runs concurrently and does not depend on `/nodes` or `/edges` succeeding. Status overlay simply skips unknown node IDs (Invariant 8). A stub implementation returning empty JSON (`{"nodes":{}}` / `[]`) would allow the MVP to serve and render the graph; full node attribute display in the detail panel and status overlay accuracy require the real parser, but neither blocks the graph render.

The specification is complete for the minimal MVP. No changes are required.
