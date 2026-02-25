# CXDB Graph UI Spec — Critique v41 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-25

## Prior Context

The v40 acknowledgements applied the Definition of Done shape expansion and documented DOT comment handling plus the RunCompleted detail-panel reachability notes. Several holdout gaps (expanded shape coverage, RunFailed with node_id, DOT comment parsing) remain deferred to the proposed holdout scenarios list.

---

## Issue #1: Holdout scenarios do not cover quoted/escaped graph IDs and discovery normalization

### The problem
Section 3.2 and 4.4 require graph ID normalization (strip quotes, unescape \\" and \\\\ sequences, trim whitespace) so that the graph ID matches `RunStarted.data.graph_name` and tab labels are safe. The holdout scenarios only test unquoted identifiers (e.g., `digraph alpha_pipeline {`). An implementation could skip unescaping or trimming, pass the holdouts, and then fail to discover pipelines whose DOT graphs use quoted IDs (legal DOT), or render the tab label incorrectly.

### Suggestion
Add a holdout scenario that uses a quoted graph ID with escapes/whitespace and asserts that:
- The tab label shows the normalized ID as literal text.
- Pipeline discovery matches a `RunStarted.graph_name` value equal to the normalized ID.
- Duplicate graph ID rejection treats quoted/escaped forms as the same normalized ID.

## Issue #2: Holdout scenarios do not cover quoted node IDs and /nodes + /edges normalization

### The problem
Section 3.2 mandates node ID normalization (unquote, unescape, trim) for `/dots/{name}/nodes` and `/dots/{name}/edges`, and Section 4.2 relies on SVG `<title>` text matching those normalized IDs. The holdout scenarios cover edge chains and port stripping, but never exercise quoted node IDs or escaped characters. An implementer could only handle bare identifiers and still pass tests, leaving the status overlay and detail panel broken for legal DOT files with quoted IDs.

### Suggestion
Add a holdout scenario where the DOT file defines a node like `"review step" [shape=box]` and an edge `"review step" -> done [label="pass"]`. Assert that `/nodes` returns the normalized key `review step`, `/edges` uses `review step` as `source`, and the SVG node with `<title>review step</title>` receives status updates and opens the detail panel correctly.
