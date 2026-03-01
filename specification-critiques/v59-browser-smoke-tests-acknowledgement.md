# CXDB Graph UI Spec — Critique v59 (browser-smoke-tests) Acknowledgement

The critique identified a structural gap in the test pyramid: no automated pipeline gate verifies that the application loads and renders in a real browser. This was demonstrated by the v58 incident where a broken msgpack CDN URL passed all pipeline gates. A new Section 12.3 (Browser Integration Tests — Smoke Layer) was added to the specification, the existing Playwright section was renumbered to 12.4, the testing layer boundaries table was updated, and Definition of Done items for browser integration testing were added.

## Issue #1: Missing browser smoke test layer in automated pipeline

**Status: Applied to specification**

A new Section 12.3 "Browser Integration Tests — Smoke Layer" was added with the following properties as recommended:

1. **Tooling:** `chromedp` (pure Go, headless Chrome via DevTools Protocol) — keeps tests within `go test`
2. **Build tag isolation:** `//go:build browser` so `go test ./...` is unaffected
3. **In-process server:** Tests start the real Go server on a random port
4. **Minimum required assertions:** Page loads without blocking JS errors, Graphviz WASM initializes, SVG contains expected nodes, tabs render with graph IDs, node click opens detail panel
5. **Pipeline integration:** Dedicated gate (e.g., `verify_browser`) after `verify_tests`
6. **CDN dependency validation:** Broken CDN URLs cause module load failure → SVG assertion timeout

Additional changes:
- Section 12 intro updated from "three distinct testing layers" to "four distinct testing layers"
- Former Section 12.3 (Playwright) renumbered to 12.4
- Former Section 12.4 (Testing Layer Boundaries) renumbered to 12.5
- New row added to testing layer boundaries table: "Application loads and renders (CDN deps, WASM init, SVG output) | Browser integration (12.3)"
- All Playwright references in boundaries table updated from (12.3) to (12.4)
- Definition of Done: New "Testing" subsection added with browser integration test checklist items

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added Section 12.3, renumbered 12.3→12.4 and 12.4→12.5, updated boundaries table, added Definition of Done testing items

## Not Addressed (Out of Scope)

- None. The single issue was fully applied.
