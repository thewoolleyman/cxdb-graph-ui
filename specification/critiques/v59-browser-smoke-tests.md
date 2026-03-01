# Critique v59 — Missing Browser Smoke Tests in Automated Pipeline

**Author:** browser-smoke-tests
**Date:** 2026-02-28

## Severity: MAJOR

## Summary

The test pyramid has a structural gap: no automated test verifies that the application actually loads and renders in a browser. The three existing testing layers (Section 12) cover server logic (Go unit tests), client logic (JS unit tests), and visual/interaction behavior (Playwright holdout scenarios) — but none of them run as part of the pipeline's automated gates. The Playwright tests in 12.3 are executed via a manual skill invocation after the pipeline completes, not during it.

This gap was exposed in practice: the v58 critique identified a broken msgpack CDN URL (`@msgpack/msgpack@3.0.0-beta2` returns 404 from jsdelivr). The pipeline ran successfully — `go test` passed, `review_final` passed — yet the application is fundamentally broken. The `<script type="module">` fails to execute because a static `import` returns 404, which means Graphviz WASM never loads, and the user sees "Loading Graphviz..." forever.

No pipeline gate catches this because no gate starts the server and loads the page in a browser.

## Root Cause

Section 12 defines three testing layers but none of them occupy the middle of the test pyramid for browser rendering:

- **12.1 (Go unit tests):** "Must run without a live CXDB instance or browser." Correct for unit tests, but means they cannot catch frontend failures.
- **12.2 (JS unit tests):** "Must run without a live server, browser, or CXDB instance." Same — tests logic extraction but not actual page rendering.
- **12.3 (Playwright UI tests):** These *would* catch it, but they're defined as a skill-based verification step run after the pipeline, not as an automated test suite the pipeline gates execute.

The result: the pipeline has no gate that answers the question "does the app actually load?"

## Recommended Fix

Add a new testing layer to Section 12 — **Browser Integration Tests** — with the following properties:

1. **Tooling:** `chromedp` (pure Go, headless Chrome via DevTools Protocol). This keeps the test within `go test` and requires no Node.js or external test runner.

2. **Build tag isolation:** Tests use `//go:build browser` so that `go test ./...` (the fast unit test suite) is unaffected. Browser tests run via `go test -tags browser -count=1 -timeout 120s ./ui/...`.

3. **In-process server:** Tests start the real Go server on a random port (`:0` or `httptest.NewServer`), eliminating external process management.

4. **Minimum required assertions:**
   - The page loads without JavaScript errors that block module execution
   - Graphviz WASM initializes (the "Loading Graphviz..." message disappears)
   - An SVG element is present in the DOM containing expected node IDs from the fixture DOT file
   - Pipeline tabs render with correct graph IDs
   - Clicking a node opens the detail panel

5. **Pipeline integration:** A dedicated pipeline gate (e.g., `verify_browser`) runs the browser test command after `verify_tests`. This keeps the fast unit test loop clean while ensuring browser rendering is verified before `review_final`.

6. **CDN dependency validation:** Because the tests load the actual `index.html` with its CDN imports, any broken CDN URL will cause the module to fail to load, which will cause the SVG assertion to timeout and fail. This directly prevents the class of bug seen in v58.

## Section 12.4 Update

The testing layer boundaries table should add a row:

| Scenario Category | Testing Layer |
|---|---|
| Application loads and renders (CDN deps, WASM init, SVG output) | Browser integration (new layer) |

## What This Does NOT Replace

- Playwright holdout scenarios remain the top-of-pyramid verification for detailed interaction behavior, CXDB mock scenarios, and visual correctness.
- Go unit tests remain the fast feedback loop for server logic.
- JS unit tests remain the coverage layer for client-side state machine logic.

The browser integration tests fill the specific gap of "does the assembled application actually work when loaded in a real browser" — the smoke test that should be the minimum bar before any pipeline run is considered successful.
