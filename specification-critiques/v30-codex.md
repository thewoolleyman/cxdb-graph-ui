# CXDB Graph UI Spec — Critique v30 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-25

## Prior Context

The v29 cycle applied all codex and opus issues. The spec now mandates HTML escaping for DOT attributes in the detail panel, clarifies that Kilroy DOTs always include per-node `shape`, documents `view=raw` metadata dependencies, explains `is_live` resolution, and notes SSE `ContextMetadataUpdated` as the reliable discovery trigger. This review focuses on remaining UI surface areas that render user-supplied text and on msgpack decoding behavior.

---

## Issue #1: HTML escaping requirements do not cover tab labels or CXDB indicator text

### The problem
Section 7.1 adds explicit HTML escaping for detail panel fields, but other UI elements also render user-sourced strings: pipeline tab labels use DOT graph IDs or filenames (Section 4.4), and the connection indicator can display configured CXDB URLs (Section 8.2). These values can include characters like `<`, `&`, or `"` if a DOT file is crafted maliciously or if a URL includes query parameters. Without an explicit requirement to render these via `textContent` (or equivalent escaping), an implementation could inadvertently use `innerHTML` and allow HTML injection outside the detail panel.

### Suggestion
Add a short security note in Section 4.4 (Pipeline Tabs) and Section 8.2 (CXDB Connection Indicator) requiring tab labels and indicator text to be rendered as text-only with HTML escaping, matching the detail panel policy. Optionally add a holdout scenario that uses a DOT graph ID containing `<b>` and expects the literal text to appear in the tab label.

## Issue #2: `decodeFirstTurn` assumes msgpack maps decode to plain objects

### The problem
Section 5.5's `decodeFirstTurn` pseudocode indexes `payload["8"]` and `payload[8]`, implying the msgpack decoder returns a plain object. However, `@msgpack/msgpack` can return a `Map` when the payload contains non-string keys (e.g., integer tags). If the decoder yields a `Map`, bracket indexing fails and `graph_name`/`run_id` resolve as `undefined`, breaking pipeline discovery for integer-tagged payloads. The spec does not specify whether to configure the decoder (`useMap` option) or how to handle `Map` results.

### Suggestion
Clarify in Section 5.5 that msgpack decoding must handle both object and `Map` outputs. Either require `decode(bytes, { useMap: false })` to coerce keys into strings (and then parse integer tags), or require a helper that detects `Map` and reads keys via `map.get(8)` / `map.get("8")`. Add a brief note near `decodeFirstTurn` to avoid implementations that assume object indexing always works.
