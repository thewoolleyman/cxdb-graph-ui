## 7. Detail Panel

Clicking an SVG node opens a detail panel. The panel displays information from both the DOT file and CXDB.

### 7.1 DOT Attributes

The detail panel displays node attributes extracted from the DOT source. Attributes are parsed server-side and served via `GET /dots/{name}/nodes` (see see `specification/contracts/server-api.md`). This avoids complex DOT parsing in browser JavaScript.

| Field | Source | Description |
|-------|--------|-------------|
| Node ID | DOT node identifier | e.g., `implement`, `verify_fmt` |
| Type | DOT `shape` attribute | Human-readable label (e.g., "LLM Task", "Tool Gate") |
| Model Class | DOT `class` attribute | e.g., `hard` (Opus), default (Sonnet) |
| Prompt | DOT `prompt` attribute | Full prompt text, scrollable, whitespace-preserved (`white-space: pre-wrap`) |
| Tool Command | DOT `tool_command` attribute | Shell command for tool gate nodes, whitespace-preserved (`white-space: pre-wrap`) |
| Question | DOT `question` attribute | Human gate question text, whitespace-preserved (`white-space: pre-wrap`) |
| Choices | Outgoing edge labels via `GET /dots/{name}/edges` | Available choices for human gate nodes — labels of edges whose `source` matches this node's ID (see see `specification/contracts/server-api.md`) |
| Goal Gate | DOT `goal_gate` attribute | Boolean flag — if `"true"`, this conditional node acts as a goal gate (displayed as a badge on the detail panel header). Goal gates use the same `diamond` shape as regular conditionals. |

**HTML escaping.** All DOT attribute values rendered in the detail panel (Node ID, Prompt, Tool Command, Question, Choices edge labels, and Goal Gate badge labels) must be HTML-escaped before DOM insertion — either via `textContent` assignment or explicit entity escaping (`<` → `&lt;`, `>` → `&gt;`, `&` → `&amp;`, `"` → `&quot;`). DOT files are user-provided inputs; unescaped rendering via `innerHTML` or string interpolation into HTML would allow injection of arbitrary markup. This applies to all text fields from the `/dots/{name}/nodes` and `/dots/{name}/edges` responses.

### 7.2 CXDB Activity

The detail panel shows recent CXDB turns for the selected node. Turns are sourced from the per-pipeline turn cache (Section 6.1, step 5), filtered to those where `turn.data.node_id` matches the selected node's DOT ID.

**Context-grouped display.** When the selected node has matching turns across multiple contexts (e.g., parallel branches), turns are displayed grouped by context rather than interleaved. Each context's turns appear in a collapsible section labeled with the CXDB instance index and context ID (e.g., "CXDB-0 / Context 33"). Within each section, turns are displayed newest-first (the UI reverses the API's oldest-first order) by `turn_id` — this is safe because `turn_id` is monotonically increasing within a single context's parent chain (see Section 6.2). Sections are ordered using a two-level sort: first by CXDB instance index (lower index first), then by highest `turn_id` among the context's matching turns (descending — most recent first). This groups contexts by instance, where `turn_id` comparison is meaningful (monotonically increasing within a single instance), and uses a stable, deterministic ordering across instances. CXDB instances have independent turn ID counters with no temporal relationship, so cross-instance `turn_id` comparison is not attempted.

| Column | Source | Description |
|--------|--------|-------------|
| Type | `declared_type.type_id` | Turn type (ToolCall, ToolResult, Prompt, etc.) |
| Tool | `data.tool_name` | Tool invoked (e.g., `shell`, `write_file`) — blank for non-tool turns |
| Output | varies by type (see mapping below) | Truncated content (expandable). Rendered with `white-space: pre-wrap` to preserve newlines, indentation, and runs of whitespace. Truncation is applied after HTML-escaping. |
| Error | `data.is_error` | Highlighted if true — only applicable to ToolResult |

