# CXDB Graph UI Spec — Critique v28 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-25

## Prior Context

The v27 cycle applied all codex issues (graph ID extraction for strict/anonymous graphs, whitespace-preserving rendering, and deterministic truncation/expansion) and all opus issues except the proposed CQL fallback scenario (which remains in proposed holdouts). This review focuses on remaining inconsistencies between normalization rules and the detail panel’s documented data fields.

---

## Issue #1: Graph ID unescaping is underspecified and diverges from node ID normalization

### The problem
Section 3.2 and Section 4.4 say graph IDs are unquoted and “unescaped,” but the only explicit escape handling listed is `\"` for quotes. By contrast, node ID normalization (Section 3.2, `/nodes`) explicitly decodes both `\"` and `\\`, and trims whitespace. If a DOT graph ID includes escaped backslashes (or any escape sequence beyond `\"`), the server/browser normalization rules are ambiguous and can diverge from `RunStarted.data.graph_name`, leading to pipeline discovery mismatches even though the DOT file is valid. This is a small but real gap because the spec explicitly reuses graph ID normalization for discovery, but does not define the same escape decoding rules as it does for node IDs.

### Suggestion
Mirror the node ID normalization rules for graph IDs: explicitly state that quoted graph IDs must unescape `\"` and `\\` (and trim leading/trailing whitespace if any), and that the server and browser use the same normalization routine. This keeps graph ID handling aligned with node ID normalization and makes discovery behavior deterministic for escaped identifiers.

## Issue #2: Detail panel references per-node counters that are never surfaced in the spec or UI requirements

### The problem
`NodeStatus` tracks `turnCount`, `errorCount`, and `toolName`, and the merge step sums `turnCount`/`errorCount` across contexts (Section 6.2). However, the detail panel section never specifies where these fields are displayed or how they’re used. The only reference is a parenthetical note saying `errorCount` remains a display-only lifetime counter shown in the detail panel, but the detail panel UX (Section 7.2) has no column or row that renders these counters, nor does the holdout suite mention them. This leaves an implementer unsure whether to build UI for these fields or ignore them. It also creates a hidden requirement (to show `errorCount`) that is not testable by the scenarios.

### Suggestion
Either (a) document exactly where these counters appear in the detail panel (e.g., a node summary header showing total turns and total errors, plus last tool name), and add a holdout scenario to validate it, or (b) explicitly state that `turnCount`, `errorCount`, and `toolName` are internal-only and not displayed. If they are internal-only, remove the “shown in the detail panel” statement to avoid contradictory requirements.
