# CXDB Graph UI Spec — Critique v58 (failed-holdout-scenarios) Acknowledgement

Both issues from v58 were applied. The blocking msgpack CDN URL was corrected from `mod.min.mjs` to `index.mjs` (the file that actually exists in the npm package). The graceful degradation claim in Section 4.1 was updated to reference import isolation, and Section 4.1.1 was expanded with an "Import isolation" requirement specifying that the msgpack decoder must be loaded via dynamic `import()` rather than a top-level `import` statement, ensuring a msgpack CDN failure does not prevent DOT rendering and tab creation.

## Issue #1: Spec prescribes a non-existent msgpack CDN URL — entire UI fails to initialize

**Status: Applied to specification**

The CDN URL in Section 4.1.1 was corrected in both the standalone URL block and the `import` statement example:

- `mod.min.mjs` → `index.mjs`

The file `index.mjs` exists in the `@msgpack/msgpack@3.0.0-beta2` npm package at the `dist.es5+esm/` path and provides the same `decode` named export.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated both occurrences of the msgpack CDN URL in Section 4.1.1 from `mod.min.mjs` to `index.mjs`

## Issue #2: Spec's graceful degradation claim contradicts actual failure mode for CDN import errors

**Status: Applied to specification**

Option (b) from the critique was implemented — import isolation is now specified. Changes:

1. **Section 4.1** — The graceful degradation paragraph was updated to reference import isolation as a requirement and point to Section 4.1.1 for the mechanism.

2. **Section 4.1.1** — A new "Import isolation" paragraph was added specifying that the msgpack decoder must be loaded via dynamic `import()` (not a top-level `import` statement). This ensures a msgpack CDN failure does not prevent the `<script type="module">` block from executing. The Graphviz WASM dependency remains a top-level import since DOT rendering cannot proceed without it. A recommended lazy-singleton pattern is provided. If dynamic import fails, `decodeFirstTurn` returns `null` and the context is retried on the next poll cycle.

This aligns the spec with the graceful degradation principle in Section 1.2: "If CXDB is unreachable, the graph is still useful for understanding pipeline structure." The msgpack decoder is a CXDB-only dependency, so its failure should not block DOT rendering.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 4.1 graceful degradation text; added "Import isolation" requirement to Section 4.1.1 with dynamic `import()` specification and lazy-singleton pattern

## Not Addressed (Out of Scope)

- None. Both issues were fully applied.
