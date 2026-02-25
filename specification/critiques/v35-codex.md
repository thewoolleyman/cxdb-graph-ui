# CXDB Graph UI Spec — Critique v35 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-25

## Prior Context

The v34 cycle resolved the resetPipelineState mapping contradiction, added tab-switch error handling for /nodes and /edges, documented RunStarted graph_dot, expanded the Kilroy turn type tables and detail panel rendering, and clarified the client_tag storage mechanism via the binary protocol.

---

## Issue #1: Initial pipeline never fetches /edges, so human gate choices are missing until a tab switch

### The problem
Section 4.4 defines that tab switching fetches /dots/{name}/edges, and Section 4.5's initialization sequence only prefetches /nodes for all pipelines. There is no step that fetches /edges for the initially rendered pipeline. The detail panel relies on outgoing edge labels to populate human gate choices (Section 7.1), and the holdout scenario “Click a human gate node” expects those choices to appear immediately.

As written, the first pipeline tab can be rendered and clicked without ever fetching /edges, so human gate nodes will show no choices until the user switches away and back (or a later change triggers the edges fetch). This is a spec completeness gap that directly affects the initial user flow.

### Suggestion
Update the initialization sequence to fetch /dots/{name}/edges for the first pipeline before the UI can open the detail panel, or add a lazy edge fetch on first detail-panel open for a node if the edge list is missing. Mirror the same error-handling rules used for tab-switch fetches to keep cached edges intact on failures. Consider adding a holdout scenario that verifies human gate choices appear when clicking a node in the first pipeline without switching tabs.