**Per-type rendering.** The Output column content varies by turn type:

| Turn Type | Output Column | Tool Column | Error Column |
|-----------|--------------|-------------|--------------|
| `Prompt` | `data.text` | blank | blank |
| `ToolCall` | `data.arguments_json` | `data.tool_name` | blank |
| `ToolResult` | `data.output` | `data.tool_name` | `data.is_error` (highlighted if true) |
| `AssistantMessage` | `data.text` | `data.model` | blank |
| `StageStarted` | "Stage started" + (if `data.handler_type` is non-empty: ": {`data.handler_type`}") | blank | blank |
| `StageFinished` | "Stage finished: {`data.status`}" + (if `data.preferred_label` is non-empty: " — {`data.preferred_label`}") + (if `data.failure_reason` is non-empty: "\n{`data.failure_reason`}") + (if `data.notes` is non-empty: "\n{`data.notes`}") + (if `data.suggested_next_ids` is non-empty: "\nNext: {comma-joined `data.suggested_next_ids`}") | blank | highlighted if `data.status` is `"fail"` |
| `StageFailed` | `data.failure_reason` + (if `data.will_retry == true`: " (will retry, attempt {`data.attempt`})") + (if `data.will_retry != true` and `data.attempt` is present and > 0: " (attempt {`data.attempt`})") | blank | highlighted (only if `data.will_retry != true`) |
| `StageRetrying` | "Retrying (attempt {`data.attempt`}" + (if `data.delay_ms` is present and > 0: ", delay {formatted_delay}") + ")" where `formatted_delay` uses the `formatMilliseconds` helper (see below) | blank | blank |
| `RunCompleted` | `data.final_status` | blank | blank |
| `RunFailed` | `data.reason` | blank | highlighted |
| `InterviewStarted` | `data.question_text` + (if `data.question_type` is non-empty: " [{`data.question_type`}]") | blank | blank |
| `InterviewCompleted` | `data.answer_value` + (if `data.duration_ms` is present and > 0: " (waited {formatted_duration})") | blank | blank |
| `InterviewTimeout` | `data.question_text` | blank | highlighted ("timeout") |
| Other/unknown | "[unsupported turn type]" (placeholder) | blank | blank |

**`formatMilliseconds` helper.** The `formatted_delay` (used by `StageRetrying`) and `formatted_duration` (used by `InterviewCompleted`) both use the same millisecond-to-human-readable conversion: if `ms >= 1000`, display as `{ms / 1000}s` — one decimal place if not a whole number, no decimal if it is (e.g., 1500 → "1.5s", 2000 → "2s", 60000 → "60s"). If `ms < 1000`, display as `{ms}ms` (e.g., 250 → "250ms", 1 → "1ms"). Values of 0 are excluded by the guard (`> 0`) before calling this helper.

**Tool gate turns.** Tool gate nodes (shape=parallelogram) produce `ToolCall` and `ToolResult` turns with `tool_name: "shell"`, the same turn types used by LLM task nodes. Kilroy's `ToolHandler` (`handlers.go` lines 536-549 and 621-652) runs the shell command and emits these turns with the command in `ToolCall.arguments_json` and stdout/stderr in `ToolResult.output`, where `is_error` reflects the exit code. No special rendering is needed — the standard per-type rendering handles tool gate turns identically to LLM task tool turns.

**Custom routing values in `StageFinished`.** For conditional nodes using custom routing outcomes (e.g., `"process"`, `"done"`, `"needs_dod"`), the `data.status` and `data.preferred_label` fields may contain the same value. The rendering displays both as-is — no deduplication is applied. For example, a conditional node with `status: "process"` and `preferred_label: "process"` displays as: "Stage finished: process — process".

