# CXDB Graph UI Spec — Critique v47 (codex) Acknowledgement

Both issues from the v47-codex critique were validated against CXDB source code and applied. Issue #1 identified a genuine spec bug: the fallback discovery algorithm permanently blacklisted contexts with null `client_tag`, which is demonstrably wrong on older CXDB deployments where `client_tag` is only session-resolved. The pseudocode and caching documentation were corrected. Issue #2 identified a missing holdout scenario for the `view=raw` requirement; the scenario was added to the canonical suite. Three additional holdout scenarios were added to fully lock in the boundary conditions around Issue #1.

## Issue #1: Fallback discovery permanently blacklists contexts with transiently missing `client_tag`

**Status: Applied to specification**

The critique is correct. Verified against CXDB source:

- `context_to_json` (`server/src/http/mod.rs` lines 1305-1395) resolves `client_tag` with a two-step fallback: first from `stored_metadata` (extracted from key 30 in the first turn payload), then from `session.as_ref().map(|s| s.client_tag.clone())`. If `stored_metadata` has no `client_tag` (which is always the case since Kilroy does not emit key 30) and there is no active session, `client_tag` is absent from the JSON entirely.

- `SessionTracker.unregister` (`server/src/metrics.rs` lines 88-99) removes all `context_to_session` entries for the session's contexts. After unregister, `get_session_for_context` returns `None`, and the session fallback in `context_to_json` produces `None`. This confirms the post-disconnect nullness the critique describes.

The spec's `discoverPipelines` pseudocode previously cached `knownMappings[key] = null` whenever `context.client_tag IS null` in the fallback path. This permanently excluded contexts whose `client_tag` was only transiently null (startup window or post-disconnect), breaking the mission-control use case for historical inspection on older CXDB deployments.

**Fix applied:** The pseudocode was split into two distinct cases:
1. `client_tag` is present but does NOT start with `"kilroy/"` → cache `null` (confirmed non-Kilroy, permanent negative)
2. `client_tag` IS null → `CONTINUE` without caching (leave unmapped, retry next poll)

The rationale comment in the pseudocode explains both scenarios (startup window and post-disconnect) with references to the CXDB source. The "Caching" prose paragraph was updated to list three (previously two) unmapped cases, explicitly calling out the null `client_tag` fallback case and its rationale.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated `discoverPipelines` pseudocode fallback block (lines 618-636) to distinguish `client_tag IS NOT null AND NOT startsWith("kilroy/")` (cache null) from `client_tag IS null` (leave unmapped, retry)
- `specification/cxdb-graph-ui-spec.md`: Added explanatory comment block in pseudocode referencing `context_to_json`'s `.or_else` fallback and `SessionTracker.unregister`
- `specification/cxdb-graph-ui-spec.md`: Updated "Caching" prose paragraph to list three (not two) unmapped cases, adding case (c) for null `client_tag` in fallback mode

## Issue #2: No holdout guarantees discovery survives missing type registries

**Status: Applied to holdout scenarios**

The critique is correct: every discovery scenario assumes the type registry is already loaded. An implementation that silently falls back to `view=typed` would fail intermittently (during the window between context creation and registry publication) without any acceptance test catching it.

Added a holdout scenario "Pipeline discovery uses view=raw to survive unpublished type registry" under the Pipeline Discovery section. The scenario specifies that `GET /turns?view=typed` would return 500 (unknown types), the UI requests with `view=raw`, the CXDB server returns raw msgpack in `bytes_b64`, and the UI decodes it client-side — asserting successful discovery without registry dependency. This forces any implementation that ignores the `view=raw` requirement to fail the acceptance suite.

Three additional scenarios were added to fully lock in Issue #1's boundary conditions:
1. **"Fallback discovery does not permanently blacklist contexts with null client_tag"** — verifies the positive case: null `client_tag` is left unmapped and retried, and when the session reconnects the context is discovered normally.
2. **"Fallback discovery still blacklists contexts with wrong-prefix client_tag"** — verifies the negative case is preserved: a context with a non-`kilroy/` prefix tag is still permanently cached as null (not all null-or-wrong-prefix handling was relaxed, only the null case).
3. The existing scenarios for CQL upgrade/downgrade already cover the `cqlSupported` flag mechanics; no changes were needed there.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added "Fallback discovery does not permanently blacklist contexts with null client_tag"
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added "Fallback discovery still blacklists contexts with wrong-prefix client_tag"
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added "Pipeline discovery uses view=raw to survive unpublished type registry"

## Not Addressed (Out of Scope)

- None. Both issues were valid and fully addressed.
