# CXDB Graph UI Spec — Critique v24 (codex) Acknowledgement

All three issues from v24-codex have been applied to the specification. Node ID normalization rules are now explicit for `/nodes` and `/edges`, `/api/dots` ordering is deterministic, and the DOT edge parsing scope is defined.

## Issue #1: Node ID normalization is unspecified for `/nodes` and `/edges`

**Status: Applied to specification**

Added a "Node ID normalization" paragraph to the `/dots/{name}/nodes` route in Section 3.2. The normalization rules mirror the graph ID normalization from Section 4.4: quoted DOT identifiers have outer `"` stripped and escape sequences resolved (`\"` → `"`, `\\` → `\`), and whitespace is trimmed. The normalized node ID is defined as the canonical key for `dotNodeIds` sets, status map keys, detail panel lookup, and edge `source`/`target` values. Added a scope limitation note: Kilroy-generated DOT files use only unquoted, alphanumeric node IDs, so quoted ID support is for correctness rather than a primary use case.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "Node ID normalization" paragraph to the `/dots/{name}/nodes` route description in Section 3.2.

## Issue #2: `/api/dots` ordering is undefined, making the "first pipeline" nondeterministic

**Status: Applied to specification**

Updated the `/api/dots` route description in Section 3.2 to specify that the `dots` array preserves the order of `--dot` flags from the command line. Added a note that the server must use an ordered data structure (e.g., a slice, not a map) for DOT file registration. The browser uses this order for tab rendering and selects the first entry as the initial pipeline.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated the `GET /api/dots` route description in Section 3.2 to mandate CLI-flag ordering.

## Issue #3: DOT edge parsing scope is underspecified (edge chains, ports, and quoted IDs)

**Status: Applied to specification**

Added a "DOT edge subset" paragraph to the `/dots/{name}/edges` route in Section 3.2. Defined the supported edge constructs: simple edges (`a -> b`), edge chains (`a -> b -> c` expanded to two edges), node ID normalization matching `/nodes`, port stripping (`node_id:port` → `node_id`), and explicit exclusion of subgraph endpoints. Each rule was informed by the Kilroy-generated DOT file patterns — edge chains and ports are included for robustness, subgraph endpoints are excluded because Kilroy does not use them.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "DOT edge subset" paragraph to the `/dots/{name}/edges` route description in Section 3.2.

## Not Addressed (Out of Scope)

- None. All three issues were applied.
