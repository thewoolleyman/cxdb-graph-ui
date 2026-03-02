# CXDB Graph UI Spec — Critique v49 (codex) Acknowledgement

Both issues were validated against CXDB source and applied. Issue #1 identified a genuine residual gap in the v48 fix: the null-tag backlog was only activated for the `cqlSupported[index] == false` (legacy fallback) path, leaving CQL-enabled instances with the same bug — after session disconnect, null-tag contexts in the supplemental fetch were silently dropped and never subjected to `fetchFirstTurn`. The spec was corrected by collecting null-tag contexts from the supplemental fetch into a `supplementalNullTagCandidates` list and seeding `nullTagCandidates` from it, making the backlog unconditional across both discovery paths. Issue #2 added a holdout scenario that locks in the specific CQL-empty / null-tag / post-disconnect failure mode on CQL-enabled CXDB.

## Issue #1: Null-tag backlog skipped when CQL is available

**Status: Applied to specification**

The critique is correct. Verified against CXDB source:

- `context_to_json` (`server/src/http/mod.rs` lines 1305-1395) resolves `client_tag` via a two-step chain: first from `stored_metadata.client_tag` (requires key 30 in msgpack, which Kilroy does not emit), then from `session.as_ref().map(|s| s.client_tag.clone())`. After `SessionTracker::unregister` (`metrics.rs` lines 88-99) removes all `context_to_session` entries, `client_tag` is permanently null for all completed-run contexts.
- The CQL search handler (`http/mod.rs` lines 433-445) reads `client_tag` exclusively from `context_metadata_cache` — it does not use the session fallback. So null-tag contexts never match `tag ^= "kilroy/"` and never appear in CQL results at all.
- Before this fix: the supplemental fetch loop (lines 594-597 in the old pseudocode) only appended `kilroy/`-prefixed contexts into `contexts`; null-tag contexts were silently discarded. The null-tag backlog collection was then guarded by `IF cqlSupported[index] == false`, which is `false` on CQL-enabled CXDB, so the backlog never ran.

**Fix applied:** Three changes to `specification/cxdb-graph-ui-spec.md`:

1. **`supplementalNullTagCandidates`** is initialized to `[]` before Phase 1 (just inside the per-instance loop, before the CQL/fallback branch). During the supplemental fetch loop, an `ELSE IF ctx.client_tag IS null` branch now appends null-tag contexts to `supplementalNullTagCandidates` instead of discarding them.

2. **`nullTagCandidates` seeded from supplemental path:** After Phase 1, `nullTagCandidates = supplementalNullTagCandidates` (instead of `nullTagCandidates = []`). The legacy fallback path still appends to `nullTagCandidates` via the main context loop as before.

3. **Null-tag batch `knownMappings` guard:** `supplementalNullTagCandidates` contexts are not pre-filtered against `knownMappings` in the supplemental loop (to keep the supplemental loop simple). The batch processing block now checks `IF key IN knownMappings: CONTINUE` before calling `fetchFirstTurn`, avoiding redundant fetches for already-cached contexts.

Updated prose:
- The null-tag backlog comment block now documents both sources (supplemental path and fallback path).
- The "Caching" prose paragraph now states the backlog applies in "both discovery paths: the CQL-empty supplemental path and the full context list fallback path."
- The third bullet under "Consequences for discovery" now explicitly covers CQL-enabled CXDB post-disconnect.
- The "Fallback behavior until Kilroy implements key 30" section now describes that null-tag contexts from the supplemental fetch are collected and processed via the backlog, enabling post-disconnect discovery on CQL-enabled instances.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added `supplementalNullTagCandidates = []` initialization before Phase 1 with explanatory comment
- `specification/cxdb-graph-ui-spec.md`: Added `ELSE IF ctx.client_tag IS null: supplementalNullTagCandidates.append(ctx)` branch in the supplemental fetch loop with a comment explaining why these contexts are candidates for the null-tag backlog
- `specification/cxdb-graph-ui-spec.md`: Changed `nullTagCandidates = []` to `nullTagCandidates = supplementalNullTagCandidates` (seeds the backlog from the supplemental path); updated the surrounding comment block to describe both sources
- `specification/cxdb-graph-ui-spec.md`: Added `IF key IN knownMappings: CONTINUE` guard at the top of the null-tag batch processing loop; updated the batch comment to explain the dual-path origin and why the guard is needed
- `specification/cxdb-graph-ui-spec.md`: Updated "Caching" prose paragraph to state the backlog applies to both discovery paths
- `specification/cxdb-graph-ui-spec.md`: Updated third "Consequences for discovery" bullet to explicitly cover CQL-enabled CXDB
- `specification/cxdb-graph-ui-spec.md`: Updated "Fallback behavior until Kilroy implements key 30" section to describe post-disconnect discovery on CQL-enabled instances via the supplemental null-tag backlog

## Issue #2: Holdouts still miss the CQL-empty null-tag regression

**Status: Applied to holdout scenarios**

The critique is correct. The existing "Fallback discovery finds completed run after session disconnect on legacy CXDB" scenario only covers the `cqlSupported == false` path. There was no acceptance test for the symmetric case on CQL-enabled CXDB: CQL returns 200 with empty contexts, the supplemental list returns a context with `client_tag: null` and `is_live: false`, and the UI must use `fetchFirstTurn` via the null-tag backlog.

Added holdout scenario "CQL-empty supplemental discovery handles null client_tag after session disconnect" in the Pipeline Discovery section immediately after the legacy CXDB scenario. The scenario specifies: CQL is supported but returns an empty contexts array; the supplemental `GET /v1/contexts?limit=10000` returns a completed Kilroy context with `client_tag: null` and `is_live: false`; the context has not been previously cached. When the UI polls, the context is collected into `supplementalNullTagCandidates`, merged into `nullTagCandidates`, processed by `fetchFirstTurn` (respecting `NULL_TAG_BATCH_SIZE`), the `RunStarted` turn is confirmed, and the context is mapped to the pipeline tab with the completed run status visible.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added "CQL-empty supplemental discovery handles null client_tag after session disconnect"

## Not Addressed (Out of Scope)

- None. Both issues were valid and fully addressed.
