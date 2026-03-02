---
name: verify:run-holdout-scenarios
description: Run the CXDB Graph UI holdout scenarios using Playwright MCP browser automation
user-invocable: true
---

You are running the CXDB Graph UI holdout scenarios as acceptance tests. These scenarios verify externally observable behavior from a user's standpoint. The holdout scenarios document is in `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`.

## Arguments

Parse `$ARGUMENTS` for named `KEY=VALUE` parameters. Ignore non-parameter text (treat it as custom run instructions — see below).

| Parameter | Values | Default |
|-----------|--------|---------|
| _(none currently)_ | — | — |

Any free text in `$ARGUMENTS` that does not match a named parameter is treated as **custom run instructions**. Apply them when deciding which batches to run, which scenarios to focus on, or how to interpret results. Examples:

- `"Only run Batch 8 (CXDB Status Overlay) and Batch 9 (Detail Panel)"`
- `"Focus on scenarios involving human gate nodes"`
- `"Skip server CLI scenarios"`
- `"Run all batches but pay extra attention to color assertions"`

If no custom instructions are provided, run all batches in order.

## Allowed activities

IMPORTANT: the only allowed tasks for this skill are as follows:

1. Running the verification for the holdout scenarios
2. If there are failures, creating the critique via the spec:critique skill
3. Reporting status to the user

## Disallowed activities

**NEVER attempt to fix any problem/bugs that you discover by yourself. You may ONLY create critiques and report about them** 

## Scope

Scenarios split into two execution modes:

- **UI scenarios** — Playwright MCP browser automation, with a browser-injectable mock for CXDB API responses
- **Server CLI scenarios** — Shell commands that verify startup behavior

Scenarios not covered here (deferred due to mocking complexity):
- Gap recovery / MAX_GAP_PAGES pagination (require stateful per-poll turn-cursor tracking)
- Null-tag backlog / supplemental CQL discovery (multi-phase discovery mocking)

## Prerequisites

Verify before starting:
1. Rust is installed: `cargo --version`
2. Playwright MCP tools are available (you must have `playwright_navigate`, `playwright_screenshot`, `playwright_click`, `playwright_evaluate`)
3. Working directory is the repo root (`pwd` ends in `cxdb-graph-ui`)
4. All fixture files exist: `ls holdout-scenarios/fixtures/`

## Scorecard

Maintain a running pass/fail scorecard. Format each result as:
```
PASS  [Section] Scenario name
FAIL  [Section] Scenario name — reason
SKIP  [Section] Scenario name — reason
```

Print the scorecard at the end with a summary count.

---

## Server Management

Kill any previous test server before starting a new batch:
```bash
pkill -f "cxdb-graph-ui" 2>/dev/null || true; sleep 1
```

Start the server in the background. Always use absolute paths:
```bash
REPO=$(pwd)
cd server && cargo run -- --dot "$REPO/holdout-scenarios/fixtures/<files>" &
sleep 2
```

The default URL is `http://127.0.0.1:9030`.

---

## Mock CXDB Injection

For all CXDB-dependent scenarios, inject the mock interceptor **immediately after navigation**, before the polling loop fires:

```javascript
// Step 1: Read the mock file and inject it
// (The LLM must read .claude/skills/run-holdout-scenarios/mock-cxdb.js and pass its content)
playwright_evaluate({ script: <contents of mock-cxdb.js> })

// Step 2: Set the scenario
playwright_evaluate({ script: "window.__mockCxdb.setScenario('pipeline_running')" })

// Step 3: Wait for at least one poll cycle (UI polls every 3 seconds)
// Then take a screenshot and/or query DOM state
```

To reload the page with a different scenario (without restarting the server), re-navigate and re-inject.

**DOM inspection helpers** (use via `playwright_evaluate`):

```javascript
// Get SVG node fill color by node label text
document.querySelector('[id*="<nodeId>"] ellipse, [id*="<nodeId>"] polygon, [id*="<nodeId>"] path')?.getAttribute('fill')

// Get tab labels
Array.from(document.querySelectorAll('.tab, [role=tab], button')).map(el => el.textContent.trim())

// Check if detail panel is open
!!document.querySelector('.detail-panel, #detail-panel, [class*="detail"]')

// Get detail panel text
document.querySelector('.detail-panel, #detail-panel, [class*="detail"]')?.textContent

// Check for error message in graph area
document.querySelector('[class*="error"], [class*="graph"]')?.textContent
```

Adapt these selectors based on what you observe in screenshots if the exact selectors differ.

---

