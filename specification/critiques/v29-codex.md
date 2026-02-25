# CXDB Graph UI Spec — Critique v29 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-25

## Prior Context

The v28 cycle applied all codex and opus issues. Graph ID normalization was aligned with node ID normalization, NodeStatus counters were marked internal-only, and CXDB edge-case notes (CQL semantics, context scoping, blob failures) were added. This review focuses on remaining UI safety and DOT parsing expectations around the detail panel.

---

## Issue #1: Detail panel text rendering does not explicitly require HTML escaping for DOT attributes

### The problem
Section 7.2 explicitly states that CXDB Output truncation is applied after HTML-escaping, but Section 7.1 (DOT attributes) does not specify HTML escaping or text-only rendering for `prompt`, `tool_command`, `question`, `node_id`, or `goal_gate` labels. Since DOT files are user-provided inputs, unescaped rendering in the detail panel would allow HTML injection (e.g., `<script>` or `<img onerror>`), which is a real risk if an implementer uses `innerHTML` or inserts unescaped strings into the DOM. The spec currently makes the CXDB output safe but leaves DOT attributes ambiguous.

### Suggestion
Add an explicit requirement in Section 7.1 that all DOT attribute values (Node ID, Prompt, Tool Command, Question, Choices, and Goal Gate badge labels) are rendered as text, with HTML escaping applied (or via `textContent`) before insertion. Optionally add a holdout scenario that uses a DOT prompt containing `<script>` or `<b>` and expects the literal text to appear, not HTML formatting or script execution.

## Issue #2: Default node attributes are ignored, but the detail panel depends on per-node shape

### The problem
Section 3.2 states that global default blocks like `node [shape=box]` are excluded from parsing, and only named node definitions are parsed. However, Section 7.1's detail panel type mapping depends on the node's `shape` attribute, which may be inherited from `node` defaults in standard DOT files. If a DOT file uses default node attributes (common Graphviz style), the SVG will render the correct shapes, but `/dots/{name}/nodes` will not report the `shape` attribute, leaving the detail panel's Type field blank or incorrect. The spec does not state that Kilroy DOT always defines `shape` on every node, so an implementer cannot know whether to support defaults or enforce explicit shapes.

### Suggestion
Either (a) extend the `/dots/{name}/nodes` parsing rules to apply default `node [...]` attributes to subsequent nodes when explicit per-node attributes are missing (at least for `shape` and `class`), or (b) explicitly require that all supported DOT inputs include per-node `shape` attributes and update the spec to treat default `node` blocks as unsupported for the detail panel. Add a holdout scenario if defaults are intended to be supported.
