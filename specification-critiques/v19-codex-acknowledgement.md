# CXDB Graph UI Spec — Critique v19 (codex) Acknowledgement

Both issues were addressed in the v21 revision cycle. Pipeline liveness/stale detection during CXDB outages was resolved via context list caching, and the `/api/dots` response format inconsistency was resolved by updating the prose to match the example.

## Issue #1: Pipeline liveness/stale detection is undefined when a CXDB instance is unreachable

**Status: Applied to specification (in v21 cycle)**

This was addressed during the v21 revision cycle (see v21-opus-acknowledgement.md, Issue #3). Section 6.1 step 1 now caches context lists per instance on success (`cachedContextLists[i]`). When an instance is unreachable, the cached context list is used as the fallback for `lookupContext` calls in both `determineActiveRuns` and `checkPipelineLiveness`. This preserves `is_live` and `created_at_unix_ms` data through transient outages, preventing false stale transitions and spurious run-change resets.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added `cachedContextLists` caching and fallback behavior in Section 6.1 step 1 (applied in v21 cycle).

## Issue #2: `/api/dots` response format still contradicts itself

**Status: Applied to specification (in v21 cycle)**

This was addressed during the v21 revision cycle (see v21-opus-acknowledgement.md, Issue #2 and v21-codex-acknowledgement.md, Issue #3). The prose was changed from "Returns a JSON array of available DOT filenames" to "Returns a JSON object with a `dots` array containing the available DOT filenames." The example response (an object with a `dots` field) is the intended format and is now consistent with the prose. The initialization sequence step 2 was also updated.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated `GET /api/dots` description in Section 3.2 and initialization step 2 in Section 4.5 (applied in v21 cycle).

## Not Addressed (Out of Scope)

- None. Both issues have been addressed (in the v21 cycle).
