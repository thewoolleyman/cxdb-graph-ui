# CXDB Graph UI Spec — Critique v19 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-24

## Prior Context

No acknowledgement file exists for v18, so changes since the last critique are unknown and the previous issues may still be open.

---

## Issue #1: Pipeline liveness/stale detection is undefined when a CXDB instance is unreachable

### The problem
Section 6.1 step 1 says that when a CXDB instance is unreachable, the poller skips it and retains its cached per-context status maps. However, step 3 (active run determination and `checkPipelineLiveness`) depends on the current poll cycle’s context lists to access `created_at_unix_ms` and `is_live`. If the instance is down, `contextLists` has no entry for those contexts, so `lookupContext` cannot resolve `created_at_unix_ms` or `is_live`.

This leaves two undefined behaviors: (a) how to pick the active run when some contexts’ `created_at_unix_ms` are missing, and (b) whether the liveness check should treat those contexts as not live. If liveness silently defaults to false, `applyStaleDetection` can mark running nodes as stale during an outage, contradicting the holdout scenario “CXDB becomes unreachable mid-session,” which expects last known status to be preserved.

### Suggestion
Define how the poller handles missing context list data from an unreachable instance. Two concrete options:

- Cache the last successful context list per instance and use cached `created_at_unix_ms` and `is_live` for active-run determination and liveness checks when the instance is down.
- Or, if any active-run context’s instance is unreachable, skip stale detection for that pipeline and avoid recomputing active-run selection for those contexts until the instance recovers.

Either way, the spec should explicitly preserve last-known liveness during outages to avoid false “stale” transitions.

---

## Issue #2: `/api/dots` response format still contradicts itself

### The problem
Section 3.2 describes `GET /api/dots` as “Returns a JSON array of available DOT filenames,” but the example response is an object with a `dots` field:

```
{ "dots": ["pipeline-alpha.dot", "pipeline-beta.dot"] }
```

An implementer could return either a raw array or the object form and still claim compliance. This ambiguity also affects the initialization sequence in Section 4.5, which doesn’t specify which schema the UI reads.

### Suggestion
Pick one schema and make it unambiguous in both prose and example. If the object form is intended, change the text to “Returns a JSON object with a `dots` array.” If a raw array is intended, update the example and specify that the UI consumes the array directly.
