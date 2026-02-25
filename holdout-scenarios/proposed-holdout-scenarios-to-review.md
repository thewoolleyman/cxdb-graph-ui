# Proposed Holdout Scenarios — To Review

Scenarios proposed during spec critique rounds that need review before incorporation into the holdout scenarios document.

---

## Per-context error scoping in "Agent stuck in error loop" scenario

**Source:** v22-opus critique, Issue #5

**Problem:** The existing "Agent stuck in error loop" holdout scenario is ambiguous about per-context scoping. The spec's `applyErrorHeuristic` pseudocode (Section 6.2) clearly defines per-context scoping via `getMostRecentToolResultsForNodeInContext`, but the holdout scenario doesn't reflect this.

**Proposed changes:**
1. Update the existing "Agent stuck in error loop" scenario to clarify that error detection is scoped per-context (errors in one context don't affect another context's node status)
2. Add a negative case: errors occurring across multiple contexts for the same node should NOT trigger the error heuristic unless they occur within a single context's recent tool results
