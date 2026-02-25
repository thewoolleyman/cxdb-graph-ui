# Proposed Holdout Scenarios — To Review

Scenarios proposed during spec critique rounds that need review before incorporation into the holdout scenarios document.

The following proposed scenarios are awaiting review for incorporation into `cxdb-graph-ui-holdout-scenarios.md` or explicit rejection.

---

## Proposed: RunStarted with null or empty graph_name

**Source:** v26-opus, Issue #3

**Scenario:** A CXDB context has a valid `RunStarted` first turn with `run_id` present but `graph_name` is null (field absent from msgpack payload, since it is marked `optional: true` in the registry bundle) or empty string.

**Expected behavior:** The context is excluded from pipeline discovery (cached as a null mapping, same as non-Kilroy contexts). It does not match any pipeline tab. No error is surfaced to the user. The context is not retried on subsequent polls.

**Why current holdout scenarios are insufficient:** The existing "Context does not match any loaded pipeline" scenario assumes the context has a valid `graph_name` that simply does not match any loaded DOT file. The null/empty `graph_name` case is a distinct code path (the guard fires before the pipeline matching loop) and exercises the optional-field handling in the msgpack decoder.

---

## Proposed: CXDB downgrades and CQL becomes unavailable mid-session

**Source:** v27-opus, Issue #4

**Scenario:**
```
Given the UI has been polling CXDB-0 successfully using CQL search
  And cqlSupported[0] is true
When CXDB-0 is restarted with a version that lacks CQL support
  And the restart is fast enough that no poll cycle sees a 502
Then the next CQL search attempt returns 404
  And the UI sets cqlSupported[0] to false
  And falls back to the context list endpoint for that poll cycle
  And subsequent polls use the context list fallback without retrying CQL
  And pipeline discovery continues uninterrupted
```

**Expected behavior:** The `cqlSupported` flag transitions from `true` to `false` on the 404 response. The fallback context list path is used for subsequent polls. Discovery is not interrupted.

**Why current holdout scenarios are insufficient:** The existing holdout scenarios cover CXDB unreachable/reconnect (connection handling section) and the basic CQL discovery flow (pipeline discovery section), but the CQL-to-fallback transition during continuous operation — where the instance remains reachable but loses CQL support — is not covered. The code path is already specified in the `discoverPipelines` pseudocode but adding the scenario makes the fallback transition explicitly testable.

---

## Proposed: Forked context discovered via parent's RunStarted turn

**Source:** v29-opus, Issue #4

**Scenario:**
```
Given a pipeline run creates a parent context with RunStarted(graph_name="alpha_pipeline")
  And the parent context forks a child context for a parallel branch
  And the child context has head_depth=500
  And the child's parent chain extends into the parent context
When the UI runs pipeline discovery for the child context
Then fetchFirstTurn paginates through the child's turns into the parent context
  And discovers the parent's RunStarted turn at depth=0
  And the child context is correctly mapped to the alpha_pipeline tab
```

**Expected behavior:** The `fetchFirstTurn` pagination follows `parent_turn_id` links across the context boundary (from child to parent), eventually finding the parent's `RunStarted` turn at depth 0. The child context is mapped to the same pipeline as the parent.

**Why current holdout scenarios are insufficient:** The existing "Context matched to pipeline via RunStarted turn" scenario assumes the RunStarted is in the same context. The "Multiple contexts for parallel branches" scenario tests merging, not discovery. A forked context's child does not contain a RunStarted turn at all — it inherits the parent's RunStarted through the parent chain. If an implementer's `fetchFirstTurn` incorrectly stops at the context boundary (e.g., by checking `context_id` matches), pipeline discovery silently fails for all parallel branches.

---

## Proposed: DOT prompt containing HTML markup renders as literal text

**Source:** v29-codex, Issue #1

**Scenario:**
```
Given a DOT node has prompt attribute containing "<script>alert('xss')</script> and <b>bold</b>"
When the user clicks the node to open the detail panel
Then the detail panel shows the literal text "<script>alert('xss')</script> and <b>bold</b>"
  And no script executes
  And no HTML formatting is applied (no bold text)
  And the angle brackets are visible as text characters
```

**Expected behavior:** All DOT attribute values are HTML-escaped or inserted via `textContent` before DOM insertion. No HTML injection is possible from DOT file content.

**Why current holdout scenarios are insufficient:** The existing "DOT file with long prompt text" scenario tests length and escape handling but does not verify that HTML-like content in DOT attributes is safely rendered. Since DOT files are user-provided inputs, HTML injection is a real risk if an implementer uses `innerHTML` for DOT attribute rendering.

---

## Proposed: Pipeline tab label with HTML-like graph ID renders as literal text

**Source:** v30-codex, Issue #1

**Scenario:**
```
Given a DOT file contains "digraph \"<b>Pipeline</b>\" {"
When the UI renders the tab bar
Then the tab label shows the literal text "<b>Pipeline</b>"
  And no HTML formatting is applied (no bold text)
  And the angle brackets are visible as text characters
```

**Expected behavior:** Tab labels are rendered via `textContent` or explicit HTML escaping. No HTML injection is possible from DOT graph IDs.

**Why current holdout scenarios are insufficient:** The existing "Tab shows graph ID from DOT declaration" scenario tests correct extraction but does not verify safe rendering of HTML-like content. The "DOT prompt containing HTML markup" proposed scenario (v29-codex) covers the detail panel but not the tab bar.

