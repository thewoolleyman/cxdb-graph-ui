# CXDB Graph UI Spec — Critique v5 (opus) Acknowledgement

All 4 issues were valid. Issues #1–#3 were applied directly to the specification. Issue #4 (holdout scenario gaps) is not addressed — holdout scenarios are a separate document outside the scope of spec revision. The spec changes for Issues #1–#3 make the behaviors testable; holdout scenarios can be updated independently.

## Issue #1: 100-turn fetch window causes completed nodes to revert to "pending"

**Status: Applied to specification**

This was a genuine correctness bug. The status map was rebuilt from scratch each poll cycle, so nodes whose lifecycle turns fell outside the 100-turn window would revert to "pending." The fix introduces a **persistent status map** with promotion-only semantics:

1. Per-context status maps are initialized once (all nodes "pending") and persist across poll cycles.
2. The `buildContextStatusMap` function was renamed to `updateContextStatusMap` and now takes the existing map as input. Statuses are only promoted (pending → running → complete, any → error), never demoted.
3. The status map resets only when the active `run_id` changes (new pipeline run detected).
4. The merged display map is recomputed each cycle from the persistent per-context maps.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 rewritten with persistent status map lifecycle, `updateContextStatusMap` algorithm with promotion-only semantics, and updated merge description
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 polling step 4 updated to reference `updateContextStatusMap`
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 turn fetch limit paragraph rewritten to acknowledge the window limitation and reference the persistent map

## Issue #2: Detail panel turn source is underspecified

**Status: Applied to specification**

Section 7.2 now explicitly specifies:
1. Turns are filtered from the polled 100-turn window by matching `turn.data.node_id` to the selected node's DOT ID.
2. Turns from multiple contexts (parallel branches) are combined and sorted newest-first by `turn_id`.
3. When all of a node's turns have scrolled out of the poll window, the detail panel shows DOT attributes but displays "No recent CXDB activity" instead of the turn list.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 7.2 expanded with explicit filtering, multi-context behavior, and empty-window message

## Issue #3: Graph ID parsing for tab labels is unspecified

**Status: Applied to specification**

Section 4.4 now specifies:
1. The browser extracts the graph ID from the DOT source when the file is first fetched (not at tab construction time from `/api/dots`).
2. The extraction uses the regex `/digraph\s+("(?:[^"\\]|\\.)*"|\w+)/` which handles both quoted and unquoted names.
3. Tabs initially display filenames and update to graph IDs as DOT files are fetched.
4. If the regex does not match, the tab falls back to the base filename.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 4.4 expanded with "Graph ID extraction" paragraph specifying regex, timing, and fallback behavior

## Issue #4: Holdout scenarios missing coverage for persistent status and turn window edge cases

**Status: Not addressed (out of scope)**

The holdout scenarios are a separate document (`holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`) maintained independently from the spec. The spec revisions for Issues #1–#3 define the behaviors precisely enough that corresponding scenarios can be written. The suggested scenarios (completed node retaining status across polls, detail panel for early-completed node, tab showing graph ID) are valid test cases but belong in a holdout scenario update pass, not in the spec revision.
