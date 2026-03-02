# CXDB Graph UI Spec — Critique v55 (codex) Acknowledgement

The v55-codex critique found no blocking issues. Issue #1 confirms the specification remains internally consistent across all sections — server flow, DOT parsing, CXDB discovery pipeline, polling/status overlay, and detail panel. Issue #2 identified a minor holdout gap: the spec's `fetchFirstTurn` pseudocode now includes a `SHOULD log a warning` directive (added in the v54 cycle) for contexts that exhaust the MAX_PAGES cap, but no holdout scenario exercised or validated that path. A scenario was added to `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` under the Pipeline Discovery section that describes a context with head_depth > 5000, asserts exactly 50 paginated requests are issued, verifies the warning log is emitted with the context ID, confirms the context is not cached as a negative result, and confirms it is retried on the next poll cycle. The spec file itself was not modified.

## Issue #1: No major issues blocking implementation

**Status: Not addressed (no action required)**

The critique confirms the specification is internally consistent and complete end-to-end. No specification changes required.

## Issue #2: Holdouts do not assert the new pagination-cap warning (minor)

**Status: Applied to holdout scenarios**

The suggestion is valid. The spec requires implementations to emit a warning when `fetchFirstTurn` returns `null` after exhausting MAX_PAGES (50 pages × 100 turns = 5000 turns), but no holdout scenario validated this path. A regression in the warning or in the non-caching behavior (the context must remain uncached and be retried, not permanently blacklisted) would be silent.

The new scenario — "Context exceeding MAX_PAGES pagination cap emits warning and defers discovery" — covers:
1. A context with `head_depth > 5000` and a valid `kilroy/` client_tag (passes Phase 1 filter)
2. Assertion that exactly 50 pages are requested with `limit=100` and `view=raw`
3. Assertion that `fetchFirstTurn` returns null after exhausting pages
4. Assertion that a warning log containing "discovery deferred" and the context ID is emitted (matching the example format in the spec pseudocode)
5. Assertion that the context is NOT cached as a negative result
6. Assertion that the context is retried on the next poll cycle

The scenario is consistent with the `get_first_turn` behavior in `cxdb/server/src/turn_store/mod.rs` (which walks `parent_turn_id` from head to depth=0) and the `head_depth` field on `ContextHead` which determines whether the pagination loop will be entered and how many pages are needed.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added scenario "Context exceeding MAX_PAGES pagination cap emits warning and defers discovery" under Pipeline Discovery section

## Not Addressed (Out of Scope)

- None. Both issues were evaluated and appropriately handled (Issue #1 required no action; Issue #2 was applied to holdout scenarios).
