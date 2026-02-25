# CXDB Graph UI Spec — Critique v33 (opus) Acknowledgement

All four issues from the v33 opus critique were evaluated. Issues #1, #2, and #4 were applied to the specification or related files. Issue #3 was a minor documentation observation that required no change.

## Issue #1: The spec's turn type system (`com.kilroy.attractor.*`) does not exist in the CXDB codebase

**Status: Applied to specification**

Added a new paragraph at the end of Section 5.4 ("Kilroy types vs. CXDB canonical types") that explicitly distinguishes the `com.kilroy.attractor.*` types from CXDB's own `cxdb.ConversationItem` type, explains that the Kilroy types are defined in the Attractor repository (not the CXDB codebase), and directs implementers to the Attractor repository as the canonical source for the `kilroy-attractor-v1` bundle definition. The note also confirms that the `decodeFirstTurn` tags (tag 1, tag 8) are stable within bundle version 1 per CXDB's versioning model.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "Kilroy types vs. CXDB canonical types" paragraph after the existing type table note in Section 5.4

## Issue #2: Forked contexts with non-Kilroy parent turns may permanently fail `view=typed`

**Status: Applied to specification**

Added a new paragraph ("Permanent failure for forked contexts with non-Kilroy parents") in Section 5.3 immediately after the existing "Type registry dependency" paragraph. The new text explains that forked contexts whose parent chains include turns with unregistered types (e.g., `cxdb.ConversationItem` from non-Kilroy clients) can fail permanently on every poll cycle until the missing bundle is published or the non-Kilroy turns fall outside the fetch window. This is distinct from the transient "registry not yet published" scenario already documented.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "Permanent failure for forked contexts with non-Kilroy parents" paragraph in Section 5.3

## Issue #3: `next_before_turn_id` naming/semantic mismatch

**Status: Not addressed**

The critic explicitly noted this is "a minor documentation observation, not a required change" and confirmed the `fetchFirstTurn` algorithm is correct. The existing spec text accurately describes the semantics. No change needed.

## Issue #4: Six proposed holdout scenarios remain without incorporation or rejection

**Status: Partially addressed**

Updated the misleading header text in `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` from "All previously proposed scenarios have been incorporated" to "The following proposed scenarios are awaiting review." The actual review and incorporation/rejection of the six scenarios is deferred to a dedicated holdout scenario review pass — it is outside the scope of a spec revision cycle.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Fixed misleading header text

## Not Addressed (Out of Scope)

- Issue #3 (pagination naming/semantic mismatch): Explicitly deferred by the critic as not requiring a change.
- Issue #4 (scenario incorporation/rejection decisions): The header was fixed, but reviewing each of the six proposed scenarios for incorporation into the main holdout document is a separate task.
