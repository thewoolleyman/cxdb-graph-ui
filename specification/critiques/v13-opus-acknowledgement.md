# CXDB Graph UI Spec — Critique v13 (opus) Acknowledgement

All 3 issues were valid and applied to the specification. Issue #1 documented the `view=typed` type registry dependency and generalized per-context turn fetch error handling beyond 502. Issue #2 guarded the `fetchFirstTurn` `headDepth == 0` branch against empty contexts. Issue #3 added explicit pseudocode for the gap recovery pagination loop and clarified the "at most once" statement. All claims were verified against the CXDB server source (`server/src/http/mod.rs`).

## Issue #1: `view=typed` turn fetch fails entirely if any turn's type is unregistered — spec has no error handling for this failure mode

**Status: Applied to specification**

Verified against CXDB source: `http/mod.rs:847-850` shows the `?` operator propagating a `StoreError::NotFound("type descriptor")` when any turn's declared type is missing from the registry, aborting the entire per-context turn fetch request with no per-turn fallback.

Applied both suggested changes:

1. **Section 5.3** — Added a "Type registry dependency" paragraph after the query parameters table. Documents that `view=typed` requires the `kilroy-attractor-v1` registry bundle to be published, explains the failure mode (entire context fetch fails if any single turn has an unregistered type), lists the three practical scenarios where this occurs (development, version mismatch, forked contexts), and cross-references Section 6.1 step 4 for the error handling behavior.

2. **Section 6.1 step 4** — Generalized per-context error handling. The step now specifies that any non-200 response from a per-context turn fetch (not just 502 instance-level failures) causes the context to be skipped for that poll cycle, retaining its cached turns and per-context status map from the last successful fetch. This prevents a single context's type registry issue from crashing the poll cycle or losing status for other contexts.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 5.3 — added type registry dependency paragraph
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 step 4 — added per-context non-200 error handling

## Issue #2: `fetchFirstTurn` crashes on empty contexts when `headDepth == 0`

**Status: Applied to specification**

The critique correctly identified that `headDepth == 0` is ambiguous — it represents both a context with exactly one turn and a newly created empty context (no turns yet, `head_turn_id: "0"`). The original code unconditionally accessed `turns[0]` which would be an out-of-bounds access for an empty context.

Applied the guard approach from the critique's suggestion:

**Section 5.5** — Updated the `headDepth == 0` branch to fetch into a variable, check for empty results, and return `null` if the context has no turns. Updated the comment from "exactly one turn" to "at most one turn" and added a note explaining the empty context race condition.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 5.5 `fetchFirstTurn` — guarded `headDepth == 0` branch against empty contexts

## Issue #3: Gap recovery pagination is described in prose but lacks pseudocode

**Status: Applied to specification**

The critique correctly identified that gap recovery was the only algorithm in the spec described solely in prose, despite having non-trivial pagination logic (backward pagination with cursor, prepending for oldest-first order, termination conditions).

Applied the suggested pseudocode and clarified the ambiguous "at most once" statement:

**Section 6.1** — Added a "Gap recovery pseudocode" block after the gap detection condition pseudocode. The pseudocode shows the backward pagination loop using `next_before_turn_id`, the prepend-to-maintain-oldest-first pattern (`gapResponse.turns + recoveredTurns`), the `lastSeenTurnId` termination check on `gapResponse.turns[0]` (oldest turn in each page), and the final prepend to the main batch. Also clarified the "at most once" statement to: "The gap recovery procedure runs at most once per context per poll cycle. Within the procedure, multiple paginated requests may be issued (one per 100 missed turns)."

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 — added gap recovery pseudocode and clarified "at most once" statement

## Not Addressed (Out of Scope)

- None — all issues were addressed.
