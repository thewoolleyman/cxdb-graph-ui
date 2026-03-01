# CXDB Graph UI Spec — Critique v20 (opus) Acknowledgement

All three issues from v20-opus have been applied to the specification. DOT attribute parsing now explicitly supports string concatenation and multi-line values; `resetPipelineState` now cleans up old-run `knownMappings` entries; and CSS status selectors now include `path` elements alongside `polygon` and `ellipse`.

## Issue #1: DOT node attribute parsing specification lacks handling for multi-line attribute values and string concatenation

**Status: Applied to specification**

Added two new parsing rules to Section 3.2 (`GET /dots/{name}/nodes`): (a) string concatenation via the DOT `+` operator between consecutive quoted strings, with the note that fragments are joined with no separator per DOT semantics; and (b) multi-line quoted values that span literal newlines, with an explicit note that a line-by-line parser is insufficient.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "String concatenation" and "Multi-line quoted values" bullet points to the DOT attribute parsing rules in Section 3.2.

## Issue #2: `resetPipelineState` clears per-context status maps but does not clear `knownMappings` — stale context entries persist and match the old run

**Status: Applied to specification**

Extended the description of `resetPipelineState` in Section 6.1 to explicitly remove `knownMappings` entries whose `runId` matches the old run. Added rationale: these entries are no longer useful, and re-discovery handles the case where context IDs reappear with different `RunStarted` data. Noted that `null` entries and new-run entries are retained. Also updated Invariant 10 to reflect that old-run mappings are removed on run change.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Extended the `resetPipelineState` helper description in Section 6.1 step 3.
- `specification/cxdb-graph-ui-spec.md`: Updated Invariant 10 to note old-run mapping removal.

## Issue #3: CSS status selectors target `polygon` and `ellipse` but miss `path` elements used by some Graphviz node shapes

**Status: Applied to specification**

Added `path` to every CSS status selector rule in Section 6.3. This ensures status coloring applies even when `@hpcc-js/wasm-graphviz` renders certain shapes (e.g., rounded variants) as SVG `path` elements rather than `polygon` or `ellipse`.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added `.node-{status} path` to all five CSS status class rules in Section 6.3.

## Not Addressed (Out of Scope)

- The suggestion to add a holdout scenario verifying status coloring on each of the six node shapes was not added. Holdout scenarios are maintained separately and are outside the scope of spec revisions.