---

## Proposed: Active run selection stable when older run spawns late branch context

**Source:** v32-codex, Issue #1 / v32-opus, Issue #2

**Scenario:**
```
Given CXDB contains contexts from a completed run A of alpha_pipeline (run_id A)
  And a new run B of alpha_pipeline has started (run_id B)
  And run B has only completed the first two nodes
  And run A spawns a late parallel branch context after run B started
When the UI polls CXDB
Then the active run remains run B (not flipped to run A)
  And the status overlay shows run B's progress
  And run A's late branch context is ignored
```

**Expected behavior:** The `determineActiveRuns` algorithm uses `context_id` (monotonically increasing at creation time) rather than `created_at_unix_ms` (which is updated on every `append_turn`). Run B's root context has a higher `context_id` than run A's contexts, so run B remains the active run regardless of late activity in run A.

**Why current holdout scenarios are insufficient:** The existing "Second run of same pipeline while first run data exists" scenario verifies that the newer run is selected, but does not cover the edge case where the older run's `created_at_unix_ms` surpasses the newer run's due to late activity. Without this scenario, an implementer using `max(created_at_unix_ms)` would pass the existing test but fail when older runs receive late turns.

---

## Proposed: /nodes prefetch non-400 failure does not block initialization

**Source:** v33-codex, Issue #2

**Scenario:**
```
Given the UI initializes with multiple DOT files
  And one /dots/{name}/nodes request fails with 500 (internal server error)
When initialization continues
Then polling still starts for all pipelines
  And the active tab renders its SVG
  And the pipeline with the failed /nodes prefetch uses an empty dotNodeIds set
  And status overlay for the affected pipeline is unavailable until the next tab switch
```

**Expected behavior:** Any non-200 response (400, 404, 500) or network error during the Step 4 `/nodes` prefetch results in a warning log and an empty `dotNodeIds` set for that pipeline. Steps 5 and 6 are not blocked.

**Why current holdout scenarios are insufficient:** The existing "DOT parse error on /nodes does not block polling" scenario covers only the 400 case. Non-400 failures (server crash, 404 from a removed DOT file, network error) exercise a different code path — an implementer might handle 400 gracefully but let 500 or network errors propagate as unhandled promise rejections, blocking initialization.

---

## ~~Proposed: Forked context with depth-0 base turn discovers RunStarted via pagination~~ REMOVED

**Source:** v31-opus, Issue #4 (removed by v32-opus, Issue #1)

**Removal reason:** The precondition is impossible. CXDB's `append_turn` updates `head_depth` on every append (`turn_store/mod.rs` lines 458-462). A context that has accumulated 50+ turns has `head_depth >= 50`, not `head_depth == 0`. The scenario describes a state that cannot exist: a context cannot simultaneously have 50+ turns and `head_depth == 0`. The `head_depth == 0` fast-path guard in `fetchFirstTurn` is defensive but not exercisable for contexts with appended turns — see the defensive note added to the spec's `fetchFirstTurn` pseudocode.

---

## Proposed: Tab-switch /nodes or /edges failure retains cached data

**Source:** v34-codex, Issue #2

**Scenario:**
```
Given the UI is showing the first pipeline with a valid status overlay
  And the second pipeline has been polled and has a cached status map
  And a transient network error causes /dots/{name}/nodes to fail
When the user clicks the second pipeline's tab
Then the SVG renders from the DOT file (if the DOT fetch succeeded)
  And the previous dotNodeIds for the second pipeline are retained
  And the cached status map is reapplied using the retained dotNodeIds
  And nodes are NOT shown as all-gray due to the /nodes fetch failure
  And a warning is logged to the console
```

**Expected behavior:** A failed `/nodes` or `/edges` fetch during tab switch retains the previously cached data for that pipeline. The cached status map is reapplied using the retained `dotNodeIds`, preventing a "gray flash" that would occur if `dotNodeIds` were cleared.

**Why current holdout scenarios are insufficient:** The existing "Switch between pipeline tabs" scenario assumes `/nodes` and `/edges` fetches succeed. The existing "DOT parse error on /nodes does not block polling" scenario covers initialization, not tab switches. A transient failure during tab switch could clear `dotNodeIds` and discard the cached status map, causing all nodes to appear pending — contradicting the "no gray flash" holdout expectation.

---

## Proposed: Node retries after StageFailed with will_retry — intermediate and final status

**Source:** v35-opus, Issue #1 and Issue #4

**Scenario:**
```
Given a pipeline run is active with node check_fmt in running state
  And CXDB contains a StageFailed turn for check_fmt with will_retry: true
  And CXDB contains a StageRetrying turn after the StageFailed
  And the retry succeeds with a StageFinished turn
When the UI polls CXDB
Then check_fmt is colored green (complete)
  And check_fmt is NOT permanently stuck in error state
```

**Expected behavior:** A `StageFailed` turn with `will_retry: true` sets the node to "running" (blue, pulsing), not "error" (red). The `will_retry: true` variant does NOT set `hasLifecycleResolution`, so subsequent non-lifecycle turns (e.g., `StageRetrying`, tool calls during the retry attempt) continue to update the node's status. When the retry succeeds (`StageFinished`), the node transitions to "complete" (green). The intermediate "running" status during the retry window prevents operators from mistakenly intervening (e.g., killing the pipeline) when the node is actively retrying and may succeed.

