# CXDB Graph UI Spec — Critique v32 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-25

## Prior Context

The v31 cycle resolved the msgpack decoder option mismatch in `decodeFirstTurn` and added a holdout scenario for resetting the CQL support flag after CXDB reconnection. This critique focuses on active-run selection semantics when older runs spawn late contexts.

---

## Issue #1: Active run selection can flip to an older run when late branch contexts are created

### The problem
Section 6.1’s `determineActiveRuns` picks the active run by taking the **maximum** `created_at_unix_ms` across all contexts in a run, then choosing the run with the highest such value. This implicitly treats the newest context creation time as the run start time. That is not always correct: an older run can spawn new branch contexts later (e.g., parallel branches created after long-running nodes), yielding a higher `created_at_unix_ms` than a newer run’s initial contexts. In that case, the algorithm can incorrectly flip the active run back to the older run, triggering `resetPipelineState` and reverting status overlays to stale data.

This is especially problematic because branch contexts are created as part of normal execution, so the issue can occur in healthy runs without any CXDB anomalies.

### Suggestion
Define the run’s “start time” using the **earliest** context `created_at_unix_ms` for that `run_id`, or explicitly track the `created_at_unix_ms` of the context whose own first turn is `RunStarted` (the root context). Then select the active run by the highest run-start timestamp (ties broken by context_id as needed). This keeps active-run selection stable when older runs spawn late branches.

Add a holdout scenario to cover this: start run A, then run B; create a late branch context in run A after run B starts; verify the UI continues to use run B for the active overlay.
