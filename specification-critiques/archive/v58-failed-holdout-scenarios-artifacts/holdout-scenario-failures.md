# Holdout Scenario Failures — v58

## Blocking Defect: Broken msgpack CDN Import URL

All four tested scenarios failed due to a single blocking defect. The `<script type="module">` in `ui/index.html` (line 301) imports:

```
https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/mod.min.mjs
```

This URL returns **HTTP 404**. The file `mod.min.mjs` does not exist in the `@msgpack/msgpack@3.0.0-beta2` npm package. The available entry point in that directory is `index.mjs`, not `mod.min.mjs`.

Because this is a top-level ES module `import` statement, the 404 causes the **entire module to fail silently**. The `init()` function never executes, Graphviz WASM never loads, tabs never render, and no SVG graph is ever produced. The page is permanently stuck showing "Loading Graphviz..." with no interactivity.

### Console error observed

```
[ERROR] Failed to load resource: the server responded with a status of 404 ()
  @ https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/mod.min.mjs
```

---

## Failure 1: Render a pipeline graph on initial load

- **Section:** DOT Rendering (Batch 1)
- **Assertion that failed:** "SVG is present in the main content area with nodes and edges visible"
- **Observed:** Page shows "Loading Graphviz..." indefinitely. No SVG element in the DOM. `graph-area` contains only `<div id="graph-msg">Loading Graphviz...</div>`.
- **Screenshot:** `mvp-blocked-by-msgpack.png`

## Failure 2: Switch between pipeline tabs

- **Section:** DOT Rendering (Batch 1)
- **Assertion that failed:** "Two tabs visible"
- **Observed:** No tabs rendered in `#topbar`. The topbar shows only the "CXDB connecting..." indicator. Tab elements are never created because `init()` never runs.
- **Screenshot:** `mvp-blocked-by-msgpack.png`

## Failure 3: Tab shows graph ID from DOT declaration

- **Section:** DOT Rendering (Batch 1)
- **Assertion that failed:** "The first tab shows 'simple_pipeline'"
- **Observed:** No tabs rendered. Same root cause as above.
- **Screenshot:** `mvp-blocked-by-msgpack.png`

## Failure 4: Pipeline tab ordering matches --dot flag order

- **Section:** DOT Rendering (Batch 1)
- **Assertion that failed:** "'simple_pipeline' tab appears before 'beta_pipeline'"
- **Observed:** No tabs rendered. Same root cause as above.
- **Screenshot:** `mvp-blocked-by-msgpack.png`

---

## Suggested Fix

In `ui/index.html` line 301, change:
```javascript
import { decode } from "https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/mod.min.mjs";
```
to:
```javascript
import { decode } from "https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/index.mjs";
```
