# CXDB Graph UI Spec — Critique v4 (opus) Acknowledgement

3 of 5 issues were applied. Issues #1 and #2 were not valid — the CXDB source code confirms that `created_at_unix_ms` and `is_live` are correct as originally specified. The SSE non-goal was added, active_sessions fields were expanded, and the discovery algorithm now uses concrete `before_turn_id` pagination.

## Issue #1: `created_at_unix_ms` field name and format do not match CXDB API

**Status: Not addressed — critique finding was incorrect**

The CXDB source code (`server/src/http/mod.rs`, `context_to_json` function) confirms the field is named `created_at_unix_ms` and contains a numeric unix milliseconds value. The original spec was correct. The critique's claim that the field is `created_at` with ISO-8601 format was based on an inaccurate exploration of the codebase.

## Issue #2: `is_live` field in context response does not exist in CXDB

**Status: Not addressed — critique finding was incorrect**

The CXDB source code confirms `is_live` is a boolean field on each context object, set to `true` when the context has an active session (`let is_live = session.is_some()`). The original spec was correct.

## Issue #3: SSE events endpoint exists but spec does not acknowledge it

**Status: Applied to specification**

Added Non-Goal #11 explaining that CXDB exposes `/v1/events` SSE endpoint but the UI uses polling for simplicity — no persistent connection management, simpler error recovery, and 3-second latency is sufficient.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 10 Non-Goals, new item #11

## Issue #4: `active_sessions` response structure has undocumented fields

**Status: Applied to specification**

Updated Section 5.2 example to include all `active_sessions` fields: `connected_at`, `context_count`, and `peer_addr` alongside the existing `client_tag`, `session_id`, and `last_activity_at`. The timestamp fields remain as numeric unix-ms values, consistent with how CXDB serializes them (confirmed in source).

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 5.2 `active_sessions` example expanded

## Issue #5: Discovery algorithm should use `before_turn_id` pagination to reach RunStarted turn

**Status: Applied to specification**

Rewrote the discovery algorithm in Section 5.5 with a concrete two-phase approach:
1. **Phase 1:** Filter contexts by `client_tag` prefix (`kilroy/`) to skip non-Kilroy contexts entirely
2. **Phase 2:** Fetch the first turn using a `fetchFirstTurn` function that paginates backward via `next_before_turn_id` cursor until reaching the oldest page

The algorithm includes the complete `fetchFirstTurn` pseudocode with the special case for `head_depth == 0` (single-turn context) and the general pagination loop. Documented that this runs at most `ceil(headDepth/64)` requests per context but only once (cached).

Combined with the v3 Issue #5 `client_tag` optimization, pagination now only runs for confirmed Kilroy contexts, not for every context on the CXDB instance.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 5.5 discovery algorithm completely rewritten with `fetchFirstTurn` function

## Not Addressed (Out of Scope)

- Issue #1 (`created_at_unix_ms`): Not a real issue — spec was already correct
- Issue #2 (`is_live`): Not a real issue — spec was already correct
