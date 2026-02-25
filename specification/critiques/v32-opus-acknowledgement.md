# CXDB Graph UI Spec — Critique v32 (opus) Acknowledgement

All four issues from v32-opus have been evaluated against the CXDB source code (`turn_store/mod.rs`, `store.rs`, `http/mod.rs`). Three were applied to the specification. One (line number fragility) was partially addressed as a minor cleanup.

## Issue #1: The proposed holdout scenario for "forked context with depth-0 base turn" contains a factually incorrect precondition

**Status: Applied to specification**

The proposed holdout scenario has been marked as REMOVED in `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` with a detailed explanation of why the precondition is impossible: `head_depth` is updated on every `append_turn`, so a context with 50+ turns has `head_depth >= 50`, not `head_depth == 0`. Added a defensive note to the `fetchFirstTurn` fast-path in the spec explaining that `head_depth == 0` means either zero appended turns or exactly one turn at depth 0, and that the `depth == 0` guard is defensive but not exercisable for contexts with accumulated turns.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added defensive note to `fetchFirstTurn` fast-path explaining `head_depth` update semantics
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Marked the v31-opus Issue #4 proposed scenario as REMOVED with explanation

## Issue #2: The spec does not document that `ContextHead.created_at_unix_ms` is updated on each `append_turn`, potentially affecting `determineActiveRuns` ordering

**Status: Applied to specification**

This is the most significant change in this revision. Adopted suggestion (b): changed `determineActiveRuns` to use `context_id` as the primary sort key instead of `created_at_unix_ms`. Since `context_id` is allocated from a monotonically increasing global counter at context creation time and never updated, it is a stable proxy for creation order. Updated the following locations:

1. **Section 5.5 "Multiple runs" paragraph**: Replaced `created_at_unix_ms` based selection with `context_id` based selection. Added explanation of why `created_at_unix_ms` is unsuitable (updated on every `append_turn`).
2. **Section 6.1 step 3**: Updated description to reference `context_id` instead of `created_at_unix_ms`. Removed the note about retaining context list data for `created_at_unix_ms` access (no longer needed).
3. **Section 6.1 pseudocode**: Simplified `determineActiveRuns` to use `max(context_id)` per run group. Removed `createdAt` from candidate construction. Removed the `created_at_unix_ms` tiebreaker (unnecessary since `context_id` is the sole comparator).
4. **Section 5.2**: Updated CQL vs fallback sort order note to clarify that `created_at_unix_ms` reflects most recent activity, not creation time. Updated `determineActiveRuns` reference to note it uses `context_id`.
5. **Section 5.2 context list fallback**: Added clarifying note that `created_at_unix_ms` in the fallback sort reflects most recent turn timestamp, not original creation time.
6. **`lookupContext` helper description**: Updated to note it provides access to `is_live` rather than `created_at_unix_ms`.

Also wrote a proposed holdout scenario to `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` covering the late-branch active-run flip edge case (based on the identical finding in v32-codex Issue #1).

Changes:
- `specification/cxdb-graph-ui-spec.md`: Multiple sections updated (5.2, 5.5, 6.1) to use `context_id` for active run selection
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added "Active run selection stable when older run spawns late branch context" proposed scenario

## Issue #3: The CQL search response does not include `title` in the field list

**Status: Not addressed — already documented**

The spec's Section 5.2 already includes `title` in the CQL response field list: "Each context object in the `contexts` array contains: `context_id`, `head_turn_id`, `head_depth`, `created_at_unix_ms`, `is_live`, `client_tag` (from cached metadata), and `title` (from cached metadata)." The critic's analysis confirmed the spec's claim is accurate but may not have noticed `title` was already present in the list.

## Issue #4: The spec's `context_to_json` line references are fragile

**Status: Partially addressed**

Removed specific line number references from three locations in Section 5.2: the `client_tag` session-tag fallback, the empty-string filter, and the `is_live` resolution. Replaced with function name references (e.g., "`context_to_json`'s `.or_else` fallback"). Line references in other sections (e.g., `turn_store/mod.rs` references for `context_id` allocation) were retained where they provide specific value for implementers verifying behavior against the CXDB source.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Removed line number references from Section 5.2 `client_tag` and `is_live` descriptions

## Not Addressed (Out of Scope)

- None. All four issues were addressed (three applied, one confirmed already documented).
