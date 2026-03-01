# CXDB Graph UI Spec — Critique v52 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-codex)
**Date:** 2026-02-25

## Prior Context

The v51 acknowledgements merged the supplemental CQL fetch with deduplication and ensured the discovery-effective context lists always include supplemental results so liveness checks stay accurate. Holdouts were added for the mixed CQL + supplemental cases.

---

## Issue #1: Cross-instance `context_id` comparison picks the wrong active run

### The problem

Section 5.5 / 6.1 (see specification/cxdb-graph-ui-spec.md:961-1048) chooses the “active run” by taking the run whose contexts have the highest `context_id`, on the assumption that `context_id` is globally monotonic. That’s true inside a single CXDB server, but different CXDB instances maintain their counters independently. When two instances are configured, the run that happened on the instance with the larger local counter wins, even if a newer run is happening on another instance whose counter recently reset (or has always been lower). Example: CXDB-0 has an old run with contexts 500–550; CXDB-1 starts a fresh run whose contexts are 12–20. The algorithm compares 550 vs 20 and continues to treat the CXDB-0 run as active, so the UI never switches to the newer run. The holdouts don’t cover this multi-instance ordering, so an implementer following the spec will produce a stale dashboard whenever runs move between servers.

### Suggestion

Pick an ordering signal that’s comparable across instances—e.g., use the `run_id` ULID (lex order tracks creation time) or the `RunStarted` turn timestamp extracted during discovery. Update the prose and pseudocode to explain the new ordering rule, and add a holdout where a newer run exists only on a different CXDB instance with lower `context_id` values to confirm the UI follows the latest run.

## Issue #2: Supplemental-merge prose still says “only append when CQL returned empty”

### The problem

In the “CQL discovery limitation” paragraph (specification/cxdb-graph-ui-spec.md:589-620) the spec still states: “`kilroy/`-prefixed contexts found in the supplemental list are only appended to `contexts` when CQL returned empty (to avoid duplicates).” The pseudocode immediately below (lines 633-646) and the new holdout “CQL returns one context, supplemental finds another active Kilroy context absent from CQL” require the opposite behavior: append any supplemental Kilroy context that is missing from the CQL response, even when CQL is non-empty. This contradiction leaves implementers unsure which rule to follow. If they follow the prose, the mixed-deployment gap reappears and the new holdout fails; if they follow the pseudocode, the prose becomes incorrect documentation.

### Suggestion

Rewrite the paragraph to match the dedup rule implemented in pseudocode: always run the supplemental fetch when CQL succeeds, merge Kilroy-prefixed contexts that are absent from CQL using a `(cxdb_index, context_id)` set, and explain that dedup prevents duplicates. Call out explicitly that this merge runs even when CQL returned results, so operators don’t regress to the old behavior. Also double-check related comments (e.g., in Section 6.1’s description of `cachedContextLists`) to ensure they describe the same behavior.
