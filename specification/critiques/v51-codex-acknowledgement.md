# CXDB Graph UI Spec — Critique v51 (codex) Acknowledgement

Both issues were valid and applied together. Issue #1 identified a genuine discovery gap: the `IF contexts IS EMPTY` guard in the supplemental merge loop silently dropped active Kilroy contexts that appeared in the supplemental list but were absent from CQL results — precisely the contexts that matter most during a mixed deployment. Because those contexts had a non-null `client_tag` (session-resolved), they were not queued for the null-tag backlog either, making them permanently undiscovered. The fix replaces the empty-check with dedup logic using a `cqlContextIds` set built from CQL results, appending any supplemental kilroy-prefixed context not already present. Issue #2 is a direct consequence of Issue #1: because the old code never appended supplemental contexts when CQL returned results, `cachedContextLists[i]` also lacked those contexts, causing `checkPipelineLiveness` to see no `is_live: true` entries and incorrectly flip running nodes to stale. Once Issue #1's merge is applied, `contexts` (and therefore `cachedContextLists[i]`) contains all discovered contexts — CQL plus supplemental — so the liveness check is always accurate. Two holdout scenarios were added.

## Issue #1: Supplemental CQL merge drops active contexts without metadata

**Status: Applied to specification**

The critique is correct. The old pseudocode at Section 5.5 appended supplemental kilroy-prefixed contexts only `IF contexts IS EMPTY`. This was correct for the original single-purpose use case (CQL empty → no key 30 at all) but broken for the mixed-deployment case (CQL partial → some contexts have key 30, others don't). In the mixed case, `contexts IS EMPTY` is false, so supplemental kilroy-prefixed contexts are skipped. Those contexts have a non-null `client_tag` (resolved from the live session by `context_to_json`'s `.or_else` fallback), so they also pass the null-check and are not queued for the null-tag backlog. The result is permanent non-discovery of any active Kilroy run whose key 30 metadata extraction has not yet completed.

Verified against CXDB source: `extract_context_metadata` (`store.rs` lines 603-681) only populates `client_tag` from key 30 of the msgpack payload. The `context_to_json` session-tag fallback is separate and populates `client_tag` for the full context list endpoint but not for CQL results (which read from `context_metadata_cache`). A context created after Kilroy emits key 30 will appear in both CQL and the supplemental list; a context on an older Kilroy instance or during the metadata extraction lag window will appear only in the supplemental list.

The fix:

1. Before the supplemental loop, builds `cqlContextIds = SET(ctx.context_id FOR ctx IN contexts)` from the CQL results.
2. Replaces `IF contexts IS EMPTY: contexts.append(ctx)` with `IF ctx.context_id NOT IN cqlContextIds: contexts.append(ctx); cqlContextIds.add(ctx.context_id)`.
3. Updated the three-case comment block above the supplemental fetch to document case (b): CQL returned some contexts but missed others (active runs lacking key 30 metadata or in metadata-extraction lag).
4. Updated the surrounding prose in the "CQL discovery limitation" paragraph to describe the dedup-based merge.
5. Updated the "Fallback behavior until Kilroy implements key 30" paragraph to enumerate all three supplemental-fetch roles explicitly (zero-CQL active discovery; mixed-deployment active discovery; null-tag backlog collection).

A holdout scenario was added: "CQL returns one context, supplemental finds another active Kilroy context absent from CQL" — verifying that both contexts are discovered in the same poll cycle and the CQL context is not duplicated.

Changes:
- `specification/cxdb-graph-ui-spec.md` Section 5.5: Replaced `IF contexts IS EMPTY` guard with `cqlContextIds` dedup set; updated comment blocks and surrounding prose paragraphs

## Issue #2: Liveness cache omits supplemental-only contexts, triggering false stale alarms

**Status: Applied to specification**

The critique is correct. The old Section 6.1 step 1 description defined the "discovery-effective context list" as "the CQL search results when non-empty, the supplemental context list when CQL returns zero results." This excluded supplemental contexts when CQL returned any results, so `cachedContextLists[i]` was incomplete in the mixed-deployment case — exactly the contexts affected by Issue #1's bug were also absent from the liveness cache. When `checkPipelineLiveness` looked them up via `lookupContext(contextLists, ...)`, it found no `is_live: true` entry and returned false, causing `applyStaleDetection` to flip running nodes to stale even though the agent was actively working.

Because Issue #1's fix merges supplemental contexts into `contexts` unconditionally (by dedup), the `contexts` array passed to and stored as `cachedContextLists[i]` now always contains the full merged set. The fix to Section 6.1 step 1 updates the prose description to match:

1. Replaced the conditional "CQL when non-empty, supplemental when empty" definition with "the merged list of CQL results plus any supplemental kilroy-prefixed contexts not already in CQL (deduplicated by `context_id`)."
2. Explicitly states that supplemental contexts are included regardless of whether CQL returned results.
3. Added a sentence documenting the mixed-deployment false-stale scenario to make the requirement clear for implementers.

A holdout scenario was added: "Live context only in supplemental response keeps liveness check true" — verifying that when CQL returns empty and the supplemental list has an `is_live: true` context, `checkPipelineLiveness` returns true and running nodes are not misclassified as stale.

Changes:
- `specification/cxdb-graph-ui-spec.md` Section 6.1 step 1: Rewrote `cachedContextLists[i]` definition to describe the full merged (CQL + supplemental dedup) list; added mixed-deployment false-stale scenario documentation

## Applied to holdout scenarios

Two new scenarios added to `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`:

- **"CQL returns one context, supplemental finds another active Kilroy context absent from CQL"** — covers Issue #1's mixed-deployment active-discovery gap.
- **"Live context only in supplemental response keeps liveness check true"** — covers Issue #2's false-stale alarm when CQL is empty but supplemental has `is_live: true` contexts.

## Not Addressed (Out of Scope)

- None. Both issues were valid and fully addressed.