**Why current holdout scenarios are insufficient:** The existing "Agent stuck in error loop" scenario tests 3 consecutive `ToolResult` errors. The "Pipeline completed" scenario tests all nodes reaching `StageFinished`. Neither covers the `StageFailed` → `StageRetrying` → `StageFinished` retry flow, which is one of the most complex status derivation paths. The `will_retry` field check is the key distinction between retriable and terminal failures, and the retry flow is common in real Kilroy pipelines (tool gate nodes frequently fail on first attempt).

---

## Proposed: Human gate choices available on first pipeline without tab switch

**Source:** v35-codex, Issue #1

**Scenario:**
```
Given the server was started with --dot /path/to/pipeline.dot
  And the DOT file contains a human gate node (shape=hexagon) with outgoing edges labeled "approve" and "reject"
When the user opens the dashboard URL in a browser
  And clicks the human gate node without switching tabs
Then the detail panel shows:
  - Type: "Human Gate"
  - Question text from DOT question attribute
  - Available choices: "approve", "reject" (from outgoing edge labels)
```

**Expected behavior:** The initialization sequence prefetches `/edges` for all pipelines (including the first one). Human gate choices are available immediately without requiring a tab switch.

**Why current holdout scenarios are insufficient:** The existing "Click a human gate node" scenario expects choices from outgoing edge labels but does not specify that this works on the initially loaded pipeline without a tab switch. An implementer who only fetches `/edges` during tab switches would pass the existing scenario (by switching tabs first) but fail when the user clicks a human gate node on the first pipeline load.

---

## Proposed: CQL search returns zero Kilroy contexts, fallback discovers them

**Source:** v36-opus, Issue #4

**Scenario:**
```
Given CXDB has Kilroy contexts with active sessions (is_live: true)
  And the Kilroy contexts lack key 30 (context_metadata) in their first turn payloads
  And CQL search for tag ^= "kilroy/" returns an empty contexts array (200 OK)
When the UI polls for pipeline discovery
Then the CQL search succeeds but finds zero matching contexts
  And the UI does NOT fall back to the context list (because CQL returned 200, not 404)
  And no Kilroy contexts are discovered via the CQL path
```

**Expected behavior:** The CQL search returns a valid response with zero results because CXDB's secondary indexes have no `client_tag` metadata for Kilroy contexts. The `cqlSupported` flag stays `true`. The context list fallback is not triggered because the CQL endpoint is functional. This is the expected behavior until Kilroy implements key 30 in turn payloads.

**Why current holdout scenarios are insufficient:** The existing "Context matched to pipeline via RunStarted turn" scenario assumes contexts are already discovered. The "CQL support flag resets on CXDB instance reconnection" scenario tests the 404-to-fallback path. No existing scenario covers the case where CQL succeeds but returns empty results due to missing metadata — which is the default behavior for all current Kilroy deployments.

---

## Proposed: Completed pipeline remains discoverable after fresh page load (once key 30 is implemented)

**Source:** v36-opus, Issue #4

**Scenario:**
```
Given a Kilroy pipeline completed and its agent session has disconnected
  And Kilroy embedded client_tag at key 30 in the first turn's payload
  And the UI's knownMappings cache has been cleared (fresh page load)
When the UI polls for pipeline discovery
Then CQL search discovers the completed pipeline's contexts via stored metadata
  And the pipeline graph shows the final status overlay (all traversed nodes green)
```

**Expected behavior:** With key 30 present, `extract_context_metadata` finds `client_tag` in the stored payload, and CQL search indexes it. The pipeline is discoverable even after session disconnect. Without key 30 (current state), `client_tag` would be `null` after disconnect, and neither CQL search nor the context list fallback would find the contexts.

**Why current holdout scenarios are insufficient:** The existing "Pipeline completed successfully" scenario assumes the UI was open during the run. No scenario covers a fresh page load after a pipeline has finished and all sessions have disconnected. This is a real operational scenario: an operator opens the UI after being notified that a pipeline run completed, expecting to see the final status.

---

## Proposed: CQL returns empty results, supplemental context list discovers active Kilroy contexts

**Source:** v37-opus, Issue #2

**Scenario:**
```
Given CXDB has Kilroy contexts with active sessions (is_live: true)
  And the Kilroy contexts lack key 30 (context_metadata) in their first turn payloads
  And CQL search for tag ^= "kilroy/" returns an empty contexts array (200 OK)
When the UI polls for pipeline discovery
Then the CQL search succeeds but finds zero matching contexts
  And the supplemental context list fetch is issued (GET /v1/contexts?limit=10000)
  And the supplemental fetch finds contexts with session-tag-resolved client_tag
  And those contexts are processed through Phase 2 (fetchFirstTurn)
  And pipeline discovery succeeds for active Kilroy contexts
```

**Expected behavior:** When CQL returns zero results, the supplemental `fetchContexts` discovers Kilroy contexts via session-tag-resolved `client_tag`. This is the primary discovery path for current Kilroy deployments (which lack key 30). The supplemental fetch only runs when CQL is empty, not on every poll cycle.

**Why current holdout scenarios are insufficient:** The existing proposed scenario "CQL search returns zero Kilroy contexts, fallback discovers them" (v36-opus) tests the OLD behavior where the UI does NOT fall back and no contexts are discovered. With the new supplemental fetch (added in v37), the behavior has changed — contexts ARE discovered. The existing proposed scenario should be superseded by this one.

---

## Proposed: DOT file deleted after server startup returns 500

