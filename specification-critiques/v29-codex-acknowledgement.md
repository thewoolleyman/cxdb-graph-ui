# CXDB Graph UI Spec — Critique v29 (codex) Acknowledgement

Both issues from v29-codex have been applied to the specification. The changes add an explicit HTML escaping requirement for DOT attribute rendering in the detail panel and clarify that Kilroy DOT files always define `shape` per-node, making default `node [...]` attribute inheritance unnecessary.

## Issue #1: Detail panel text rendering does not explicitly require HTML escaping for DOT attributes

**Status: Applied to specification**

Added an "HTML escaping" paragraph in Section 7.1, immediately after the DOT attributes table and before Section 7.2 (CXDB Activity). The paragraph requires all DOT attribute values (Node ID, Prompt, Tool Command, Question, Choices edge labels, Goal Gate badge labels) to be HTML-escaped before DOM insertion — either via `textContent` assignment or explicit entity escaping (`<` → `&lt;`, `>` → `&gt;`, `&` → `&amp;`, `"` → `&quot;`). Notes that DOT files are user-provided inputs and that unescaped rendering via `innerHTML` would allow injection. This complements the existing HTML-escaping requirement for CXDB Output in Section 7.2.

A proposed holdout scenario ("DOT prompt containing HTML markup renders as literal text") was also written to `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` to exercise this requirement.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "HTML escaping" paragraph in Section 7.1 after the DOT attributes table.
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added HTML injection holdout scenario proposal.

## Issue #2: Default node attributes are ignored, but detail panel depends on per-node shape

**Status: Applied to specification**

Extended the "Named nodes only" parsing rule in Section 3.2 (`/dots/{name}/nodes`) to explicitly state that Kilroy-generated DOT files always define `shape` explicitly on every node — verified against actual Kilroy pipeline DOT files (e.g., `start [shape=Mdiamond]`, `implement [shape=box, ...]`, `check_fmt [shape=diamond]`). Documents that default `node [...]` attributes are therefore not needed for `shape` resolution, and that if a node lacks an explicit `shape` attribute, the detail panel's Type field displays no type label rather than falling back to a Graphviz default. This clarifies the implementer's obligations without requiring support for inherited default attributes.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Extended "Named nodes only" bullet in Section 3.2 node attribute parsing rules with explicit Kilroy `shape` guarantee and fallback behavior.

## Not Addressed (Out of Scope)

- None. Both issues were applied.
