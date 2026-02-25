# CXDB Graph UI Spec — Critique v29 (opus) Acknowledgement

All four issues from v29-opus have been evaluated. Three were applied directly to the specification with targeted edits informed by the CXDB source. The fourth (holdout scenario for forked context discovery) was deferred as a proposed holdout scenario.

## Issue #1: `view=raw` does not eliminate turn metadata dependency — `TurnMeta` is still accessed

**Status: Applied to specification**

Added a new "`view=raw` subsystem dependencies" paragraph in Section 5.3, immediately after the "Blob-level failure scope" paragraph. The note documents that `view=raw` eliminates only the type registry dependency, that the turn metadata store (`get_turn_meta` at `turn_store/mod.rs` line 496-500) and blob store are still accessed for every turn regardless of the `view` parameter, and that `declared_type` fields are extracted from `TurnMeta` unconditionally before the view-dependent code path runs (`http/mod.rs` lines 807-808). Notes that failures in either subsystem have the same blast radius as blob corruption and are handled by existing per-context error handling.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "`view=raw` subsystem dependencies" paragraph in Section 5.3 after the blob-level failure scope paragraph.

## Issue #2: `is_live` is resolved dynamically from session tracker — stale detection fires instantly

**Status: Applied to specification**

Added an "`is_live` resolution" paragraph in Section 5.2, immediately after the context list response description. Documents that `is_live` is resolved dynamically from CXDB's session tracker (not a stored field), that both CQL search and context list fallback resolve it identically (`http/mod.rs` lines 422-423 and 1313-1315), that session removal is instantaneous on disconnect, and that stale detection can fire on the very first poll cycle after an agent crash. This clarifies that the Section 8.2 statement about contexts transitioning to `is_live: false` is an instant signal, not a gradual transition.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "`is_live` resolution" paragraph in Section 5.2 after the context list response format.

## Issue #3: `ContextMetadataUpdated` SSE event is a more reliable discovery trigger than `ContextCreated`

**Status: Applied to specification**

Amended non-goal item 11 (No browser-side SSE event streaming) in Section 10 to document both `ContextCreated` and `ContextMetadataUpdated` SSE events. Notes that `ContextMetadataUpdated` fires after the metadata cache and CQL secondary indexes are populated (`events.rs` lines 27-36, Go client `ContextMetadataUpdatedEvent` at `clients/go/events.go` lines 19-25), making it the more reliable trigger for discovery. Explains the race condition with `ContextCreated`-based triggers (CQL may not yet find the context). The existing mention of `ContextMetadataUpdated` in the metadata labels optimization paragraph (Section 5.5) is complemented by this non-goal note.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Expanded non-goal item 11 with `ContextMetadataUpdated` event documentation and race condition note.

## Issue #4: No holdout scenario for forked context discovery via parent's RunStarted

**Status: Deferred — proposed holdout scenario written**

The suggested holdout scenario exercises a critical correctness path (forked context's `fetchFirstTurn` crossing the context boundary to discover the parent's `RunStarted`). This is well-documented in the spec (Section 5.5, "Cross-context traversal for forked contexts") but not covered by existing holdout scenarios. The proposed scenario has been written to `holdout-scenarios/proposed-holdout-scenarios-to-review.md` for review before incorporation.

Changes:
- `holdout-scenarios/proposed-holdout-scenarios-to-review.md`: Added "Forked context discovered via parent's RunStarted turn" proposed scenario.

## Not Addressed (Out of Scope)

- None. All four issues were either applied or deferred with proposed holdout scenarios.
