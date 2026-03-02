# CXDB Graph UI Spec — Critique v26 (codex) Acknowledgement

Both issues from v26-codex have been applied to the specification. The detail panel now has a per-type rendering mapping table for all turn types, and a note about numeric `turn_id` comparison for ordering.

## Issue #1: Detail panel does not specify how to render non-ToolResult turns

**Status: Applied to specification**

Added a "Per-type rendering" mapping table to Section 7.2 that specifies the Output, Tool, and Error column content for each turn type: Prompt shows `data.text`, ToolCall shows `data.arguments_json`, ToolResult shows `data.output` with `data.is_error` in the Error column, lifecycle turns (StageStarted, StageFinished, StageFailed) show fixed labels, and unknown types show a "[unsupported turn type]" placeholder. Updated the existing column table's Output description to say "varies by type (see mapping below)" and the Tool column to note "blank for non-tool turns". This ensures implementers have an unambiguous rendering rule for every turn type that may appear in the cache.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added per-type rendering mapping table and updated column descriptions in Section 7.2.

## Issue #2: Detail panel ordering does not specify numeric turn_id comparison

**Status: Applied to specification**

Added an explicit note in Section 7.2 that all `turn_id` comparisons used for ordering within the detail panel — both within-context sorting and cross-context section ordering — must be numeric (`parseInt(turn_id, 10)`), consistent with Section 6.2. Referenced the same lexicographic failure example (`"999" > "1000"`).

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added numeric `turn_id` comparison requirement to Section 7.2's ordering paragraph.

## Not Addressed (Out of Scope)

- None. Both issues were applied.
