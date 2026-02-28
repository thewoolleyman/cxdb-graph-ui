# CXDB Graph UI Spec — Critique v57 (sonnet)

**Critic:** sonnet (claude-sonnet-4-6)
**Date:** 2026-02-27

## Prior Context

v56-sonnet and v56-codex both found no MVP-blocking issues. The spec has been stable for many cycles.

---

## Issue #1: API and discovery logic scenarios belong in the spec as invariants, not in holdout scenarios

### The problem

The holdout scenarios document contains two categories of scenarios that are not UI-testable and should not be treated as acceptance tests requiring a running browser:

1. **API response format scenarios** — "Edge chain expansion in /edges response", "Port suffixes stripped from edge node IDs", "DOT file with comments parses correctly", "Quoted node IDs normalize correctly for /nodes, /edges…", "DOT attribute concatenation and multiline quoted values", "Nodes and edges inside subgraphs are included in /nodes and /edges responses", and the various `/nodes`/`/edges` parse error → 400 scenarios. These test the JSON shape returned by server endpoints. A browser test can only observe the downstream UI effect, not the API contract directly.

2. **JavaScript discovery state machine scenarios** — the entire "Pipeline Discovery" section (~25 scenarios). These test internal client-side logic: CQL search, null-tag backlogs, `NULL_TAG_BATCH_SIZE` batch limiting, msgpack decoding, `MAX_PAGES` pagination cap, `cachedContextLists`, `knownMappings`, `cqlSupported` flag lifecycle, and run-selection by ULID ordering. None of these have a visible UI manifestation until the final computed state; intermediate steps (which API was called, how many times, what was cached) are invisible to Playwright DOM inspection.

Placing these in the holdout scenarios document implies they will be exercised by a UI test runner. They will not be, and this creates a false sense of coverage.

### Suggestion

Move these two categories out of the holdout scenarios document and into the specification itself as **testability invariants**:

- **Section for API contract invariants**: Each server endpoint should have an explicit invariant block listing the required JSON shape, error codes, and edge-case behaviors (chain expansion, port stripping, comment handling, parse error format). These become the contract for Go unit tests and curl-level integration tests.

- **Section for client-side logic invariants**: The discovery state machine, run-selection logic, gap-recovery algorithm, and CQL/fallback switching behavior should each have an explicit invariant block. These become the contract for JavaScript unit tests (e.g., Vitest or Jest) that import the discovery module directly and inject mock CXDB responses without a browser.

The spec currently describes much of this behavior narratively in Sections 4, 5, and 6, but does not identify it as requiring programmatic (non-UI) test coverage.

---

## Issue #2: The spec requires 100% line and branch coverage for all JavaScript and Go code

### The problem

The specification has no statement about test coverage requirements. Given the complexity of the implementation — a custom DOT parser in Go, a multi-phase discovery state machine in JavaScript, gap recovery with pagination, error loop detection, run-selection by ULID ordering, and CXDB proxy logic — a lack of coverage requirements means that large portions of critical logic can ship untested.

This is already observable: the initial Go implementation of `parseEdges` contained a bug (calling `skipToStatementEnd` after reading the `digraph` keyword, which caused the entire graph body to be skipped, returning zero edges for every DOT file). This bug was invisible until a test was written — and no tests existed at the time of the bug's introduction. Full branch coverage would have caught it immediately.

### Suggestion

Add a **Testing Requirements** section to the specification (or to the invariants section proposed above) stating:

> All Go code in `ui/` must have 100% line and branch coverage as measured by `go test -cover`. All JavaScript code in `ui/index.html` (once extracted to a testable module) must have 100% line and branch coverage as measured by the chosen JS test runner (e.g., Vitest with V8 coverage). Coverage must be verified as part of CI before any implementation is considered complete.

This requirement should name specific tools (`go test -coverprofile`, `go tool cover -func`, Vitest/V8 for JS) and specify that coverage is enforced, not merely aspirational. It should also require that JavaScript logic be extracted from inline `<script>` tags into importable modules as a prerequisite for testability.
