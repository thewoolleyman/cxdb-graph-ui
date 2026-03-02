# CXDB Graph UI Spec — Critique v17 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v16 cycle had two critics (opus and codex). Opus's 3 issues were all applied: (1) removed stale 65535 cap prose in Section 5.5, (2) removed vestigial `turnCache` parameter from `applyErrorHeuristic`, (3) clarified detail panel context-section ordering to use node-specific `turn_id`. Codex's 2 issues were also applied: (1) added duplicate DOT basename rejection at startup with a holdout scenario, (2) added the missing stale pipeline holdout scenario.

---

## Issue #1: SVG status class application never removes previous status classes — visual corruption on node transitions

### The problem

Section 4.2 defines the matching algorithm for applying status to SVG nodes:

```
FOR EACH g IN svg.querySelectorAll('g.node'):
    nodeId = g.querySelector('title').textContent.trim()
    status = nodeStatusMap[nodeId] OR "pending"
    g.setAttribute('data-status', status)
    g.classList.add('node-' + status)
```

Section 6.3 says "Status classes are reapplied on every poll cycle. The SVG itself is not re-rendered — only `data-status` attributes and CSS classes are updated."

The problem: `classList.add` only adds classes — it never removes them. When a node transitions from `running` to `complete`, the element ends up with both `node-running` and `node-complete` classes. Both CSS rules apply simultaneously: the node gets green fill from `node-complete` AND the pulse animation from `node-running`. The visual result is a green pulsing node — a state that doesn't exist in the status model and misleads the operator into thinking the node is still active.

The `data-status` attribute is set correctly, but the CSS selectors in Section 6.3 target class names (`.node-running`, `.node-complete`), not the `data-status` attribute. So the attribute alone doesn't fix the rendering.

### Suggestion

Update the Section 4.2 matching algorithm to remove all status classes before adding the current one:

```
STATUS_CLASSES = ["node-pending", "node-running", "node-complete", "node-error", "node-stale"]

FOR EACH g IN svg.querySelectorAll('g.node'):
    nodeId = g.querySelector('title').textContent.trim()
    status = nodeStatusMap[nodeId] OR "pending"
    g.setAttribute('data-status', status)
    g.classList.remove(...STATUS_CLASSES)
    g.classList.add('node-' + status)
```

---

## Issue #2: `fetchFirstTurn` loop always makes an unnecessary second HTTP request despite prose claiming "single request"

### The problem

Section 5.5 prose states: "the algorithm requests `headDepth + 1` turns to fetch the entire context in a single request" and "the first turn is always fetched in a single request regardless of context depth."

But the `fetchFirstTurn` pseudocode (line 456) uses a pagination loop. When `headDepth > 0`, the loop sets `fetchLimit = headDepth + 1` and fetches. For a well-formed context with exactly `headDepth + 1` turns:

1. First request: returns all `headDepth + 1` turns. `response.turns.length == fetchLimit`, so the `< fetchLimit` break condition is NOT met. `response.next_before_turn_id` is non-null (set to the oldest turn's ID per Section 5.3), so the `IS null` break condition is NOT met. The loop continues.
2. Second request: uses `before_turn_id = <oldest turn's ID>`, which returns 0 turns. The `turns IS EMPTY` break fires.

The algorithm makes 2 HTTP requests every time, not 1 as the prose claims. Since discovery runs once per context, the extra request doubles the HTTP cost of pipeline discovery. With many contexts (the spec uses `limit=10000`), this could mean thousands of unnecessary requests on initial page load.

### Suggestion

Add an explicit break after the first fetch when all turns are returned. The simplest fix: since `fetchLimit = headDepth + 1` is designed to return all turns in one request, remove the loop entirely for the `headDepth > 0` case and use a single fetch:

```
FUNCTION fetchFirstTurn(cxdbIndex, contextId, headDepth):
    IF headDepth == 0:
        response = fetchTurns(cxdbIndex, contextId, limit=1)
        IF response.turns IS EMPTY:
            RETURN null
        RETURN response.turns[0]

    -- Fetch the entire context in one request.
    -- headDepth + 1 = total turn count. CXDB parses limit as u32 with no enforced maximum.
    response = fetchTurns(cxdbIndex, contextId, limit=headDepth + 1)
    IF response.turns IS EMPTY:
        RETURN null
    RETURN response.turns[0]  -- oldest turn (oldest-first ordering) = first turn
```

If a defensive fallback loop is desired (in case `headDepth` is stale), keep the loop but add an additional break condition: `IF response.turns.length == fetchLimit: BREAK` — this correctly terminates when the server returns exactly as many turns as requested, meaning the full context was fetched.

---

## Issue #3: Error loop holdout scenario does not match the spec's ToolResult-only heuristic — implementer could check all turn types and still pass

### The problem

The holdout scenario for error loop detection (line 87 of holdout scenarios) reads:

```
Given a pipeline run is active
  And the most recent 3+ turns on a node have is_error: true
When the UI polls CXDB
Then that node is colored red (error)
```

The spec's `applyErrorHeuristic` (Section 6.2, line 755) is more specific: it calls `getMostRecentToolResultsForNodeInContext`, which only examines `ToolResult` turns (turns whose `declared_type.type_id` is `com.kilroy.attractor.ToolResult`). The spec explicitly explains why: "Only `ToolResult` turns carry the `is_error` field ... including [other turn types] would dilute the error detection window and prevent the heuristic from firing during typical error loops where turn types interleave as Prompt → ToolCall → ToolResult."

The holdout scenario says "the most recent 3+ turns" without specifying they must be `ToolResult` turns. An implementer testing against the holdout could check all turn types. In a real error loop, the interleaving pattern is Prompt → ToolCall → ToolResult(error) → Prompt → ToolCall → ToolResult(error) → ..., so the 3 most recent turns of ANY type would be [Prompt, ToolCall, ToolResult] — only 1 of which has `is_error: true`. The test would pass (the implementer's broader check would also detect 3 consecutive ToolResult errors) but the implementation would be wrong (it would fail to detect errors when non-ToolResult turns interleave).

### Suggestion

Update the holdout scenario to be specific about the turn type filter:

```
Given a pipeline run is active
  And the 3 most recent ToolResult turns on a node each have is_error: true
  And non-ToolResult turns (Prompt, ToolCall) are interleaved between them
When the UI polls CXDB
Then that node is colored red (error)
```

The interleaving condition is important — it ensures the test distinguishes between "check all turns" and "check only ToolResult turns."
