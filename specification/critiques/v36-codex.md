# CXDB Graph UI Spec — Critique v36 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-25

## Prior Context

The v35 cycle resolved the missing `/edges` prefetch for the initial pipeline, added retry-aware `StageFailed` handling, aligned optional `node_id` annotations with the registry, documented Kilroy-side truncation for large text fields, and deferred a retry-flow holdout scenario to the proposed list.

---

## Issue #1: Cached status map for inactive pipelines is undefined even after background polling

### The problem
The holdout scenario “Switch between pipeline tabs” requires that when the second pipeline has already been polled, its cached status map is immediately applied with no gray flash. Section 6.1 step 6 currently merges status maps only for the active pipeline: “Per-context maps for inactive pipelines are also updated but their merged maps are not computed until the user switches to that tab.” Section 4.4 says a cached status map for the newly selected pipeline (from a previous poll cycle) is immediately reapplied, implying the merged map exists in advance.

As written, the spec never defines how a merged status map for an inactive pipeline is produced or cached after background polling. An implementer following Section 6.1 literally would update per-context maps but have no merged map to apply on tab switch, and would likely show all-gray until the next poll or require an ad-hoc merge at tab switch without specification support. This is a concrete consistency gap between the polling algorithm and the tab-switch behavior the holdout scenario demands.

### Suggestion
Explicitly define one of the following in Section 6.1 and Section 4.4 (and keep them consistent):

1) Compute merged maps for all pipelines on every poll cycle (including inactive pipelines), and cache the merged map per pipeline for immediate tab-switch application, or
2) On tab switch, compute the merged map on-demand from the current per-context maps and caches before applying it, and document that this on-demand merge is what satisfies the “no gray flash” requirement.

Also update the “Switch between pipeline tabs” scenario or add a brief implementation note that the merged map is available (or computed) even when the pipeline is inactive, since the scenario explicitly depends on it.

---

## Issue #2: RunStarted.graph_name matching lacks the same normalization rules used for DOT graph IDs

### The problem
Section 4.4 defines a detailed graph ID normalization algorithm (unquote, unescape, trim) for DOT graph identifiers, and Section 3.2 rejects anonymous graphs at startup. In Section 5.5, pipeline discovery matches `RunStarted.data.graph_name` directly against the graph ID without any normalization step. If a DOT graph ID is quoted or contains escape sequences, the normalized graph ID used for tabs and server-side uniqueness checks may not match the raw `graph_name` string from RunStarted unless it happens to be emitted in the exact same normalized form.

This creates a subtle mismatch: the spec claims to support quoted graph IDs, but the discovery algorithm doesn’t specify that `graph_name` is normalized in the same way, so a quoted DOT graph could fail pipeline discovery even though the server and UI accept it. There is also no holdout scenario covering a quoted graph ID discovery case.

### Suggestion
Add an explicit normalization step in Section 5.5 before matching `graph_name` to pipeline graph IDs: apply the same unquote, unescape, and trim rules used in Section 4.4 (and Section 3.2’s graph ID parsing). Then add a holdout scenario such as “Quoted graph ID pipeline discovery” to verify that a DOT file with `digraph "alpha pipeline" {` is correctly matched to a RunStarted `graph_name` with the same quoted form.

---

The most significant finding is Issue #1: the spec’s polling algorithm does not define how inactive pipelines get a merged status map, yet the tab-switch scenario requires one to exist for immediate application.
