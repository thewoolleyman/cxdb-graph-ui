# CXDB Graph UI Spec -- Critique v37 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-25

## Prior Context

The v36 cycle had two critics (opus and codex). Opus raised four issues: incorrect claim about CXDB binary protocol embedding `client_tag` at key 30 (applied -- spec now documents the current limitation and required Kilroy-side change), metadata extraction asymmetry paragraph assuming key 30 is present (applied -- split into current-state and future-state sections), `decodeFirstTurn` type comparison mismatch (already resolved in prior round), and missing holdout scenario for CQL returning zero Kilroy contexts (deferred as proposed holdout scenarios). Codex raised two issues: merged status map for inactive pipelines undefined after background polling (applied -- Section 6.1 step 6 now merges for all pipelines every poll cycle), and `RunStarted.graph_name` normalization mismatch (applied -- documented that Kilroy parser only accepts unquoted identifiers). All issues addressed.

This critique is informed by reading the **Kilroy source code** (`kilroy/internal/attractor/engine/cxdb_events.go`, `kilroy/internal/attractor/engine/cli_stream_cxdb.go`, `kilroy/internal/attractor/engine/handlers.go`, `kilroy/internal/attractor/dot/parser.go`, `kilroy/internal/cxdb/kilroy_registry.go`, `kilroy/internal/cxdb/msgpack_encode.go`) and the **CXDB server source code** (`cxdb/server/src/http/mod.rs`, `cxdb/server/src/store.rs`).

---

## Issue #1: Prompt.text is NOT truncated by Kilroy, but the spec implies all high-frequency text fields are capped at 8,000 characters

### The problem

Section 7.2's "Kilroy-side truncation" paragraph states:

> "Kilroy truncates large text fields at the source before appending to CXDB: `AssistantMessage.text`, `ToolCall.arguments_json`, and `ToolResult.output` are each capped at 8,000 characters by the Kilroy engine (`cli_stream_cxdb.go`). The UI's client-side truncation (below) operates within this limit. Expanding a truncated turn row via 'Show more' shows at most 8,000 characters, not the full original content... An implementer need not handle arbitrarily large text values for these fields."

This is factually correct for the three named fields -- `cli_stream_cxdb.go` lines 46, 66, and 87 each call `truncate(value, 8_000)`. However, the `Prompt` turn type's `text` field is NOT truncated. `cxdbPrompt` in `cxdb_events.go` (line 56) passes `text` directly without calling `truncate`:

```go
func (e *Engine) cxdbPrompt(ctx context.Context, nodeID, text string) {
    _, _, _ = e.CXDB.Append(ctx, "com.kilroy.attractor.Prompt", 1, map[string]any{
        "run_id":       e.Options.RunID,
        "node_id":      nodeID,
        "text":         text,           // <-- no truncation
        "timestamp_ms": nowMS(),
    })
}
```

The `promptText` originates from `handlers.go` line 321 where it is the full assembled prompt -- typically 5,000-50,000+ characters for complex LLM tasks. This is written to `prompt.md` (line 317) immediately before being appended to CXDB, confirming it is the untruncated prompt.

The per-type rendering table in Section 7.2 maps `Prompt` turns to `data.text` in the Output column. An implementer reading the truncation paragraph would reasonably conclude that no text field exceeds 8,000 characters and skip defensive handling for large payloads. But `Prompt.text` can be 10x that limit. The client-side 500-character/8-line truncation in the Output column handles the visual presentation, but the underlying data transfer and memory allocation could be significant if an implementer assumes all text fields fit in a small buffer.

Similarly, `StageFailed.failure_reason` and `RunFailed.reason` are not truncated at the Kilroy side, though these are typically short error messages.

### Suggestion

Amend the Kilroy-side truncation paragraph to explicitly list which fields are NOT truncated:

> "Kilroy truncates `AssistantMessage.text`, `ToolCall.arguments_json`, and `ToolResult.output` at 8,000 characters. **`Prompt.text` is NOT truncated** and may contain the full assembled LLM prompt (commonly 5,000-50,000+ characters). Other text fields (`StageFailed.failure_reason`, `RunFailed.reason`, `InterviewStarted.question_text`) are also not truncated but are typically short. The client-side Output column truncation (500 characters / 8 lines) handles visual presentation for all fields regardless of source-side truncation."

---

## Issue #2: The `discoverPipelines` pseudocode does not handle the case where CQL returns zero results but the context list fallback WOULD find contexts via session-tag resolution

### The problem

Section 5.5's "CQL discovery limitation" paragraph correctly identifies that CQL returns zero Kilroy contexts until Kilroy implements key 30. The paragraph explains that the CQL endpoint returns a valid 200 with empty results, so `cqlSupported` stays `true` and the UI does not fall back.

However, the `discoverPipelines` pseudocode has no path to recover from this state. The only trigger for the context list fallback is `cqlSupported[index] == false`, which requires a 404 from the CQL endpoint. There is no conditional like "if CQL returned zero results, try the fallback." The pseudocode accurately reflects the spec's design intent (CQL-first, fallback only for older CXDB versions), but this means the most common deployment scenario -- current Kilroy without key 30, against a CQL-capable CXDB -- produces zero discovered contexts indefinitely.