**Source:** v37-opus, Issue #3

**Scenario:**
```
Given the server was started with --dot /path/to/pipeline.dot
  And the DOT file is deleted from disk after server startup
When a browser requests /dots/pipeline.dot
Then the server returns 500 with a plain-text error body
  And the browser displays an error message in the graph area
  And the page does not crash or become unresponsive
When the DOT file is restored to disk
  And the user clicks the pipeline's tab again
Then the DOT file is fetched successfully
  And the graph renders normally
```

**Expected behavior:** The server returns 500 (not 404) because the filename is registered but the file cannot be read. The browser displays the error in the graph area. Recovery is automatic on the next fetch after the file is restored.

**Why current holdout scenarios are insufficient:** The existing "Unregistered DOT file requested" scenario tests 404 for filenames not in the `--dot` map. The existing "DOT file with syntax error" scenario tests Graphviz WASM parse errors. Neither covers the case where a registered file becomes unreadable after startup — which is a distinct server-side error path (disk I/O failure vs. unregistered filename vs. DOT syntax error).

---

## Proposed: Node finishes with failure status (StageFinished status: "fail")

**Source:** v38-opus, Issue #4

**Scenario:**
```
Given a pipeline run is active
  And a node emits StageFinished with status: "fail" and failure_reason: "Test suite failed with 3 errors"
  And the run subsequently emits RunFailed
When the UI polls CXDB
Then the failed node is colored red (error), not green (complete)
  And the detail panel shows "Stage finished: fail" with the failure_reason
  And the node has hasLifecycleResolution = true (preventing stale detection from overriding)
```

**Expected behavior:** The `updateContextStatusMap` algorithm checks `StageFinished.data.status`. When `status == "fail"`, the node is set to "error" (red) instead of "complete" (green). The `hasLifecycleResolution` flag is still set to `true` because `StageFinished` is an authoritative lifecycle turn regardless of the status value. The detail panel renders the `status`, `preferred_label`, and `failure_reason` fields from the `StageFinished` turn.

**Why current holdout scenarios are insufficient:** The existing "Pipeline completed — last node marked complete via StageFinished" scenario assumes all nodes finished successfully (non-"fail" status). The "Agent stuck in error loop" scenario tests the ToolResult error heuristic, not lifecycle-level failure. No existing scenario covers the `StageFinished { status: "fail" }` path, which is a common occurrence when a node fails terminally (no retries configured or max retries exceeded) and the run subsequently fails via `RunFailed`. The boundary between "complete" and "error" at the lifecycle level is currently untested.

---

## Proposed: CQL-empty supplemental context list populates cachedContextLists for liveness checks

**Source:** v38-codex, Issue #1

**Scenario:**
```
Given CXDB has active Kilroy contexts with is_live: true
  And the Kilroy contexts lack key 30 (context_metadata) in their first turn payloads
  And CQL search for tag ^= "kilroy/" returns an empty contexts array (200 OK)
  And the supplemental context list fetch discovers contexts via session-tag resolution
When the UI checks pipeline liveness (checkPipelineLiveness)
Then the supplemental context list is stored in cachedContextLists
  And lookupContext can find the active-run contexts
  And checkPipelineLiveness returns true (pipeline is live)
  And running nodes are NOT misclassified as stale
```

**Expected behavior:** When CQL returns zero results and the supplemental `fetchContexts` discovers Kilroy contexts, the supplemental list (not the empty CQL result) is stored in `cachedContextLists[i]`. This ensures `lookupContext` and `checkPipelineLiveness` can access the `is_live` field from the supplemental contexts, preventing false stale detection.

**Why current holdout scenarios are insufficient:** The existing "CQL returns empty results, supplemental context list discovers active Kilroy contexts" proposed scenario (v37-opus) tests the discovery path but does not verify that the discovered contexts are available for liveness checks. An implementer could correctly discover contexts via the supplemental path but still store the empty CQL result in `cachedContextLists`, causing `checkPipelineLiveness` to return false and `applyStaleDetection` to misclassify running nodes as stale.

---

## Proposed: Pipeline run fails on a specific node (RunFailed with node_id)

**Source:** v39-opus, Issue #2 and Issue #4

**Scenario:**
```
Given a pipeline run is active with node implement in running state
  And Kilroy emits a RunFailed turn with node_id = "implement" and reason = "agent crashed"
When the UI polls CXDB
Then the implement node is colored red (error), not blue (running)
  And the node has hasLifecycleResolution = true
  And the detail panel shows the RunFailed reason
```

**Expected behavior:** The `updateContextStatusMap` algorithm has an explicit `RunFailed` case that sets `newStatus = "error"` and `hasLifecycleResolution = true`. `RunFailed` is treated as an authoritative lifecycle turn (alongside `StageFinished` and `StageFailed`) that unconditionally overrides the node's current status. Kilroy's `cxdbRunFailed` always includes a `node_id` key, but the value may be an empty string if the run fails before entering any node — when non-empty, the turn enters the status derivation for the named node.

**Why current holdout scenarios are insufficient:** The existing scenarios test `StageFinished` (per-node completion), `StageFailed` (per-node failure with optional retry), and the error loop heuristic (3 consecutive `ToolResult` errors). `RunFailed` is a distinct pipeline-level catastrophic failure event — it marks the node where the pipeline failed but represents a pipeline-wide halt, not a per-node lifecycle transition. Without explicit coverage, an implementer could omit the `RunFailed` case from the status derivation (as the pseudocode originally did before v39), causing `RunFailed` turns to fall through to the "infer running" default and leave the failed node as blue (running) instead of red (error).

