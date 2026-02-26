# CXDB Graph UI Spec — Critique v56 (sonnet) Acknowledgement

The v56-sonnet critique found no MVP-blocking issues. The critique validated the complete critical path end-to-end — server startup, `//go:embed` file layout, tab bar via `/api/dots`, DOT file fetch and Graphviz WASM rendering, status overlay polling, and CXDB discovery — and confirmed all steps are covered with sufficient specificity for an implementer to build a working MVP. One non-blocking observation was raised: Section 4.1.1 described the msgpack library as providing "a `decode(Uint8Array)` function" without showing an explicit import statement, in contrast to Section 4.1's full Graphviz import pattern. This observation was applied as a minor consistency improvement: the explicit import and usage pattern for the msgpack `decode` named export was added to Section 4.1.1. The source code of `kilroy/internal/cxdb/msgpack_encode.go` and `kilroy_registry.go` was consulted via the knowledge-graph MCP server to verify that `run_id` is tag `"1"` and `graph_name` is tag `"8"` in `RunStarted` (confirming the spec's field tag inventory is correct), and that kilroy encodes msgpack with string-form integer keys (confirming the spec's string-key decoding guidance is correct).

## No MVP-blocking issues found

**Status: Not addressed (no action required)**

The critique confirms the specification is complete and consistent for the MVP scope. All eight critical path steps are covered with sufficient specificity:

1. `go run ui/main.go --dot <path>` startup (Sections 3.1, 3.3) — specified
2. `//go:embed index.html` layout and compile-time error (Section 3.2) — specified
3. `/api/dots` and `/api/cxdb/instances` endpoints (Sections 3.2, 4.5) — specified
4. Prefetch of `/dots/{name}/nodes` and `/dots/{name}/edges` (Section 4.5 step 4) — specified
5. DOT fetch from `/dots/{name}` with fresh-read semantics (Section 3.2) — specified
6. Graphviz WASM CDN URL, import pattern, and `gv.layout()` call (Section 4.1) — pinned and explicit
7. SVG injection and status overlay CSS classes (Sections 4.2, 6.3) — specified
8. Polling interval, discovery algorithm, status derivation (Sections 4.5, 6.1) — specified

## Issue: Msgpack import pattern not shown explicitly (non-blocking observation)

**Status: Applied to specification**

The observation is valid as a consistency improvement. Section 4.1 shows the full Graphviz import and usage:
```javascript
import { Graphviz } from "https://esm.sh/@hpcc-js/wasm-graphviz@1.6.1";
```

Section 4.1.1 only described the msgpack library as providing "a `decode(Uint8Array)` function" without showing the analogous import form. An equivalent explicit import block was added to Section 4.1.1 immediately after the CDN URL:

```javascript
import { decode } from "https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/mod.min.mjs";
const payload = decode(uint8ArrayBytes);
```

The prose was updated to describe `decode` as a "named export" rather than simply a "function" to reinforce the import pattern. The kilroy source (`msgpack_encode.go`) was consulted to verify the named export convention is consistent with the library's API and the string-key encoding behavior documented in `decodeFirstTurn`.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added explicit import and usage code block for msgpack `decode` named export in Section 4.1.1; updated prose to describe it as a "named export"

## Not Addressed (Out of Scope)

- None. The critique identified no issues requiring action beyond the non-blocking observation, which was applied.
