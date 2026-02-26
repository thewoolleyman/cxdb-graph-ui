# CXDB Graph UI Spec — Critique v50 (codex) Acknowledgement

Both issues were validated and applied. Issue #1 identified a genuine starvation bug in the null-tag backlog loop: slicing `nullTagCandidates` to `[0..NULL_TAG_BATCH_SIZE]` before iteration means that once the first N contexts are cached in `knownMappings`, they permanently occupy the top of the sorted list and the `CONTINUE` skip exhausts the slice without ever reaching the (N+1)th context. The fix changes the loop to iterate the full sorted list with an explicit `nullTagProcessed` counter, breaking only when `nullTagProcessed >= NULL_TAG_BATCH_SIZE` — ensuring already-cached entries do not consume batch slots. Issue #2 identified a transitional-deployment gap: the supplemental fetch only ran when CQL returned empty results, so legacy null-tag contexts were permanently invisible when CQL had any data. The fix removes the `IF contexts IS EMPTY` guard around the supplemental fetch, making it run on every CQL-supported poll cycle; `kilroy/`-prefixed contexts from the supplemental pass are still only appended when CQL is empty (to avoid duplicates), but null-tag context collection is now unconditional. A holdout scenario for each issue was added to the holdout scenarios file.

## Issue #1: Null-tag backlog skips older contexts once the newest are cached

**Status: Applied to specification**

The critique is correct. The old loop `FOR EACH context IN nullTagCandidates[0..NULL_TAG_BATCH_SIZE]` truncates the list before iteration. When five (or more) null-tag contexts are already in `knownMappings`, the loop body executes `CONTINUE` for each of the N slots in the slice and exits without ever examining index N or beyond. This is permanent — the newer contexts stay at the top of the descending-context_id sort every poll cycle.

The fix:

1. Added `nullTagProcessed = 0` initialization before the loop.
2. Changed `FOR EACH context IN nullTagCandidates[0..NULL_TAG_BATCH_SIZE]` to `FOR EACH context IN nullTagCandidates:` with `IF nullTagProcessed >= NULL_TAG_BATCH_SIZE: BREAK` at the top of the loop body.
3. Added `nullTagProcessed++` after `fetchFirstTurn` is invoked (in both the success and transient-failure paths), with an explicit comment that the `knownMappings` skip does NOT count toward the batch limit.
4. Updated the comment block above the loop to explain why iteration over the full list (not a slice) is necessary.
5. Updated the "Fallback behavior until Kilroy implements key 30" prose paragraph to note the counter-based approach and the starvation prevention.
6. Updated the "Consequences for discovery" bullet to reference the counter-based iteration.

A holdout scenario was added to prove that when six null-tag contexts exist and the five newest are already cached, the sixth is still discovered within the same poll cycle.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Changed `FOR EACH context IN nullTagCandidates[0..NULL_TAG_BATCH_SIZE]` to full-list iteration with explicit `nullTagProcessed` counter; added `BREAK` guard; added `nullTagProcessed++` in both success and catch paths; updated surrounding comments and prose

## Issue #2: Supplemental discovery never runs alongside non-empty CQL results

**Status: Applied to specification**

The critique is correct. In a mixed deployment (Kilroy partially upgraded to emit key 30), CQL returns new contexts while legacy completed runs remain invisible to CQL. The `IF contexts IS EMPTY` guard around the supplemental fetch meant those legacy contexts were never collected into `supplementalNullTagCandidates` and thus never processed by the null-tag backlog. This is the opposite of graceful degradation.

The fix removes the `IF contexts IS EMPTY` wrapper from the supplemental fetch entirely. The supplemental `fetchContexts(index, limit=10000)` now runs unconditionally whenever `cqlSupported[index] != false`. Inside the supplemental loop:
- `kilroy/`-prefixed contexts are appended to `contexts` only when `contexts IS EMPTY` (preventing duplicates when CQL already returned them).
- `null`-tag contexts are appended to `supplementalNullTagCandidates` unconditionally (regardless of whether CQL had results).

Prose changes:
- Rewrote the "CQL discovery limitation" paragraph to describe the always-run supplemental fetch and its two roles (active-session kilroy discovery when CQL is empty; null-tag backlog collection always).
- Rewrote the "Fallback behavior until Kilroy implements key 30" paragraph to explain the mixed-deployment scenario.
- Updated the "Consequences for discovery" bullet for the null-tag backlog to note the unconditional supplemental pass.
- Updated the pseudocode comment block describing `supplementalNullTagCandidates` and the null-tag backlog sources.

A holdout scenario was added for the mixed-deployment case: CQL returns one modern context; supplemental returns both the modern context and a legacy null-tag context; the legacy context is discovered via the null-tag backlog; the modern context is not duplicated.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Removed `IF contexts IS EMPTY` guard on supplemental fetch; added `IF contexts IS EMPTY` guard only on the kilroy-prefix append inside the supplemental loop; updated all prose and pseudocode comments describing supplemental fetch behavior

## Not Addressed (Out of Scope)

- None. Both issues were valid and fully addressed.
