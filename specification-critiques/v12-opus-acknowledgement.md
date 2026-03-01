# CXDB Graph UI Spec — Critique v12 (opus) Acknowledgement

All 3 issues were valid and applied to the specification. Issue #1 corrected the turn ordering assumption from newest-first to oldest-first across 6 spec sections, fixing index references in `fetchFirstTurn` and gap recovery that would have caused incorrect behavior. Issue #2 added `limit=10000` to context list fetches to prevent pipeline discovery from missing Kilroy contexts when non-Kilroy contexts accumulate. Issue #3 qualified the CORS statement to accurately distinguish REST endpoints (no CORS) from the SSE endpoint (`Access-Control-Allow-Origin: *`). All claims were verified against the CXDB server source (`server/src/turn_store/mod.rs` and `server/src/http/mod.rs`).

## Issue #1: CXDB returns turns in oldest-first order, not newest-first — all turn array indexing is reversed

**Status: Applied to specification**

Verified against CXDB source: `get_last` (`turn_store/mod.rs:520`) calls `results.reverse()` after walking the parent chain from head to root, producing oldest-first output. The HTTP handler preserves this ordering. `next_before_turn_id` uses `turns.first()` (the oldest turn in the oldest-first array) as the backward pagination cursor.

Applied all 6 sub-fixes from the critique:

1. **Section 5.3** — Changed "turns are always ordered newest-first; CXDB does not support ascending order" to "turns are always ordered oldest-first — ascending by depth within the context's parent chain."

2. **Section 5.5 `fetchFirstTurn`** — Changed `lastTurns[lastTurns.length - 1]` to `lastTurns[0]` and updated the comment to "first element of the final page is the oldest (first) turn." Also updated the prose to say "CXDB returns turns oldest-first."

3. **Section 6.1 gap recovery** — Changed `turns[turns.length - 1]` to `turns[0]` for `oldestFetched` and updated the comment.

4. **Section 6.1 polling step 4** — Changed "(returns newest-first by default)" to "(returns oldest-first)."

5. **Section 6.1 turn fetch limit** — Changed "CXDB always returns turns newest-first" to "CXDB returns turns oldest-first."

6. **Section 6.2 `lastTurnId` assignment** — Updated the comment to reflect oldest-first ordering: "Since turns arrive oldest-first, later encounters per node in the batch have higher turn IDs."

7. **Section 6.2 turn deduplication** — Updated "mixed order" comment to accurately describe the gap recovery join point behavior.

8. **Section 6.2 lifecycle precedence** — Updated the non-temporal order example from "(e.g., newest-first)" to describe the gap recovery prepend scenario.

9. **Section 7.2** — Clarified that the API returns oldest-first but the UI reverses for display (newest-first for better UX). Updated both the context-grouped display paragraph and the per-section ordering note.

10. **Section 6.2 `applyErrorHeuristic`** — Updated `getMostRecentTurnsForNodeInContext` description to say "sorted by `turn_id` descending (newest-first)" to clarify this is a client-side sort, not the API order.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Sections 5.3, 5.5, 6.1, 6.2, 7.2 — corrected turn ordering from newest-first to oldest-first throughout

## Issue #2: Context list default limit of 20 — pipeline discovery may miss Kilroy contexts

**Status: Applied to specification**

Verified against CXDB source: `http/mod.rs:209` shows `.unwrap_or(20)` as the default limit for `/v1/contexts`. The limit parameter is parsed as `u32` with no explicit maximum, so `limit=10000` is accepted.

Added `limit=10000` to all context list fetches:

1. **Section 5.2** — Updated the endpoint example to `GET /v1/contexts?limit=10000` and added documentation explaining the `limit` parameter (default: 20), why 10000 is necessary, and why the UI doesn't use server-side tag filtering.

2. **Section 5.5** — Added `limit=10000` to the `fetchContexts(index)` call in the discovery pseudocode. Added prose explaining that the default of 20 is insufficient and that non-Kilroy contexts can push Kilroy contexts outside the window.

3. **Section 6.1 step 1** — Updated the polling step to show `GET /api/cxdb/{i}/v1/contexts?limit=10000`.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Sections 5.2, 5.5, 6.1 — added `limit=10000` to context list fetches with documentation

## Issue #3: SSE endpoint sets CORS headers — spec's CORS claim is overly broad

**Status: Applied to specification**

Verified against CXDB source: `http/mod.rs:1217,1237` show `Access-Control-Allow-Origin: *` set on the SSE endpoint in both the structured response path and raw socket write path. REST endpoints do not set CORS headers.

Qualified the statement in Section 2 from "CXDB's HTTP API (port 9010) does not set CORS headers" to a precise distinction: "CXDB's REST endpoints (contexts, turns) do not set CORS headers. The SSE endpoint (`/v1/events`) does set `Access-Control-Allow-Origin: *`, but the UI uses polling, not SSE (Section 10)."

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 2 "Why a proxy for CXDB" — qualified CORS statement to distinguish REST vs SSE endpoints

## Not Addressed (Out of Scope)

- None — all issues were addressed.
