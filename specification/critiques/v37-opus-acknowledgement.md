# CXDB Graph UI Spec — Critique v37 (opus) Acknowledgement

All four issues from the v37 opus critique were evaluated and applied to the specification. Changes were verified against the Kilroy source code (`cxdb_events.go`, `cli_stream_cxdb.go`) and the existing spec structure.

## Issue #1: Prompt.text is NOT truncated by Kilroy, but the spec implies all high-frequency text fields are capped at 8,000 characters

**Status: Applied to specification**

The Kilroy-side truncation paragraph in Section 7.2 was amended to explicitly identify which fields are NOT truncated. Verified against Kilroy source: `cxdbPrompt` in `cxdb_events.go` passes `text` directly without calling `truncate`, while `cli_stream_cxdb.go` lines 46, 66, and 87 truncate `AssistantMessage.text`, `ToolCall.arguments_json`, and `ToolResult.output` respectively. The paragraph now names `Prompt.text` as untruncated (commonly 5,000-50,000+ characters), lists `StageFailed.failure_reason`, `RunFailed.reason`, and `InterviewStarted.question_text` as also untruncated but typically short, and notes that the client-side 500-character/8-line truncation handles visual presentation for all fields regardless of source-side truncation. An implementer warning was added that `Prompt.text` may be significantly larger than 8,000 characters.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Amended Kilroy-side truncation paragraph in Section 7.2 to explicitly list truncated and untruncated fields

## Issue #2: The discoverPipelines pseudocode does not handle CQL returning zero results when the context list fallback WOULD find contexts via session-tag resolution

**Status: Applied to specification**

Added a supplemental context list fetch to the `discoverPipelines` pseudocode. When CQL search succeeds but returns zero contexts, the algorithm now issues `fetchContexts(index, limit=10000)` and filters for `kilroy/`-prefixed `client_tag` values. This handles the common deployment scenario where Kilroy lacks key 30 metadata — CQL returns empty results but the context list resolves `client_tag` from the active session's tag. The supplemental fetch runs once per poll cycle per instance only when CQL is empty, preserving CQL as the primary path when it has results.

Also updated three related paragraphs for consistency:
1. The "CQL discovery limitation" introduction paragraph now references the supplemental fetch instead of instructing operators to time their browser sessions.
2. The "Fallback behavior until Kilroy implements key 30" paragraph now describes the supplemental fetch behavior and its limitations (still requires active session for discovery; fresh page loads after all sessions disconnect still cannot discover completed pipelines until key 30 is implemented).

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added supplemental context list fetch to `discoverPipelines` pseudocode (Section 5.5)
- `specification/cxdb-graph-ui-spec.md`: Updated "CQL discovery limitation" paragraph to reference supplemental fetch
- `specification/cxdb-graph-ui-spec.md`: Updated "Fallback behavior until Kilroy implements key 30" paragraph

## Issue #3: The spec does not specify what HTTP status code the Go server returns when a DOT file has a read error for the /dots/{name} raw DOT endpoint

**Status: Applied to specification**

Added error handling documentation to the `/dots/{name}` route in Section 3.2. The server returns 500 with a plain-text error body when a registered file cannot be read from disk (e.g., deleted after startup, permission error). The browser handles non-200 responses by displaying an error message in the graph area (replacing the SVG). Recovery is automatic since the file is re-read on every request.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added file-read error handling to `GET /dots/{name}` route in Section 3.2

## Issue #4: RunStarted.graph_dot is documented but the spec does not explain why DOT files from disk are preferred

**Status: Applied to specification**

Added non-goal #11 "No DOT rendering from CXDB" to Section 10. The rationale explains three reasons for using `--dot` flags over `graph_dot`: (a) viewing pipelines before any CXDB data exists, (b) reflecting live DOT file regeneration without a new run, and (c) rendering pipelines that have never been executed. The `graph_dot` field is noted as available for future features (e.g., historical run reconstruction).

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added non-goal #11 (renumbered existing #11 SSE to #12) in Section 10

## Not Addressed (Out of Scope)

- None. All four issues were fully addressed.
