# CXDB Graph UI Spec — Critique v17 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-24

## Prior Context

v16’s issues were all applied: duplicate DOT basenames are now rejected at startup with a holdout scenario, the stale-pipeline detection scenario was added to holdouts, the 65,535 cap reference was removed, the `applyErrorHeuristic` signature was cleaned up, and the detail-panel context ordering now uses node-specific recency.

---

## Issue #1: Human gate “choices” are specified but no source for outgoing edge labels is defined

### The problem
The holdout scenario “Click a human gate node” requires “Available choices from outgoing edge labels.” However, the spec only defines server-side parsing for node attributes (`GET /dots/{name}/nodes`) and does not define any mechanism to extract edge labels. The browser-side rendering description (Section 4.3) identifies edge titles in the SVG but does not describe how to map outgoing edges to label text, nor does it guarantee that Graphviz emits label text in a parseable place. An implementer can meet the current spec without any way to populate the “choices” field for human gates, which contradicts the holdout scenario.

### Suggestion
Add a concrete data source for edge labels. Options:
- Extend the server with `GET /dots/{name}/edges` returning `{ source, target, label }` from DOT parsing, and use that to populate human-gate choices.
- Or explicitly require the client to parse edge labels from the SVG (e.g., `g.edge title` plus associated `text` label), with clear rules for matching source node IDs to outgoing edges.

Whichever approach is chosen, update Section 7.2 to reference the defined source for human-gate choices, and add a small note in DOT parsing rules about edge label parsing if it is server-side.

---

## Issue #2: Polling error handling for failed turn fetches is untested in holdout scenarios

### The problem
Section 6.1 step 4 specifies a critical resilience rule: if a per-context turn fetch returns a non-200 response (e.g., missing type registry or transient server error), the UI must skip that context for the poll cycle and retain its cached turns and status map. This behavior is essential for correctness when a single context has unregistered types, but no holdout scenario covers it. An implementation could ignore this and still satisfy all existing holdouts.

### Suggestion
Add a holdout scenario under “CXDB Connection Handling” (or “Status Overlay”) that exercises the non-200 turn fetch path. Example:

```
### Scenario: Turn fetch fails for one context
Given a pipeline run is active across multiple contexts
  And one context returns a non-200 response when fetching turns (e.g., type registry missing)
When the UI polls CXDB
Then the failing context is skipped for that poll cycle
  And its last known node status remains visible
  And other contexts continue to update normally
```

This makes the error-handling contract testable and aligns with the spec’s resilience guarantees.
