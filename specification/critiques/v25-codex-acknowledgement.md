# CXDB Graph UI Spec — Critique v25 (codex) Acknowledgement

Both issues from v25-codex have been applied to the specification. The msgpack dependency gap (shared with opus issue #2) is addressed by the new Section 4.1.1, and edge attribute parsing rules now explicitly reference the node parsing rules.

## Issue #1: Msgpack decoding dependency for `view=raw` is not specified

**Status: Applied to specification**

This issue overlaps with v25-opus Issue #2 and was addressed in the same edit. Added Section 4.1.1 "Browser Dependencies" documenting the `@msgpack/msgpack` CDN dependency at a pinned URL (`https://cdn.jsdelivr.net/npm/@msgpack/msgpack@3.0.0-beta2/dist.es5+esm/mod.min.mjs`), its usage context (only `decodeFirstTurn`, not regular polling), and the base64 decoding approach using `atob()`. The `decodeFirstTurn` pseudocode in Section 5.5 was also updated to use integer-tag-based access (addressing the related opus issue about raw msgpack field access).

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added Section 4.1.1 "Browser Dependencies" with pinned msgpack CDN URL, usage notes, and base64 decoding helper.
- `specification/cxdb-graph-ui-spec.md`: Updated `decodeFirstTurn` pseudocode in Section 5.5 to use tag-based access.

## Issue #2: Edge label attribute parsing rules are underspecified

**Status: Applied to specification**

Added an explicit statement to the `/dots/{name}/edges` route description that edge attribute parsing reuses the same rules as node attribute parsing: quoted and unquoted values, `+` concatenation of quoted fragments, multi-line quoted strings, and the same escape decoding (`\"` → `"`, `\n` → newline, `\\` → `\`). This ensures human-gate choices and edge labels are decoded correctly even when labels contain whitespace, escaped characters, or multi-line content.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated the `/dots/{name}/edges` route description in Section 3.2 to reference the node attribute parsing rules explicitly.

## Not Addressed (Out of Scope)

- None. Both issues were applied.