## Batch 1: DOT Rendering — Pure UI

**Server:** `--dot holdout-scenarios/fixtures/simple-pipeline.dot --dot holdout-scenarios/fixtures/multi-tab-b.dot`
**URL:** `http://127.0.0.1:9030`
**Mock:** Not needed (no CXDB required)

Navigate to the URL. Run these scenarios from the **DOT Rendering** section of the holdout-scenarios doc:

### Render a pipeline graph on initial load
Assert: SVG is present in the main content area with nodes and edges visible. Take a screenshot to confirm.

### Switch between pipeline tabs
Assert: Two tabs visible. Click second tab. Graph changes. Second tab is visually active.

### DOT file with long prompt text
Click the `fix_fmt` node (its prompt is >500 chars). Assert: node renders normally in SVG and detail panel shows the prompt text when clicked.

### Tab shows graph ID from DOT declaration
Assert: The first tab shows "simple_pipeline" (not "simple-pipeline.dot"). The second tab shows "beta_pipeline".

### Pipeline tab ordering matches --dot flag order
Assert: "simple_pipeline" tab appears before "beta_pipeline" (matches DOT flag order).

### Human gate choices available on first pipeline without tab switch
Click the `review_gate` node without switching tabs. Assert: detail panel shows "Human Gate", the question "Approve the implementation?", and choices "approve" and "reject".

---

## Batch 2: All Node Shapes

**Server:** Kill previous. Start with: `--dot holdout-scenarios/fixtures/all-shapes.dot`

### Nodes rendered with correct shapes
Take a screenshot. Assert each node shape renders correctly:
- `node_start_diamond` → diamond (Mdiamond)
- `node_start_circle` → circle
- `node_llm_task` → rectangle/box
- `node_conditional` → diamond
- `node_tool_gate` → parallelogram
- `node_human_gate` → hexagon
- `node_parallel` → component shape
- `node_fan_in` → tripleoctagon
- `node_stack_loop` → house
- `node_exit_square` → square (Msquare)
- `node_exit_doublecircle` → double circle

Use a screenshot for visual verification. If shapes are not clearly identifiable from the screenshot, use `playwright_evaluate` to inspect SVG element types (ellipse, polygon, path).

---

## Batch 3: HTML/XSS Injection

**Server:** Kill previous. Start with: `--dot holdout-scenarios/fixtures/html-injection.dot --dot holdout-scenarios/fixtures/html-tab-label.dot`

### DOT prompt containing HTML markup renders as literal text
Navigate to `http://127.0.0.1:9030`. Click the `xss_test` node. Assert: detail panel shows `<script>alert('xss')</script> and <b>bold</b>` as literal text (no script execution, no bold formatting). Use `playwright_evaluate` to check the detail panel's textContent contains the literal angle brackets.

### Pipeline tab label with HTML-like graph ID renders as literal text
Assert: The second tab shows the literal text `<b>Pipeline</b>` (not bold). Check via `textContent` rather than `innerHTML`.

---

## Batch 4: Syntax Error Handling

**Server:** Kill previous. Start with: `--dot holdout-scenarios/fixtures/syntax-error.dot --dot holdout-scenarios/fixtures/simple-pipeline.dot`

Navigate to `http://127.0.0.1:9030` (broken_pipeline tab is first).

### DOT file with syntax error
Assert: Graph area shows a Graphviz error message (not a blank page). Page is still responsive (tabs clickable).

### DOT parse error on /nodes does not block polling
Assert: Polling starts (no crash). The simple_pipeline tab (second) loads its SVG normally.

### DOT parse error on /edges does not block detail panel
Switch to the broken_pipeline tab. Click any visible SVG element. Assert: detail panel opens (or does not crash). No human gate choice buttons are shown for the broken pipeline.

---

## Batch 5: Quoted Identifiers

**Server:** Kill previous. Start with: `--dot holdout-scenarios/fixtures/quoted-ids.dot`

### Quoted graph ID with escapes normalizes for tab label
Assert: Tab label shows `my "quoted" pipeline` (with literal quotes, not escaped).

### Quoted node IDs render and interact correctly
Assert: A node labeled "review step" is visible in the SVG. Click it. Assert: detail panel shows Node ID `review step`.

Now inject mock and set scenario `pipeline_running` with graph_name `my "quoted" pipeline` (update mock data via `playwright_evaluate` if needed, or use `no_pipeline` to just test the UI interaction without status).

---

## Batch 6: DOT File Regeneration and Deletion

**Server:** Keep the quoted-ids server running, or restart with simple-pipeline.

