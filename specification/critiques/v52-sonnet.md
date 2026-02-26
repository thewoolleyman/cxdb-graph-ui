# CXDB Graph UI Spec — Critique v52 (sonnet)

**Critic:** sonnet (claude-sonnet-4-6)
**Date:** 2026-02-25

## Prior Context

v51 addressed two MVP-blocking issues: the `index.html` co-location requirement (it must reside at `ui/index.html` alongside `ui/main.go` for `//go:embed` to resolve correctly) and the Graphviz WASM CDN URL (switched from jsDelivr's UMD bundle to the esm.sh CDN which serves a valid ES module). Additionally, v51-codex fixed the supplemental CQL merge logic and the liveness cache for mixed deployments.

---

## No MVP-Blocking Issues Found

This critique is scoped exclusively to issues that would block a minimal MVP: one that can serve the page and render a single-pipeline graph from a DOT file. After reviewing the full specification with that constraint, no remaining blocking issues were found.

The critical path for the minimal MVP is:

1. `go run ui/main.go --dot pipeline.dot` starts the Go server
2. Browser fetches `/` → serves `ui/index.html` (embedded via `//go:embed`)
3. Browser fetches `/api/dots` → returns `{ "dots": ["pipeline.dot"] }`
4. Browser fetches `/api/cxdb/instances` → returns configured CXDB URLs
5. Browser fetches `/dots/pipeline.dot/nodes` and `/dots/pipeline.dot/edges` (prefetch)
6. Browser fetches `/dots/pipeline.dot` → returns DOT file content
7. `@hpcc-js/wasm-graphviz` loaded from `https://esm.sh/@hpcc-js/wasm-graphviz@1.6.1` renders SVG
8. Polling starts; if CXDB is unreachable, all nodes display as gray (pending)

Each step in this path is now adequately specified:

- Go module structure (`ui/go.mod`, module name `cxdb-graph-ui`, stdlib-only) — specified in Sections 2 and 3.3
- `index.html` co-location at `ui/index.html` — specified in Section 3.2 after v51-sonnet fix
- All required server routes — specified in Section 3.2
- Graphviz WASM import and usage pattern — specified in Section 4.1 after v51-sonnet fix
- Initialization sequence and error handling — specified in Section 4.5
- Graceful degradation when CXDB is unreachable — specified in Invariant #3 and Section 1.2

The specification is mature and well-developed after 51 revision cycles. Within the MVP scope requested, no gaps remain that would prevent an implementing agent from producing a working result.

## Minor Observations (Non-Blocking)

The following observations do not block the MVP and are noted only for completeness. Per the critique scope, no action is required.

- **HTML structure underspecified.** The spec does not prescribe HTML element IDs or DOM structure for `index.html`. An implementing agent has full latitude here. This is appropriate for a behavioral spec and is not a gap.
- **Content-Type header not specified for `GET /`.** The Go standard library's HTTP server auto-detects `text/html` from the content of the embedded file, so this is not an issue in practice.
- **`go run ui/main.go` working directory assumption.** The command is documented as running from the repo root. The spec does not state this explicitly, but the relative path `ui/main.go` makes it self-evident.

None of these rise to the level of a blocking issue for the MVP.

=== CRITIQUE SKILL COMPLETE ===
WARNING: If you are executing this skill as part of a loop (e.g., spec:critique-revise-loop), you are NOT done. Return to the loop protocol now and execute the next step. Check the loop's exit criteria before stopping.
=== END CRITIQUE SKILL ===
