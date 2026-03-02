# CXDB Graph UI Spec — Critique v24 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-24

## Prior Context

The v23 cycle embedded `index.html` with `go:embed`, specified `/nodes` and `/edges` error handling, switched context discovery to CQL search with a fallback path, added `view=raw` decoding for `RunStarted`, and documented the error-heuristic window limitation. This critique focuses on remaining implementability gaps around identifier normalization, ordering guarantees, and DOT edge parsing scope.

---

## Issue #1: Node ID normalization is unspecified for `/nodes` and `/edges`

### The problem

The spec defines a normalization algorithm for **graph IDs** (Section 4.4) to match `RunStarted.data.graph_name`, but it never defines how **node IDs** should be normalized when parsing DOT for `/dots/{name}/nodes` or `/dots/{name}/edges`. Graphviz’s SVG `<title>` values for nodes are unquoted/unescaped node identifiers, while DOT source can legally use quoted IDs with spaces or escape sequences. If the server returns raw, quoted IDs from the DOT parser while the SVG uses normalized IDs, then:

- Status overlays will not match turns whose `node_id` is normalized.
- The detail panel will not find attributes for clicked SVG nodes.
- Edge labels for human-gate choices may not resolve when edge endpoints are quoted IDs.

Because the spec never states how to normalize node IDs, different implementations could choose different conventions and silently break the node matching contract.

### Suggestion

Add explicit node ID normalization rules for `/nodes` and `/edges` to mirror the SVG `<title>` output and CXDB `node_id` values. At minimum: unquote DOT identifiers, unescape `\"` and `\\`, and trim whitespace, using the same normalization approach as the graph ID regex. Then state that this normalized node ID is the canonical key used for:

- `dotNodeIds` sets
- status map keys
- detail panel lookup
- edge `source`/`target` values

If the implementation only supports unquoted, alphanumeric node IDs (as in Kilroy-generated DOT), state that limitation explicitly and reject or warn on quoted IDs.

---

## Issue #2: `/api/dots` ordering is undefined, making the “first pipeline” nondeterministic

### The problem

The UI renders the “first pipeline” after fetching `/api/dots` (Section 4.5, step 5). The spec does not define whether `/api/dots` preserves the original `--dot` flag order, sorts alphabetically, or uses Go map iteration order. In Go, ranging over a map is randomized, so an implementation that builds a map from basenames and then emits keys could produce nondeterministic tab ordering and initial pipeline selection across runs.

This conflicts with the holdout scenario “Switch between pipeline tabs,” which assumes a stable first pipeline, and it makes it hard to predict which pipeline the UI will render on load.

### Suggestion

Specify that `/api/dots` must return filenames in the same order as the `--dot` flags were provided on the CLI. If a different ordering is desired (e.g., sorted), document it explicitly and update the UI initialization to select a deterministic tab by name instead of index. Either way, the ordering must be deterministic and specified to avoid relying on Go map iteration.

---

## Issue #3: DOT edge parsing scope is underspecified (edge chains, ports, and quoted IDs)

### The problem

Section 3.2 describes `/dots/{name}/edges` as parsing `source -> target` statements and extracting the `label` attribute. DOT syntax supports edge chains (`a -> b -> c`), node ports (`a:out -> b:in`), quoted node IDs, and subgraph endpoints. The spec does not say whether any of these constructs must be supported or intentionally rejected.

An implementer could reasonably only parse single-edge statements without ports or quoted IDs, which might break when a DOT file includes any of the legal but more complex forms. This matters because edge labels are required to populate human-gate choices in the detail panel.

### Suggestion

Define the expected DOT subset for edge parsing. Either:

1. **Constrain the input**: explicitly state that pipeline DOT files will only use simple `node_id -> node_id` edges with no ports, no edge chains, and no subgraph endpoints; or
2. **Define expanded parsing rules**: treat `a -> b -> c` as two edges (`a -> b`, `b -> c`), strip port suffixes from node IDs (or include them consistently), and apply the same node ID normalization as Issue #1.

This makes the `/edges` contract implementable and reduces ambiguity around which DOT constructs are in-scope.
