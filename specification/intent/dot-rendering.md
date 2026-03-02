## 4. DOT Rendering

### 4.1 Graphviz WASM

The `@hpcc-js/wasm-graphviz` package is installed via pnpm and imported as a standard TypeScript module:

```typescript
import { Graphviz } from "@hpcc-js/wasm-graphviz";
const gv = await Graphviz.load();
const svg = gv.layout(dotString, "svg", "dot");
```

This library compiles Graphviz to WebAssembly and exposes a `Graphviz` named export with TypeScript type definitions. Vite handles bundling and WASM asset loading. The UI calls `gv.layout(dotString, "svg", "dot")` with the raw DOT file content fetched from `/dots/{name}`. The resulting SVG is injected into the main content area via the `GraphViewer` component.

If the WASM module fails to load (e.g., corrupted build artifact, browser incompatibility), the graph area displays an error message. The rest of the UI (tabs, connection indicator) still renders — the Graphviz initialization is isolated in the `useGraphviz` hook and its failure does not prevent other React components from mounting.

### 4.1.1 Browser Dependencies

The frontend has two npm dependencies for browser-side functionality, both installed via pnpm and bundled by Vite:

1. **Graphviz WASM** — `@hpcc-js/wasm-graphviz` (pinned version in `package.json`). Used for DOT-to-SVG rendering. Imported as a standard ES module with full TypeScript types.

2. **Msgpack decoder** — `@msgpack/msgpack` (pinned version in `package.json`). Used exclusively by `decodeFirstTurn` (Section 5.2) to extract `graph_name` and `run_id` from the raw msgpack payload of `RunStarted` turns fetched with `view=raw`. Not used during regular turn polling (`view=typed`), which returns pre-decoded JSON. The expected usage:

```typescript
import { decode } from "@msgpack/msgpack";
const payload = decode(uint8ArrayBytes);
```

**Graceful degradation for msgpack.** Although both dependencies are now bundled (eliminating CDN failure modes), the msgpack decoder should still be loaded lazily via dynamic `import()` in the `decodeFirstTurn` code path. If the WASM module for msgpack fails to initialize, `decodeFirstTurn` returns `null` for the affected context, and pipeline discovery falls back to retrying on the next poll cycle. DOT rendering and the rest of the UI are unaffected.

**Base64 decoding** uses the browser's built-in `atob()` function combined with a `Uint8Array` conversion — no additional library is needed:

```typescript
function base64ToBytes(b64: string): Uint8Array {
    const binary = atob(b64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
}
```

No other npm packages are required for browser-side functionality. All other functionality (DOM manipulation, fetch, SVG interaction) uses browser built-in APIs.

### 4.2 SVG Node Identification

Graphviz SVG output wraps each node in a predictable structure:

```xml
<g id="node1" class="node">
  <title>implement</title>
  <polygon points="..." fill="..." stroke="..."/>
  <text>implement</text>
</g>
```

The `<title>` element contains the DOT node ID. This is the key used to match CXDB turn data to SVG elements.

**CXDB `node_id` matching assumption.** The UI assumes that `turn.data.node_id` values from CXDB are already normalized — i.e., they match the normalized DOT node IDs produced by the server's `/nodes` endpoint and the SVG `<title>` text. No additional normalization (unquoting, unescaping, trimming) is applied to CXDB `node_id` values before comparison. This assumption holds for Kilroy-generated CXDB data because Kilroy's DOT parser normalizes node IDs during parsing (`dot/parser.go`), stores them as `model.Node.ID`, and passes `node.ID` directly to CXDB event functions (`cxdb_events.go`). The CXDB `node_id` is therefore already the normalized form. Non-Kilroy pipelines that emit raw (un-normalized) DOT identifiers as CXDB `node_id` values (e.g., including outer quotes or escape sequences) would not match. Supporting such pipelines would require normalizing CXDB `node_id` values, which is out of scope for the initial implementation.

**Matching algorithm:**

```
STATUS_CLASSES = ["node-pending", "node-running", "node-complete", "node-error", "node-stale"]

FOR EACH g IN svg.querySelectorAll('g.node'):
    nodeId = g.querySelector('title').textContent.trim()
    status = nodeStatusMap[nodeId] OR "pending"
    g.setAttribute('data-status', status)
    g.classList.remove(...STATUS_CLASSES)
    g.classList.add('node-' + status)
```

### 4.3 Edge Identification

Edges follow a similar structure:

```xml
<g id="edge1" class="edge">
  <title>implement&#45;&gt;check_implement</title>
  <path d="..."/>
</g>
```

The title contains `source->target` with HTML entity encoding for `->` (`&#45;&gt;`).

### 4.4 Pipeline Tabs

When multiple DOT files are provided via `--dot`, the UI renders a tab bar. Each tab is labeled with the DOT file's graph ID or the filename as a fallback.