**Pipeline-level turns without `node_id`.** The detail panel filters turns to those where `turn.data.node_id` matches the selected node's DOT ID. Pipeline-level turns that lack a `node_id` field — specifically `RunCompleted` (which carries only `run_id` and `final_status` — see see `specification/contracts/cxdb-upstream.md`) — will never match any node's filter and therefore never appear in the per-node detail panel. The `RunCompleted` row in the table above is included for completeness and documents the intended rendering *if* a `RunCompleted` turn were ever displayed, but it is unreachable in practice. `RunFailed`, by contrast, always includes a `node_id` field (Kilroy's `cxdbRunFailed` always passes one), though the value may be an empty string if the run fails before entering any node — in that case the `node_id` filter excludes it from all per-node detail panels. When `node_id` is a valid DOT node ID, the turn does appear in the detail panel for the failed node. Other pipeline-level turns without `node_id` (`CheckpointSaved`, `Artifact`, `Blob`, `BackendTraceRef`) fall through to the "Other/unknown" row but are similarly excluded by the `node_id` filter.

This mapping ensures all turn types that may appear in the turn cache render meaningfully. The high-value additions are: `AssistantMessage` (shows model name and LLM response text — a high-frequency turn type critical for the "mission control" use case), `InterviewStarted`/`InterviewCompleted`/`InterviewTimeout` (human gate interaction events — `InterviewStarted` includes `question_type` to distinguish gate modes, `InterviewCompleted` includes `duration_ms` to show how long the pipeline waited for human input), `StageRetrying` (shows retry attempt count and backoff delay), and `RunCompleted`/`RunFailed` (pipeline-level lifecycle events). `StageFailed` now renders `failure_reason` instead of a generic label. The remaining low-value types (`Artifact`, `Blob`, `BackendTraceRef`, `CheckpointSaved`, `GitCheckpoint`, `ParallelStarted`, `ParallelBranchStarted`, `ParallelBranchCompleted`, `ParallelCompleted`) fall through to the "Other/unknown" row — they carry no user-facing content beyond what is already reflected in the status overlay. The `StageStarted` lifecycle turn displays its `handler_type` field (e.g., "Stage started: codergen", "Stage started: tool", "Stage started: wait.human") to help operators identify what kind of execution is beginning — particularly useful for conditional nodes with `TypeOverride` that use a different handler than their shape would suggest. The `handler_type` value comes from Kilroy's `resolvedHandlerType` function (`cxdb_events.go` line 72, `handlers.go` lines 174-182). `StageFinished` renders its `status`, `preferred_label`, `failure_reason`, `notes`, and `suggested_next_ids` fields because these carry substantive operator-facing information: `status` distinguishes success from failure (a node with `status: "fail"` displays as red/error in the overlay), `preferred_label` shows which edge the pipeline chose at a conditional node, `failure_reason` explains why a node failed, `notes` provides a concise handler-generated summary of what happened during node execution (e.g., "applied workaround for flaky test", "retried 2 times before success") — the only narrative record beyond the raw tool call/result stream, and `suggested_next_ids` shows which downstream nodes the pipeline selected (useful for understanding branching decisions at conditional/routing nodes). Both `notes` and `suggested_next_ids` are always emitted by Kilroy's `cxdbStageFinished` (`cxdb_events.go` lines 87-88) but may be empty. `StageRetrying` renders `delay_ms` alongside `attempt` to show the backoff delay between retry attempts — this helps operators judge whether a persistent failure (escalating delays) warrants intervention.

**Kilroy-side truncation.** Kilroy truncates three high-frequency text fields at the source before appending to CXDB: `AssistantMessage.text`, `ToolCall.arguments_json`, and `ToolResult.output` are each capped at 8,000 characters by the Kilroy engine (`cli_stream_cxdb.go` lines 46, 66, 87). The UI's client-side truncation (below) operates within this limit for these fields. Expanding a truncated turn row via "Show more" shows at most 8,000 characters for these fields, not the full original content (e.g., a complete LLM response may exceed 8,000 characters but only the truncated version reaches CXDB). **`Prompt.text` is NOT truncated** — `cxdbPrompt` in `cxdb_events.go` passes the full assembled LLM prompt directly to CXDB without calling `truncate`. Prompt text commonly ranges from 5,000 to 50,000+ characters for complex LLM tasks. Other text fields (`StageFailed.failure_reason`, `RunFailed.reason`, `InterviewStarted.question_text`) are also not truncated at the Kilroy side but are typically short. The client-side Output column truncation (500 characters / 8 lines) handles visual presentation for all fields regardless of source-side truncation. An implementer should not assume all text values fit within 8,000 characters — `Prompt.text` in particular may be significantly larger.

**Prompt expansion behavior.** Because `Prompt.text` is not truncated at the source, clicking "Show more" on a `Prompt` turn expands to the full prompt text — which may be 50,000+ characters. Implementations must handle this gracefully. The required behavior is to apply the same 8,000-character secondary cap on expansion for `Prompt` turns as for `AssistantMessage`, `ToolCall`, and `ToolResult` turns. When a `Prompt` turn is capped at 8,000 characters on expansion, the UI must display a disclosure note (e.g., "(truncated to 8,000 characters — full prompt available in CXDB)") so the operator knows the content is not complete. This cap prevents unbounded DOM growth and maintains consistent UX across all expandable turn types. Implementations that expand `Prompt` turns without a secondary cap are not spec-compliant — the combination of an unbounded prompt (no source-side truncation) and a no-cap expansion would inject tens of thousands of characters into a single DOM element, creating visible layout and performance issues.

**Truncation and expansion.** The Output column truncates content to the first 500 characters or 8 lines, whichever limit is reached first. Truncation is applied after HTML-escaping and before rendering in the `white-space: pre-wrap` container. When content is truncated, a "Show more" toggle appears inline below the visible excerpt. Clicking "Show more" expands the row to display the full content (still whitespace-preserved) and changes the toggle to "Show less" to re-collapse. Each turn row has its own independent expand/collapse state. Line breaks in the visible truncated excerpt are preserved (truncation does not collapse whitespace). Fixed-label outputs (lifecycle turns, unknown types) are never truncated.

Within each context section, turns are displayed newest-first (reversed from the API's oldest-first order for better UX — most recent activity at the top). All `turn_id` comparisons used for ordering within the detail panel — both within-context sorting and cross-context section ordering — must be numeric (`parseInt(turn_id, 10)`), consistent with Section 6.2. Lexicographic comparison breaks for IDs of different digit lengths (e.g., `"999" > "1000"` lexicographically). The panel shows at most 20 turns per context section. If all of a node's turns have scrolled out of the 100-turn poll window (i.e., the node completed early and subsequent nodes have generated many turns), the detail panel shows the node's DOT attributes but displays "No recent CXDB activity" in place of the turn list. The node's status remains correct via the persistent status map (Section 6.2).

### 7.3 Shape-to-Type Label Mapping

| Shape | Display Label |
|-------|--------------|
| `Mdiamond` | Start |
| `circle` | Start |
| `Msquare` | Exit |
| `doublecircle` | Exit |
| `box` | LLM Task |
| `diamond` | Conditional |
| `parallelogram` | Tool Gate |
| `hexagon` | Human Gate |
| `component` | Parallel |
| `tripleoctagon` | Parallel Fan-in |
| `house` | Stack Manager Loop |
| *(any other)* | LLM Task (default) |

The table above reflects all ten shapes in Kilroy's `shapeToType` function (`kilroy/internal/attractor/engine/handlers.go`). `circle` is an alternative start shape (rendered as `<ellipse>` in SVG) and `doublecircle` is an alternative exit shape (rendered as two nested `<ellipse>` elements). `component`, `tripleoctagon`, and `house` are all rendered as `<polygon>` in SVG. The default row matches Kilroy's `default` case, which returns `"codergen"` (mapped to "LLM Task" in the UI) for any unrecognized shape — this ensures the UI handles DOT files with unexpected shapes gracefully.
