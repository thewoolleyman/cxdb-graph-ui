# CXDB Graph UI Spec — Critique v11 (opus) Acknowledgement

All 3 issues were valid and applied to the specification. Issue #1 replaced cross-context turn interleaving in the detail panel with context-grouped display, eliminating cross-instance and cross-context `turn_id` comparison. Issue #2 replaced the gap recovery condition that assumed consecutive turn IDs with a sparse-ID-safe check using `oldestFetched > lastSeenTurnId` and `next_before_turn_id IS NOT null`. Issue #3 propagated `hasLifecycleResolution` through `mergeStatusMaps` so the guard in `applyErrorHeuristic` is meaningful rather than dead code. All changes were verified against the CXDB server source (`server/src/turn_store/mod.rs`) which confirms turn IDs are allocated from a global counter (`next_turn_id: u64`) shared across all contexts on an instance.

## Issue #1: Detail panel sorts cross-instance turns by `turn_id`

**Status: Applied to specification**

Adopted the critique's option (a): context-grouped display. Section 7.2 now specifies that turns from multiple contexts are displayed in collapsible sections grouped by context (labeled with CXDB instance index and context ID), rather than combined and interleaved by `turn_id`. Within each section, turns are sorted newest-first by `turn_id` (safe for intra-context ordering since the parent chain is monotonically increasing). Sections are ordered by the highest `turn_id` among matching turns as a proxy for recency within each instance. The 20-turn limit now applies per context section rather than globally. Added explicit note that cross-instance `turn_id` comparison would produce arbitrary ordering rather than temporal ordering.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 7.2 — replaced combined cross-context sort with context-grouped display, added "Context-grouped display" paragraph explaining the design and rationale

## Issue #2: Gap recovery condition assumes consecutive `turn_id` within a context

**Status: Applied to specification**

Confirmed via CXDB server source (`turn_store/mod.rs:61,408-409`) that `next_turn_id` is a global counter shared across all contexts on an instance, making intra-context turn IDs sparse (not consecutive). Replaced the `turn_id > lastSeenTurnId + 1` condition with `oldestFetched > lastSeenTurnId AND response.next_before_turn_id IS NOT null`. The first clause detects that the 100-turn fetch window doesn't reach back to the cursor without assuming consecutive IDs. The second clause (`next_before_turn_id IS NOT null`) prevents false positives when the batch already reaches the beginning of the context. Added pseudocode block and explanatory paragraph documenting why the `+ 1` assumption is incorrect for globally-allocated turn IDs.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 "Gap recovery" — replaced condition with sparse-ID-safe check, added pseudocode block and explanation of global turn ID allocation

## Issue #3: `hasLifecycleResolution` not propagated through `mergeStatusMaps`

**Status: Applied to specification**

Adopted the critique's propagation approach. Added a line to the `mergeStatusMaps` inner loop that sets `merged[nodeId].hasLifecycleResolution = true` if ANY per-context map has it true for that node. This makes the `NOT mergedMap[nodeId].hasLifecycleResolution` guard in `applyErrorHeuristic` meaningful rather than dead code (previously always evaluating to `NOT false` = `true`). Updated the prose paragraph after the merge pseudocode to explain the propagation semantics. While the dead condition was accidentally correct (a node can only be "running" in the merged map if no context has resolved it), the explicit propagation is self-documenting and defensive against future changes to the merge logic.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 `mergeStatusMaps` pseudocode — added `IF contextStatus.hasLifecycleResolution: merged[nodeId].hasLifecycleResolution = true` in the inner loop
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 "Multi-context merging" paragraph — added explanation of `hasLifecycleResolution` propagation semantics

## Not Addressed (Out of Scope)

- None — all issues were addressed.
