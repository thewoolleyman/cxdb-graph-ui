# Browser Rendering Verification

## Task

Verify that the CXDB Graph UI application actually loads and renders a visible graph in a real browser. This is a black-box smoke test: if the page loads and you can see a rendered pipeline graph with nodes and edges, it passes. This catches broken CDN URLs, WASM initialization failures, and JavaScript errors that prevent rendering.

## Context

All deterministic gates (fmt, clippy, build, tests) have passed. This stage uses the Playwright MCP browser tools to start the server, load the page, and verify that the rendered output is correct.

## Prerequisites

You have access to Playwright MCP browser tools: `browser_navigate`, `browser_snapshot`, `browser_take_screenshot`, `browser_evaluate`, `browser_click`, `browser_wait_for`, `browser_console_messages`.

## What to Do

### Step 1: Start the server

Build and start the server in the background with the fixture DOT files shipped in `holdout-scenarios/fixtures/`:

```bash
REPO=$(pwd)
cd server && cargo build --release && cd ..
./server/target/release/cxdb-graph-ui \
  --dot "$REPO/holdout-scenarios/fixtures/simple-pipeline.dot" \
  --dot "$REPO/holdout-scenarios/fixtures/multi-tab-b.dot" &
sleep 2
```

Verify the server is responding:
```bash
curl -sf http://127.0.0.1:9030/ > /dev/null
```

### Step 2: Navigate and wait for rendering

1. Navigate to `http://127.0.0.1:9030`
2. Wait up to 30 seconds for the "Loading Graphviz..." message to disappear
3. If "Loading Graphviz..." is still shown after 30 seconds, this is a **FAIL** — the WASM or a CDN dependency is broken

### Step 3: Verify the graph rendered

Take a screenshot of the page. Visually confirm:

- An SVG pipeline graph is visible (not a blank page, not an error message)
- The graph contains labeled nodes connected by edges
- The graph looks like a pipeline (directed graph flowing top-to-bottom or left-to-right)

Also use `browser_evaluate` to programmatically confirm:

```javascript
(() => {
  const svg = document.querySelector('svg');
  if (!svg) return { pass: false, reason: 'No SVG element found' };
  const nodes = svg.querySelectorAll('.node');
  const edges = svg.querySelectorAll('.edge');
  if (nodes.length === 0) return { pass: false, reason: 'SVG has no nodes' };
  if (edges.length === 0) return { pass: false, reason: 'SVG has no edges' };
  return { pass: true, nodes: nodes.length, edges: edges.length };
})()
```

**FAIL** if no graph is visible or the SVG contains no nodes/edges.

### Step 4: Verify pipeline tabs

Use `browser_evaluate` or `browser_snapshot` to check:

- At least two tabs are visible (we started with two DOT files)
- The first tab label is "simple_pipeline" (graph ID, not filename)

**FAIL** if tabs are missing or the first tab label is wrong.

### Step 5: Verify node click opens detail panel

1. Click on a node in the SVG
2. Verify the detail panel opens and shows node information (Node ID, Type)

**FAIL** if clicking a node does not open a detail panel.

### Step 6: Check for JavaScript errors

Use `browser_console_messages` with level "error" to check for JavaScript errors. CDN 404s, module load failures, and uncaught exceptions will appear here.

- A 404 on `/favicon.ico` is acceptable (ignore it)
- A 404 or error on any CDN dependency (msgpack, graphviz WASM) is a **FAIL**
- Any uncaught JavaScript error is a **FAIL**

### Step 7: Clean up

Kill the server process:
```bash
pkill -f cxdb-graph-ui 2>/dev/null || true
```

### Step 8: Report results

Write a summary of pass/fail for each check to `.ai/verify_browser.md`.

## Status Contract

Write status JSON to `$KILROY_STAGE_STATUS_PATH` (absolute path). If unavailable, use `$KILROY_STAGE_STATUS_FALLBACK_PATH`.

Success (all checks pass): `{"status":"success"}`
Failure: `{"status":"fail","failure_reason":"browser_rendering_broken","failure_signature":"<comma-separated-failed-checks>","details":"<specific failures>","failure_class":"deterministic"}`

Failure signatures use these check names: `graphviz_load`, `graph_render`, `tabs`, `node_click`, `js_errors`.

Example: `{"status":"fail","failure_reason":"browser_rendering_broken","failure_signature":"graphviz_load,graph_render","details":"Page stuck on Loading Graphviz after 30s. Console shows 404 on msgpack CDN URL.","failure_class":"deterministic"}`

Do not write nested `status.json` files after `cd`.
