# CXDB Graph UI Spec — Critique v48 (codex) Acknowledgement

Both issues were validated against CXDB source and applied. Issue #1 identified a genuine residual gap in the v47 fix: the `CONTINUE` before `fetchFirstTurn` in the fallback path meant null-tag contexts were never examined, leaving completed runs on legacy CXDB permanently undiscoverable after session disconnect. The spec was corrected with a bounded null-tag backlog mechanism. Issue #2 added a holdout scenario that locks in the specific failure mode — a completed run with `is_live: false` and `client_tag: null` must be discoverable via `fetchFirstTurn` after session disconnect.

## Issue #1: Fallback discovery still loses completed runs on legacy CXDB

**Status: Applied to specification**

The critique is correct. Verified against CXDB source (`server/src/metrics.rs` `SessionTracker::unregister` lines 88-99, `server/src/http/mod.rs` `context_to_json` lines 1305-1395):

- `context_to_json` resolves `client_tag` via a two-step chain: first from `stored_metadata.client_tag` (requires key 30 in msgpack payload, which Kilroy does not emit), then from `session.as_ref().map(|s| s.client_tag.clone())` (only available while the session is active).
- `SessionTracker::unregister` removes all `context_to_session` entries for the session's contexts. After `unregister`, `get_session_for_context` returns `None`, and the session fallback in `context_to_json` produces `None`. This confirms: for every Kilroy context on a legacy CXDB instance (no key 30, no active session), `client_tag` is permanently null after the run completes.

The v47 fix (preventing permanent blacklisting of null-tag contexts) was necessary but not sufficient. The v47 pseudocode did `CONTINUE` before `fetchFirstTurn` for null-tag contexts, so although they were not cached as null, they were also never examined — they accumulated in an invisible set of perpetually-unclassified contexts. A fresh browser load after pipeline completion would never discover them.

**Fix applied:** A **null-tag backlog** mechanism was added to the `discoverPipelines` pseudocode. Instead of `CONTINUE`-ing for null-tag contexts, the algorithm collects them into `nullTagCandidates`. After the main context loop, the candidates are sorted descending by `context_id` (newest first, as context_id is monotonically increasing from a global counter per `turn_store/mod.rs`), and the top `NULL_TAG_BATCH_SIZE` = 5 are subjected to `fetchFirstTurn`. This bounds the per-cycle cost: CXDB instances with many null-tag contexts (e.g., many completed historical runs) will process them in batches over multiple poll cycles. Once `fetchFirstTurn` confirms a context as Kilroy, it is cached positively. Once confirmed non-Kilroy, it is cached as null (permanent negative, no re-fetch). Transient fetch errors leave the context uncached for retry.

The "Caching" prose paragraph and the "Consequences for discovery" bullet were updated to describe the null-tag backlog and its role in enabling historical run discovery on legacy CXDB.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated `discoverPipelines` pseudocode to collect null-tag contexts into `nullTagCandidates` rather than unconditionally `CONTINUE`-ing; added null-tag batch processing block after the main loop with `NULL_TAG_BATCH_SIZE = 5`
- `specification/cxdb-graph-ui-spec.md`: Updated "Caching" prose paragraph to describe the null-tag backlog mechanism and its three-outcome classification (positive/negative/transient)
- `specification/cxdb-graph-ui-spec.md`: Updated "The UI's `knownMappings` cache and null-tag backlog mitigate this" bullet under "Consequences for discovery"

## Issue #2: No holdout locks in discovery-after-disconnect on fallback path

**Status: Applied to holdout scenarios**

The critique is correct. The existing holdout "Fallback discovery does not permanently blacklist contexts with null client_tag" only covers the reconnection case (session returns, `client_tag` becomes non-null). It does not test the case that v47 aimed to fix: `is_live: false`, `client_tag: null`, run completed, session gone permanently — which is exactly the scenario that was broken before v47 and is now addressed by the null-tag backlog in Issue #1.

Added holdout scenario "Fallback discovery finds completed run after session disconnect on legacy CXDB" under the Pipeline Discovery section. The scenario specifies: CXDB lacks CQL, a Kilroy run has completed with session disconnected, the context appears with `client_tag: null` and `is_live: false`, the context has not been previously cached. When the UI polls, it enqueues the context in the null-tag backlog, fetches the first turn via `fetchFirstTurn`, confirms the `RunStarted` declared type, decodes `graph_name` and `run_id` from the msgpack payload, and maps the context to the pipeline tab with the run's final state visible in the status overlay.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added "Fallback discovery finds completed run after session disconnect on legacy CXDB"

## Not Addressed (Out of Scope)

- None. Both issues were valid and fully addressed.
