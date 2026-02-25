# CXDB Graph UI Spec — Critique v32 (codex) Acknowledgement

The single issue from v32-codex has been applied to the specification. This finding overlaps with v32-opus Issue #2 — both critics independently identified the `created_at_unix_ms` update semantics as a correctness risk for active run selection.

## Issue #1: Active run selection can flip to an older run when late branch contexts are created

**Status: Applied to specification**

Changed `determineActiveRuns` to use `context_id` as the primary (and sole) sort key for active run selection, instead of `max(created_at_unix_ms)`. CXDB's `context_id` is allocated from a monotonically increasing global counter at context creation time and never updated, making it a stable proxy for creation order. This eliminates the flip scenario where an older run's late branch context receives a turn with a newer timestamp than the current run's contexts.

The codex critique suggested using `min(created_at_unix_ms)` or the root context's `created_at_unix_ms`. The opus critique (v32-opus Issue #2) suggested using `context_id` as the primary sort key. We adopted the `context_id` approach because it is simpler (no need to identify root contexts) and immune to the `append_turn` update semantics entirely.

Wrote a proposed holdout scenario to `holdout-scenarios/proposed-holdout-scenarios-to-review.md` covering the late-branch active-run flip edge case, as the codex critique suggested.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated `determineActiveRuns` in Sections 5.5 and 6.1 to use `context_id` instead of `created_at_unix_ms`
- `holdout-scenarios/proposed-holdout-scenarios-to-review.md`: Added "Active run selection stable when older run spawns late branch context" proposed scenario

## Not Addressed (Out of Scope)

- None. The single issue was fully applied.
