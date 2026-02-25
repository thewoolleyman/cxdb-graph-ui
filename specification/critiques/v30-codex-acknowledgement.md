# CXDB Graph UI Spec — Critique v30 (codex) Acknowledgement

Both issues from v30-codex have been applied to the specification. The changes extend HTML escaping requirements to pipeline tab labels and the CXDB connection indicator, and clarify msgpack decoder configuration to handle Map vs object return types in `decodeFirstTurn`.

## Issue #1: HTML escaping requirements do not cover tab labels or CXDB indicator text

**Status: Applied to specification**

Added an "HTML escaping" paragraph in Section 4.4 (Pipeline Tabs), immediately before the tab-switching paragraph. The note requires tab labels (whether graph IDs or filenames) to be rendered as text-only via `textContent` or explicit HTML entity escaping, referencing the detail panel policy in Section 7.1. Added a matching "HTML escaping" paragraph in Section 8.2 (CXDB Connection Indicator) requiring CXDB URLs displayed in the indicator to use text-only rendering. Added a Definition of Done item for tab label and indicator text escaping. Two proposed holdout scenarios were written: one for HTML-like graph IDs in tab labels, and one complementing the existing CQL reconnection proposal.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "HTML escaping" paragraph in Section 4.4 (Pipeline Tabs)
- `specification/cxdb-graph-ui-spec.md`: Added "HTML escaping" paragraph in Section 8.2 (CXDB Connection Indicator)
- `specification/cxdb-graph-ui-spec.md`: Added Definition of Done item for tab label and indicator text escaping
- `holdout-scenarios/proposed-holdout-scenarios-to-review.md`: Added "Pipeline tab label with HTML-like graph ID" proposed scenario

## Issue #2: `decodeFirstTurn` assumes msgpack maps decode to plain objects

**Status: Applied to specification**

Updated the `decodeFirstTurn` pseudocode in Section 5.5 to explicitly pass `{ useMaps: false }` to `msgpackDecode`. Added comments explaining that `@msgpack/msgpack` may return `Map` objects when payloads contain integer keys (which Kilroy/CXDB payloads do), that `useMaps: false` coerces integer keys to string keys in the resulting object enabling bracket indexing, and that if the decoder does not support `useMaps: false`, the implementer should convert `Map` results to objects via `Object.fromEntries`. The existing `||` fallback for string-vs-integer keys is preserved as a defensive measure.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated `decodeFirstTurn` pseudocode in Section 5.5 with `useMaps: false` decoder option and Map handling guidance

## Not Addressed (Out of Scope)

- None. Both issues were applied.
