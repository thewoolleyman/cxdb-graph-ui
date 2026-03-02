# CXDB Graph UI Spec — Critique v18 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-24

## Prior Context

The v17 cycle applied all issues from opus and codex: status class cleanup was added, `fetchFirstTurn` now uses a single request, the error-loop scenario now targets ToolResult turns with interleaving, the edges endpoint was added for human-gate choices, and the non-200 turn-fetch resilience path gained a holdout scenario.

---

## Issue #1: `/api/dots` response format is internally inconsistent (array vs object)

### The problem
Section 3.2 describes `GET /api/dots` as returning a JSON array of filenames, but the example response is an object with a `dots` field:

```
Returns a JSON array of available DOT filenames...

{ "dots": ["pipeline-alpha.dot", "pipeline-beta.dot"] }
```

This is a spec-level contradiction. An implementer could legitimately return a raw array (`["a.dot", "b.dot"]`) or the object shape (`{"dots": [...]}`) and still claim compliance. The rest of the spec (e.g., the initialization sequence in Section 4.5) doesn’t pin the schema either.

### Suggestion
Choose one format and define it unambiguously. If the object form is intended, change the prose to “Returns a JSON object with a `dots` array” and keep the example; if an array is intended, update the example and anywhere the client reads `response.dots` accordingly.

---

## Issue #2: Poller updates inactive pipelines without defining how their node IDs are loaded

### The problem
Section 6.1 says “Per-context maps for inactive pipelines are also updated” so that tab switches can reapply cached status immediately. However, `updateContextStatusMap` requires `dotNodeIds` for each pipeline, and the spec only guarantees fetching the active pipeline’s DOT file (Section 4.5 step 4). There is no explicit requirement to prefetch DOT data (or `/dots/{name}/nodes`) for non-active pipelines before the poller starts.

As written, an implementer could legitimately only load the active pipeline’s node IDs. In that case, inactive pipelines cannot be updated during polling, and the holdout scenario “Switch between pipeline tabs” (“the second pipeline has been polled at least once” and cached status is immediately reapplied) cannot be satisfied without extra, unstated behavior.

### Suggestion
Specify how node IDs for all pipelines are loaded before polling updates inactive pipelines. Two concrete options:

- On startup, fetch `/dots/{name}/nodes` for every pipeline listed by `/api/dots`, cache `dotNodeIds`, then start polling.
- Alternatively, explicitly limit per-context status updates to the active pipeline only, and relax the holdout scenario to say cached status appears only after the pipeline has been opened at least once.

The first option aligns with the current holdout scenario wording and the “no gray flash” requirement on tab switch.

---

## Issue #3: Graph ID extraction can break pipeline discovery for `graph` or quoted graph names

### The problem
Section 4.4 extracts the graph ID using `/digraph\s+("(?:[^"\\]|\\.)*"|\w+)/` and falls back to the filename if the regex does not match (e.g., if the DOT file uses `graph` instead of `digraph`). Pipeline discovery in Section 5.5 matches `RunStarted.data.graph_name` against the extracted graph ID. If the DOT file uses `graph` (undirected) or a quoted name with spaces, the regex fails (or returns the quoted string including quotes), the UI falls back to the filename, and the `graph_name` match will fail even when the context is correct. That yields “no active pipeline run” status for a valid run.

### Suggestion
Either (a) expand the extraction to handle `graph` as well as `digraph` and normalize quoted names by unquoting and unescaping before matching, or (b) explicitly constrain supported DOT inputs to `digraph` with unquoted graph IDs and state that pipeline discovery relies on that constraint. Option (a) is safer and preserves the “generic pipeline support” principle in Section 1.2.
