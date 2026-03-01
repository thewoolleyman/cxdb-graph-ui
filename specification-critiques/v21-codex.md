# CXDB Graph UI Spec — Critique v21 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-24

## Prior Context

The v20 acknowledgements indicate that all previously raised issues were applied: discovery now retries on transient fetch errors, graph ID uniqueness is enforced at startup, DOT attribute parsing supports concatenation/multi-line values, `resetPipelineState` removes old-run mappings, and CSS selectors include `path`. This critique focuses on remaining gaps and new issues.

---

## Issue #1: Empty contexts are permanently classified as non-Kilroy

### The problem

In Section 5.5, `fetchFirstTurn` returns `null` when `headDepth == 0` and the response has no turns (an empty context). The discovery algorithm then falls through to the `ELSE` clause and caches `knownMappings[key] = null`, which permanently classifies the context as non-Kilroy. This can happen when a context is created but no `RunStarted` turn has been appended yet (e.g., during early pipeline startup or transient CXDB lag). The mapping becomes a false negative and is never retried, so the pipeline may never appear in the UI even once turns arrive.

This is distinct from the transient error path, which now retries on failure. The spec does not define a retry policy for the empty-context case, even though it is a common, non-error state.

### Suggestion

Treat `firstTurn == null` as an unknown state (similar to transient errors) and do not cache `null` in `knownMappings`. Leave the context unmapped so discovery retries on subsequent polls until a `RunStarted` turn appears or a non-RunStarted first turn is confirmed. Alternatively, require a second check when `headDepth == 0 && is_live == true` to delay classification until a turn is present.

---

## Issue #2: Status caching for inactive pipelines lacks a defined node list source

### The problem

Section 6.1 step 6 states that per-context status maps for inactive pipelines are updated so that cached status can be reapplied when switching tabs. However, `updateContextStatusMap` requires `dotNodeIds`, and the initialization sequence in Section 4.5 only fetches and renders the first pipeline's DOT file. The spec does not define how `dotNodeIds` are obtained for pipelines that have not yet been selected, nor does it mention prefetching `/dots/{name}` or `/dots/{name}/nodes` for all pipelines.

This leaves an implementation gap: either status maps cannot be computed for inactive pipelines (contradicting the holdout scenario that expects cached status on tab switch), or the UI must prefetch node lists, but that behavior is not specified.

### Suggestion

Specify a concrete strategy, such as:

- Prefetch `/dots/{name}/nodes` (or the full DOT source) for all pipelines after `/api/dots` returns, so `dotNodeIds` are available for background polling; or
- Defer per-context status map computation for inactive pipelines and explicitly state that cached status is only applied after a pipeline has been fetched at least once (and adjust the holdout scenario accordingly).

---

## Issue #3: `/api/dots` response format is internally inconsistent

### The problem

Section 3.2 describes `GET /api/dots` as “Returns a JSON array of available DOT filenames,” but the example response is an object wrapper: `{ "dots": ["pipeline-alpha.dot", "pipeline-beta.dot"] }`. The holdout scenarios and initialization sequence reference `/api/dots` but do not clarify which format is normative. This ambiguity can lead to incompatible implementations between server and client, or between tests and code.

### Suggestion

Pick one format and make it consistent across the spec. If the intended response is the object wrapper, change the sentence to “Returns a JSON object with a `dots` array.” If the intended response is a raw array, update the example and any dependent UI logic accordingly.
