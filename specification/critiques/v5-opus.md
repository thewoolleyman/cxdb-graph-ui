# CXDB Graph UI Spec — Critique v5 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v4 critique raised 5 issues. Two were rejected as incorrect (the spec's `created_at_unix_ms` and `is_live` fields were verified against CXDB source code). Three were applied: SSE was added as Non-Goal #11, `active_sessions` fields were expanded, and the discovery algorithm was rewritten with concrete `fetchFirstTurn` pagination using `before_turn_id`. The spec now has a two-phase discovery algorithm with `client_tag` prefix filtering and backward pagination.

---

## Issue #1: 100-turn fetch window causes completed nodes to revert to "pending"

### The problem

Section 6.1 fetches `limit=100` turns per context per poll cycle. Section 6.2's `buildContextStatusMap` initializes every node to `"pending"` and then processes only the turns within that 100-turn window. The status map is recomputed from scratch on every poll cycle.

Consider a pipeline where node A completes, then node B starts and generates 150 tool calls before finishing. The `StageFinished` turn for node A is now beyond the 100-turn window. On the next poll:

1. `buildContextStatusMap` initializes node A to `"pending"`
2. The 100 fetched turns contain only turns for node B (and maybe node C)
3. No turns for node A are in the window
4. Node A remains `"pending"` — it visually reverts from green to gray

The spec claims (Section 6.1): "For very long-running nodes that generate many turns, older turns outside the window are irrelevant — the most recent lifecycle turn for each node determines its status." This claim is incorrect. The most recent lifecycle turn for node A *does* determine its status, but that turn is outside the fetch window, so the algorithm never sees it.

This is a correctness bug that would manifest during any pipeline where a single node generates more than ~100 turns (common for LLM task nodes running complex implementations).

### Suggestion

Maintain a **persistent status map** that accumulates across poll cycles rather than recomputing from scratch. Specifically:

1. Initialize the status map once (all nodes "pending") when a pipeline is first displayed.
2. On each poll, process fetched turns and **promote** node statuses (pending → running → complete, or any → error) but never **demote** them. A node that reached "complete" stays "complete" even if its lifecycle turns fall outside the fetch window.
3. Only reset the status map when the active `run_id` changes (new pipeline run detected).

Update the `buildContextStatusMap` pseudocode to accept the existing map as input and only apply promotions, not reinitialize. Update the merge algorithm similarly.

## Issue #2: Detail panel turn source is underspecified

### The problem

Section 7.2 says turns are "filtered from the most recent poll data" and "at most 20 turns per node." But the poll data contains at most 100 turns *across all nodes*. Several ambiguities remain:

1. **Are detail panel turns a subset of the 100 polled turns?** If so, a node that completed 200 turns ago would show zero turns in the detail panel, even though the user just clicked it to see what happened.

2. **What does "filtered" mean?** The 100 polled turns are for the entire context. Does the detail panel filter by `turn.data.node_id == selectedNodeId`? This is implied but never stated explicitly.

3. **What if the node has turns across multiple contexts?** Section 6.2 merges status maps across contexts, but Section 7.2 doesn't specify whether the detail panel shows turns from all matching contexts or just one.

An implementing agent would need to make several design decisions that the spec leaves open.

### Suggestion

Add explicit detail panel data flow:

1. State that turns displayed are filtered from the polled turns by matching `turn.data.node_id` to the selected node's DOT ID.
2. Specify whether turns from multiple contexts (parallel branches) are interleaved or grouped.
3. Acknowledge the limitation: if all of a node's turns have scrolled out of the 100-turn poll window, the detail panel shows no CXDB activity for that node. (Or, if Issue #1's persistent map is adopted, consider caching turns per-node as well.)

## Issue #3: Graph ID parsing for tab labels is unspecified

### The problem

Section 4.4 says tabs are "labeled with the DOT file's graph ID (extracted from the `digraph <name> {` declaration) or the filename if parsing fails." However, the spec does not specify:

1. **Where this parsing happens** — server-side or browser-side? The `/api/dots` endpoint returns only filenames. The browser fetches the raw DOT content. Presumably the browser parses it, but this is not stated.

2. **What regex or parsing method to use.** DOT graph declarations can vary: `digraph foo {`, `digraph "foo bar" {`, `digraph{` (no space). A naive regex could fail on quoted names or missing whitespace.

3. **When parsing happens.** Is the graph ID extracted once when tabs are built (from the DOT list endpoint), or when each DOT file is first fetched? If tabs are built from `/api/dots` (which returns only filenames), the graph ID isn't available until the DOT file is fetched.

### Suggestion

Specify that the browser extracts the graph ID from the DOT source when the file is first fetched, using a pattern like `/digraph\s+("(?:[^"\\]|\\.)*"|\w+)/` (handling both quoted and unquoted names). Tabs initially show filenames and update to graph IDs as DOT files are fetched. Alternatively, have the server extract graph IDs and include them in the `/api/dots` response.

## Issue #4: Holdout scenarios missing coverage for persistent status and turn window edge cases

### The problem

The holdout scenarios do not test:

1. **Completed node reverting to pending** — No scenario covers a long-running node pushing earlier nodes' lifecycle turns out of the 100-turn window. This is the most likely real-world failure mode (Issue #1).

2. **Detail panel for a node with no recent turns** — No scenario covers clicking a node that completed early in the pipeline and whose turns are no longer in the poll window.

3. **Tab label showing graph ID vs filename** — No scenario verifies that tabs display the graph ID from the DOT `digraph` declaration.

4. **Multiple poll cycles** — Most scenarios describe a single poll. No scenario verifies that status is stable across multiple poll cycles (e.g., a completed node stays green on subsequent polls).

### Suggestion

Add holdout scenarios:

```
### Scenario: Completed node retains status across polls
Given node A completed and node B is running with 150+ tool call turns
When the UI polls CXDB
Then node A remains green (complete), not gray (pending)
  And node B is blue (running)

### Scenario: Detail panel for early-completed node
Given node A completed 200+ turns ago
When the user clicks node A
Then the detail panel shows node A's DOT attributes
  And indicates no recent CXDB activity is available in the poll window

### Scenario: Tab shows graph ID from DOT declaration
Given a DOT file containing "digraph alpha_pipeline {"
When the UI renders the tab bar
Then the tab label is "alpha_pipeline", not the filename
```
