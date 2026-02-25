# CXDB Graph UI Spec — Critique v47 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-codex)
**Date:** 2026-02-25

## Prior Context

The v46 acknowledgements incorporated the turn field inventory fixes (adding `call_id`, `status`, `join_policy`, `error_policy` to Section 5.4) and confirmed that previously requested holdout scenarios for interviews, `StageStarted`, and lifecycle retries already live in the canonical suite. No structural changes were made to the discovery algorithm or polling logic since the last critique.

---

## Issue #1: Fallback discovery permanently blacklists contexts with transiently missing `client_tag`

### The problem
Section 5.5 instructs the fallback path (`cqlSupported[index] == false`) to mark any context whose `client_tag` is `null` as `knownMappings[key] = null` (lines 618-623). That negative cache is permanent. Unfortunately, on CXDB versions without CQL support—which is exactly when this fallback is active—`client_tag` can legitimately be `null` during normal operation:

- Immediately after context creation but before session metadata is registered, the context list returns the context without a `client_tag`.
- After the run finishes and the session disconnects, `context_to_json` drops the session-derived tag and returns `null` unless Kilroy embeds key 30 metadata (which current builds do not).

Following the spec as written, the UI will permanently blacklist those contexts the first time they appear without a `client_tag`, so discovery never retries them even after metadata extraction (or a new active session) fills in the tag. On older CXDB deployments—precisely the environments that lack CQL—this means a fresh page load after a run completes can never rediscover that run, breaking the mission-control use case for historical inspection.

### Suggestion
Adjust the fallback algorithm so that contexts with `client_tag == null` are treated as "unknown" rather than permanently cached negatives. Leave them unmapped (no `knownMappings` entry) so discovery retries on subsequent polls, and gate the expensive `fetchFirstTurn` call behind a stricter heuristic (e.g., skip when `client_tag` is missing but do **not** cache null). Adding a holdout scenario that boots the UI with CQL disabled, observes a context whose session disconnects mid-run, and verifies the pipeline remains discoverable would lock this in.

## Issue #2: No holdout guarantees discovery survives missing type registries

### The problem
Section 5.5 goes to great lengths to require `fetchFirstTurn` to use `view=raw`, explicitly to sidestep the window where the Kilroy registry bundle has not yet been published. If an implementation naively uses the default `view=typed`, the first discovery request against an empty registry fails with 500, and the pipeline is invisible until the registry upload completes—exactly the scenario the spec is trying to avoid.

However, the canonical holdout suite never exercises this edge case. Every discovery scenario assumes the registry is already loaded, so an implementation that ignores the `view=raw` requirement still passes all tests. That leaves a critical regression vector: the UI will intermittently fail in real runs (first poll happens milliseconds before the bundle upload), yet the acceptance suite stays green.

### Suggestion
Add a holdout scenario under "Pipeline Discovery" that simulates a CXDB instance where `GET /turns` with `view=typed` fails due to an unpublished registry bundle, and asserts that the UI still discovers the pipeline (implying it must use `view=raw`). This forces the acceptance suite to cover the resilience described in Section 5.5.

---
