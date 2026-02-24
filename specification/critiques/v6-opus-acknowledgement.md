# CXDB Graph UI Spec — Critique v6 (opus) Acknowledgement

All 4 issues were valid and applied to the specification. Issues #1 and #2 were correctness bugs in the `updateContextStatusMap` pseudocode — turn counters were inflated by re-processing overlapping turns, and `lastTurnId` was overwritten with progressively older values. Issue #3 was a performance fix for `fetchFirstTurn` pagination. Issue #4 clarified the DOT attribute parsing scope.

## Issue #1: turnCount and errorCount double-count across poll cycles

**Status: Applied to specification**

The `updateContextStatusMap` function now accepts and returns a `lastSeenTurnId` cursor per context. On each poll, turns with `turn_id <= lastSeenTurnId` are skipped (with an early `BREAK` since turns are newest-first). Only newly appended turns are processed, preventing `turnCount` and `errorCount` inflation. The cursor initializes to `null` and resets on `run_id` change. Added explanatory "Turn deduplication" paragraph after the algorithm.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 `updateContextStatusMap` signature updated to accept/return `lastSeenTurnId`; added cursor check with `BREAK`; added "Turn deduplication" paragraph
- `specification/cxdb-graph-ui-spec.md`: Section 6.1 polling step 4 updated to reference `lastSeenTurnId` cursor advancement

## Issue #2: lastTurnId ends up pointing to the oldest turn in the batch

**Status: Applied to specification**

The unconditional `existingMap[nodeId].lastTurnId = turn.turn_id` assignment was replaced with a conditional that only sets the field when it is `null`. Since turns are processed newest-first, the first encounter per node captures the most recent turn ID. Added explanatory "lastTurnId assignment" paragraph after the algorithm.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 6.2 `updateContextStatusMap` — `lastTurnId` assignment guarded by `IS null` check; added "lastTurnId assignment" paragraph

## Issue #3: fetchFirstTurn uses limit=64 requiring many round trips

**Status: Applied to specification**

The `fetchFirstTurn` algorithm now calculates `fetchLimit = min(headDepth + 1, 65535)` to fetch the entire context in a single request when possible. For contexts with ≤65,535 turns (virtually all Kilroy pipelines), this reduces discovery from ~156 requests to 1. The pagination loop remains as a fallback for the rare context exceeding the CXDB limit.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 5.5 `fetchFirstTurn` — replaced hardcoded `limit=64` with calculated `fetchLimit`; updated surrounding prose to describe the optimization and its bounds

## Issue #4: DOT attribute parsing scope is unspecified

**Status: Applied to specification**

Section 3.2's `/dots/{name}/nodes` description now includes explicit parsing rules: both quoted and unquoted attribute values, exclusion of global default blocks (`node [...]`, `edge [...]`, `graph [...]`), inclusion of nodes inside subgraphs, and supported escape sequences (`\"`, `\n`, `\\`).

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 3.2 — replaced single-sentence parsing description with structured list of parsing rules
