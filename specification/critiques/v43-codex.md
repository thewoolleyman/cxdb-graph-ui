# CXDB Graph UI Spec — Critique v43 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-25

## Prior Context

The v42 acknowledgements added a CXDB `node_id` matching assumption note, updated StageStarted detail rendering with `handler_type`, and clarified tool gate turn rendering. Two new proposed holdout scenarios were recorded (CQL-empty supplemental discovery and gap-recovery deduplication). No new holdouts were added for DOT comment parsing.

---

## Issue #1: Turn ID numeric comparison rule is contradicted by multiple pseudocode snippets

### The problem
Section 6.2 explicitly mandates numeric ordering for `turn_id` comparisons (parseInt) because lexicographic comparisons fail for differing digit lengths. However, several pseudocode snippets still use direct `>`/`<=` comparisons on raw string IDs, which implies lexicographic ordering. This shows up in:

- `updateContextStatusMap` (`newLastSeenTurnId` computation, `lastTurnId` updates, deduplication comparisons).
- Gap recovery detection (`oldestFetched > lastSeenTurnId`, `oldestInGap <= lastSeenTurnId`).
- `applyErrorHeuristic` helper note about sorting by `turn_id` descending (not explicitly numeric).

An implementer following the pseudocode literally could violate the numeric comparison requirement and silently corrupt deduplication and gap recovery, especially once turn IDs cross digit boundaries (e.g., 999 vs 1000). This is a spec consistency issue in a correctness-critical area.

### Suggestion
Update all affected pseudocode blocks to explicitly use numeric comparisons, either by wrapping every comparison in `parseInt(..., 10)` or by defining a helper like `compareTurnId(a, b)` and using it consistently. Also update the error-heuristic helper description to state that the newest-first ordering must use numeric comparison within a context.

## Issue #2: Holdout scenarios do not cover DOT comment stripping and quoted-comment safety

### The problem
Section 3.2 defines complex comment-stripping rules that must ignore `//` and `/* */` sequences inside quoted strings and must throw parse errors for unterminated block comments or unterminated strings. These are easy to get wrong in a custom DOT parser, yet no holdout scenario exercises them. Without a holdout, an implementation could pass all scenarios while incorrectly stripping prompt text like `prompt="check http://example.com"` (treating `//` as a comment) or failing to error on unterminated comments/strings.

### Suggestion
Add a holdout scenario that includes:
- A node prompt containing `//` and `/* */` inside quoted strings to assert they are preserved.
- An unterminated block comment to assert `/dots/{name}/nodes` returns 400 with a DOT parse error.
- An unterminated quoted string to assert the same error behavior.

This will validate the most failure-prone part of the DOT parser and align test coverage with the spec’s detailed parsing rules.
