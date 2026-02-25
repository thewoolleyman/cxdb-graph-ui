# CXDB Graph UI Spec — Critique v39 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-25

## Prior Context

The v38 round addressed seven issues across both critics. The opus critique resulted in: StageFinished rendering updated to show dynamic `data.status`/`data.preferred_label`/`data.failure_reason` fields instead of a fixed label; Section 5.4 type table updated with missing `StageStarted` and `StageFinished` fields; status derivation amended to map `StageFinished { status: "fail" }` to "error" instead of "complete"; Invariant #5 updated accordingly; a proposed holdout scenario written for the StageFinished fail case. The codex critique resulted in: `cachedContextLists[i]` now populated from the discovery-effective context list (fixing false stale detection when CQL returns empty); node pruning step added to `updateContextStatusMap` pseudocode; the error loop holdout scenario clarified to require errors within the current 100-turn poll window.

---

## Issue #1: Shape-to-type mapping is incomplete — five shapes used in Kilroy pipelines are missing from Section 7.3

### The problem

Section 7.3 lists six shapes in the shape-to-type label mapping table: `Mdiamond`, `Msquare`, `box`, `diamond`, `parallelogram`, `hexagon`. However, Kilroy's `shapeToType` function (`kilroy/internal/attractor/engine/handlers.go` lines 119-142) maps **ten** shapes:

```go
case "Mdiamond", "circle":       return "start"
case "Msquare", "doublecircle":  return "exit"
case "box":                      return "codergen"
case "hexagon":                  return "wait.human"
case "diamond":                  return "conditional"
case "component":                return "parallel"
case "tripleoctagon":            return "parallel.fan_in"
case "parallelogram":            return "tool"
case "house":                    return "stack.manager_loop"
```

The five missing shapes are:
- `circle` (maps to "start" — alternative to `Mdiamond`)
- `doublecircle` (maps to "exit" — alternative to `Msquare`)
- `component` (maps to "parallel" — parallel branch handler)
- `tripleoctagon` (maps to "parallel.fan_in" — fan-in handler)
- `house` (maps to "stack.manager_loop" — stack manager loop)

This has three downstream consequences:

1. **Section 7.3 table** — An implementing agent seeing a DOT file with `shape=component` nodes would not know what display label to use. The table needs entries for all ten shapes.

2. **CSS selectors in Section 6.3** — The CSS rules target `polygon`, `ellipse`, and `path` child elements. Graphviz renders `component` as an SVG `<polygon>` (it is a rectangle with a specific decoration), and `tripleoctagon` and `house` also render as `<polygon>`. `circle` renders as an `<ellipse>`. `doublecircle` renders as **two** nested `<ellipse>` elements — the CSS selectors would color both, which is likely correct but worth noting explicitly. The existing selectors likely cover all cases, but the spec should confirm this rather than leaving it to implementer investigation.

3. **Holdout scenarios** — The "Nodes rendered with correct shapes" scenario (DOT Rendering section) and the "Status coloring applies to all node shapes" scenario only list six shapes. They need to include the five additional shapes to ensure an implementation handles the full set.

### Suggestion

- Add the five missing shapes to the Section 7.3 table with appropriate display labels (e.g., "Parallel", "Parallel Fan-in", "Stack Manager Loop", and "Start"/"Exit" as aliases for the existing entries).
- Add a note in Section 6.3 confirming that the `polygon`, `ellipse`, `path` CSS selectors cover all ten shapes' SVG output, and note the `doublecircle` dual-ellipse case.
- Update the two holdout scenarios to reference all ten shapes.

## Issue #2: `RunFailed` with `node_id` falls through to the non-lifecycle "infer running" branch in the status derivation pseudocode

### The problem

Section 5.4 documents that `RunFailed` carries an optional `node_id` field, and the explanatory text at line 557 states: "RunFailed carries an optional `node_id` — when present, it participates in status derivation." The `updateContextStatusMap` pseudocode (lines 1005-1060) processes turns with these explicit type checks:

- `StageFinished` -> complete or error
- `StageFailed` -> error or running (with retry)
- `StageStarted` -> running
- `ELSE` -> running (non-lifecycle turns: infer running)

`RunFailed` has no explicit case and falls through to the `ELSE` branch, which sets `newStatus = "running"`. This means a `RunFailed` turn with `node_id` would mark the node as "running" — clearly incorrect for a pipeline-level failure event. Additionally, because `RunFailed` is not recognized as a lifecycle turn, it follows the non-lifecycle promotion path (line 1044), meaning it cannot override a node that already has `hasLifecycleResolution = true`.

Kilroy's `cxdbRunFailed` (`cxdb_events.go` line 315) always passes a `node_id` to the function, so in practice `RunFailed` turns will have `node_id` populated and will enter the status derivation.

### Suggestion

Add an explicit `RunFailed` case to the `updateContextStatusMap` pseudocode:

```
ELSE IF typeId == "com.kilroy.attractor.RunFailed":
    newStatus = "error"
    existingMap[nodeId].hasLifecycleResolution = true
```

And add `RunFailed` to the lifecycle turn override condition (lines 1040-1041) alongside `StageFinished` and `StageFailed`. The "Lifecycle turn precedence" paragraph should also mention `RunFailed` as an authoritative lifecycle signal.

## Issue #3: The `default` case in Kilroy's `shapeToType` is not reflected in the spec's shape-to-type mapping

### The problem

Kilroy's `shapeToType` function has a `default` case that returns `"codergen"` for any unrecognized shape. This means a DOT file with an arbitrary shape (e.g., `shape=octagon`, `shape=rect`) would still be handled by Kilroy as a codergen node. The spec's Section 7.3 table has no "default" or "fallback" row, so an implementer encountering an unrecognized shape in a DOT file would not know what display label to show in the detail panel.

### Suggestion

Add a default/fallback row to the Section 7.3 table: "Any other shape -> LLM Task (default)". This matches Kilroy's behavior and ensures the UI handles DOT files with unexpected shapes gracefully.

## Issue #4: No holdout scenario covers `RunFailed` with `node_id` marking a node as error

### The problem

The holdout scenarios test `StageFinished`, `StageFailed`, and the error loop heuristic for node error states, but there is no scenario testing `RunFailed` with a `node_id`. Given that `RunFailed` is a pipeline-level catastrophic failure event (distinct from per-node `StageFailed`), its interaction with the status overlay deserves explicit coverage — especially since the current pseudocode handles it incorrectly (Issue #2).

### Suggestion

Add a holdout scenario such as:

```
### Scenario: Pipeline run fails on a specific node (RunFailed with node_id)
Given a pipeline run is active with node implement in running state
  And Kilroy emits a RunFailed turn with node_id = "implement" and reason = "agent crashed"
When the UI polls CXDB
Then the implement node is colored red (error)
  And the detail panel shows the RunFailed reason
```
