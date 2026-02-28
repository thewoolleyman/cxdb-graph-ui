# CXDB Graph UI Spec — Critique v57 (sonnet) Acknowledgement

Both issues raised in v57-sonnet were applied in full. The spec gained a new Section 12 (Testing Requirements) that defines three testing layers with 100% coverage targets for Go and JavaScript, identifies which testing tools are required, and maps every scenario category to its correct layer. Section 9 (Invariants) gained five new invariants: four API contract invariants (edge chain expansion, port stripping, parse error 400 body, comment handling) and one client-side logic invariant establishing the JS unit test layer boundary. The holdout scenarios document was annotated throughout with per-scenario testing layer tags and two section-level notes directing readers to the correct testing layer.

## Issue #1: API and discovery logic scenarios belong in the spec as invariants, not in holdout scenarios

**Status: Applied to specification and applied to holdout scenarios**

Both categories identified in the critique were addressed:

**API contract invariants (server layer):** Four new invariants were added to Section 9 under a new "API Contract" heading (Invariants 16–19):
- Invariant 16: `/edges` expands edge chain syntax (verified at API layer)
- Invariant 17: `/edges` strips port suffixes (verified at API layer)
- Invariant 18: Parse errors produce HTTP 400 with `{"error": "DOT parse error: ..."}` body (verified at API layer)
- Invariant 19: Comments stripped before parsing; comments inside quoted strings preserved (verified at API layer)

These make the API contracts explicit programmatic invariants rather than implicit behaviors buried in Section 3.2 prose.

**Client-side logic invariants (JS unit test layer):** One new invariant was added to Section 9 under a new "Client-Side Logic" heading (Invariant 20). It names the ten discovery state machine behaviors that require JS-level unit testing and explicitly cannot be verified by Playwright DOM inspection: `fetchFirstTurn` pagination, `knownMappings`, `determineActiveRuns` ULID selection, gap recovery, error loop detection per-context, `cqlSupported` flag lifecycle, `NULL_TAG_BATCH_SIZE` batch limiting, supplemental dedup merge, and `cachedContextLists` liveness.

**Holdout scenarios annotated:**
- A key was added at the top of the document explaining the four testing layer tags.
- Each API-contract scenario was tagged `*(Go test)*`: edge chain expansion, port stripping, comment stripping, attribute concatenation, subgraph inclusion, DOT file with comments, DOT parse error (400) for `/nodes` and `/edges`.
- The Pipeline Discovery section received a section-level note directing to JS unit tests and spec Section 12.2.
- The Server section received a section-level note explaining that startup validation scenarios require Bash subprocess testing and API format scenarios are Go tests.
- Individual Server scenarios were tagged `*(Bash)*`, `*(Go test)*`, or `*(Go test + Playwright)*` as appropriate.
- Split-layer scenarios (where the 400 response is a Go test but the client recovery behavior is a Playwright test) were tagged `*(Go test + Playwright)*`.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added Invariants 16–20 to Section 9 under new "API Contract" and "Client-Side Logic" sub-headings.
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added testing layer key at top; tagged all API-contract and discovery scenarios with their required testing layer; added section-level notes to Pipeline Discovery and Server sections.

## Issue #2: The spec requires 100% line and branch coverage for all JavaScript and Go code

**Status: Applied to specification**

A new Section 12 (Testing Requirements) was added at the end of the spec. It defines three testing layers:

- **Section 12.1 — Go unit tests:** 100% line and branch coverage for all Go code in `ui/`, measured with `go test -cover -coverprofile=coverage.out ./...` and `go tool cover -func`. The test suite lives in `ui/main_test.go` using `package main`. Enforcement via `script/smoke-test-suite-fast`.

- **Section 12.2 — JavaScript unit tests:** 100% line and branch coverage for all JS, measured with Vitest/V8 (`vitest run --coverage --coverage.provider=v8 --coverage.100`). Notes that JS must be extracted from inline `<script>` tags into importable ES modules as a prerequisite. This section explicitly lists the ten behaviors from Invariant 20 as the primary scope.

- **Section 12.3 — Playwright UI tests:** Scopes what Playwright can and cannot test, references the `run-holdout-scenarios` skill, specifies mock CXDB via `page.route`, and notes that server startup scenarios are tested via Bash subprocess within the same skill.

- **Section 12.4 — Testing layer boundaries:** A table mapping every scenario category to its required testing layer (Playwright, Go tests, JS unit tests, or Bash subprocess).

The concrete example from the critique (the `parseEdges` bug where `skipToStatementEnd` was called after reading the `digraph` keyword, silently returning zero edges for every graph) was the motivating case for this requirement — full branch coverage would have caught it during initial implementation.

The Table of Contents was updated to include Section 12.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added Section 12 (Testing Requirements) with subsections 12.1–12.4; updated Table of Contents.

## Not Addressed (Out of Scope)

- None. Both issues were fully applied.
