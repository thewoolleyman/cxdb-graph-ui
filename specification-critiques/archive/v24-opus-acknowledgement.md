# CXDB Graph UI Spec — Critique v24 (opus) Acknowledgement

All five issues from v24-opus have been applied to the specification. The changes correct factual inaccuracies about CQL search response fields, document previously-unspecified CQL parameters and error handling, add explicit 400 handling to the discovery pseudocode, and narrow the SSE non-goal to preserve the server-side SSE option.

## Issue #1: CQL search context objects do not contain "the same fields as the context list response" — discrepancy affects metadata labels optimization

**Status: Applied to specification**

Fixed the factual claim in Section 5.2. The CQL search response fields are now enumerated explicitly: `context_id`, `head_turn_id`, `head_depth`, `created_at_unix_ms`, `is_live`, `client_tag` (from cached metadata), and `title` (from cached metadata). The absent fields are now listed: `labels`, `session_id`, `last_activity_at`, `lineage`, `provenance`, `active_sessions`, and `active_tags`. Updated the "Metadata labels optimization" paragraph in Section 5.5 to acknowledge that CQL search does not return `labels`, making the optimization incompatible with the CQL-first discovery path without per-context requests or a CXDB enhancement.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Rewrote the CQL search response field description in Section 5.2 with exact fields and explicit absence list.
- `specification/cxdb-graph-ui-spec.md`: Updated the metadata labels optimization paragraph in Section 5.5 to document the CQL `labels` gap and three potential workarounds.

## Issue #2: CQL search `limit` parameter is undocumented

**Status: Applied to specification**

Added a paragraph to Section 5.2 documenting the optional `limit` query parameter: matching contexts are sorted by `context_id` descending before truncation. Stated that the UI omits `limit` to retrieve all Kilroy contexts (needed for active-run determination) and noted that proportionally larger responses from environments with many historical Kilroy runs are acceptable for the initial implementation.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added `limit` parameter documentation paragraph to Section 5.2 after the CQL response field description.

## Issue #3: CQL search sorts by `context_id` descending, not by `created_at_unix_ms`

**Status: Applied to specification**

Added a note to Section 5.2 documenting that CQL results are sorted by `context_id` descending (verified in `store.rs` line 387), which is effectively equivalent to creation-time ordering since CXDB allocates context IDs monotonically. Noted that the context list fallback sorts by `created_at_unix_ms` descending and that `determineActiveRuns` does not depend on response ordering.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added sort key documentation paragraph to Section 5.2 alongside the CQL response field description.

## Issue #4: CQL error response shape (400) is undocumented

**Status: Applied to specification**

Added a "CQL error response" paragraph to Section 5.2 documenting the 400 response shape (`error`, `error_type`, `position`, `field`). Updated the `discoverPipelines` pseudocode in Section 5.5 to add explicit handling for 400 responses: log the error, skip the instance for this poll cycle, but do NOT set `cqlSupported[index] = false` (CQL is supported, the query just failed). This distinguishes three failure modes: "CQL not available" (404 → fallback), "CQL query error" (400 → log and skip), and "instance unreachable" (network error → skip and retain cache).

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "CQL error response" paragraph with JSON example to Section 5.2.
- `specification/cxdb-graph-ui-spec.md`: Added `ELSE IF httpError.status == 400` branch to the `discoverPipelines` pseudocode in Section 5.5.

## Issue #5: SSE non-goal is too broad — server-side SSE subscription is a lower-complexity option

**Status: Applied to specification**

Narrowed non-goal #11 from "No SSE event streaming" to "No browser-side SSE event streaming." Added a note that the Go proxy server could optionally subscribe to CXDB's SSE endpoint server-side (using the Go client's `SubscribeEvents` function) to reduce discovery latency without changing the browser's polling architecture. Explicitly marked as not required for the initial implementation.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Rewrote non-goal #11 in Section 10 to scope the exclusion to browser-side SSE and document the server-side SSE option.

## Not Addressed (Out of Scope)

- None. All five issues were applied.
