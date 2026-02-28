# CXDB Graph UI Spec — Critique v58 (failed-holdout-scenarios)

**Critic:** failed-holdout-scenarios (claude-opus-4-6)
**Date:** 2026-02-28

## Prior Context

v57-sonnet raised two structural issues (API/discovery scenarios belong as invariants, not holdout scenarios; spec needs coverage requirements). Both were applied in full — Section 12 (Testing Requirements) was added, and Invariants 16–20 were added to Section 9. No MVP-blocking defects were identified in recent critique cycles.

This critique is generated from a holdout scenario test run that attempted to verify the minimal MVP (pipeline graph rendering and header/tab display). All four tested scenarios failed due to a single blocking defect in the specification's prescribed CDN URL.

---

## Issue #1: Spec prescribes a non-existent msgpack CDN URL — entire UI fails to initialize

**Severity: BLOCKING — prevents all UI functionality**

### The problem

Section 4.1.1 of the specification prescribes the following CDN URL for the msgpack decoder:

```
https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/mod.min.mjs
```

This URL returns HTTP 404. The file `mod.min.mjs` does not exist in the `@msgpack/msgpack@3.0.0-beta2` npm package. The available ES module entry point in that directory is `index.mjs`.

Because this import is a top-level ES module `import` statement in `index.html`, the 404 causes the **entire `<script type="module">` block to fail silently**. No JavaScript executes. The `init()` function never runs. Graphviz WASM never loads. Tabs are never created. No SVG graph is ever rendered. The page is permanently stuck displaying "Loading Graphviz..." with zero interactivity.

This was confirmed by Playwright testing: after navigating to `http://127.0.0.1:9030` and waiting 15+ seconds, the page showed only "Loading Graphviz..." with a "CXDB connecting..." indicator. No tabs, no SVG, no graph. The browser console showed:

```
[ERROR] Failed to load resource: the server responded with a status of 404 ()
  @ https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/mod.min.mjs
```

See `mvp-blocked-by-msgpack.png` in the artifacts directory for the screenshot.

### Failed holdout scenarios

All four MVP scenarios tested failed:

1. **Render a pipeline graph on initial load** — No SVG in DOM; `graph-area` contains only `<div id="graph-msg">Loading Graphviz...</div>`
2. **Switch between pipeline tabs** — No tabs rendered in `#topbar`
3. **Tab shows graph ID from DOT declaration** — No tabs rendered
4. **Pipeline tab ordering matches --dot flag order** — No tabs rendered

### Suggestion

In Section 4.1.1, change the prescribed msgpack CDN URL from:

```
https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/mod.min.mjs
```

to:

```
https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/index.mjs
```

Also update the corresponding `import` statement example in Section 4.1.1 from:

```javascript
import { decode } from "https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/mod.min.mjs";
```

to:

```javascript
import { decode } from "https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/index.mjs";
```

The `index.mjs` file exists in the published npm package and provides the same `decode` named export.

---

## Issue #2: Spec's graceful degradation claim contradicts actual failure mode for CDN import errors

### The problem

Section 4.1 states:

> If the CDN is unreachable, the WASM module fails to load and the graph area displays an error message. The rest of the UI (tabs, connection indicator) still renders.

This claim is false for the current architecture. Because **both** CDN dependencies (Graphviz WASM and msgpack) are imported as top-level `import` statements in a single `<script type="module">` block, a failure of **either** import prevents the entire module from executing. If the msgpack CDN is unreachable or returns 404, the Graphviz import also never completes (from the browser's perspective — the module is dead), and `init()` never runs. Tabs, the connection indicator update loop, and all other UI functionality are inside `init()`, so nothing renders.

The spec's graceful degradation guarantee ("tabs, connection indicator still renders") only holds if the failing import is isolated — but the current single-module architecture does not isolate them.

### Suggestion

Either:

**(a) Update the spec to reflect reality:** Remove or qualify the graceful degradation claim in Section 4.1. State that if any CDN import fails, the entire UI is non-functional because all imports share a single ES module scope.

Or:

**(b) Specify import isolation:** Require that CDN dependencies be loaded in separate `<script type="module">` blocks or use dynamic `import()` with try/catch, so that a failure in one dependency does not prevent other UI functionality from initializing. For example, the msgpack import could be lazy-loaded only when `decodeFirstTurn` is first called, since it is not needed for DOT rendering or tab creation.

Option (b) would actually deliver on the graceful degradation principle stated in Section 1.2: "If CXDB is unreachable, the graph is still useful for understanding pipeline structure." Currently, a broken msgpack URL (which is only needed for CXDB discovery) also breaks DOT rendering, violating this principle.
