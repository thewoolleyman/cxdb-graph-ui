# CXDB Graph UI Spec — Critique v34 (opus) Acknowledgement

All four issues from the v34 opus critique were evaluated. Issues #1, #2, and #3 were applied to the specification. Issue #4 was applied as a documentation clarification.

## Issue #1: `resetPipelineState` prose contradicts the pseudocode on whether old-run mappings are removed from `knownMappings`

**Status: Applied to specification**

Replaced the contradictory prose paragraph after the `determineActiveRuns` pseudocode (Section 6.1) that stated `resetPipelineState` "removes `knownMappings` entries whose `runId` matches the old run's `run_id`" with language that explicitly states `resetPipelineState` does **not** remove old-run entries. The new text explains the rationale (avoiding expensive re-discovery) and notes that old-run entries are harmless since the algorithm naturally ignores them. This now aligns with the inline pseudocode comments, Invariant #10, and the v33 codex acknowledgement.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Rewrote `resetPipelineState` prose description in Section 6.1 to match pseudocode and Invariant #10

## Issue #2: `decodeFirstTurn` field inventory missing `graph_dot (12)`

**Status: Applied to specification**

Updated the `decodeFirstTurn` field inventory comment in Section 5.5 to include `graph_dot (12)`. Added a note explaining that it contains the full pipeline DOT source at run start time, available for future features (e.g., reconstructing the exact graph used for a historical run) but unused by the initial implementation.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added `graph_dot (12)` with explanatory note to field inventory comment in Section 5.5

## Issue #3: Section 5.4 lists only 9 turn types but the actual Kilroy registry bundle defines 23 types

**Status: Applied to specification**

Expanded the Section 5.4 type table from 9 entries to 23 entries, covering all types defined in the `kilroy-attractor-v1` registry bundle. Updated the paragraph below the table to explain which types carry `node_id` (and thus participate in status derivation) and which are skipped by the null guard.

Also expanded the Section 7.2 per-type rendering table to include detail panel rendering for the high-value missing types: `AssistantMessage` (model name + response text), `InterviewStarted`/`InterviewCompleted`/`InterviewTimeout` (human gate events), `StageRetrying` (retry attempt count), `RunCompleted`/`RunFailed` (pipeline-level lifecycle), and `StageFailed` (now shows `failure_reason` instead of a generic label). Low-value types (`Artifact`, `Blob`, `BackendTraceRef`, `CheckpointSaved`, `GitCheckpoint`, parallel events) fall through to the "Other/unknown" row.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Expanded Section 5.4 type table to 23 entries with all Kilroy registry bundle types
- `specification/cxdb-graph-ui-spec.md`: Expanded Section 7.2 per-type rendering table with 7 new entries for high-value turn types

## Issue #4: Kilroy `client_tag` mechanism clarification (binary protocol session tag)

**Status: Applied to specification**

Added a clarification to the `client_tag` stability requirement paragraph in Section 5.5 explaining that Kilroy satisfies the requirement via the binary protocol's session-level `client_tag` — CXDB's binary protocol embeds the session's `client_tag` at key 30 in the outer msgpack envelope, so the tag is durably stored even though Kilroy does not explicitly set key 30 in the application-level data map.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added clarification about binary protocol mechanism to `client_tag` stability requirement in Section 5.5

## Not Addressed (Out of Scope)

- None. All four issues were addressed.
