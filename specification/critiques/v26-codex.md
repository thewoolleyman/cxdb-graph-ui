# CXDB Graph UI Spec — Critique v26 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-24

## Prior Context

The v25 cycle applied all issues from both critics. The spec now documents browser-side msgpack decoding (with a pinned CDN dependency), explains raw msgpack tag access, clarifies CQL bootstrap lag, connects SSE metadata to the labels optimization, and aligns edge parsing rules with node parsing. This critique focuses on remaining implementability gaps in the detail panel turn rendering and ordering.

---

## Issue #1: Detail panel does not specify how to render non-ToolResult turns

### The problem
Section 7.2 defines the detail panel columns as Type, Tool, Output, and Error, and maps Output to `data.output`. However, the spec explicitly says the panel should show Prompt and ToolCall turns, and those types do not include `data.output` (Prompt uses `data.text`, ToolCall uses `data.arguments_json`). The holdout scenario "Click a node to see details" expects Prompt and ToolCall rows to be meaningful, but there is no mapping for how their content should display, nor what to do for lifecycle turns (StageStarted/StageFinished) that may be present in the cache. An implementer could end up with blank Output cells or inconsistent ad-hoc formatting.

### Suggestion
Add a small mapping table for detail panel row rendering by turn type:
- Prompt: Output column shows `data.text`
- ToolCall: Output column shows `data.arguments_json`
- ToolResult: Output column shows `data.output` (with `data.is_error` controlling the Error column)
- Lifecycle turns: Output column shows a fixed label (e.g., "Stage started"/"Stage finished") and Tool column is blank
Also specify that unknown types render with a placeholder (e.g., "[unsupported turn type]") to avoid empty rows.

## Issue #2: Detail panel ordering does not specify numeric turn_id comparison

### The problem
Section 7.2 states that turns are sorted newest-first by `turn_id` within a context, and that context sections are ordered by highest `turn_id` when sharing the same CXDB instance index. It does not explicitly say that `turn_id` comparisons are numeric. Earlier (Section 6.2) the spec emphasizes numeric ordering for turn IDs because they are numeric strings; if an implementer reuses lexicographic comparison in the detail panel, the ordering will break once IDs reach different digit lengths (e.g., `"999"` appearing after `"1000"`). This is a subtle UX bug that will show up in the detail panel even if the status overlay is correct.

### Suggestion
Add a brief note in Section 7.2 that all `turn_id` comparisons used for ordering within the detail panel must be numeric (e.g., `parseInt(turn_id, 10)`), consistent with Section 6.2. This keeps newest-first ordering correct across long runs.