**Graph ID extraction.** The browser extracts the graph ID from the DOT source when the file is first fetched, using a regex pattern that handles both `digraph` and `graph` keywords, optional `strict` prefix, and both quoted and unquoted names: `/^\s*(strict\s+)?(di)?graph\s+("(?:[^"\\]|\\.)*"|\w+)/m`. The `strict` keyword prefix, if present, is consumed but does not affect the extracted ID. If the name is quoted, the UI unquotes it (strips the outer `"` characters), unescapes internal sequences (`\"` → `"`, `\\` → `\`), and trims leading/trailing whitespace before using it as the graph ID. This normalization is identical to node ID normalization (Section 3.2, `/dots/{name}/nodes`). If the regex does not match (e.g., anonymous graphs like `digraph { ... }`), the tab falls back to the base filename. However, the server rejects anonymous graphs at startup (see `specification/contracts/server-api.md`), so in normal operation the regex always matches. The filename fallback exists only for defensive robustness if the browser-side regex encounters an edge case the server's identical regex did not. Tabs initially display filenames (from the `/api/dots` response) and update to graph IDs as each DOT file is fetched and parsed. Pipeline discovery in Section 5.2 matches `RunStarted.data.graph_name` against the normalized (unquoted, unescaped) graph ID.

**HTML escaping.** Tab labels (whether graph IDs or filenames) must be rendered as text-only — via `textContent` assignment or explicit HTML entity escaping (`<` → `&lt;`, `>` → `&gt;`, `&` → `&amp;`, `"` → `&quot;`). Graph IDs are extracted from user-provided DOT files and may contain characters like `<`, `&`, or `"`. Rendering via `innerHTML` would allow HTML injection in the tab bar. This matches the detail panel escaping policy (Section 7.1).

Switching tabs fetches the DOT file fresh and re-renders the SVG. On every tab switch (or any event that refetches a DOT file), the UI also refetches `GET /dots/{name}/nodes` and `GET /dots/{name}/edges` to refresh cached node/edge metadata and updates `dotNodeIds` for that pipeline. This ensures that DOT file regeneration (new nodes, removed nodes, changed prompts, updated edge labels) is reflected in the status overlay, detail panel, and human-gate choices — not just the SVG rendering. When the node list changes, new nodes are initialized as "pending" in the per-context status maps, and removed nodes are dropped from the maps. If a cached merged status map exists for the newly selected pipeline (computed by the polling loop — Section 6.1, step 6, which merges status maps for all loaded pipelines on every poll cycle), it is immediately reapplied to the new SVG (after reconciling with the refreshed `dotNodeIds`). Otherwise, all nodes start as pending. The next poll cycle refreshes the status with live data. This avoids a gray flash when switching between tabs for pipelines that have already been polled.

**Tab-switch error handling.** If the `/dots/{name}/nodes` fetch fails during a tab switch — whether 400 (DOT parse error), 404, 500, or network error — the browser logs a warning and retains the previous `dotNodeIds` for that pipeline (or falls back to an empty set if no previous data exists). This ensures that cached status maps are not discarded spuriously due to transient errors. If the `/dots/{name}/edges` fetch fails, the browser retains the previous edge list for that pipeline (or uses an empty list if none exists), keeping the rest of the detail panel functional. These failure policies mirror the initialization prefetch rules (Section 4.5, Step 4) and align with the graceful-degradation principle (Section 1.2). The DOT file fetch itself (for SVG rendering) is handled independently — a DOT fetch failure displays the Graphviz error in the graph area but does not affect the cached status overlay.

### 4.5 Initialization Sequence

When the browser loads `index.html`, the following sequence executes:

1. **Load Graphviz WASM** — Initialize `@hpcc-js/wasm-graphviz` (bundled via Vite). During loading, the graph area shows "Loading Graphviz...".
2. **Fetch DOT file list** — `GET /api/dots` returns available DOT filenames (as a JSON object with a `dots` array). Build the tab bar.
3. **Fetch CXDB instance list** — `GET /api/cxdb/instances` returns configured CXDB URLs.
4. **Prefetch node IDs and edges for all pipelines** — For every DOT filename returned by `/api/dots`, fetch `GET /dots/{name}/nodes` to obtain `dotNodeIds` and `GET /dots/{name}/edges` to obtain the edge list for each pipeline. The `/nodes` prefetch ensures that background polling (step 6) can compute per-context status maps for all pipelines from the first poll cycle, not just the active tab. Without this, the holdout scenario "Switch between pipeline tabs" (which expects cached status to be immediately reapplied with no gray flash) cannot be satisfied. The `/edges` prefetch ensures that human gate choices (derived from outgoing edge labels — Section 7.1) are available for the initially rendered pipeline without requiring a tab switch. Without this, clicking a human gate node on the first pipeline would show no choices until the user switches away and back. **Error handling:** If any `/nodes` prefetch fails — whether 400 (DOT parse error), 404 (DOT file removed between `/api/dots` and `/nodes`), 500 (internal server error), or network error — the browser logs a warning and proceeds with an empty `dotNodeIds` set for that pipeline. If any `/edges` prefetch fails, the browser logs a warning and proceeds with an empty edge list for that pipeline. A failed prefetch must not block steps 5 or 6. The active tab still renders its SVG, and polling starts for all pipelines. The affected pipeline will have no status overlay (for `/nodes` failures) or no human gate choices (for `/edges` failures) until the next tab switch triggers a fresh fetch.
5. **Render first pipeline** — Fetch the first DOT file via `GET /dots/{name}`, render it as SVG.
6. **Start polling** — Trigger the first CXDB poll immediately (t=0). After each poll completes, schedule the next poll 3 seconds later via `setTimeout`. The first poll triggers pipeline discovery for all contexts.

Steps 2 and 3 run in parallel. Steps 4 and 5 require steps 1 and 2 to complete. Step 4 fetches node IDs and edges for all pipelines in parallel (both `/nodes` and `/edges` for each pipeline can be fetched concurrently). Step 5 may run concurrently with step 4's requests for non-first pipelines. Step 6 requires steps 3 and 4 to complete but does not block on step 5.
