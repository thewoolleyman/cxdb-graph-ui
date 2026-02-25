# Proposed Holdout Scenarios — To Review

Scenarios proposed during spec critique rounds that need review before incorporation into the holdout scenarios document.

All previously proposed scenarios have been incorporated into `cxdb-graph-ui-holdout-scenarios.md`.

---

## Proposed: RunStarted with null or empty graph_name

**Source:** v26-opus, Issue #3

**Scenario:** A CXDB context has a valid `RunStarted` first turn with `run_id` present but `graph_name` is null (field absent from msgpack payload, since it is marked `optional: true` in the registry bundle) or empty string.

**Expected behavior:** The context is excluded from pipeline discovery (cached as a null mapping, same as non-Kilroy contexts). It does not match any pipeline tab. No error is surfaced to the user. The context is not retried on subsequent polls.

**Why current holdout scenarios are insufficient:** The existing "Context does not match any loaded pipeline" scenario assumes the context has a valid `graph_name` that simply does not match any loaded DOT file. The null/empty `graph_name` case is a distinct code path (the guard fires before the pipeline matching loop) and exercises the optional-field handling in the msgpack decoder.

---

## Proposed: CXDB downgrades and CQL becomes unavailable mid-session

**Source:** v27-opus, Issue #4

**Scenario:**
```
Given the UI has been polling CXDB-0 successfully using CQL search
  And cqlSupported[0] is true
When CXDB-0 is restarted with a version that lacks CQL support
  And the restart is fast enough that no poll cycle sees a 502
Then the next CQL search attempt returns 404
  And the UI sets cqlSupported[0] to false
  And falls back to the context list endpoint for that poll cycle
  And subsequent polls use the context list fallback without retrying CQL
  And pipeline discovery continues uninterrupted
```

**Expected behavior:** The `cqlSupported` flag transitions from `true` to `false` on the 404 response. The fallback context list path is used for subsequent polls. Discovery is not interrupted.

**Why current holdout scenarios are insufficient:** The existing holdout scenarios cover CXDB unreachable/reconnect (connection handling section) and the basic CQL discovery flow (pipeline discovery section), but the CQL-to-fallback transition during continuous operation — where the instance remains reachable but loses CQL support — is not covered. The code path is already specified in the `discoverPipelines` pseudocode but adding the scenario makes the fallback transition explicitly testable.

---

## Proposed: Forked context discovered via parent's RunStarted turn

**Source:** v29-opus, Issue #4

**Scenario:**
```
Given a pipeline run creates a parent context with RunStarted(graph_name="alpha_pipeline")
  And the parent context forks a child context for a parallel branch
  And the child context has head_depth=500
  And the child's parent chain extends into the parent context
When the UI runs pipeline discovery for the child context
Then fetchFirstTurn paginates through the child's turns into the parent context
  And discovers the parent's RunStarted turn at depth=0
  And the child context is correctly mapped to the alpha_pipeline tab
```

**Expected behavior:** The `fetchFirstTurn` pagination follows `parent_turn_id` links across the context boundary (from child to parent), eventually finding the parent's `RunStarted` turn at depth 0. The child context is mapped to the same pipeline as the parent.

**Why current holdout scenarios are insufficient:** The existing "Context matched to pipeline via RunStarted turn" scenario assumes the RunStarted is in the same context. The "Multiple contexts for parallel branches" scenario tests merging, not discovery. A forked context's child does not contain a RunStarted turn at all — it inherits the parent's RunStarted through the parent chain. If an implementer's `fetchFirstTurn` incorrectly stops at the context boundary (e.g., by checking `context_id` matches), pipeline discovery silently fails for all parallel branches.

---

## Proposed: DOT prompt containing HTML markup renders as literal text

**Source:** v29-codex, Issue #1

**Scenario:**
```
Given a DOT node has prompt attribute containing "<script>alert('xss')</script> and <b>bold</b>"
When the user clicks the node to open the detail panel
Then the detail panel shows the literal text "<script>alert('xss')</script> and <b>bold</b>"
  And no script executes
  And no HTML formatting is applied (no bold text)
  And the angle brackets are visible as text characters
```

**Expected behavior:** All DOT attribute values are HTML-escaped or inserted via `textContent` before DOM insertion. No HTML injection is possible from DOT file content.

**Why current holdout scenarios are insufficient:** The existing "DOT file with long prompt text" scenario tests length and escape handling but does not verify that HTML-like content in DOT attributes is safely rendered. Since DOT files are user-provided inputs, HTML injection is a real risk if an implementer uses `innerHTML` for DOT attribute rendering.

---

## Proposed: CQL support flag resets on CXDB instance reconnection

**Source:** v30-opus, Issue #4

**Scenario:**
```
Given a CXDB instance initially runs an older version without CQL support
  And the UI's CQL search to that instance returned 404
  And the UI is using the context list fallback for that instance
When the CXDB instance becomes unreachable
  And then reconnects after being upgraded to a CQL-supporting version
Then the UI resets the cqlSupported flag for that instance
  And retries CQL search on the next poll cycle
  And discovers CQL is now supported
  And subsequent polls use CQL search instead of the fallback
```

**Expected behavior:** The `cqlSupported` flag is reset from `false` to unset when the instance becomes unreachable. On reconnection, the UI retries CQL search. If the upgraded instance supports CQL (returns 200 instead of 404), the flag is set to `true` and subsequent polls use CQL search.

**Why current holdout scenarios are insufficient:** The existing "One of multiple CXDB instances unreachable" scenario tests partial connectivity and status preservation, but not the `cqlSupported` flag lifecycle. The "CXDB downgrades and CQL becomes unavailable" proposed scenario (v27-opus) covers the opposite direction (CQL-supported to unsupported). This scenario covers the upgrade path where a non-CQL instance gains CQL support during a UI session. If an implementer forgets to reset the flag on reconnection, the UI permanently uses the slower fallback path for that instance — a silent performance regression.

---

## Proposed: Pipeline tab label with HTML-like graph ID renders as literal text

**Source:** v30-codex, Issue #1

**Scenario:**
```
Given a DOT file contains "digraph \"<b>Pipeline</b>\" {"
When the UI renders the tab bar
Then the tab label shows the literal text "<b>Pipeline</b>"
  And no HTML formatting is applied (no bold text)
  And the angle brackets are visible as text characters
```

**Expected behavior:** Tab labels are rendered via `textContent` or explicit HTML escaping. No HTML injection is possible from DOT graph IDs.

**Why current holdout scenarios are insufficient:** The existing "Tab shows graph ID from DOT declaration" scenario tests correct extraction but does not verify safe rendering of HTML-like content. The "DOT prompt containing HTML markup" proposed scenario (v29-codex) covers the detail panel but not the tab bar.
