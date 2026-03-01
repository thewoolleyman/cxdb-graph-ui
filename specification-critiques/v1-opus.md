# CXDB Graph UI Spec — Critique v1 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

This is the first critique. No prior revision cycle.

---

## Issue #1: Status derivation algorithm doesn't account for StageStarted/StageFinished/StageFailed turn types

### The problem

Section 5.4 defines explicit turn types for node lifecycle events: `StageStarted`, `StageFinished`, and `StageFailed`. However, the status derivation algorithm in Section 6.2 ignores these entirely. Instead, it infers "running" from the most recent turn's `node_id` and "complete" from the heuristic that older turns on a different node mean that node completed.

This creates several problems:
1. A node that explicitly failed via `StageFailed` won't be marked as "error" unless it also happens to have 3+ consecutive `is_error` turns. The `StageFailed` turn type is never checked.
2. A node that has a `StageFinished` turn is still only marked "complete" by the indirect heuristic (a later node has activity), not by the authoritative signal.
3. The `StageStarted` turn could definitively mark a node as "running" rather than relying on it being the most recent `node_id`.
4. If a pipeline finishes all nodes and the last node has a `StageFinished` turn, the algorithm would mark it as "running" (it's the most recent `node_id`) rather than "complete" — there's no subsequent node to trigger the completion heuristic.

### Suggestion

Revise the `buildNodeStatusMap` algorithm to use `StageStarted`, `StageFinished`, and `StageFailed` as primary status signals:
- `StageStarted` → "running"
- `StageFinished` → "complete"
- `StageFailed` → "error"

Fall back to the current heuristic only when these lifecycle turns are absent (e.g., for older CXDB data that may not have them).

## Issue #2: No specification for how turns are fetched for the status overlay

### The problem

Section 6.1 says "for each context matching the active pipeline, fetch recent turns" but does not specify the query parameters. The turns endpoint (Section 5.1) supports `limit` and `order` parameters, but the polling cycle doesn't say what values to use.

The detail panel specifies `limit=20` and `order=desc` (Section 7.2), but the status overlay may need different parameters. If only 20 recent turns are fetched for status computation, a pipeline with many nodes could miss completed nodes whose turns fell outside the window.

The discovery algorithm (Section 5.5) specifies `limit=1, order=asc` for fetching the first turn — this level of specificity is needed for the status polling as well.

### Suggestion

Specify the exact `limit` and `order` parameters used when polling turns for status overlay computation. Consider whether a single fetch with a fixed limit is sufficient, or whether the algorithm needs to paginate. If a fixed limit is used, document what happens when a pipeline has more turns than the limit (e.g., "nodes whose turns fall outside the window remain in their last known status").

## Issue #3: No specification for handling multiple active runs of the same pipeline

### The problem

The spec describes pipeline discovery mapping contexts to pipelines via `graph_name`, but doesn't address what happens when CXDB contains multiple runs of the same pipeline (e.g., a developer re-runs a pipeline, producing a second `RunStarted` context with the same `graph_name`).

The status derivation algorithm merges turns from all matching contexts. If one run completed successfully and a new run is in progress, the merged turns would create conflicting status signals — the old run's turns would mark nodes as "complete" while the new run's early-stage turns might not have reached those nodes yet.

### Suggestion

Specify how to handle multiple runs of the same pipeline. Options:
1. Use only the most recent run (highest `context_id` or most recent `created_at_unix_ms`).
2. Group runs and let the user select which run to view.
3. Always use the most recent `RunStarted` context and its associated contexts.

Document the chosen approach and add a holdout scenario for "second run of same pipeline while first run's data is still in CXDB."

## Issue #4: Multi-context turn merging for parallel branches is under-specified

### The problem

Section 6.2 states: "When multiple CXDB contexts match the active pipeline, turns from all contexts are merged and sorted by depth before applying the algorithm."

The status derivation algorithm as written assumes a single linear sequence of turns. It uses "the most recent turn" to determine the "running" node and treats turns on different nodes as evidence of completion. With parallel branches, multiple nodes can genuinely be "running" simultaneously.

The spec acknowledges this parenthetically ("Each context contributes its own 'running' node if it is currently active") but the algorithm pseudocode doesn't implement this. The single `currentNodeId` variable tracks only one running node, and the algorithm would mark parallel running nodes as "complete" when it encounters a different node_id.

### Suggestion

Rewrite the status derivation algorithm to handle parallel contexts explicitly. One approach: run the algorithm independently per context, then merge the per-context status maps with "running" taking priority over "complete" (a node that is running in any context should show as running). Document the merge precedence: error > running > complete > pending.

## Issue #5: `run_id` field is present in turn data but never used

### The problem

The turn response example in Section 5.3 includes `run_id: "01KJ7JPB3C2AHNP9AYX7D19BWK"` and the context list response in Section 5.2 includes `client_tag: "kilroy/01KJ7JPB3C2AHNP9AYX7D19BWK"`. These appear to be the same identifier, linking contexts to pipeline runs.

The spec never uses `run_id` or `client_tag` for anything. This is a missed opportunity — `run_id` could help solve Issue #3 (multiple runs of the same pipeline) by grouping contexts that share the same run_id.

### Suggestion

Either document how `run_id` / `client_tag` should be used (e.g., for grouping contexts into runs) or explicitly note it as unused in a non-goals section. If used, it could replace or supplement the `graph_name` matching for pipeline discovery.

## Issue #6: CDN dependency for @hpcc-js/wasm-graphviz has no fallback or version pin

### The problem

Section 4.1 says the browser loads `@hpcc-js/wasm-graphviz` from a CDN (jsDelivr) but doesn't specify the exact version or URL. An implementing agent wouldn't know which version to use. CDN availability is also a risk for a tool used in potentially restricted environments.

### Suggestion

Specify the exact CDN URL including version pin (e.g., `https://cdn.jsdelivr.net/npm/@hpcc-js/wasm-graphviz@1.6.1/dist/index.min.js`). Consider documenting behavior if the CDN is unreachable (the graph simply won't render — consistent with "no build toolchain" but worth noting).

## Issue #7: DOT attribute parsing for detail panel is unspecified

### The problem

Section 7.1 says the detail panel "parses the DOT source to extract node attributes" like `prompt`, `tool_command`, `question`, `class`, and `goal_gate`. However, the spec provides no guidance on how to parse DOT syntax. DOT attribute values can contain escaped quotes, newlines, HTML labels, and other complex syntax.

An implementing agent would need to write a DOT parser or use a library. Given the "no build toolchain" constraint, this likely means a regex-based parser in inline JavaScript, which is error-prone for complex DOT attributes.

### Suggestion

Either:
1. Specify a simple parsing approach (e.g., regex patterns for `nodeId [key="value"]` syntax) with documented limitations.
2. State that `graph_dot` from the `RunStarted` turn should be used instead of re-parsing the DOT file.
3. Consider having the Go server parse the DOT file and expose node attributes via a JSON API endpoint (e.g., `GET /dots/{name}/nodes`).

## Issue #8: Missing holdout scenario for the last node in a pipeline

### The problem

As noted in Issue #1, the status derivation algorithm determines "complete" by observing activity on a subsequent node. The last node in a pipeline has no subsequent node. If the pipeline finishes, the last node would remain "running" forever (or until the error threshold is hit, incorrectly marking it as "error").

No holdout scenario tests this case.

### Suggestion

Add a holdout scenario:
```
Given a pipeline run has completed all nodes including the final exit node
When the UI polls CXDB
Then the final node is colored green (complete), not blue (running)
```

This would force the spec to address how the last node transitions to "complete."

## Issue #9: No specification for initial page load sequence

### The problem

The spec describes individual features (DOT rendering, CXDB polling, pipeline discovery) but doesn't describe the initialization sequence when the page first loads. An implementing agent would need to determine:

1. When does the Graphviz WASM module load? (It's async.)
2. What does the user see while WASM loads?
3. Does the first DOT file render immediately, or wait for CXDB discovery?
4. Is the first poll triggered immediately or after a 3-second delay?
5. How does the UI determine which DOT files are available? (The server has `/dots/{name}` but no endpoint to list all available DOT files.)

### Suggestion

Add a section describing the initialization sequence:
1. Browser loads `index.html`, which loads Graphviz WASM from CDN
2. While WASM loads, show a loading indicator
3. Fetch available DOT files (requires a list endpoint — see point 5 above, or embed the list in the HTML)
4. Render the first DOT file as SVG
5. Start CXDB polling immediately (first poll at t=0, then every 3 seconds)
6. First poll triggers pipeline discovery

Also add a `GET /api/dots` endpoint that returns the list of available DOT filenames, or embed the list in the served HTML.

## Issue #10: Holdout scenarios don't cover the goal_gate DOT attribute

### The problem

Section 7.1 lists `goal_gate` as a DOT attribute displayed in the detail panel, but no holdout scenario tests it. The shape-to-type mapping (Section 7.3) doesn't include a goal gate shape, and it's unclear how `goal_gate` differs from other node types visually.

### Suggestion

Either add a holdout scenario for goal gate nodes or remove `goal_gate` from the detail panel attributes if it's just a boolean flag on other node types. Clarify what a "goal gate" looks like in the graph and how it differs from other conditionals.
