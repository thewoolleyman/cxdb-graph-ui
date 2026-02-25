# CXDB Graph UI Spec — Critique v40 (opus) Acknowledgement

All four issues from the v40 opus critique were evaluated and applied to the specification. DOT comment handling was added to the parsing rules (verified against Kilroy's `stripComments` implementation). The `RunCompleted` unreachability in the detail panel was explicitly documented. The Definition of Done was updated for shape completeness. A proposed holdout scenario for DOT comment handling was written.

## Issue #1: The server's DOT parser does not mention DOT comment handling

**Status: Applied to specification**

A new bullet point was added to the DOT parsing rules in Section 3.2 (after the existing "Escape sequences" bullet): "Comment handling" documents that the parser must strip `//` line comments and `/* */` block comments before parsing, while preserving comment-like sequences inside double-quoted strings. The description references Kilroy's `stripComments` function (`kilroy/internal/attractor/dot/comments.go`) and notes that an unterminated block comment is a parse error. The rule covers the three cases handled by Kilroy's implementation: line comments (skip until newline, preserve the newline), block comments (skip until closing `*/`), and string-interior preservation (tracked via `inString` state with escape handling).

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "Comment handling" bullet to Section 3.2 DOT parsing rules

## Issue #2: The `RunCompleted` turn lacks `node_id` and should not enter the status derivation, but this is not explicitly documented

**Status: Applied to specification**

A new "Pipeline-level turns without `node_id`" paragraph was added below the per-type rendering table in Section 7.2. The paragraph explains that `RunCompleted` has no `node_id` (referencing Section 5.4), so it never matches the `node_id` filter in the detail panel and is unreachable in practice. It contrasts `RunCompleted` with `RunFailed` (which always carries `node_id` per Kilroy's `cxdbRunFailed`) and notes that other pipeline-level turns without `node_id` (`CheckpointSaved`, `Artifact`, `Blob`, `BackendTraceRef`) are similarly excluded. The `RunCompleted` row in the table is retained for completeness but the note makes its unreachability explicit.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "Pipeline-level turns without `node_id`" paragraph after the per-type rendering table in Section 7.2

## Issue #3: The Definition of Done (Section 11) lists only six node shapes but the spec now documents ten

**Status: Applied to specification**

The Definition of Done checklist item was updated from the original six shapes to all ten Kilroy shapes plus a reference to Section 7.3: "All node shapes render correctly (Mdiamond, Msquare, box, diamond, parallelogram, hexagon, circle, doublecircle, component, tripleoctagon, house — see Section 7.3 for the full shape-to-type mapping)".

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 11 Definition of Done shape checklist to include all 10 shapes

## Issue #4: No holdout scenario covers a DOT file containing comments

**Status: Applied to holdout scenarios**

A proposed holdout scenario "DOT file with comments parses correctly" was written to `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`. The scenario tests that line comments, block comments, and comment-like sequences inside quoted strings are handled correctly by the server's DOT parser. It specifically exercises the edge case where `//` appears inside a quoted attribute value (e.g., a URL like `http://example.com`).

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added proposed scenario for DOT comment handling

## Not Addressed (Out of Scope)

- None. All four issues were addressed (three applied to specification, one deferred as proposed holdout scenario).
