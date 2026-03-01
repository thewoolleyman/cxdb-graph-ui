# CXDB Graph UI Spec — Critique v50 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-codex)
**Date:** 2026-02-25

## Prior Context

The v49 acknowledgement seeded the null-tag backlog from the supplemental discovery path so CQL-enabled instances that return empty results still recover completed runs, and it added a holdout that exercises that flow. It also kept the backlog shared between the CQL-empty supplemental path and the legacy fallback path.

---

## Issue #1: Null-tag backlog skips older contexts once the newest are cached

### The problem

Section 5.5 limits backlog processing to the slice `nullTagCandidates[0..NULL_TAG_BATCH_SIZE]` after sorting by descending `context_id` (lines 704-711 of the pseudocode). When the same contexts reappear on the next poll (they always do), they still occupy the top of the sorted list. Because the loop only iterates over that fixed slice, any context past index 4 is never examined. If the first five entries are already in `knownMappings`, the loop simply `CONTINUE`s for each of them and exits without ever reaching the sixth item—so additional null-tag contexts are permanently starved.

This happens as soon as there are more than `NULL_TAG_BATCH_SIZE` completed runs with null tags. After the newest five are discovered, older ones remain undiscovered forever, even though the backlog exists to recover historical runs in exactly that state. The new holdout (“CQL-empty supplemental discovery handles null client_tag after session disconnect”) only covers a single context, so it does not expose the starvation.

### Suggestion

Update the backlog loop to enforce the batch size via a counter rather than truncating the candidate list before iteration. For example:

1. Iterate the entire sorted `nullTagCandidates` array.
2. Skip already-cached contexts as today.
3. Increment a `processed` counter only when `fetchFirstTurn` is actually invoked.
4. Break once `processed == NULL_TAG_BATCH_SIZE`.

Add a holdout scenario with more than five null-tag contexts (e.g., six completed runs) to prove that older contexts are eventually classified.

## Issue #2: Supplemental discovery never runs alongside non-empty CQL results

### The problem

The supplemental `/v1/contexts` fetch is only triggered when `searchResponse.contexts` is empty (Section 5.5, lines 592-601). This fixes today’s “all contexts missing metadata” case, but it fails in the transitional state the spec says we’re heading toward: once Kilroy starts emitting key 30 metadata, new runs will appear in CQL results while legacy runs (which lack metadata) remain invisible to CQL. Because the current algorithm sees a non-empty CQL array, it skips the supplemental fetch entirely, so those legacy contexts are never queued for the null-tag backlog. Operators lose access to historical runs right after the upgrade—the exact opposite of the graceful-degradation goal.

### Suggestion

Run the supplemental fetch whenever either (a) the CQL response is empty, or (b) there are still unmapped contexts whose last-seen state required the backlog (e.g., track whether any `(index, context_id)` pairs remain unknown and `client_tag` was null on the previous cycle). An easier invariant is to always issue the supplemental call when any context in `knownMappings` for that instance is still unmapped and `cqlSupported[index]` is true—then merge and deduplicate results before processing.

Add a holdout scenario that simulates a mixed deployment: CQL returns one modern context with metadata, while the supplemental list contains older null-tag contexts. The expected outcome is that the backlog still runs for the legacy contexts and discovers them.
