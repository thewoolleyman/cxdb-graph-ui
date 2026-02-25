# CXDB Graph UI Spec — Critique v48 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-codex)
**Date:** 2026-02-25

## Prior Context

The v47 acknowledgements (opus) applied the fallback discovery fix by no longer caching `null` for contexts whose `client_tag` is missing, and they added three holdout scenarios around CQL fallback behaviour plus the `view=raw` discovery guard. No structural changes were made to the discovery pagination or polling loops.

---

## Issue #1: Fallback discovery still loses completed runs on legacy CXDB

### The problem

Section 5.5 claims the amended fallback logic keeps historical runs discoverable on CXDB versions without CQL by “leaving `client_tag == null` contexts unmapped so discovery retries on subsequent polls.” However, the pseudocode immediately continues the loop whenever `client_tag` is null:

```
IF cqlSupported[index] == false:
    ...
    ELSE IF context.client_tag IS null:
        CONTINUE  -- transiently missing tag; do NOT cache null, retry on next poll
```

Because the loop `CONTINUE`s before `fetchFirstTurn`, the UI never examines those contexts. On older CXDB builds (the exact scenario that sets `cqlSupported[index] == false`), `client_tag` is resolved only while a session is live. As soon as the Kilroy run finishes and the session disconnects, `/v1/contexts` returns `client_tag: null` permanently. A fresh browser load after the run completes sees every Kilroy context in the `client_tag == null` bucket, skips them, and therefore never discovers the pipeline: `knownMappings` stays empty, status overlay never activates, and the “mission control” view for historical runs is still broken. The v47 fix prevents permanent negative caching but does not restore discoverability.

### Suggestion

Adjust the fallback branch so that `client_tag == null` contexts are still eligible for `fetchFirstTurn`, but gate the work to avoid brute-forcing every context:

- Introduce a bounded retry queue (e.g., “null-tag backlog”) limited to the newest N contexts per poll, prioritised by `context_id`, so the UI fetches the first turn for a manageable subset each cycle.
- Once a context is positively identified as Kilroy, cache the mapping as usual; if it is confirmed non-Kilroy, cache `null` to avoid repeat work.
- If the first-turn fetch fails (transient error), leave it in the backlog for the next poll.

Document this behaviour explicitly and note that it is required for historical inspection on CXDB instances lacking key-30 metadata. Without this change the spec still cannot satisfy the “mission control for completed runs” goal it just tried to fix.

## Issue #2: No holdout locks in discovery-after-disconnect on fallback path

### The problem

The new holdout “Fallback discovery does not permanently blacklist contexts with null client_tag” only verifies that the UI retries discovery once the session reconnects and `client_tag` becomes non-null again. It never exercises the critical case that exposed Issue #1: a legacy CXDB instance with CQL disabled, the run has completed, the session is gone, and `client_tag` remains null forever. Under the current spec the UI silently fails, yet every holdout still passes. The acceptance suite therefore cannot catch regressions (or prove any future fix) for the exact failure mode v47 aimed to address.

### Suggestion

Add a holdout scenario such as:

```
### Scenario: Fallback discovery finds completed run after session disconnect
Given CXDB lacks CQL support (GET /v1/contexts/search returns 404)
  And a Kilroy run completed and its context now appears in GET /v1/contexts with client_tag: null and is_live: false
When the UI polls for discovery
Then the UI fetches the first turn for that context despite the missing client_tag
  And maps it to the correct pipeline tab via RunStarted.graph_name
  And the status overlay shows the run’s final state
```

This scenario forces implementations to handle null tagged contexts proactively (Issue #1’s fix) and prevents regressions where historical runs disappear on legacy CXDB deployments.