---

## Proposed: Missing shapes in holdout scenarios (Parallel, Parallel Fan-in, Stack Manager Loop, circle, doublecircle)

**Source:** v39-opus, Issue #1

**Scenario (Nodes rendered with correct shapes — extended):**
```
Given the UI has rendered a pipeline graph containing all ten Kilroy node shapes
Then start nodes (shape=Mdiamond) display as diamonds
  And start nodes (shape=circle) display as circles
  And exit nodes (shape=Msquare) display as squares
  And exit nodes (shape=doublecircle) display as double circles
  And LLM task nodes (shape=box) display as rectangles
  And conditional nodes (shape=diamond) display as diamonds
  And tool gate nodes (shape=parallelogram) display as parallelograms
  And human gate nodes (shape=hexagon) display as hexagons
  And parallel nodes (shape=component) display as components
  And parallel fan-in nodes (shape=tripleoctagon) display as tripleoctagons
  And stack manager loop nodes (shape=house) display as houses
```

**Scenario (Status coloring applies to all node shapes — extended):**
```
Given a pipeline graph contains all ten node shapes (including circle, doublecircle, component, tripleoctagon, house)
  And CXDB has status data marking each node as complete
When the UI applies the status overlay
Then all ten nodes display with green fill (complete status)
  And the CSS fill rules match regardless of whether the shape renders as polygon, ellipse, or path
  And doublecircle nodes (which render as two nested <ellipse> elements) have both ellipses colored
```

**Expected behavior:** The CSS selectors `.node-complete polygon, .node-complete ellipse, .node-complete path` cover all SVG elements generated by Graphviz for the ten shapes. The `doublecircle` shape produces two nested `<ellipse>` elements; both are selected and colored by the CSS rules.

