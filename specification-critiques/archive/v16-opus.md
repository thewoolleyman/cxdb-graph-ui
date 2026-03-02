# CXDB Graph UI Spec — Critique v16 (opus)

**Critic:** opus (Claude Opus 4.6)
**Date:** 2026-02-24

## Prior Context

The v15 critique raised 3 issues, all applied: (1) added a per-type field inventory to Section 5.4 with key data fields per turn type; (2) corrected the `limit` parameter from "1–65535" to "u32 with no enforced maximum" and removed the 65535 cap in `fetchFirstTurn`; (3) added stale pipeline detection using `is_live`, introducing the "stale" node status for crashed/dead pipelines. All were verified against the CXDB server source.

---

## Issue #1: Section 5.5 prose still references "capped at the CXDB maximum of 65,535" — contradicts the v15 fix

### The problem

The v15 revision correctly updated the `fetchFirstTurn` pseudocode to use `fetchLimit = headDepth + 1` without a 65535 cap, and updated the comment within the pseudocode to say "CXDB parses limit as u32 with no enforced maximum." However, the prose paragraph immediately before the `fetchFirstTurn` pseudocode (line 453) still reads:

> "the algorithm requests up to `headDepth + 1` turns (capped at the CXDB maximum of 65,535) to fetch the entire context in as few requests as possible"

This directly contradicts the corrected pseudocode and the Section 5.3 `limit` parameter description. An implementer reading the prose would apply a 65535 cap; an implementer reading the pseudocode would not. The spec now contains two conflicting specifications for the same behavior.

### Suggestion

Update the Section 5.5 prose (line 453) to match the corrected pseudocode. Replace:

> "the algorithm requests up to `headDepth + 1` turns (capped at the CXDB maximum of 65,535) to fetch the entire context in as few requests as possible"

with:

> "the algorithm requests `headDepth + 1` turns to fetch the entire context in a single request"

This aligns with both the pseudocode and the v15 acknowledgement's statement that "the first turn is always fetched in a single request regardless of context depth."

---

## Issue #2: `applyErrorHeuristic` function signature includes unused `turnCache` parameter alongside `perContextCaches`

### The problem

The `applyErrorHeuristic` pseudocode in Section 6.2 (line 755) has this signature:

```
FUNCTION applyErrorHeuristic(mergedMap, dotNodeIds, turnCache, perContextCaches):
```

The function body only uses `perContextCaches` — the `turnCache` parameter is never referenced. The preceding prose (line 752) explains the historical reason: "the `turnCache` parameter was previously referenced but not passed to `updateContextStatusMap`." This explanatory note acknowledges the parameter is vestigial but doesn't remove it.

For an implementer, an unused parameter in pseudocode raises questions: Is it needed for a side effect? Is it passed through to a helper? Is there an implementation detail the pseudocode omits? The function's call site in step 6 (line 572) says "using the per-pipeline turn cache," further muddying which parameter is the actual data source.

### Suggestion

Remove `turnCache` from the function signature:

```
FUNCTION applyErrorHeuristic(mergedMap, dotNodeIds, perContextCaches):
```

And update the step 6 call description to say "using the per-context turn caches for the active pipeline" instead of "using the per-pipeline turn cache" to match the actual parameter name.

---

## Issue #3: Detail panel context-section ordering criterion is ambiguous — "highest `head_turn_id` among its matching turns" conflates context-level and turn-level concepts

### The problem

Section 7.2 (line 838) specifies the ordering of context sections in the detail panel:

> "Sections are ordered by recency: the context with the highest `head_turn_id` among its matching turns appears first (as a proxy for most recent activity within each CXDB instance)."

This sentence is grammatically ambiguous and conflates two different concepts:

1. **`head_turn_id`** is a context-level property from the context list response (Section 5.2) — it represents the newest turn in the entire context, across all nodes.

2. **"among its matching turns"** implies filtering to turns that match the selected node's `node_id`.

These cannot both be true. Either:
- (a) Sort context sections by the context's `head_turn_id` (a context-level property, unrelated to the selected node), or
- (b) Sort context sections by the highest `turn_id` among the context's turns that match the selected node (a node-specific recency signal).

Interpretation (b) is more useful for the detail panel — if a context has recent activity on the selected node, its section should appear first, regardless of the context's overall activity. But interpretation (a) is what `head_turn_id` literally means. An implementer could reasonably choose either.

### Suggestion

Clarify the ordering to use node-specific recency. Replace the ambiguous sentence with:

> "Sections are ordered by recency: for each context that has matching turns, compute the highest `turn_id` among its turns for the selected node. The context with the highest such `turn_id` appears first. This uses intra-context `turn_id` ordering (safe within a single context's parent chain). Contexts from different CXDB instances are ordered independently by this criterion — cross-instance `turn_id` comparison is not meaningful."

If the intent was actually to use the context-level `head_turn_id`, then remove "among its matching turns" and note that this is a coarse proxy that may not reflect the selected node's recency.
