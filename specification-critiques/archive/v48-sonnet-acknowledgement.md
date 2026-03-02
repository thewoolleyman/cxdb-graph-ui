# CXDB Graph UI Spec — Critique v48 (sonnet) Acknowledgement

All four issues were validated against Kilroy and CXDB source and addressed. Issue #1 removed a phantom field (`attempt`) from `StageStarted`'s documented key data fields — confirmed absent from `cxdbStageStarted` in `cxdb_events.go`. Issue #2 added explicit guidance that `Prompt.text` expansion is capped at 8,000 characters with a disclosure note, matching the cap applied to the other three expandable turn types. Issue #3 added explicit pseudocode for the `cqlSupported` flag reset mechanism (keyed on `instanceReachable` transitions) and a new holdout scenario for the `cqlSupported=false` → unreachable → reconnect path. Issue #4 added two holdout scenarios locking in the `suggested_next_ids` rendering format for `StageFinished`, one with a populated array and one with an empty array.

## Issue #1: `StageStarted.attempt` documented as an emitted field but never emitted by Kilroy

**Status: Applied to specification**

The critique is correct. Verified against `/Users/cwoolley/workspace/kilroy/internal/attractor/engine/cxdb_events.go` lines 64-74: `cxdbStageStarted` emits exactly four fields — `run_id`, `node_id`, `timestamp_ms`, `handler_type`. No `attempt` field. The `attempt` field is emitted by `cxdbStageFailed` (line 185-197) and `cxdbStageRetrying` (lines 200-211), but not by `cxdbStageStarted`.

The Section 5.4 turn type inventory table's `StageStarted` row previously listed `node_id`, `handler_type (optional)`, `attempt (optional)`. The `attempt (optional)` entry was incorrect — it does not exist in the current Kilroy implementation and is not in the `kilroy-attractor-v1` registry bundle. Removing it prevents implementing agents from displaying a phantom "attempt 2" label on `StageStarted` turns (a field that would always be absent from real CXDB data).

Note: `run_id` and `timestamp_ms` are emitted by `cxdbStageStarted` (as they are for all event types) but are omitted from the "Key Data Fields" column consistently across the table — the column documents only the fields consumed by the UI or otherwise significant to rendering, not the full wire format. This is consistent with how `run_id` is omitted from `StageFailed`, `StageRetrying`, etc.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Removed `attempt (optional)` from the `StageStarted` row in the Section 5.4 turn type inventory table

## Issue #2: `AssistantMessage.text` truncation causes incorrect "Show more" UX promise

**Status: Applied to specification**

The critique is correct. The spec correctly documented that `Prompt.text` is not truncated at source (`cxdbPrompt` in `cxdb_events.go` lines 52-62 passes `text` directly without calling `truncate`), and that prompts can range from 5,000 to 50,000+ characters. However, it gave no guidance on what "Show more" should do when expanding a `Prompt` turn — an implementing agent would have to choose between: (a) exposing the full unbounded content, or (b) applying a secondary cap. Without a spec requirement, implementations would diverge and there would be no acceptance test to catch the unbounded-expansion case.

Added a new **"Prompt expansion behavior"** paragraph after the existing Kilroy-side truncation paragraph in Section 7.2. The required behavior is: apply the same 8,000-character secondary cap on expansion for `Prompt` turns as for `AssistantMessage`, `ToolCall`, and `ToolResult` turns. When capped, display a disclosure note (e.g., "(truncated to 8,000 characters — full prompt available in CXDB)"). This prevents unbounded DOM injection and maintains consistent UX.

A new holdout scenario "Prompt turn Show more expansion is capped at 8,000 characters with disclosure" was added to the Detail Panel section, providing an acceptance test for this requirement.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "Prompt expansion behavior" paragraph after the Kilroy-side truncation paragraph in Section 7.2 specifying the 8,000-character secondary cap with disclosure note
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added "Prompt turn Show more expansion is capped at 8,000 characters with disclosure"

## Issue #3: `cqlSupported` flag reset semantics are underspecified for the reconnection case

**Status: Applied to specification**

The critique is correct on all three points:

1. The spec prose mentioned the reset but did not define "unreachable" at the implementation level.
2. There was no pseudocode showing when `cqlSupported[i]` is reset to `undefined`.
3. An implementer following the `discoverPipelines` pseudocode literally would never reset the flag — the reset only appeared in prose.

Added explicit pseudocode and prose to Section 6.1 step 1: the UI tracks a per-instance `instanceReachable[i]` flag. On each poll cycle, before issuing discovery requests, the poll detects reachability from the HTTP response code. A non-502 response after a 502 indicates reconnection. On reconnection, `cqlSupported[i]` is reset to `undefined`, allowing the next poll cycle to retry CQL. The reset occurs at reachability detection time (not inside the CQL path), so it applies regardless of whether the reconnected response comes from a CQL search, context list, or any proxied request. This is the cleanest semantics: a single 502 counts as "unreachable" (consistent with Section 3.2's existing 502 proxy behavior), and any non-502 after a 502 counts as "reconnected."

Added a new holdout scenario "cqlSupported flag resets on reconnection even when instance had no CQL" that covers the previously-untested path: `cqlSupported=false` (not just `true` → upgrade). This scenario verifies that after an unreachable-then-reconnect cycle on a non-CQL instance, the flag is reset, CQL is retried, gets 404 again, and `cqlSupported` is correctly set back to `false` — discovery continues normally. The existing "CQL support flag resets on CXDB instance reconnection" scenario covers the `false` → upgrade → `true` direction; the new scenario covers the `false` → unreachable → reconnect (still `false`) direction.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added `cqlSupported` flag reset pseudocode and prose to Section 6.1 step 1, introducing `instanceReachable[i]` flag and reset-on-reconnect semantics
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added "cqlSupported flag resets on reconnection even when instance had no CQL"

## Issue #4: No holdout scenario for the `StageFinished` detail panel rendering of `suggested_next_ids`

**Status: Applied to holdout scenarios**

The critique is correct. Verified against `/Users/cwoolley/workspace/kilroy/internal/attractor/engine/cxdb_events.go` lines 76-90: `cxdbStageFinished` always emits `suggested_next_ids` (from `out.SuggestedNextIDs`). The Section 7.2 per-type rendering table correctly specifies the `\nNext: {comma-joined suggested_next_ids}` suffix. However, no holdout scenario tested this specific format, meaning an implementation that omitted the `\nNext:` line would pass all acceptance tests.

Two holdout scenarios were added to the Detail Panel section:
1. **"StageFinished with suggested_next_ids renders Next line in detail panel"** — tests a conditional node with `suggested_next_ids: ["check_goal", "finalize"]`, asserting the output includes `\nNext: check_goal, finalize` with a literal newline before "Next:".
2. **"StageFinished with empty suggested_next_ids omits Next line"** — tests the empty/absent case, asserting no `\nNext:` line is appended, preventing regressions in the guard condition.

Together these lock in both the positive and negative cases for `suggested_next_ids` rendering.

Changes:
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added "StageFinished with suggested_next_ids renders Next line in detail panel"
- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`: Added "StageFinished with empty suggested_next_ids omits Next line"

## Not Addressed (Out of Scope)

- None. All four issues were valid and fully addressed.