**Why current holdout scenarios are insufficient:** The existing "Nodes rendered with correct shapes" scenario lists only six shapes (`Mdiamond`, `Msquare`, `box`, `diamond`, `parallelogram`, `hexagon`). The "Status coloring applies to all node shapes" scenario also lists only six. Five shapes used in Kilroy pipelines (`circle`, `doublecircle`, `component`, `tripleoctagon`, `house`) are missing. An implementer who tests only the six listed shapes would not discover issues with the missing five (particularly `doublecircle`'s dual-ellipse rendering).

---

## Proposed: DOT file with comments parses correctly

**Source:** v40-opus, Issue #1 and Issue #4

**Scenario:**
```
Given a DOT file contains line comments (// ...) and block comments (/* ... */)
  And a node attribute value contains a URL with // (e.g., prompt="check http://example.com")
When the browser fetches /dots/{name}/nodes
Then the comments are stripped and do not appear as node attributes or cause parse errors
  And the URL inside the quoted attribute value is preserved (not treated as a comment)
  And edges defined after comment lines are parsed correctly
```

**Expected behavior:** The server's DOT parser strips `//` line comments and `/* */` block comments before parsing nodes and edges. Comments inside double-quoted strings are NOT stripped — the parser tracks quoted-string state and only recognizes comment delimiters outside of strings. This matches Kilroy's `stripComments` function in `kilroy/internal/attractor/dot/comments.go`.

**Why current holdout scenarios are insufficient:** No existing scenario tests DOT comment handling. Kilroy-generated DOT files from the YAML-to-DOT compiler may not contain comments, but hand-edited or annotated DOT files commonly do. An implementer who builds a parser that works for comment-free DOT files could fail on files with comments — particularly the edge case where `//` appears inside a quoted attribute value (e.g., a URL).

---

## Proposed: Conditional node with custom routing outcome shows as complete

**Source:** v41-opus, Issue #1 and Issue #4

**Scenario:**
```
Given a pipeline run has a conditional node using custom routing
  And CXDB contains a StageFinished turn for that node with data.status = "process" (a custom routing value)
  And data.preferred_label = "process"
When the UI polls CXDB
Then the node is colored green (complete), not red (error)
  And the detail panel shows "Stage finished: process — process"
  And no deduplication is applied between status and preferred_label
```

**Expected behavior:** Kilroy's `ParseStageStatus` function (`runtime/status.go` lines 31-39) accepts arbitrary custom routing values beyond the five canonical statuses. The `status == "fail"` check in `updateContextStatusMap` is the only branch that produces "error" — all other values (including custom routing values like `"process"`, `"done"`, `"port"`, `"needs_dod"`) produce "complete". The detail panel renders both `data.status` and `data.preferred_label` as-is, even when they contain the same value.

**Why current holdout scenarios are insufficient:** The existing "Pipeline completed — last node marked complete via StageFinished" scenario uses a canonical status value. An implementation that hardcodes a switch/case on the five canonical values and falls through to an error/default case for unrecognized values would pass all current holdout scenarios but fail for real Kilroy pipelines using custom routing (consensus_task.dot, semport.dot).

---

## Proposed: Quoted graph ID with escapes normalizes for tab label and pipeline discovery

**Source:** v41-codex, Issue #1

**Scenario:**
```
Given a DOT file contains: digraph "my \"quoted\" pipeline" {
  And a CXDB context has RunStarted with graph_name = 'my "quoted" pipeline'
When the UI renders the tab bar
Then the tab label shows the literal text: my "quoted" pipeline
  And the tab label is rendered via textContent (no HTML injection)
When the UI runs pipeline discovery
Then the context is matched to the tab because the normalized graph ID matches RunStarted.graph_name
When a second DOT file also declares: digraph "my \"quoted\" pipeline" {
Then the server rejects the second DOT file at startup with a duplicate graph ID error
```

**Expected behavior:** Graph ID normalization (Section 4.4) strips outer quotes, resolves escape sequences (`\"` to `"`), and trims whitespace. The normalized ID is used for tab labels (via safe text rendering), pipeline discovery (matching against `RunStarted.data.graph_name`), and duplicate ID rejection. Both the server (Section 3.2) and the browser use identical normalization logic.

**Why current holdout scenarios are insufficient:** The existing "Tab shows graph ID from DOT declaration" scenario uses only an unquoted identifier (`alpha_pipeline`). An implementation that skips quote stripping or escape resolution would pass the existing scenario but fail to discover pipelines with quoted graph IDs, render incorrect tab labels, or miss duplicate ID collisions between quoted and unquoted forms.

---

## Proposed: Quoted node IDs normalize correctly for /nodes, /edges, status overlay, and detail panel

**Source:** v41-codex, Issue #2

**Scenario:**
```
Given a DOT file defines a node: "review step" [shape=box, prompt="Review the implementation"]
  And the DOT file defines an edge: "review step" -> done [label="pass"]
  And CXDB contains turns with node_id = "review step" (the normalized form)
When the browser fetches /dots/{name}/nodes
Then the response contains key "review step" (without quotes) with shape "box"
When the browser fetches /dots/{name}/edges
Then the response contains an edge with source "review step" and target "done"
When the UI renders the SVG
Then the node has <title>review step</title> in the SVG
  And the status overlay applies the correct status color to the node
When the user clicks the "review step" node
Then the detail panel shows Node ID: "review step" and Type: "LLM Task"
  And the detail panel shows CXDB turns matching node_id "review step"
```

**Expected behavior:** Node ID normalization (Section 3.2) strips outer quotes, resolves escapes, and trims whitespace. The normalized ID matches the SVG `<title>` text that Graphviz produces and the `node_id` values in CXDB turns. The `/nodes` endpoint returns normalized keys, and `/edges` returns normalized `source`/`target` values.

**Why current holdout scenarios are insufficient:** The existing holdout scenarios for node rendering and detail panel use unquoted identifiers only (`implement`, `check_fmt`). The edge scenarios test chains and port stripping but not quoted endpoints. An implementer who only handles bare identifiers would pass all existing tests but break the status overlay and detail panel for legal DOT files with quoted node IDs.

---

## Proposed: Gap recovery does not double-count already-processed turns

**Source:** v42-opus, Issue #3

**Scenario:**
```
Given a pipeline run is active with the implement node running
  And the UI has polled successfully, processing turns up to turn_id 500
  And 150 new turns are appended (turn_ids 501-650)
When the UI polls CXDB on the next cycle
Then the initial fetch (limit=100) returns turns 551-650
  And gap recovery fetches turns 501-550 (back to lastSeenTurnId 500)
  And turns 1-500 are NOT re-processed (skipped by deduplication)
  And turnCount for the node reflects only newly processed turns (501-650)
```

**Expected behavior:** Gap recovery prepends older turns before the main batch. The `lastSeenTurnId` deduplication check (`turn.turn_id <= lastSeenTurnId`) ensures already-processed turns are skipped even though the combined batch is not in strictly ascending order. The `newLastSeenTurnId` cursor is computed as the maximum `turn_id` across the entire batch before the processing loop begins. `turnCount` and `errorCount` are not inflated by re-processing overlapping turns.

**Why current holdout scenarios are insufficient:** The existing "Lifecycle turn missed during poll gap is recovered" scenario tests that a `StageFinished` turn outside the 100-turn window is recovered via gap recovery, but does not verify the deduplication boundary. An implementation that correctly fetches gap-recovery pages but fails to skip already-processed turns would pass the existing scenario while silently inflating internal counters — potentially causing the error loop heuristic to fire incorrectly if an implementer uses `errorCount` instead of the specified "3 consecutive recent ToolResult errors" check.

---

## Proposed: CQL-empty supplemental discovery populates status overlay and liveness

**Source:** v42-codex, Issue #1

**Scenario:**
```
Given CXDB has active Kilroy contexts with is_live: true
  And the Kilroy contexts lack key 30 (context_metadata) in their first turn payloads
  And CQL search for tag ^= "kilroy/" returns 200 OK with an empty contexts array
  And the supplemental context list fetch discovers contexts via session-tag resolution
When the UI polls for pipeline discovery and status overlay
Then the supplemental fetch maps contexts to pipelines via RunStarted turns
  And the status overlay updates with node colors from the discovered contexts
  And checkPipelineLiveness returns true (pipeline is live, not stale)
  And running nodes are NOT misclassified as stale
```

**Expected behavior:** When CQL returns zero results, the supplemental `fetchContexts` discovers Kilroy contexts via session-tag-resolved `client_tag`. The discovered contexts are processed through pipeline discovery (Phase 2), status maps are built, and the supplemental context list is stored in `cachedContextLists` for liveness checks. This is the complete end-to-end path: discovery, status overlay, and liveness — not just discovery alone.

**Why current holdout scenarios are insufficient:** The existing proposed scenarios test individual pieces of this path: "CQL returns empty results, supplemental context list discovers active Kilroy contexts" (v37-opus) tests discovery, and "CQL-empty supplemental context list populates cachedContextLists for liveness checks" (v38-codex) tests liveness. No scenario verifies the full end-to-end flow from CQL-empty through status overlay rendering. An implementation could pass the individual scenarios while failing to connect the supplemental discovery to the status overlay rendering pipeline.

---

## Proposed: Node retrying after StageFailed with will_retry=true shows as running

**Source:** v43-opus, Issue #3

**Scenario:**
```
Given a pipeline run is active with the implement node running
  And the agent encounters an error and Kilroy emits StageFailed with will_retry=true
  And Kilroy subsequently emits StageRetrying and then StageStarted for a new attempt
When the UI polls CXDB
Then the implement node is colored blue (running), not red (error)
  And hasLifecycleResolution is false for the implement node
  And the detail panel shows the StageFailed, StageRetrying, and StageStarted turns
```

**Expected behavior:** A `StageFailed` turn with `will_retry=true` sets the node to "running" (blue, pulsing) and does NOT set `hasLifecycleResolution`. The subsequent `StageRetrying` turn (a non-lifecycle turn) infers "running", which is a no-op since the node is already running. The subsequent `StageStarted` turn also sets "running". Throughout this sequence, the node remains running and open to future lifecycle resolution. An implementer who incorrectly treats all `StageFailed` turns as setting `hasLifecycleResolution=true` (ignoring the `will_retry` guard) would cause all subsequent non-lifecycle turns to be ignored, freezing the node at "error" when it should show "running" during retry.

**Why current holdout scenarios are insufficient:** The existing "Agent stuck in error loop" scenario tests 3 consecutive `ToolResult` errors (the heuristic path). The proposed "Node retries after StageFailed with will_retry" scenario (v35-opus) tests the end-to-end retry flow through to `StageFinished` completion. Neither isolates the intermediate state: `StageFailed(will_retry=true)` → `StageRetrying` → `StageStarted` where the node must remain "running" and `hasLifecycleResolution` must remain `false`. This intermediate state is the most error-prone part of the retry sequence.

---

## Proposed: DOT comment stripping preserves quoted-string content and rejects unterminated constructs

**Source:** v43-codex, Issue #2

**Scenario (comment safety):**
```
Given a DOT file contains a node with prompt="check http://example.com"
  And the DOT file contains a line comment (// this is a comment)
  And the DOT file contains a block comment (/* block comment */)
When the browser fetches /dots/{name}/nodes
Then the node's prompt attribute value is "check http://example.com" (// inside quotes preserved)
  And the line comment and block comment are stripped (do not appear as node attributes)
  And edges defined after comment lines are parsed correctly
```

**Scenario (unterminated block comment):**
```
Given a DOT file contains /* with no matching */
When the browser fetches /dots/{name}/nodes
Then the server returns 400 with a JSON error body containing "DOT parse error"
```

**Scenario (unterminated quoted string during comment stripping):**
```
Given a DOT file contains a " with no matching closing "
When the browser fetches /dots/{name}/nodes
Then the server returns 400 with a JSON error body containing "DOT parse error"
```

**Expected behavior:** The server's DOT parser strips `//` line comments and `/* */` block comments before parsing node and edge definitions, but only outside of double-quoted strings. Comments inside quoted strings are preserved verbatim. Unterminated block comments and unterminated strings are parse errors, matching Kilroy's `stripComments` function (`kilroy/internal/attractor/dot/comments.go` lines 56 and 67).

**Why current holdout scenarios are insufficient:** No existing holdout scenario exercises DOT comment stripping. The proposed "DOT file with comments parses correctly" scenario (v40-opus) tests basic comment stripping and URL safety but does not explicitly test the error paths for unterminated block comments and unterminated strings. These are the most failure-prone parsing paths — a custom parser that handles well-formed comments correctly may still crash or hang on unterminated constructs.

---

## Proposed: Anonymous graph rejected at server startup

**Source:** v44-codex, Issue #1

**Scenario:**
```
Given a DOT file contains "digraph {" with no graph identifier
When the user runs: go run ui/main.go --dot /path/to/anonymous.dot
Then the server exits with a non-zero code
  And prints an error stating that named graphs are required for discovery
```

**Expected behavior:** The server's graph ID extraction regex (`/^\s*(strict\s+)?(di)?graph\s+("(?:[^"\\]|\\.)*"|\w+)/m`) does not match anonymous graphs (e.g., `digraph { ... }` with no identifier after the keyword). The server rejects the DOT file at startup with a non-zero exit code and an error message stating that named graphs are required for pipeline discovery, since `RunStarted.data.graph_name` must match the graph ID.

**Why current holdout scenarios are insufficient:** The existing Server holdout scenarios test duplicate graph IDs, duplicate basenames, and missing DOT files, but none exercise the anonymous-graph rejection path. An implementation could silently accept anonymous graphs and fall back to filenames in the browser, which would break pipeline discovery because `RunStarted.graph_name` would never match a filename-based tab label.

---

## Proposed: DOT attribute concatenation and multiline quoted values

**Source:** v44-codex, Issue #2

**Scenario:**
```
Given a DOT node attribute uses concatenation: prompt="first " + "second"
  And a DOT node attribute contains a literal newline inside quotes
When the browser fetches /dots/{name}/nodes
Then the parsed prompt value is "first second" (concatenated with no separator)
  And the multiline prompt preserves the newline in the returned attribute value
```

**Expected behavior:** The server's DOT parser supports the `+` concatenation operator for quoted attribute values (joining fragments with no separator, per DOT semantics) and handles multi-line quoted strings (a value beginning with `"` extends to the next unescaped `"`, regardless of intervening newlines). These rules are specified in Section 3.2 of the spec.

**Why current holdout scenarios are insufficient:** The existing "DOT file with long prompt text" scenario tests escaped newlines and quotes but does not exercise `+` concatenation or literal newlines inside quoted strings. An implementer could build a line-by-line parser that passes the existing scenario but fails on these two required parsing rules, leading to truncated prompts or parse errors for valid DOT files.

---

## Proposed: StageFinished with status=fail shows as error, not complete

**Source:** v44-opus, Issue #3

**Scenario:**
```
Given a pipeline run is active with the implement node running
  And CXDB contains a StageFinished turn for implement with status: "fail"
When the UI polls CXDB
Then the implement node is colored red (error), not green (complete)
  And hasLifecycleResolution is true for the implement node
  And the detail panel shows "Stage finished: fail" with the failure_reason
```

**Expected behavior:** The `updateContextStatusMap` algorithm checks `StageFinished.data.status`. When `status == "fail"`, the node is set to "error" (red) instead of "complete" (green). The `hasLifecycleResolution` flag is set to `true` because `StageFinished` is an authoritative lifecycle turn regardless of the status value.

**Why current holdout scenarios are insufficient:** The existing "Pipeline completed successfully" and "Pipeline completed — last node marked complete via StageFinished" scenarios assume all nodes finished with non-fail status. The "Agent stuck in error loop" scenario tests the ToolResult error heuristic, not lifecycle-level failure. The `StageFinished { status: "fail" }` → red path is documented in the spec's Definition of Done but not exercised by any holdout scenario. An implementer could handle all `StageFinished` turns as "complete" (ignoring the `status` field check) and pass every existing holdout. Note: this supersedes the similar v38-opus proposed scenario by being more concise and focused.

---

## Proposed: Gap recovery bounded by MAX_GAP_PAGES advances cursor to oldest recovered turn

**Source:** v45-opus, Issue #4

**Scenario:**
```
Given a pipeline run is active with a context that accumulated 2000+ turns during a poll gap
  And the gap recovery issues MAX_GAP_PAGES (10) paginated requests covering 1000 turns
  And a StageFinished turn for node A exists beyond the 1000-turn recovery window
When gap recovery completes
Then lastSeenTurnId is set to the oldest recovered turn's turn_id (not the newest)
  And node A retains its previous status (running) since the StageFinished was not recovered
  And the next poll cycle's 100-turn window contains the most recent state
```

**Expected behavior:** When gap recovery exhausts `MAX_GAP_PAGES` (10 pages × 100 turns = 1,000 turns), the spec requires setting `lastSeenTurnId = recoveredTurns[0].turn_id` — the oldest recovered turn. This ensures the next poll cycle detects a gap from the oldest recovered point (not from the newest), preserving the possibility of catching up on the window just before the boundary. An implementer who mistakenly uses the newest recovered turn as the new cursor would advance past unrecovered turns, which would never be fetched. The `lastSeenTurnId` cursor is specifically set to the oldest (not the newest) recovered turn to bound the window correctly.

**Why current holdout scenarios are insufficient:** The existing "Lifecycle turn missed during poll gap is recovered" scenario tests the basic gap recovery case (gap fits within MAX_GAP_PAGES). It does not cover the MAX_GAP_PAGES truncation case, which exercises the cursor-advancement logic specifically. The spec documents the correct cursor assignment (`recoveredTurns[0].turn_id` = oldest) versus the common implementation mistake (using the newest recovered turn). Without this scenario, an implementer who uses `max(turn_id)` for the post-gap cursor — which is correct for the normal flow but incorrect for the truncated-gap case — would pass all existing holdouts.

---

## Proposed: Nodes and edges inside subgraphs are included in /nodes and /edges responses

**Source:** v45-codex, Issue #2

**Scenario:**
```
Given a DOT file contains:
  subgraph cluster_a { a [shape=box] }
  subgraph cluster_b { b [shape=diamond] }
  a -> b [label="go"]
When the browser fetches /dots/{name}/nodes and /dots/{name}/edges
Then the nodes response includes a and b
  And the edges response includes (a, b, "go")
  And a has shape "box" and b has shape "diamond"
```

**Expected behavior:** Nodes defined inside `subgraph` blocks are included in the `/dots/{name}/nodes` response with their attributes. Edges defined at the top level (or inside subgraphs) connecting subgraph-scoped nodes are included in the `/dots/{name}/edges` response. Subgraphs are used in real pipeline DOT files for layout grouping (e.g., `cluster_` prefixed subgraphs) and contain valid node definitions. Section 3.2 requires that nodes and edges inside subgraphs be included.

**Why current holdout scenarios are insufficient:** The existing DOT parsing scenarios exercise edge chains, port stripping, and basic node parsing — all with top-level node definitions. None verify that a parser correctly descends into subgraph blocks to extract node and edge definitions. A parser that only processes top-level graph statements (ignoring the recursive structure of subgraphs) would silently drop nodes and edges that appear in real Kilroy DOT files using `subgraph cluster_` for layout.

