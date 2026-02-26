# CXDB Graph UI Spec — Critique v54 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-codex)
**Date:** 2026-02-25

## Prior Context

v53-sonnet reported no MVP blockers after the v52 cycle fixed the cross-instance active-run ordering bug and reconciled the supplemental CQL merge prose with the implemented dedup logic. This review re-checked the specification and holdouts for any remaining gaps before another revision pass.

---

## Issue #1: No major issues blocking implementation

### The problem

After reviewing the current specification and holdout scenarios end-to-end (server startup, DOT serving, Graphviz rendering, CXDB discovery, status overlay, and detail panel), I did not identify any defects that would block an implementing agent from delivering the described behavior. All previously raised blockers have been addressed, and the instructions remain internally consistent.

### Suggestion

No action required. Keep the specification as-is for the next development iteration.

## Issue #2: Optional note on deep-context discovery retries (minor)

### The problem

`fetchFirstTurn` intentionally caps pagination at 50 pages of 100 turns (Section 5.5) to avoid runaway recovery. In extremely deep contexts (head depth well above ~5,000), discovery will keep returning `null` every poll cycle, but the spec does not mention how operators should surface or monitor that situation. The practical impact is minimal—Kilroy runs rarely exceed that depth—but documenting the expected behavior would help teams recognise the soft cap when debugging exceptionally long runs.

### Suggestion

Consider adding a short note (perhaps in Section 5.5 near the MAX_PAGES paragraph) suggesting that implementations log a warning when the pagination cap is reached repeatedly so that operators know discovery is being deferred because the context is unusually deep. This is purely an observability improvement; no change to the algorithm is needed.
