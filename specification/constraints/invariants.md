# Invariants

**Graph Rendering**

1. **Every DOT node appears in the SVG.** The UI does not filter, hide, or skip nodes. The graph is rendered as-is by Graphviz WASM.

2. **SVG rendering is deterministic.** The same DOT input always produces the same SVG layout. Node positions are determined entirely by Graphviz, not by the UI.

3. **Graph renders without CXDB.** If CXDB is unreachable, the graph renders with all nodes in pending (gray) state. CXDB is an overlay, not a prerequisite.

4. **DOT files are never modified.** The UI reads DOT files. It never writes to them.

   **Status Overlay**

5. **Status is derived from CXDB turns, never fabricated.** A node's status is determined primarily by lifecycle turns (`StageStarted` → running, `StageFinished` with `status != "fail"` → complete, `StageFinished` with `status == "fail"` → error, terminal `StageFailed` → error). A `StageFailed` with `will_retry: true` sets status to "running" (not "error") and does not count as lifecycle resolution — the node is actively retrying. When lifecycle turns are absent, a heuristic fallback infers status from turn activity. The UI does not infer status beyond what the turn data provides.

6. **Status is mutually exclusive.** Every node has exactly one status: `pending`, `running`, `complete`, `error`, or `stale`.

7. **Polling delay is constant at 3 seconds.** After each poll cycle completes, the next poll is scheduled 3 seconds later via `setTimeout`. At most one poll cycle is in flight at any time. The delay does not back off, speed up, or adapt.

8. **Unknown node IDs in CXDB are ignored.** If a turn references a `node_id` not in the loaded DOT file, the UI silently skips it.

9. **Pipeline scoping is strict.** The status overlay only uses CXDB contexts whose `RunStarted` turn's `graph_name` matches the active DOT file's graph ID. Turns from unrelated contexts never appear. This holds across all configured CXDB instances.

10. **Context-to-pipeline mapping is immutable once resolved and never removed.** Once a context is successfully mapped to a pipeline via its `RunStarted` turn (or confirmed as non-Kilroy with a `null` mapping), the mapping is never re-evaluated or deleted. The `RunStarted` turn does not change. Mappings are keyed by `(cxdb_index, context_id)`. Contexts whose discovery failed due to transient errors, and empty contexts (no turns yet), are not cached and are retried on subsequent polls until classification succeeds. Old-run mappings are retained in `knownMappings` even after `resetPipelineState` clears per-context status maps, cursors, and turn caches — this prevents expensive re-discovery (`fetchFirstTurn`) for old-run contexts on every poll cycle. The `determineActiveRuns` algorithm naturally ignores old-run contexts because their `runId` does not match the current active run.

11. **CXDB instances are polled independently.** A single unreachable CXDB instance does not prevent polling of other instances. The connection indicator shows per-instance status.

    **Server**

12. **The server is stateless.** It caches nothing. Every DOT request reads from disk. Every CXDB request is proxied in real time.

13. **Only registered DOT files are servable.** The `/dots/` endpoint serves only files registered via `--dot` flags. Unregistered filenames return 404.

14. **CXDB proxy is transparent.** Requests and responses are forwarded without modification.

    **Detail Panel**

15. **Content is displayed verbatim with whitespace preserved.** Prompt text, tool commands, and CXDB output are shown as-is (with HTML escaping for XSS prevention) in containers styled with `white-space: pre-wrap`. This preserves newlines, indentation, and runs of whitespace. The UI does not summarize or reformat.

   **API Contract**

16. **`/edges` expands chain syntax.** A DOT edge chain `a -> b -> c [label="x"]` is expanded into two independent edges: `(a, b, "x")` and `(b, c, "x")`. No direct edge from `a` to `c` is emitted. Each segment inherits the label from the chain's attribute block. This invariant is verified at the API layer (Rust test or curl), not via the UI.

17. **`/edges` strips port suffixes.** Port syntax (`node_id:port` or `node_id:port:compass`) in edge endpoints is stripped: `a:out -> b:in` produces edge `{source: "a", target: "b", label: null}`. This invariant is verified at the API layer.

18. **Parse errors produce 400 with a JSON error body.** An unterminated block comment (`/*` without matching `*/`) or an unterminated string literal (`"` without a closing `"`) in a DOT file causes both `/dots/{name}/nodes` and `/dots/{name}/edges` to return HTTP 400 with a JSON body of the form `{"error": "DOT parse error: ..."}`. This invariant is verified at the API layer.

19. **Comments in DOT source are stripped before parsing; comments inside quoted strings are preserved.** A URL such as `http://example.com` inside a quoted attribute value is not treated as a line comment. This invariant is verified at the API layer.

   **Client-Side Logic**

20. **Discovery state machine behavior is verified by TypeScript unit tests, not by UI tests.** The pure logic modules in `frontend/src/lib/` (discovery, status derivation, merging, gap recovery) are directly importable by Vitest. The following client-side behaviors require direct TypeScript-level testing (mocking CXDB API responses and inspecting internal state) and cannot be reliably verified through Playwright DOM inspection alone:
    - `fetchFirstTurn` pagination and `MAX_PAGES` cap
    - `knownMappings` caching and null-entry semantics
    - `determineActiveRuns` ULID-based run selection
    - Gap recovery (`lastSeenTurnId` cursor, `MAX_GAP_PAGES` bound)
    - Error loop detection scoped per context
    - `cqlSupported` flag lifecycle (set, reset on reconnect, fallback path)
    - `NULL_TAG_BATCH_SIZE` batch limiting
    - Supplemental context list dedup merge
    - `cachedContextLists` population for liveness checks

    This invariant establishes the testing layer boundary: these behaviors belong in the Vitest unit test suite that imports the `frontend/src/lib/` modules directly, not in the Playwright UI test skill.
