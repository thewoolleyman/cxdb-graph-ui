# CXDB Graph UI Spec — Critique v34 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-25

## Prior Context

The v33 cycle retained old-run mappings in `knownMappings` to avoid repeated `fetchFirstTurn` rediscovery, and clarified that `/nodes` prefetch failures (beyond DOT parse errors) should fall back to empty node sets without blocking polling. It also added documentation about Kilroy types vs. CXDB canonical types and the permanent `view=typed` failure mode for forked contexts with non-Kilroy parents.

---

## Issue #1: `resetPipelineState` semantics are self-contradictory (retain vs. remove old-run mappings)

### The problem
The `determineActiveRuns` pseudocode now includes inline comments that `resetPipelineState` does NOT remove old-run entries from `knownMappings` to avoid expensive re-discovery. This matches the updated invariant (#10). However, the prose immediately after the pseudocode still says that `resetPipelineState` “removes `knownMappings` entries whose `runId` matches the old run's `run_id`” for memory hygiene. That is the opposite of the comments and invariant, and it reintroduces the v33-codex bug (re-discovery every poll).

This leaves implementers with conflicting guidance: the algorithm block says “retain,” but the prose says “remove.” It is unclear which is authoritative, and the wrong choice has a measurable performance cost and violates invariant #10.

### Suggestion
Edit the post-pseudocode paragraph in Section 6.1 to align with the comments and invariant: explicitly state that `resetPipelineState` clears per-context status maps, cursors, and turn caches but **does not remove** `knownMappings` entries for old runs. If memory hygiene needs discussion, propose an explicit optional eviction policy (e.g., time-based pruning) that preserves the “never re-fetch RunStarted” invariant.

---

## Issue #2: Tab-switch fetches lack defined error handling for `/nodes` and `/edges` failures

### The problem
Section 4.4 specifies that switching tabs fetches the DOT file plus `/dots/{name}/nodes` and `/dots/{name}/edges`, then updates `dotNodeIds` and edge caches. The spec defines robust error handling for **initialization prefetch** failures (Section 4.5, Step 4) and for `/nodes` or `/edges` returning 400 due to DOT parse errors (Sections 3.2). But the tab-switch flow does not define what to do if those fetches fail due to other errors: 404 (file removed), 500, or transient network failures.

Without explicit handling, a failed `/nodes` fetch on tab switch can clear `dotNodeIds`, causing all nodes to appear pending and breaking the “cached status map is immediately reapplied” holdout scenario. A failed `/edges` fetch can silently remove human gate choices even when the DOT file is still valid. These are user-visible degradations and can happen during transient outages (or when a DOT file is regenerated between the DOT fetch and the `/nodes`/`/edges` fetches).

### Suggestion
Extend Section 4.4 (tab switching) with a failure policy mirroring the initialization prefetch rules:

- If `/nodes` fails with any non-200 response or network error, log a warning and retain the previous `dotNodeIds` for that pipeline (or fall back to empty if none exists), so cached status maps are not discarded spuriously.
- If `/edges` fails, retain the previous edge list for that pipeline (or use empty), and keep the rest of the detail panel functional.

Add a holdout scenario covering tab switch with a transient `/nodes` or `/edges` failure to ensure cached status does not “gray out” due to fetch errors.

---

If these two consistency/error-handling gaps are addressed, the spec remains internally coherent and implementable. The most significant issue is the conflicting `resetPipelineState` description, which would lead to divergent implementations.
