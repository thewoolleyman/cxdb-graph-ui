# CXDB Graph UI Spec — Critique v51 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-codex)
**Date:** 2026-02-25

## Prior Context

The v50 acknowledgements landed the counter-based null-tag backlog iteration and made the supplemental context-list fetch run on every CQL-supported poll to keep legacy runs discoverable. New holdouts were added for both scenarios.

---

## Issue #1: Supplemental CQL merge drops active contexts without metadata

### The problem
Section 5.5’s `discoverPipelines` pseudocode seeds `contexts = searchResponse.contexts` and then calls the supplemental `/v1/contexts` fetch (lines 590-623). Kilroy-prefixed contexts from that supplemental pass are appended only when `contexts IS EMPTY` (lines 609-614). In a mixed deployment where CQL returns *some* contexts but misses others — the common case while metadata key 30 is still rolling out — the missing contexts appear in the supplemental response with a non-null `client_tag` (resolved from the live session), yet `contexts IS EMPTY` is false, so they are never appended. Because they also have non-null `client_tag`, they are not queued for the null-tag backlog. Those contexts are therefore never processed in Phase 2, so active runs whose contexts lack key 30 remain undiscovered despite the supplemental fetch.

### Suggestion
Merge supplemental Kilroy contexts even when CQL returned results. Deduplicate by `(context_id, index)` so already-present entries are skipped, but append any missing ones before the Phase 2 loop. Add a holdout that covers “CQL returns one context, supplemental returns that context plus another Kilroy context absent from CQL; both must be discovered.”

## Issue #2: Liveness cache omits supplemental-only contexts, triggering false stale alarms

### The problem
Section 6.1 step 1 (lines 933-943) instructs storing the “discovery-effective context list” in `cachedContextLists[i]` so `checkPipelineLiveness` (lines 1014-1021) can evaluate `is_live`. With the current merge rule, supplemental contexts that weren’t appended to `contexts` stay invisible to the cache. When CQL misses a live context (metadata not yet extracted), the cached list also misses it, so `checkPipelineLiveness` sees no live sessions and `applyStaleDetection` (lines 1275-1282) flips running nodes to “stale,” even though the agent is active. Operators would get a false “Pipeline stalled — no active sessions” warning while work continues.

### Suggestion
Explicitly include supplemental contexts in the per-instance cache regardless of whether CQL returned entries. Either merge them into the `contexts` array before caching (per Issue #1’s fix) or store a union of CQL and supplemental lists. Add a holdout where a live context only appears in the supplemental response to ensure the liveness check stays true.
