# CXDB Graph UI Spec — Critique v51 (sonnet)

**Critic:** sonnet (claude-sonnet-4-6)
**Date:** 2026-02-25

## Prior Context

v50 fixed two issues: the `go.mod` requirement omission (sonnet) and a null-tag backlog starvation bug plus a mixed-deployment supplemental-fetch gap (codex). The spec is now highly detailed and well-developed. This critique focuses exclusively on issues that would block a minimal MVP from being built — specifically, one that can serve the page and render a single-pipeline graph.

---

## Issue #1: `index.html` file location never stated

### The problem

The spec requires `//go:embed index.html` in `ui/main.go`, and Go's embed directive resolves paths relative to the source file's package directory. Therefore `index.html` must be at `ui/index.html`. However, the spec never states this explicitly. Section 3.2 (`GET /`) says the `main.go` file embeds `index.html` at compile time, but does not say the file must be co-located at `ui/index.html`.

An implementing agent that creates `index.html` at the repository root (alongside the `specification/` directory, for example) and `ui/main.go` separately will receive a compile error:

```
pattern index.html: no matching files found
```

This blocks compilation entirely and blocks the MVP.

### Suggestion

Add an explicit statement in Section 3.2 (`GET /`) and/or Section 2 ("Why Go" / file layout) that `index.html` must reside at `ui/index.html`, co-located with `ui/main.go` and `ui/go.mod`. A sentence such as: "The `index.html` file is located at `ui/index.html` alongside `main.go`. The `//go:embed` directive resolves paths relative to the source file's directory, so `index.html` and `main.go` must be in the same directory." This is the only missing piece of file layout information that could block compilation.

---

## Issue #2: Graphviz WASM CDN URL may not be an importable ES module

### The problem

Section 4.1 specifies the CDN URL for Graphviz WASM as:

```
https://cdn.jsdelivr.net/npm/@hpcc-js/wasm-graphviz@1.6.1/dist/index.min.js
```

Section 4.1.1 states that both CDN dependencies are loaded via `<script type="module">`. For `<script type="module">` with a named export (`Graphviz.load()`), the URL must serve an ES module (ESM) file with `export` statements. The filename `dist/index.min.js` is the conventional UMD bundle entry point for npm packages — not an ES module. The ES module build for `@hpcc-js/wasm-graphviz` is typically at a different path (e.g., `dist/index.es6.min.js` or similar, or via jsDelivr's `+esm` transformation).

If an implementing agent uses the specified URL with an ES module import, the browser will throw a `SyntaxError: The requested module ... does not provide an export named 'Graphviz'` (or equivalent), and the Graphviz WASM will fail to load. This blocks SVG rendering entirely, which blocks the MVP.

The msgpack URL in Section 4.1.1 correctly uses `dist.es5+esm/mod.min.mjs` — an explicit ESM path. The Graphviz URL does not follow the same pattern.

### Suggestion

Verify and replace the Graphviz WASM CDN URL with one that is confirmed to work as an ES module import in a browser `<script type="module">` context. If jsDelivr's `+esm` auto-transformation is used, the URL would be:

```
https://cdn.jsdelivr.net/npm/@hpcc-js/wasm-graphviz@1.6.1/dist/index.min.js+esm
```

Or the correct ESM entry point for that package version should be identified and pinned. Also add a brief note showing the expected import statement, e.g.:

```javascript
import { Graphviz } from "https://cdn.jsdelivr.net/npm/...";
const gv = await Graphviz.load();
const svg = gv.layout(dotString, "svg", "dot");
```

This makes the CDN URL testable and unambiguous for an implementing agent.