### DOT file regenerated while UI is open
- Navigate to the simple_pipeline tab.
- Note the current graph structure.
- Using Bash, append a comment to the DOT file to simulate regeneration (or actually modify the file to add a new node).
- Click the pipeline's tab again.
- Assert: The graph reflects the updated DOT file.

### DOT file deleted after server startup (from Server section)
- Using Bash, temporarily rename/delete the fixture file.
- Click the pipeline's tab.
- Assert: Browser shows an error message in the graph area, page is not crashed.
- Restore the file.
- Click the tab again.
- Assert: Graph renders normally.

---

## Batch 7: /nodes and /edges Failure Handling

**Server:** Kill previous. Start with: `--dot holdout-scenarios/fixtures/simple-pipeline.dot --dot holdout-scenarios/fixtures/multi-tab-b.dot`

These scenarios involve the internal `/dots/{name}/nodes` and `/dots/{name}/edges` endpoints. Inject a mock that intercepts these (not CXDB) to simulate failures.

Read mock-cxdb.js — but for this batch, write a **custom one-shot fetch override** targeting `/dots/` endpoints:

```javascript
// Inject once at the start of this batch
const orig = window.fetch.bind(window);
let _nodesFailOnce = true;
window.fetch = async (url, opts) => {
  if (_nodesFailOnce && url.includes('/nodes')) {
    _nodesFailOnce = false;
    return new Response('Internal Server Error', { status: 500 });
  }
  return orig(url, opts);
};
```

### /nodes prefetch non-400 failure does not block initialization
Inject the fetch override before page load (reload after injection). Assert: polling still starts, SVG is visible, no crash.

### Tab-switch /nodes or /edges failure retains cached data
Navigate. Inject CXDB mock (scenario: `pipeline_running`). Wait for first poll. Switch to beta_pipeline tab. Inject nodes failure for that tab. Switch back to simple_pipeline. Assert: status overlay remains correct (not all-gray).

---

## Batch 8: CXDB Status Overlay

**Server:** Kill previous. Start with: `--dot holdout-scenarios/fixtures/simple-pipeline.dot --dot holdout-scenarios/fixtures/multi-tab-b.dot`

Navigate to `http://127.0.0.1:9030`. Read `mock-cxdb.js` and inject it immediately after navigation.

For each scenario below: call `setScenario(name)`, wait 4 seconds (one poll cycle), take a screenshot, and inspect node fill colors via `playwright_evaluate`.

**Color expectations:**
- Green fill → complete
- Blue fill (possibly with animation class) → running
- Red fill → error
- Orange fill → stalled
- Gray fill → pending (no status)

| Holdout Scenario | Mock Scenario | Key Assertions |
|---|---|---|
| Pipeline actively running — nodes colored by status | `pipeline_running` | implement=green, fix_fmt=blue, others=gray |
| Agent stuck in error loop (per-context scoping) | `error_loop` | fix_fmt=red |
| Error loop detection does not span contexts | `parallel_branches` (no per-context error) | fix_fmt=blue (not red) |
| Pipeline completed successfully | `pipeline_complete` | all traversed nodes=green |
| Pipeline stalled after agent crash | `pipeline_stalled` | fix_fmt=orange, top bar shows stall message |
| No active pipeline run | `no_pipeline` | all nodes=gray |
| Multiple contexts for same pipeline (parallel branches) | `parallel_branches` | fix_fmt=blue, check_fmt=blue |
| StageFailed with will_retry=true leaves node in running state | `stage_failed_retry` | fix_fmt=blue |
| StageFailed retry sequence resolves to complete when retry succeeds | `pipeline_complete` (include retry in turns if needed) | fix_fmt=green |
| StageFinished with status=fail colors node as error | `stage_finished_fail` | fix_fmt=red |
| RunFailed marks specified node as error | `run_failed` | fix_fmt=red |
| Second run of same pipeline while first run data exists | `second_run` | B's nodes shown, A's complete nodes NOT shown |
| Conditional node with custom routing outcome shows as complete | `conditional_custom` (use all-shapes server) | node_conditional=green |

For the **"Status coloring applies to all node shapes"** scenario:
- Restart server with `--dot holdout-scenarios/fixtures/all-shapes.dot`
- Inject mock, set scenario `all_shapes_complete`
- Assert: all 11 node shapes show green fill

---

## Batch 9: Detail Panel

**Server:** Kill previous. Start with: `--dot holdout-scenarios/fixtures/simple-pipeline.dot`
Navigate. Inject mock-cxdb.js.

