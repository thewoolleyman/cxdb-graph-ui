# CXDB Graph UI Spec — Critique v45 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-25

## Prior Context

No v44 acknowledgement file is present yet, so no new changes are recorded since the v44 critique. The last acknowledged updates (v43) covered numeric turn_id comparisons, StageFinished notes/suggested_next_ids rendering, StageRetrying delay rendering, and unmatched-route 404 behavior, plus two proposed holdouts still pending inclusion.

---

## Issue #1: Holdout scenarios do not verify the CQL-empty supplemental discovery path

### The problem
Section 5.5 introduces a critical workaround for the current Kilroy limitation (missing key 30 metadata): when CQL search returns an empty list, the UI must issue a supplemental full context list fetch and filter by `client_tag` to discover active runs. This path is essential for discovery to work during active sessions and for liveness detection to avoid falsely marking running nodes as stale.

The holdout scenarios include CQL support fallback (404) and reconnection behavior, but there is no scenario that exercises the “CQL returns 200 with zero contexts → supplemental fetch” branch. An implementation that treats empty CQL results as “no pipelines” would still pass the current holdouts, yet would fail to discover running pipelines until Kilroy embeds key 30.

### Suggestion
Add a Pipeline Discovery holdout scenario that requires the supplemental path:

```
### Scenario: CQL returns empty, supplemental context list still discovers active run
Given CXDB supports CQL and returns 200 with an empty contexts array for tag ^= "kilroy/"
  And the full context list includes an active context whose client_tag starts with "kilroy/"
When the UI runs pipeline discovery
Then the pipeline is discovered via the supplemental context list
  And the status overlay uses that context's turns
  And pipeline liveness reflects is_live from the supplemental list
```

This locks in the temporary-but-critical behavior until Kilroy implements key 30 metadata.

## Issue #2: Holdout scenarios do not cover nodes and edges inside subgraphs

### The problem
Section 3.2 explicitly requires that nodes defined inside `subgraph` blocks are included in `/dots/{name}/nodes`, and Section 3.2 `/edges` requires edges inside subgraphs to be included as well. These are correctness requirements for pipelines that use subgraphs for layout or grouping.

The current holdouts exercise edge chains, port stripping, and basic node parsing, but none verify that subgraph-scoped nodes or edges are parsed and surfaced. A parser that ignores subgraph contents would still pass existing scenarios, while silently dropping nodes and edges that appear in real DOT graphs.

### Suggestion
Add a DOT parsing holdout scenario that includes subgraph-scoped content:

```
### Scenario: Nodes and edges inside subgraphs are included
Given a DOT file contains:
  subgraph cluster_a { a [shape=box] }
  subgraph cluster_b { b [shape=diamond] }
  a -> b [label="go"]
When the browser fetches /dots/{name}/nodes and /dots/{name}/edges
Then the nodes response includes a and b
  And the edges response includes (a, b, "go")
```

This ensures the parser does not drop valid subgraph-scoped definitions.
