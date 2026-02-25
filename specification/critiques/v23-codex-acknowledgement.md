# CXDB Graph UI Spec — Critique v23 (codex) Acknowledgement

Both issues from v23-codex have been applied to the specification. The `index.html` asset resolution strategy is now explicit (`go:embed`), and DOT parse error handling is specified for `/nodes` and `/edges` endpoints.

## Issue #1: Server does not specify how index.html is located when running from repo root

**Status: Applied to specification**

Updated Section 3.2's `GET /` route to specify that `index.html` is embedded via Go's `//go:embed` directive at compile time. This eliminates the ambiguity about runtime file resolution — `go run ui/main.go` compiles to a temp directory, so relative file paths from the source would fail. The embedded filesystem ensures the asset is always available regardless of working directory. Changed the error response from 404 to 500 (embed failure should not happen in a correctly compiled binary).

Changes:
- `specification/cxdb-graph-ui-spec.md`: Rewrote the `GET /` route description in Section 3.2 to specify `//go:embed` resolution.

## Issue #2: DOT parse failures for /nodes and /edges are not specified and can break initialization

**Status: Applied to specification**

Added error handling specifications for both `/dots/{name}/nodes` and `/dots/{name}/edges` endpoints in Section 3.2. Both endpoints now return 400 with a JSON error body (`{"error": "DOT parse error: ..."}`) when DOT syntax prevents parsing. Specified the browser's fallback behavior: a 400 from `/nodes` results in an empty `dotNodeIds` set (the SVG error from Graphviz WASM is still displayed, polling proceeds with empty status maps); a 400 from `/edges` results in an empty edge list (human gate choices unavailable). This ensures the "DOT file with syntax error" holdout scenario does not block the rest of the UI lifecycle.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added error response (400) and browser fallback behavior to the `/dots/{name}/nodes` route in Section 3.2.
- `specification/cxdb-graph-ui-spec.md`: Added error response (400) and browser fallback behavior to the `/dots/{name}/edges` route in Section 3.2.

## Not Addressed (Out of Scope)

- None. Both issues were applied.
