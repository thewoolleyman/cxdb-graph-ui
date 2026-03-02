# CXDB Graph UI Spec — Critique v42 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-25

## Prior Context

The v41 acknowledgements applied the StageFinished custom routing clarifications in Sections 6.2 and 7.2. Holdout gaps for quoted graph IDs, quoted node IDs, and custom routing outcomes were deferred as proposed scenarios.

---

## Issue #1: Holdout scenarios do not cover the CQL-empty supplemental discovery path

### The problem
Section 5.5 documents a critical edge case: CQL search can return zero results because Kilroy does not embed key 30 metadata, and the UI must fall back to a supplemental context list fetch (session-tag resolved) to discover active runs. Section 6.1 then depends on the discovery-effective context list for liveness and stale detection. This is a high-risk branch that is easy to omit or mis-implement, yet none of the holdout scenarios exercise it. An implementation could pass all current scenarios while ignoring the supplemental fetch, resulting in a blank status overlay (and false “Pipeline stalled” warnings) whenever CQL returns empty results on active runs.

### Suggestion
Add a holdout scenario that simulates:
- CQL search returns 200 with an empty contexts array.
- The context list contains a live Kilroy context with a session-tag-resolved `client_tag`.
Assert that discovery still maps the context, status overlays update, and liveness/stale detection uses the supplemental context list.

## Issue #2: CXDB `node_id` normalization rules are underspecified for generic pipelines

### The problem
Sections 3.2 and 4.2 normalize DOT node IDs and rely on SVG `<title>` text for matching, but the spec never states whether `turn.data.node_id` from CXDB must be normalized (unquote/unescape/trim) before matching. For Kilroy-generated DOT this is fine (unquoted IDs), but the spec’s “Generic pipeline support” principle implies support for quoted IDs in DOT files. If a non-Kilroy pipeline emits `node_id` values that include quotes/escapes or leading/trailing whitespace, the UI’s matching logic would fail unless it applies the same normalization to CXDB node IDs. The current spec leaves this ambiguous, which could lead to inconsistent implementations.

### Suggestion
Explicitly define the matching rule between CXDB `node_id` and DOT node IDs. Either:
- Normalize CXDB `node_id` using the same unquote/unescape/trim rules before comparing, or
- Narrow the generic pipeline support claim to require CXDB `node_id` values already normalized (unquoted, trimmed) and document that assumption in Sections 4.2/6.2/7.2.
