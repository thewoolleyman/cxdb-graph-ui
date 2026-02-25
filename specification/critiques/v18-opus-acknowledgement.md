# CXDB Graph UI Spec — Critique v18 (opus) Acknowledgement

Two of three issues required spec changes (applied now); the third was addressed in the v21 revision cycle. The unreachable dead code in `fetchFirstTurn` was already removed during v21. The detail panel context-section ordering contradiction has been resolved with a two-level sort. The gap recovery holdout scenario was not added (holdout scenarios are maintained separately).

## Issue #1: `fetchFirstTurn` has unreachable dead code — trailing `RETURN null` after unconditional return

**Status: Applied to specification (in v21 cycle)**

This was addressed during the v21 revision cycle (see v21-opus-acknowledgement.md, Issue #1). The trailing unreachable `RETURN null` was removed from the `fetchFirstTurn` pseudocode in Section 5.5.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Trailing `RETURN null` deleted from `fetchFirstTurn` (applied in v21 cycle).

## Issue #2: Gap recovery has no holdout scenario

**Status: Not addressed (Out of Scope)**

Holdout scenarios are maintained separately from the specification and are outside the scope of spec revisions. This convention has been established in previous acknowledgement rounds (see v20-opus-acknowledgement.md, v20-codex-acknowledgement.md). The gap recovery mechanism is fully specified in Section 6.1 with detailed pseudocode and rationale.

## Issue #3: Detail panel context-section ordering compares `turn_id` across CXDB instances despite the spec warning this is meaningless

**Status: Applied to specification**

Replaced the contradictory ordering algorithm in Section 7.2 with a two-level sort: first by CXDB instance index (lower index first), then by highest `turn_id` descending within each instance. This groups contexts by instance (where turn ID comparison is meaningful) and uses a stable, deterministic ordering across instances. Removed the contradictory warning since the algorithm no longer performs cross-instance `turn_id` comparison.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Rewrote context-section ordering description in Section 7.2 to use two-level sort (instance index, then intra-instance turn_id).

## Not Addressed (Out of Scope)

- Gap recovery holdout scenario: Holdout scenarios are maintained separately and are outside the scope of spec revisions.
