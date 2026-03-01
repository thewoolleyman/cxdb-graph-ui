# CXDB Graph UI Spec — Critique v18 (codex) Acknowledgement

Two of three issues were addressed in the v21 revision cycle; the third (graph ID extraction) has been applied now. The `/api/dots` response format was resolved in v21, inactive pipeline node ID loading was resolved in v21, and graph ID extraction now handles `graph` keyword and quoted names.

## Issue #1: `/api/dots` response format is internally inconsistent (array vs object)

**Status: Applied to specification (in v21 cycle)**

This was addressed during the v21 revision cycle (see v21-opus-acknowledgement.md, Issue #2 and v21-codex-acknowledgement.md, Issue #3). The prose was updated to "Returns a JSON object with a `dots` array" to match the example response. The initialization sequence step 2 was also updated.

Changes:
- `specification/cxdb-graph-ui-spec.md`: `/api/dots` description and initialization step 2 updated (applied in v21 cycle).

## Issue #2: Poller updates inactive pipelines without defining how their node IDs are loaded

**Status: Applied to specification (in v21 cycle)**

This was addressed during the v21 revision cycle (see v21-opus-acknowledgement.md, Issue #5 and v21-codex-acknowledgement.md, Issue #2). A new initialization step 4 ("Prefetch node IDs for all pipelines") was added to Section 4.5 that fetches `GET /dots/{name}/nodes` for every pipeline before the poller starts.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added initialization step 4 for node ID prefetching (applied in v21 cycle).

## Issue #3: Graph ID extraction can break pipeline discovery for `graph` or quoted graph names

**Status: Applied to specification**

Updated the graph ID extraction regex in Section 4.4 from `/digraph\s+(...)/ ` to `/(di)?graph\s+(...)/`, so it matches both `digraph` and `graph` keywords. Added explicit unquoting and unescaping: when the captured name is quoted, outer `"` characters are stripped and internal `\"` sequences are unescaped before the graph ID is used for pipeline discovery. Added a note that pipeline discovery matches against the normalized (unquoted, unescaped) graph ID.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated graph ID extraction regex, added unquoting/unescaping rules, and added pipeline discovery matching note in Section 4.4.

## Not Addressed (Out of Scope)

- None. All three issues have been addressed (two in the v21 cycle, one in this revision).