| Holdout Scenario | Mock Scenario | Actions and Assertions |
|---|---|---|
| Click a node to see details | `pipeline_running` | Click fix_fmt → panel shows Node ID, Type "LLM Task", prompt, CXDB turns |
| Click a tool gate node | `pipeline_running` | Click check_fmt → Type "Tool Gate", tool_command shown |
| Click a human gate node | `no_pipeline` | Click review_gate → Type "Human Gate", question, choices "approve"/"reject" |
| Detail panel for early-completed node outside poll window | `pipeline_running` | Click implement → panel shows DOT attributes |
| Close detail panel | `no_pipeline` | Open panel, then click outside or close button → panel closes |
| Human gate interview turns render in CXDB Activity section | `human_gate_interview` | Click review_gate → InterviewStarted shows "Approve the implementation? [SingleSelect]", InterviewCompleted shows "YES (waited 45s)" |
| InterviewTimeout turn renders with error highlight | `interview_timeout` | Click review_gate → InterviewTimeout shows question text, Error column highlighted "timeout" |
| StageStarted turn renders handler_type | `stage_started_types` | Click fix_fmt → "Stage started: codergen"; click check_fmt → "Stage started: tool" |
| StageFinished with suggested_next_ids renders Next line | `stage_finished_next` | Click implement → "Stage finished: pass — pass\nNext: fix_fmt, check_fmt" |
| StageFinished with empty suggested_next_ids omits Next line | `pipeline_complete` | Click implement → "Stage finished: pass — pass" (no Next line) |
| Prompt turn Show more expansion is capped at 8,000 characters | `prompt_long` | Click fix_fmt → find Prompt turn row → click "Show more" → expanded content ≤ 8,000 chars with truncation disclosure |

---

## Batch 10: CXDB Connection Handling

**Server:** Kill previous. Start with: `--dot holdout-scenarios/fixtures/simple-pipeline.dot` and no `--cxdb` flag (or with an invalid CXDB address for the unreachable test).

Navigate. Inject mock-cxdb.js.

| Holdout Scenario | Mock Scenario | Key Assertions |
|---|---|---|
| No CXDB instances running | `cxdb_unreachable` | UI shows "CXDB unreachable" or similar. Graph still renders. All nodes gray. Polling continues (indicator shows error state). |
| One of multiple CXDB instances unreachable | `cxdb_partial` (requires 2 CXDB instances) | Start server with `--cxdb http://... --cxdb http://...`. CXDB-0 data shown; indicator shows partial connectivity. |
| CXDB becomes unreachable mid-session | Inject `pipeline_running`, wait, then switch to `cxdb_unreachable` | Last known node status is preserved (not cleared). |
| All CXDB instances return empty context lists | `no_pipeline` | All nodes remain gray. |
| CQL support flag — CQL not supported | `cql_not_supported` | /search returns 404, fallback to /contexts. Pipeline still discovered and status shown. |

Note: The "One of multiple CXDB instances unreachable" scenario requires restarting the server with two `--cxdb` flags. The mock's `cxdb_partial` scenario handles the 502 for instance index 1 automatically.

---

## Batch 11: Server CLI Scenarios

These test the Rust server's process startup behavior. Do NOT use Playwright. Use shell commands only.

Kill any running test server first: `pkill -f "cxdb-graph-ui" 2>/dev/null || true`

Build the binary once for reliable exit code testing:
```bash
cd server && cargo build --release && cp target/release/cxdb-graph-ui /tmp/cxdb-graph-ui-test
```

### Start with single DOT file
```bash
/tmp/cxdb-graph-ui-test --dot holdout-scenarios/fixtures/simple-pipeline.dot &
sleep 1
curl -sf http://127.0.0.1:9030/ > /dev/null && echo "PASS: server started" || echo "FAIL: server not reachable"
pkill -f cxdb-graph-ui-test
```
Assert: server starts on port 9030.

### Start with custom port and CXDB address
```bash
/tmp/cxdb-graph-ui-test --dot holdout-scenarios/fixtures/simple-pipeline.dot --port 9035 --cxdb http://10.0.0.5:9010 &
sleep 1
curl -sf http://127.0.0.1:9035/ > /dev/null && echo "PASS: custom port" || echo "FAIL: port 9035 not reachable"
pkill -f cxdb-graph-ui-test
```

### No DOT file provided
```bash
/tmp/cxdb-graph-ui-test 2>&1; echo "exit:$?"
```
Assert: exits with non-zero code, prints error/usage message.

