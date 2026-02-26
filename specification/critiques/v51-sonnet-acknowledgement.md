# CXDB Graph UI Spec — Critique v51 (sonnet) Acknowledgement

Both issues were valid and applied. Issue #1 identified that the spec never stated `index.html` must reside at `ui/index.html` alongside `ui/main.go`, despite the `//go:embed` directive requiring path resolution relative to the source file's package directory. An implementing agent placing `index.html` at the repository root would receive a compile error blocking the MVP entirely. The fix adds an explicit paragraph to Section 3.2. Issue #2 identified that the Graphviz WASM CDN URL (`dist/index.min.js`) is a UMD bundle, not an ES module, and would cause a `SyntaxError` when loaded via `<script type="module">` — blocking SVG rendering and the MVP. Verified by fetching the URL and confirming the file has no `export` statements. The jsDelivr `+esm` transformation does not work for this package (returns 404). The fix switches to the `esm.sh` CDN, which serves a valid ES module re-export, and adds the expected `import { Graphviz }` usage pattern.

## Issue #1: `index.html` file location never stated

**Status: Applied to specification**

The critique is correct. The `//go:embed` directive in Go resolves paths relative to the package directory of the source file containing the directive, not relative to the working directory or repository root. Since the directive is in `ui/main.go`, the embedded file must be at `ui/index.html`. This is confirmed by kilroy's use of `//go:embed` in multiple files (`internal/agent/prompt_assets.go`, `cmd/kilroy/prompt_assets.go`, `internal/attractor/engine/prompt_assets.go`) — in every case, the embedded assets are co-located with the `.go` file that embeds them. The compile error when the path doesn't resolve (`pattern index.html: no matching files found`) is fatal and would stop any implementing agent who creates `index.html` at the repository root.

The fix adds an explicit paragraph immediately after the existing `GET /` description in Section 3.2:

> **`index.html` file location.** The `//go:embed` directive resolves paths relative to the source file's package directory. Therefore `index.html` must reside at `ui/index.html`, co-located with `ui/main.go`. Placing `index.html` anywhere else (e.g., at the repository root) will cause a compile error: `pattern index.html: no matching files found`. Both files must be in the same directory (`ui/`).

Changes:
- `specification/cxdb-graph-ui-spec.md` Section 3.2 (`GET /`): Added `index.html` file location paragraph stating the co-location requirement and the compile error that results from placing it elsewhere

## Issue #2: Graphviz WASM CDN URL may not be an importable ES module

**Status: Applied to specification**

The critique is correct. The jsDelivr URL `https://cdn.jsdelivr.net/npm/@hpcc-js/wasm-graphviz@1.6.1/dist/index.min.js` was verified by fetching its content: the file begins with a jsDelivr minification skip comment and contains no `export` statements. It uses a global-assignment pattern (`s.Graphviz = y`) — a UMD/IIFE bundle, not an ES module. A `<script type="module">` import would throw `SyntaxError: The requested module does not provide an export named 'Graphviz'` immediately on page load, blocking all SVG rendering.

The jsDelivr `+esm` transformation (`dist/index.min.js+esm`) was also tested and returns HTTP 404 — jsDelivr's auto-ESM transformation does not support this package.

The `esm.sh` CDN was verified as a working alternative. `https://esm.sh/@hpcc-js/wasm-graphviz@1.6.1` returns:
```
/* esm.sh - @hpcc-js/wasm-graphviz@1.6.1 */
export * from "/@hpcc-js/wasm-graphviz@1.6.1/es2022/wasm-graphviz.mjs";
```
This is a valid ES module re-export, fully compatible with `<script type="module">` and `import { Graphviz }` named imports.

The fix:

1. Replaced the CDN URL in Section 4.1 from `https://cdn.jsdelivr.net/npm/@hpcc-js/wasm-graphviz@1.6.1/dist/index.min.js` to `https://esm.sh/@hpcc-js/wasm-graphviz@1.6.1`.
2. Added an explanation of why the jsDelivr URL is not an ES module and why the esm.sh CDN is used instead.
3. Added the expected import and usage pattern to make the correct invocation unambiguous for implementing agents:
   ```javascript
   import { Graphviz } from "https://esm.sh/@hpcc-js/wasm-graphviz@1.6.1";
   const gv = await Graphviz.load();
   const svg = gv.layout(dotString, "svg", "dot");
   ```
4. Updated Section 4.1.1's reference to "jsDelivr CDN" to "esm.sh CDN" to match.

Changes:
- `specification/cxdb-graph-ui-spec.md` Section 4.1: Replaced CDN URL with `https://esm.sh/@hpcc-js/wasm-graphviz@1.6.1`; added ESM validation note and import usage example
- `specification/cxdb-graph-ui-spec.md` Section 4.1.1: Updated Graphviz WASM bullet to reference esm.sh

## Not Addressed (Out of Scope)

- None. Both issues were valid and fully addressed.
