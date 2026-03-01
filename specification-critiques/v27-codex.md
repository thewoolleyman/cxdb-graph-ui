# CXDB Graph UI Spec — Critique v27 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-24

## Prior Context

The v26 cycle applied all issues from both critics: it clarified per-type detail panel rendering and numeric `turn_id` ordering, and tightened discovery details (RunStarted tag numbers, optional `graph_name` handling, removal of `graph_dot`, and cross-context traversal notes). This critique focuses on remaining edge cases in graph ID handling and text rendering fidelity.

---

## Issue #1: Graph ID extraction does not define behavior for `strict` or anonymous graphs, risking server/browser mismatch and discovery failure

### The problem
Section 3.2 says the server extracts graph IDs using `/(di)?graph\s+("(?:[^"\\]|\\.)*"|\w+)/` (identifier after `digraph`) and fails on duplicates, while Section 4.4 uses the same regex in the browser and falls back to the filename when the regex does not match (unusual formatting or anonymous graphs). The spec does not say what the server should do when the regex does not match. This creates two ambiguities:

1. **`strict digraph` is valid DOT** but does not match the current regex because `strict` precedes `digraph`. The server may fail to extract a graph ID (or extract the wrong token), while the browser will fall back to the filename. This can break the duplicate graph ID check and cause pipeline discovery to silently fail because `RunStarted.graph_name` will not match the filename fallback.
2. **Anonymous graphs** (`digraph { ... }`) trigger the browser filename fallback but have no defined server-side behavior. A server implementation might treat the missing ID as an error, or as an empty string, or as a fallback, leading to inconsistencies with the browser and the discovery mapping.

These cases are edge-y but valid DOT, and the spec is otherwise explicit about graph ID matching. The undefined behavior here makes it hard to implement predictably and can create a silent status overlay failure.

### Suggestion
Define graph ID extraction behavior for both server and browser in one place, and ensure they are consistent. Specifically:

- Expand the regex to accept an optional `strict` prefix, e.g. `/^\s*strict\s+(di)?graph\s+("(?:[^"\\]|\\.)*"|\w+)/` or adjust the parsing logic to handle `strict` explicitly.
- Decide on a single policy for anonymous graphs: either (a) **reject at server startup** with a clear error stating that named graphs are required for pipeline discovery, or (b) **use the filename as the graph ID** on both server and browser, and note that `RunStarted.graph_name` must match the filename for discovery to work.
- Update the duplicate graph ID check to use the same fallback policy so server and browser always agree on the normalized graph ID.

## Issue #2: “Verbatim” rendering is specified, but whitespace preservation for prompts/outputs is undefined

### The problem
The spec promises that content is displayed verbatim (Invariant 15) and includes a holdout scenario where long prompts contain escaped newlines and quotes. However, Section 7.1/7.2 does not specify how the UI preserves whitespace for prompt text, tool arguments, and tool output. In HTML, using a normal `<div>` with `textContent` collapses newlines and runs of whitespace, which contradicts “verbatim” and can make multiline prompts/output unreadable. An implementer could reasonably follow the spec and still end up collapsing whitespace, failing the intent of the long-prompt scenario.

### Suggestion
Explicitly require whitespace-preserving rendering for prompt text and turn output/arguments, for example:

- Render prompt/output/arguments in a `<pre>`-like container or apply `white-space: pre-wrap;` so `\n` and indentation are preserved.
- Clarify that truncation (for the Output column) should preserve line breaks in the visible excerpt and provide an expand/collapse affordance that reveals the full, whitespace-preserved text.

## Issue #3: Detail panel truncation/expansion behavior is referenced but not specified

### The problem
The detail panel column table says Output is “Truncated content (expandable)” and the holdout scenario expects “Truncated output (expandable),” but there is no spec for the truncation policy (character limit? line limit?), nor how expansion works (per-row toggle, modal, or inline). This is an implementation choice that directly affects UX and testability. Two implementers could both be compliant with the current spec and produce incompatible behaviors, and the holdout scenario is not concrete enough to validate the UI.

### Suggestion
Define a simple, deterministic truncation rule and expansion mechanism, such as:

- Truncate to the first N characters (e.g., 500) or first M lines (e.g., 8), whichever comes first.
- Provide a “Show more” toggle per row that expands inline to show the full content, and “Show less” to collapse.
- Ensure truncation is applied after HTML-escaping and whitespace-preserving rendering so visible text matches the stored payload.

If the project wants to avoid committing to a number, at least document that the truncation limit must be a fixed constant and that the expand control is per-turn row.