The "Fallback behavior" paragraph at the end of the section acknowledges this and suggests workarounds (open the UI while the pipeline is running, or target a non-CQL CXDB). But these workarounds are fragile: opening the UI while the pipeline is running does NOT trigger the context list fallback either, because CQL is still the primary path and still returns zero results. The context list fallback only runs when `cqlSupported[index] == false`. The workaround paragraph appears to assume that CQL returning empty results would somehow trigger the fallback, but the pseudocode contradicts this.

The spec should either:
1. Add a "CQL empty results" fallback path to the pseudocode, or
2. Correct the workaround paragraph to accurately describe the available options.

### Suggestion

Add a fallback trigger for empty CQL results in the `discoverPipelines` pseudocode. After the CQL search succeeds but returns zero contexts:

```
searchResponse = fetchCqlSearch(index, 'tag ^= "kilroy/"')
contexts = searchResponse.contexts
cqlSupported[index] = true
-- CQL succeeded but returned zero contexts. This could mean either:
-- (a) There are genuinely no Kilroy contexts, or
-- (b) Kilroy contexts exist but lack key 30 metadata.
-- To handle case (b), also fetch the context list and check for
-- session-tag-resolved client_tags as a supplemental discovery path.
IF contexts IS EMPTY:
    supplemental = fetchContexts(index, limit=10000)
    FOR EACH ctx IN supplemental:
        IF ctx.client_tag IS NOT null AND ctx.client_tag.startsWith("kilroy/"):
            contexts.append(ctx)
```

This preserves CQL as the primary path when it has results, but falls back to the context list for the specific case where CQL returns nothing. The supplemental fetch runs once per poll cycle per instance only when CQL is empty, so the overhead is minimal. This eliminates the requirement that operators open the UI during an active pipeline session and enables discovery of contexts with session-tag-resolved `client_tag`.

---

## Issue #3: The spec does not specify what HTTP status code the Go server returns when a DOT file has a parse error for the `/dots/{name}` raw DOT endpoint (as opposed to `/dots/{name}/nodes` and `/dots/{name}/edges`)

### The problem

Section 3.2 specifies error handling for `/dots/{name}/nodes` (returns 400 with JSON error body for parse errors) and `/dots/{name}/edges` (same). But `/dots/{name}` itself -- the raw DOT file endpoint -- simply says "Files are read fresh on each request." The spec does not address what happens if reading the file fails (e.g., file deleted after registration, permission error). The server builds its filename-to-path map at startup, but the file could be removed between startup and request time.

This matters because the browser's initialization sequence (Section 4.5, Step 5) fetches the raw DOT file for rendering. If the file has been removed or is unreadable, the server needs a defined response. Section 4.1 says "the graph area displays an error message" when Graphviz WASM encounters an error, but that covers Graphviz parse errors, not HTTP fetch failures.

### Suggestion

Add to Section 3.2's `/dots/{name}` route:

> "If the registered file cannot be read from disk (e.g., deleted after server startup, permission error), the server returns 500 with a plain-text error body describing the failure. The browser handles non-200 responses from `/dots/{name}` by displaying an error message in the graph area (replacing the SVG). The file is re-read on every request, so recovery is automatic once the file is restored."

---

## Issue #4: `RunStarted.graph_dot` is documented as an optional field but never mentioned as a potential alternative for DOT file serving

### The problem

Section 5.4 documents `RunStarted.graph_dot` as an optional field containing the full pipeline DOT source. Section 5.5's `decodeFirstTurn` documents it as "available for future features (e.g., reconstructing the exact graph used for a historical run) but unused by the initial implementation." The Kilroy source confirms this: `cxdb_events.go` line 30-31 embeds `e.DotSource` in the `graph_dot` field of `RunStarted`.

The spec requires `--dot` flags to specify DOT file paths. But the DOT source is already available in CXDB via `RunStarted.graph_dot`. An implementer reading the spec might wonder why the DOT file must be specified on the command line when it is already embedded in the execution trace. This is a design question, not a bug, but the spec does not explain the rationale.

More concretely: the spec mentions that DOT files are "read fresh on each request" so that "DOT file regeneration is picked up without server restart." But if the UI were to use `graph_dot` from `RunStarted`, it would always show the DOT source from the run's start time, not the current file on disk. These are different design tradeoffs, and the spec should briefly note why `--dot` flags are preferred over embedded `graph_dot`.

### Suggestion

Add a brief note to Section 1.2 (Design Principles) or Section 10 (Non-Goals):

> "**DOT files from disk, not CXDB.** Although `RunStarted.graph_dot` embeds the pipeline DOT source at run start time, the UI reads DOT files from disk via `--dot` flags. This enables: (a) viewing the pipeline graph before any CXDB data exists (e.g., while composing the pipeline), (b) reflecting live DOT file regeneration without requiring a new CXDB run, and (c) rendering pipelines that have never been executed. The `graph_dot` field is available for future features (e.g., historical run reconstruction) but is not used for graph rendering."
