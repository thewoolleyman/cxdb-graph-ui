# Proposed Holdout Scenarios — To Review

Scenarios proposed during spec critique rounds that need review before incorporation into the holdout scenarios document.

All previously proposed scenarios have been incorporated into `cxdb-graph-ui-holdout-scenarios.md`.

---

## Proposed: RunStarted with null or empty graph_name

**Source:** v26-opus, Issue #3

**Scenario:** A CXDB context has a valid `RunStarted` first turn with `run_id` present but `graph_name` is null (field absent from msgpack payload, since it is marked `optional: true` in the registry bundle) or empty string.

**Expected behavior:** The context is excluded from pipeline discovery (cached as a null mapping, same as non-Kilroy contexts). It does not match any pipeline tab. No error is surfaced to the user. The context is not retried on subsequent polls.

**Why current holdout scenarios are insufficient:** The existing "Context does not match any loaded pipeline" scenario assumes the context has a valid `graph_name` that simply does not match any loaded DOT file. The null/empty `graph_name` case is a distinct code path (the guard fires before the pipeline matching loop) and exercises the optional-field handling in the msgpack decoder.
