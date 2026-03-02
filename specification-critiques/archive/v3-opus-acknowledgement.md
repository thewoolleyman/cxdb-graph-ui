# CXDB Graph UI Spec — Critique v3 (opus) Acknowledgement

All 5 issues were evaluated and applied to the specification. The turns endpoint documentation now reflects CXDB's actual API: no `order` parameter, correct default limit, pagination via `before_turn_id`/`next_before_turn_id`, `decoded_as` field documented, and `client_tag` added to context objects with `tag` query parameter documented.

## Issue #1: Turns endpoint uses `order=desc`/`order=asc` parameters that do not exist in CXDB

**Status: Applied to specification**

Removed all `order` parameter references throughout the spec:
- Section 5.1 endpoint table: changed to `?limit={n}&before_turn_id={id}`
- Section 5.3 example: changed to `GET /v1/contexts/{context_id}/turns?limit=100` (no order param)
- Section 5.5 discovery algorithm: completely rewritten to use `client_tag` prefix filtering and `before_turn_id` pagination (see v4 Issue #5 for the concrete pagination algorithm)
- Section 6.1 polling step 3: removed `order=desc`, added note that CXDB returns newest-first by default
- Section 6.1 "Turn fetch limit" paragraph: removed `order=desc` reference

Changes:
- `specification/cxdb-graph-ui-spec.md`: Sections 5.1, 5.3, 5.5, 6.1 updated

## Issue #2: Spec claims default turns limit is 20 but CXDB default is 64

**Status: Applied to specification**

Updated Section 5.3 example to use `limit=100` (matching the polling usage) instead of `limit=20`. Added a query parameters table documenting that CXDB's default limit is 64.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 5.3 example URL and new query parameters table

## Issue #3: Turns response includes `next_before_turn_id` for pagination but spec does not document it

**Status: Applied to specification**

Added `next_before_turn_id` to the Section 5.3 response example JSON. Added a "Response fields" section documenting `next_before_turn_id` as a pagination cursor — pass it as `before_turn_id` to fetch the next page of older turns, `null` when no more turns exist.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 5.3 response example and new "Response fields" documentation

## Issue #4: Turn response includes additional fields not shown in spec example

**Status: Applied to specification**

Added `decoded_as` and `parent_turn_id` to the Section 5.3 response example. Added documentation clarifying that the UI uses `declared_type.type_id` for type matching (sufficient because Attractor types do not use version migration), and that `parent_turn_id` is present but unused by the UI. Other storage-level fields (`content_hash_b3`, `encoding`, `compression`, `uncompressed_len`) are omitted from the example as they are internal to CXDB's storage layer.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 5.3 response example and "Response fields" documentation

## Issue #5: Context list response includes fields the spec omits

**Status: Applied to specification**

Updated Section 5.2 to include `client_tag` on context objects in the example response. Documented the `tag` query parameter on the contexts endpoint for server-side filtering. Added `connected_at`, `context_count`, and `peer_addr` to the `active_sessions` example. Updated the discovery algorithm (Section 5.5) to use `client_tag` prefix filtering as the primary mechanism for identifying Kilroy contexts, eliminating the need to fetch turns for non-Kilroy contexts.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 5.2 example response updated with `client_tag` on contexts, `tag` parameter documented, `active_sessions` fields expanded. Section 5.5 discovery algorithm rewritten with `client_tag` prefix filter.

## Not Addressed (Out of Scope)

- None. All issues were addressed.
