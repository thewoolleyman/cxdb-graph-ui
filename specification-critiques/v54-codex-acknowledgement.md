# CXDB Graph UI Spec — Critique v54 (codex) Acknowledgement

The v54-codex critique found no defects blocking implementation. Issue #1 is a confirmation that the specification is complete. Issue #2 raised a valid minor observability improvement: the `fetchFirstTurn` algorithm caps pagination at `MAX_PAGES = 50`, meaning contexts deeper than ~5000 turns are silently retried every poll cycle without any operator-visible signal. The suggestion to add a warning log at the cap-exceeded path was applied: the pseudocode now includes an explicit `SHOULD log a warning` comment, and the "Pagination cost" prose paragraph was extended to describe the repeated-deferral scenario and the expected operator-facing behavior. No holdout scenario changes were needed.

## Issue #1: No major issues blocking implementation

**Status: Not addressed (no action required)**

The critique confirms the specification is internally consistent and complete end-to-end. All previously raised blockers have been addressed. No specification changes required.

## Issue #2: Optional note on deep-context discovery retries (minor)

**Status: Applied to specification**

The suggestion is valid. Contexts that repeatedly hit the `MAX_PAGES` cap return `null` from `fetchFirstTurn` on every poll cycle, which is indistinguishable from a context that is genuinely still accumulating turns (and will eventually be discovered). Without any logging, an operator debugging a missing pipeline would have no signal that discovery is being permanently deferred due to depth. Since `fetchFirstTurn` results are not cached as negative results when `null` is returned, the retry loop is silent.

The fix adds:

1. A `SHOULD log a warning` comment in the `fetchFirstTurn` pseudocode immediately before `RETURN null` after the `MAX_PAGES` loop exits, with an example log message format (`"discovery deferred: context {contextId} exceeds MAX_PAGES pagination cap"`).

2. An extension to the "Pagination cost" prose paragraph explaining that implementations should emit a warning log when a context repeatedly hits the cap — distinguishing the permanent-deferral case (depth genuinely exceeds ~5000 turns across many poll cycles) from a transient network error, and noting that deferral continues until either the head depth decreases below the cap or a future CXDB HTTP endpoint exposes `get_first_turn` directly.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added `SHOULD log a warning` comment in `fetchFirstTurn` pseudocode at the `RETURN null` after MAX_PAGES exceeded
- `specification/cxdb-graph-ui-spec.md`: Extended "Pagination cost" paragraph to describe the repeated-deferral scenario and the operator-facing warning log expectation

## Not Addressed (Out of Scope)

- None. Both issues were evaluated and appropriately handled (Issue #1 required no action; Issue #2 was applied).
