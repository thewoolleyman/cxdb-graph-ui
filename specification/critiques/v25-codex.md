# CXDB Graph UI Spec — Critique v25 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-24

## Prior Context

The v24 cycle applied all issues from both opus and codex. The spec now precisely documents CQL search response fields and errors, adds the `limit` parameter note, clarifies CQL ordering vs context-list ordering, narrows the SSE non-goal, and specifies node ID normalization, `/api/dots` ordering, and the supported DOT edge subset. This critique focuses on remaining implementability gaps in the frontend parsing and decoding path.

---

## Issue #1: Msgpack decoding dependency for `view=raw` is not specified

### The problem

Section 5.5 requires `fetchFirstTurn` to use `view=raw`, base64-decode `bytes_b64`, and msgpack-decode the payload to extract `graph_name` and `run_id`. However, the spec never identifies how the browser is expected to decode msgpack given the “no build toolchain” constraint. Without an explicit dependency or decoder contract, an implementer has to guess which library to use, how to load it (CDN vs inline), and which API to call. This is a critical missing piece because the discovery algorithm depends on successful msgpack decoding and the server is constrained to Go standard library only (no msgpack package there either).

### Suggestion

Add a short subsection (near Section 4.1 or Section 5.5) specifying the exact msgpack decoder dependency and how it is loaded in the single HTML file, including a pinned CDN URL and minimal usage example (e.g., `msgpack.decode(bytes)`). If you want to avoid a third-party library, explicitly allow a tiny inlined msgpack decoder and define its interface. Also note that the decoder is only used for `RunStarted` discovery and should be a no-op when `view=typed` is used for regular polling.

---

## Issue #2: Edge label attribute parsing rules are underspecified

### The problem

The `/dots/{name}/edges` route states that edge labels come from the `label` attribute in the edge’s attribute block, but it does not define how that attribute is parsed. In contrast, `/dots/{name}/nodes` defines detailed parsing rules: quoted vs unquoted values, `+` concatenation, multi-line strings, and escape handling. If the edge parser only handles simple `label=foo` forms, then quoted labels, multi-line labels, or escaped characters will be returned incorrectly or not at all, which directly affects the human gate choices shown in the detail panel.

### Suggestion

Explicitly state that edge attribute parsing reuses the same rules as node attribute parsing: support quoted/unquoted values, `+` concatenation of quoted fragments, multi-line quoted strings, and the same escape decoding (`\"`, `\n`, `\\`). This keeps human-gate choices correct even when labels contain whitespace or escaped content.
