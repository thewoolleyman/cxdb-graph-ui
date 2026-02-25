# CXDB Graph UI Spec — Critique v20 (codex) Acknowledgement

Both issues from v20-codex have been applied to the specification. Pipeline discovery now distinguishes transient fetch errors from confirmed non-Kilroy classifications, and graph ID uniqueness is enforced at startup.

## Issue #1: Pipeline discovery permanently ignores contexts after transient turn fetch failures

**Status: Applied to specification**

Modified the discovery algorithm pseudocode in Section 5.5 to wrap `fetchFirstTurn` in a try/catch. When the fetch fails due to a transient error (non-200, timeout, type registry miss), the context is left unmapped (not cached as `null`) so that discovery retries on the next poll cycle. Only confirmed classifications (successful fetch returning a `RunStarted` turn or a non-`RunStarted` first turn) are cached. Updated the caching description to explain this distinction. Also updated Invariant 10 to note that transient failures are not cached and are retried.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added try/catch to Phase 2 of `discoverPipelines` pseudocode in Section 5.5.
- `specification/cxdb-graph-ui-spec.md`: Updated the "Caching" paragraph in Section 5.5 to describe transient error handling.
- `specification/cxdb-graph-ui-spec.md`: Updated Invariant 10 to note transient failure retry behavior.

## Issue #2: Graph ID collisions across multiple DOT files are undefined

**Status: Applied to specification**

Added a graph ID uniqueness check to Section 3.2 (DOT file serving). At startup, the server parses each DOT file to extract its graph ID and exits with an error if duplicates exist. This mirrors the existing basename collision check and prevents ambiguous pipeline discovery where multiple tabs would match the same CXDB contexts.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "Graph ID uniqueness" paragraph to the `/dots/{name}` route description in Section 3.2.

## Not Addressed (Out of Scope)

- The suggestion to add a holdout scenario for duplicate graph IDs was not added. Holdout scenarios are maintained separately and are outside the scope of spec revisions.
