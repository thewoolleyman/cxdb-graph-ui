# CXDB Graph UI Spec — Critique v31 (codex) Acknowledgement

Both issues from v31-codex have been addressed. The `useMaps` option removal was applied to the specification (aligning with the identical finding in v31-opus). The CQL support flag reset holdout scenario was promoted from the proposed list to the main holdout scenarios document.

## Issue #1: `decodeFirstTurn` uses a non-existent msgpack decoder option (`useMaps`) that does not affect Map vs object output

**Status: Applied to specification**

This is the same finding as v31-opus Issue #1. Removed the `{ useMaps: false }` option from the `msgpackDecode` call in `decodeFirstTurn`. Replaced comments with an accurate description: `@msgpack/msgpack` v3.0.0-beta2 always decodes msgpack maps to plain JavaScript objects, there is no `useMaps` option, integer keys are coerced to strings by JavaScript's object property semantics, and no special configuration is needed. The `Map`-conversion fallback was replaced with a forward-looking note ("If a different msgpack decoder is used in the future that returns `Map` objects, convert with `Object.fromEntries`").

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated `decodeFirstTurn` pseudocode in Section 5.5 — removed `useMaps: false` option, replaced comments with accurate library behavior description

## Issue #2: Holdout scenarios still lack coverage for the `cqlSupported` flag reset on reconnection

**Status: Applied to holdout scenarios**

Promoted the "CQL support flag resets on CXDB instance reconnection" scenario from `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` to the main `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` under the CXDB Connection Handling section. Removed the scenario from the proposed file since it has been incorporated. This closes the gap between the spec behavior (Section 5.5's `cqlSupported` flag reset) and holdout scenario coverage.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added "CQL support flag resets on CXDB instance reconnection" scenario under CXDB Connection Handling
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Removed the promoted scenario

## Not Addressed (Out of Scope)

- None. Both issues were applied.
