# CXDB Graph UI Spec — Critique v23 (opus) Acknowledgement

All five issues from v23-opus have been evaluated against the CXDB server source. Four were applied to the specification with material changes to the discovery algorithm, `fetchFirstTurn`, and error heuristic documentation. One (Issue #2) was applied as a documentation note for a future optimization.

## Issue #1: CXDB has a CQL search endpoint with prefix matching (`^=`) that would solve the context discovery scalability problem — the spec does not mention it

**Status: Applied to specification**

Verified the CQL search endpoint at `GET /v1/contexts/search?q=...` in the CXDB source (`server/src/http/mod.rs` lines 388–484) and confirmed the `^=` (starts with) operator on the `tag` field (`server/src/cql/parser.rs` lines 300–327, `executor.rs` `Operator::Starts`, `indexes.rs` `lookup_tag_prefix`). Replaced the `GET /v1/contexts?limit=10000` approach with CQL search as the primary context discovery mechanism. Added fallback to the full context list when CQL returns 404 (older CXDB versions). Updated Section 5.2 to document the CQL search endpoint, its response shape (`total_count`, `elapsed_ms`, `query`, `contexts`), and the tradeoff that CQL search does not include `lineage` or `active_sessions` data. Updated the `discoverPipelines` pseudocode in Section 5.5 to use CQL search with per-instance `cqlSupported` flag. Downgraded the truncation risk paragraph to apply only to the fallback path. Updated Section 5.1 endpoint table and Section 6.1 step 1 to reference CQL search.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Rewrote Section 5.2 as "Context Discovery Endpoints" with CQL search as primary and context list as fallback.
- `specification/cxdb-graph-ui-spec.md`: Rewrote `discoverPipelines` pseudocode in Section 5.5 to use CQL search with fallback.
- `specification/cxdb-graph-ui-spec.md`: Updated Section 5.1 endpoint table to include CQL search endpoint.
- `specification/cxdb-graph-ui-spec.md`: Updated Section 6.1 step 1 to reference CQL search.

## Issue #2: The spec's `fetchFirstTurn` backward pagination is unnecessary — CXDB's context metadata cache already extracts `client_tag`, and `RunStarted` data could be cached server-side via labels

**Status: Applied to specification (as documentation note)**

Added a "Metadata labels optimization" paragraph after the caching description in Section 5.5. Documents that if Kilroy embeds `graph_name` and `run_id` in the context metadata labels (e.g., `["kilroy:graph=alpha_pipeline", "kilroy:run=01KJ7..."]`), the UI could read them from the context list response, eliminating `fetchFirstTurn` entirely. Explicitly labeled as "not required for initial implementation" — the pagination approach works correctly today. This is a Kilroy-side change, not a CXDB change.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "Metadata labels optimization" paragraph to Section 5.5.

## Issue #3: The spec does not account for CXDB's `ContextMetadataUpdated` event — `client_tag` can change after context creation

**Status: Applied to specification**

Added a "`client_tag` stability requirement" paragraph to Section 5.5's caching section. Documents the CXDB `client_tag` fallback chain (stored metadata → session tag), the failure mode when key 30 is absent (tag disappears when session disconnects), and the explicit requirement that Kilroy must embed `client_tag` in the first turn's context metadata for reliable classification. Verified the fallback chain in `context_to_json` (`server/src/http/mod.rs` lines 1320–1324).

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "`client_tag` stability requirement" paragraph to Section 5.5.

## Issue #4: The spec's `view=typed` default for `fetchFirstTurn` creates a hard dependency on the type registry — `view=raw` offers a more resilient discovery path

**Status: Applied to specification**

Updated `fetchFirstTurn` to use `view=raw` instead of the default `view=typed`. Verified in the CXDB source (`server/src/http/mod.rs` lines 838–845) that `declared_type` is present in both `view=raw` and `view=typed` responses. Added a `decodeFirstTurn` helper that checks `declared_type.type_id` (available in raw view), and only decodes the base64-encoded msgpack payload (`bytes_b64`) when the type is `RunStarted`. Documented the bootstrap ordering problem (type registry not yet published when UI first discovers a pipeline) and how `view=raw` eliminates it. Regular turn polling continues using `view=typed`.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "Using `view=raw` for discovery" paragraph to Section 5.5.
- `specification/cxdb-graph-ui-spec.md`: Updated `fetchFirstTurn` pseudocode to pass `view="raw"` to all `fetchTurns` calls.
- `specification/cxdb-graph-ui-spec.md`: Added `decodeFirstTurn` helper pseudocode.

## Issue #5: `getMostRecentToolResultsForNodeInContext` scans cached turns, but the turn cache is replaced on each poll — error loop detection can miss errors from previous poll cycles

**Status: Applied to specification (documented limitation)**

Added an "Error heuristic window limitation" paragraph after the `getMostRecentToolResultsForNodeInContext` description in Section 6.2. Documents that the heuristic only detects errors visible in the current 100-turn fetch window, that slow error loops spanning multiple poll windows will not trigger the heuristic, and why this is acceptable for the initial implementation (the heuristic targets rapid error loops). Did not implement the cross-poll error buffer (option 1 from the critique) — the added complexity is not justified for an edge case that is better addressed by lifecycle turns (`StageFailed`).

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "Error heuristic window limitation" paragraph to Section 6.2.

## Not Addressed (Out of Scope)

- None. All five issues were addressed (four as spec changes, one as a documented limitation with rationale).