### Duplicate DOT basenames rejected
```bash
/tmp/cxdb-graph-ui-test --dot holdout-scenarios/fixtures/simple-pipeline.dot --dot /tmp/simple-pipeline.dot 2>&1; echo "exit:$?"
```
First create `/tmp/simple-pipeline.dot`:
```bash
cp holdout-scenarios/fixtures/simple-pipeline.dot /tmp/simple-pipeline-dup.dot
# Rename to create same basename
cp /tmp/simple-pipeline-dup.dot /tmp/simple-pipeline.dot
/tmp/cxdb-graph-ui-test --dot holdout-scenarios/fixtures/simple-pipeline.dot --dot /tmp/simple-pipeline.dot 2>&1; echo "exit:$?"
```
Assert: exits non-zero, error message mentions "pipeline.dot" conflict.

### Duplicate graph IDs rejected
```bash
# Create a DOT file with the same graph ID as simple-pipeline.dot (simple_pipeline)
cat > /tmp/simple-pipeline-dup-id.dot << 'EOF'
digraph simple_pipeline {
  start [shape=Mdiamond];
  exit [shape=Msquare];
  start -> exit;
}
EOF
/tmp/cxdb-graph-ui-test --dot holdout-scenarios/fixtures/simple-pipeline.dot --dot /tmp/simple-pipeline-dup-id.dot 2>&1; echo "exit:$?"
```
Assert: exits non-zero, error mentions "simple_pipeline" duplicate graph ID.

### Anonymous graph rejected at server startup
```bash
cat > /tmp/anonymous.dot << 'EOF'
digraph {
  start [shape=Mdiamond];
  exit [shape=Msquare];
  start -> exit;
}
EOF
/tmp/cxdb-graph-ui-test --dot /tmp/anonymous.dot 2>&1; echo "exit:$?"
```
Assert: exits non-zero, error states named graphs are required.

---

## Reporting

After completing all batches, print the full scorecard and a summary:

```
=== HOLDOUT SCENARIO RESULTS ===

PASS  [DOT Rendering] Render a pipeline graph on initial load
PASS  [DOT Rendering] Switch between pipeline tabs
...
FAIL  [Status Overlay] Pipeline stalled — orange color not applied
...
SKIP  [CXDB Connection] Gap recovery bounded by MAX_GAP_PAGES — deferred (complex mocking)

=== SUMMARY ===
Passed: N
Failed: N
Skipped: N
Total: 72

=== END ===
```

For each FAIL result, include the screenshot filename (saved during the batch run) and the specific assertion that failed.

---

## Post-Run Critique (on failures)

If there are **no FAIL results**, stop here. The run is complete.

If any FAIL results exist, invoke the `spec:critique` skill to produce a critique with suggested spec or implementation fixes targeting the failures.

### Step 1: Determine the next critique version

List `specification-critiques/` and find the highest existing version N using the same filename-pattern logic as the critique skill (`vN-<author>.md`, `vN-acknowledgement.md`, etc.). The artifacts and critique will use version N+1.

The author is always `failed-holdout-scenarios`. This makes the artifacts path deterministic:

```
ARTIFACTS_DIR="specification-critiques/v{N+1}-failed-holdout-scenarios-artifacts"
```

### Step 2: Copy screenshots to the artifacts directory

Create the artifacts directory and copy all screenshots taken during this run into it:

```bash
mkdir -p "$ARTIFACTS_DIR"
cp /path/to/screenshots/*.png "$ARTIFACTS_DIR/"
```

Use the actual screenshot paths as reported by the Playwright MCP tool during the run.

### Step 3: Write the failures summary to the artifacts directory

Write a detailed description of every FAIL result to:

```
specification-critiques/v{N+1}-failed-holdout-scenarios-artifacts/holdout-scenario-failures.md
```

Include for each failure:
- The scenario name and section
- The specific assertion that failed
- The screenshot filename(s) that captured the failure
- Any DOM inspection output or error messages observed

### Step 4: Invoke spec:critique

Invoke the `spec:critique` skill with the fixed author, the artifacts directory, and a failure-focused prompt:

```
/spec:critique AUTHOR=failed-holdout-scenarios ARTIFACTS_DIR={ARTIFACTS_DIR} "Read holdout-scenario-failures.md and all other files in the ARTIFACTS_DIR. For each failure documented there, examine the referenced screenshots and suggest concrete changes to the specification or the implementation contract that would make the observed behavior correct."
```

The critique skill will write to `specification-critiques/v{N+1}-failed-holdout-scenarios.md`.
