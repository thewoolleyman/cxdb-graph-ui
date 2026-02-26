# CXDB Graph UI — Holdout Scenarios

## DOT Rendering

### Scenario: Render a pipeline graph on initial load
```
Given the UI server is running with --dot /path/to/pipeline.dot
When a user opens the dashboard URL in a browser
Then the pipeline DOT file is fetched from /dots/pipeline.dot
  And @hpcc-js/wasm-graphviz renders it as an SVG in the main content area
  And every node from the DOT file is visible as an SVG element
  And edges between nodes are rendered with arrows
  And the graph layout follows the DOT rankdir attribute
```

### Scenario: Switch between pipeline tabs
```
Given the server was started with multiple --dot flags
  And the UI is showing the first pipeline graph
  And the second pipeline has been polled at least once
When the user clicks the second pipeline's tab
Then the UI fetches the second DOT file from /dots/
  And renders the second pipeline graph, replacing the previous SVG
  And the second tab is visually active
  And the cached status map for the second pipeline is immediately reapplied
  And nodes are not shown as all-gray between tab switch and next poll
```

### Scenario: Nodes rendered with correct shapes
```
Given the UI has rendered a pipeline graph containing all Kilroy node shapes
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

### Scenario: DOT file with long prompt text
```
Given a DOT node has a prompt attribute exceeding 500 characters
  And the prompt contains escaped newlines and quotes
When the graph is rendered
Then the node renders normally in the SVG
  And the full prompt text is available in the detail panel when clicked
```

### Scenario: DOT file regenerated while UI is open
```
Given the UI is showing a pipeline graph
  And the DOT file on disk is regenerated
When the user clicks the pipeline's tab again
Then the updated DOT file is fetched (server reads fresh from disk)
  And the graph reflects the new pipeline structure
```

### Scenario: DOT file with syntax error
```
Given the DOT file contains invalid syntax
When the UI attempts to render it
Then @hpcc-js/wasm-graphviz throws an error
  And the UI displays the error message in the graph area
  And the page does not crash or become unresponsive
  And other pipelines (if any) remain functional
```

### Scenario: DOT parse error on /nodes does not block polling
```
Given a DOT file with invalid syntax is loaded
When the browser fetches /dots/{name}/nodes during initialization
Then the server returns 400 with a JSON error body
  And the browser proceeds with an empty dotNodeIds set for that pipeline
  And polling starts normally for all pipelines
  And the graph area shows the Graphviz error message
```

### Scenario: DOT parse error on /edges does not block detail panel
```
Given a DOT file with invalid syntax is loaded
When the browser fetches /dots/{name}/edges
Then the server returns 400 with a JSON error body
  And the browser proceeds with an empty edge list for that pipeline
  And human gate choices are unavailable in the detail panel
  And other detail panel functionality (node attributes, CXDB turns) is unaffected
```

### Scenario: Edge chain expansion in /edges response
```
Given a DOT file contains the edge chain: a -> b -> c [label="x"]
When the browser fetches /dots/{name}/edges
Then the response contains two edges: (a, b, "x") and (b, c, "x")
  And not a single edge from a to c
```

### Scenario: Port suffixes stripped from edge node IDs
```
Given a DOT file contains: a:out -> b:in
When the browser fetches /dots/{name}/edges
Then the response contains an edge (a, b, null) with port suffixes removed
```

### Scenario: Tab shows graph ID from DOT declaration
```
Given a DOT file containing "digraph alpha_pipeline {"
When the UI renders the tab bar
Then the tab label is "alpha_pipeline", not the filename
```

### Scenario: Pipeline tab ordering matches --dot flag order
```
Given the server was started with: --dot b.dot --dot a.dot
When the UI renders the tab bar
Then the "b" tab appears before the "a" tab (not alphabetically sorted)
  And the first pipeline rendered is from b.dot
```

### Scenario: DOT prompt containing HTML markup renders as literal text
```
Given a DOT node has prompt attribute containing "<script>alert('xss')</script> and <b>bold</b>"
When the user clicks the node to open the detail panel
Then the detail panel shows the literal text "<script>alert('xss')</script> and <b>bold</b>"
  And no script executes
  And no HTML formatting is applied (no bold text)
  And the angle brackets are visible as text characters
```

### Scenario: Pipeline tab label with HTML-like graph ID renders as literal text
```
Given a DOT file contains "digraph \"<b>Pipeline</b>\" {"
When the UI renders the tab bar
Then the tab label shows the literal text "<b>Pipeline</b>"
  And no HTML formatting is applied (no bold text)
  And the angle brackets are visible as text characters
```

### Scenario: /nodes prefetch non-400 failure does not block initialization
```
Given the UI initializes with multiple DOT files
  And one /dots/{name}/nodes request fails with 500 (internal server error)
When initialization continues
Then polling still starts for all pipelines
  And the active tab renders its SVG
  And the pipeline with the failed /nodes prefetch uses an empty dotNodeIds set
  And status overlay for the affected pipeline is unavailable until the next tab switch
```

### Scenario: Tab-switch /nodes or /edges failure retains cached data
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

### Scenario: DOT file with comments parses correctly
```
Given a DOT file contains line comments (// ...) and block comments (/* ... */)
  And a node attribute value contains a URL with // (e.g., prompt="check http://example.com")
When the browser fetches /dots/{name}/nodes
Then the comments are stripped and do not appear as node attributes or cause parse errors
  And the URL inside the quoted attribute value is preserved (not treated as a comment)
  And edges defined after comment lines are parsed correctly

Given a DOT file contains /* with no matching */
When the browser fetches /dots/{name}/nodes
Then the server returns 400 with a JSON error body containing "DOT parse error"

Given a DOT file contains a " with no matching closing "
When the browser fetches /dots/{name}/nodes
Then the server returns 400 with a JSON error body containing "DOT parse error"
```

### Scenario: Quoted graph ID with escapes normalizes for tab label and pipeline discovery
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

### Scenario: Quoted node IDs normalize correctly for /nodes, /edges, status overlay, and detail panel
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

### Scenario: DOT attribute concatenation and multiline quoted values
```
Given a DOT node attribute uses concatenation: prompt="first " + "second"
  And a DOT node attribute contains a literal newline inside quotes
When the browser fetches /dots/{name}/nodes
Then the parsed prompt value is "first second" (concatenated with no separator)
  And the multiline prompt preserves the newline in the returned attribute value
```

### Scenario: Nodes and edges inside subgraphs are included in /nodes and /edges responses
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

---

## CXDB Status Overlay

### Scenario: Pipeline actively running — nodes colored by status
```
Given CXDB is running and reachable
  And an Attractor pipeline run is in progress
  And the agent has completed expand_spec and implement_proto
  And the agent is currently on the implement node
When the UI polls CXDB and builds the node status map
Then expand_spec is colored green (complete)
  And implement_proto is colored green (complete)
  And implement is colored blue with a pulsing animation (running)
  And subsequent nodes are colored gray (pending)
```

### Scenario: Agent stuck in error loop (per-context scoping)
```
Given a pipeline run is active with a single context
  And within the current 100-turn poll window for that context
  And the 3 most recent ToolResult turns on a node within that context each have is_error: true
  And non-ToolResult turns (Prompt, ToolCall) are interleaved between them
When the UI polls CXDB
Then that node is colored red (error)
```

### Scenario: Error loop detection does not span contexts
```
Given a pipeline run has two parallel branch contexts for the same node
  And context A has 2 recent ToolResult turns with is_error: true
  And context B has 1 recent ToolResult turn with is_error: true
  And neither context independently has 3 consecutive error ToolResults
When the UI polls CXDB
Then the node is NOT colored red (error)
  And the node retains its running status (blue)
```

### Scenario: Pipeline completed successfully
```
Given a pipeline run completed with all nodes successful
When the UI polls CXDB
Then all traversed nodes are colored green (complete)
  And no node is pulsing
```

### Scenario: Pipeline stalled after agent crash
```
Given a pipeline run is active with a node in running state
  And all active-run contexts transition to is_live: false
When the UI polls CXDB
Then the running node is marked stale (orange)
  And the top bar shows "Pipeline stalled — no active sessions"
```

### Scenario: No active pipeline run
```
Given CXDB is running but no pipeline is currently executing
  And there are no historical contexts matching the loaded DOT file
When the UI polls CXDB
Then all nodes remain gray (pending)
```

### Scenario: Pipeline completed — last node marked complete via StageFinished
```
Given a pipeline run has completed all nodes including the final exit node
  And CXDB contains a StageFinished turn for the final node
When the UI polls CXDB
Then the final node is colored green (complete), not blue (running)
  And all traversed nodes are colored green
```

### Scenario: Multiple contexts for same pipeline (parallel branches)
```
Given a pipeline run has spawned parallel branches
  And multiple CXDB contexts have RunStarted turns with the same graph_name and same run_id
When the UI polls CXDB
Then turns from all matching contexts contribute to the status map
  And nodes running in different branches are both colored blue (running)
  And the detail panel shows activity from all branches
```

### Scenario: Completed node retains status across polls
```
Given a pipeline run is active
  And node A completed early (StageFinished processed)
  And node B is currently running with 150+ tool call turns
  And node A's lifecycle turns have fallen outside the 100-turn poll window
When the UI polls CXDB
Then node A remains green (complete), not gray (pending)
  And node B is blue (running)
```

### Scenario: Lifecycle turn missed during poll gap is recovered
```
Given a pipeline run is active with node implement in running state
  And the UI has polled successfully, recording lastSeenTurnId for the context
  And the agent completes implement (StageFinished) and starts the next node
  And more than 100 turns are appended after StageFinished
When the UI polls CXDB on the next cycle
Then the initial fetch (limit=100) does not contain the StageFinished turn
  And gap recovery issues paginated requests to fetch turns back to lastSeenTurnId
  And the StageFinished turn is recovered and processed
  And implement is colored green (complete), not blue (running)
```

### Scenario: Parallel branch error loop with lifecycle resolution in another branch
```
Given a pipeline run has two parallel branch contexts for the same node
  And context A has completed the node (StageFinished turn present, hasLifecycleResolution = true)
  And context B is stuck in an error loop on the same node (3 consecutive error ToolResults)
When the UI polls CXDB
Then the error heuristic fires because context B lacks lifecycle resolution
  And the node is colored red (error), not green (complete)
```

### Scenario: Status coloring applies to all node shapes
```
Given a pipeline graph contains all ten node shapes:
  - start (shape=Mdiamond)
  - start (shape=circle)
  - exit (shape=Msquare)
  - exit (shape=doublecircle)
  - llm_task (shape=box)
  - conditional (shape=diamond)
  - tool_gate (shape=parallelogram)
  - human_gate (shape=hexagon)
  - parallel (shape=component)
  - parallel_fan_in (shape=tripleoctagon)
  - stack_manager_loop (shape=house)
  And CXDB has status data marking each node as complete
When the UI applies the status overlay
Then all nodes display with green fill (complete status)
  And the CSS fill rules match regardless of whether the shape renders as polygon, ellipse, or path
  And doublecircle nodes (which render as two nested <ellipse> elements) have both ellipses colored
```

### Scenario: Second run of same pipeline while first run data exists
```
Given CXDB contains contexts from a completed run of alpha_pipeline (run_id A)
  And a new run of alpha_pipeline starts (run_id B)
  And run B has only completed the first two nodes
When the UI polls CXDB
Then only contexts with run_id B are used for the status overlay
  And nodes completed in run A but not yet reached in run B show as pending
```

### Scenario: StageFailed with will_retry=true leaves node in running state
```
Given a pipeline run is active with the implement node running
  And Kilroy emits StageFailed for implement with will_retry: true
  And Kilroy subsequently emits StageRetrying and then StageStarted for a new attempt
When the UI polls CXDB
Then the implement node is colored blue (running), not red (error)
  And hasLifecycleResolution is false for the implement node
  And the detail panel shows the StageFailed, StageRetrying, and StageStarted turns
```

### Scenario: StageFailed retry sequence resolves to complete when retry succeeds
```
Given a pipeline run is active with node check_fmt in running state
  And CXDB contains a StageFailed turn for check_fmt with will_retry: true
  And CXDB contains a StageRetrying turn after the StageFailed
  And the retry succeeds with a StageFinished turn
When the UI polls CXDB
Then check_fmt is colored green (complete)
  And check_fmt is NOT permanently stuck in error state
```

### Scenario: StageFinished with status=fail colors node as error
```
Given a pipeline run is active with the implement node running
  And CXDB contains a StageFinished turn for implement with status: "fail"
When the UI polls CXDB
Then the implement node is colored red (error), not green (complete)
  And hasLifecycleResolution is true for the implement node
  And the detail panel shows "Stage finished: fail" with the failure_reason
```

### Scenario: RunFailed marks specified node as error
```
Given a pipeline run is active with node implement in running state
  And Kilroy emits a RunFailed turn with node_id = "implement" and reason = "agent crashed"
When the UI polls CXDB
Then the implement node is colored red (error), not blue (running)
  And the node has hasLifecycleResolution = true
  And the detail panel shows the RunFailed reason
```

### Scenario: Active run selection stable when older run spawns late branch context
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

### Scenario: Newer run on low-context_id CXDB instance is selected as active run
```
Given two CXDB instances are configured (CXDB-0 and CXDB-1)
  And CXDB-0 contains contexts 500-550 from an old completed run of alpha_pipeline (run_id_old)
  And run_id_old was created at time T1 (older ULID, lexicographically smaller)
  And CXDB-1 contains contexts 12-20 from a newer run of alpha_pipeline (run_id_new)
  And run_id_new was created at time T2 > T1 (newer ULID, lexicographically larger)
When the UI polls both CXDB instances and runs determineActiveRuns for alpha_pipeline
Then the active run is run_id_new (the newer run on CXDB-1 with lower context_ids)
  And the status overlay reflects CXDB-1's contexts 12-20
  And CXDB-0's contexts 500-550 are excluded from the status overlay
  And the UI does not incorrectly treat run_id_old as the active run due to higher context_id values
```

### Scenario: Conditional node with custom routing outcome shows as complete
```
Given a pipeline run has a conditional node using custom routing
  And CXDB contains a StageFinished turn for that node with data.status = "process" (a custom routing value)
  And data.preferred_label = "process"
When the UI polls CXDB
Then the node is colored green (complete), not red (error)
  And the detail panel shows "Stage finished: process — process"
  And no deduplication is applied between status and preferred_label
```

### Scenario: Gap recovery does not double-count already-processed turns
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

### Scenario: Gap recovery bounded by MAX_GAP_PAGES advances cursor to oldest recovered turn
```
Given a pipeline run is active with a context that accumulated 2000+ turns during a poll gap
  And the gap recovery issues MAX_GAP_PAGES (10) paginated requests covering 1000 turns
  And a StageFinished turn for node A exists beyond the 1000-turn recovery window
When gap recovery completes
Then lastSeenTurnId is set to the oldest recovered turn's turn_id (not the newest)
  And node A retains its previous status (running) since the StageFinished was not recovered
  And the next poll cycle's 100-turn window contains the most recent state
```

---

## Pipeline Discovery

### Scenario: Context matched to pipeline via RunStarted turn
```
Given CXDB contains a context whose first turn is a RunStarted event
  And RunStarted.data.graph_name == "alpha_pipeline"
  And the UI has loaded a DOT file with "digraph alpha_pipeline {"
When the UI runs pipeline discovery
Then the context is associated with that pipeline tab
  And its turns are used for the status overlay
```

### Scenario: Context does not match any loaded pipeline
```
Given CXDB contains a context whose RunStarted.graph_name is "other_pipeline"
  And no loaded DOT file has graph ID "other_pipeline"
When the UI runs pipeline discovery
Then the context is ignored for status overlay purposes
```

### Scenario: Context-to-pipeline mapping is cached
```
Given the UI has already discovered context 33 on CXDB-0 belongs to alpha_pipeline
When the next poll cycle runs
Then the UI does NOT re-fetch the RunStarted turn for (CXDB-0, context 33)
  And only fetches RunStarted for newly appeared context IDs
```

### Scenario: Pipeline discovered across multiple CXDB instances
```
Given two CXDB instances are configured
  And CXDB-0 contains a context whose RunStarted.graph_name == "alpha_pipeline"
  And CXDB-1 contains a context whose RunStarted.graph_name == "beta_pipeline"
  And DOT files for both pipelines are loaded
When the UI runs pipeline discovery
Then the alpha_pipeline tab shows status from CXDB-0's context
  And the beta_pipeline tab shows status from CXDB-1's context
  And no manual pairing was required
```

### Scenario: Same pipeline on multiple CXDB instances
```
Given two CXDB instances are configured
  And both contain contexts whose RunStarted.graph_name == "alpha_pipeline"
When the UI displays the alpha_pipeline tab
Then turns from both CXDB instances are merged into the status overlay
```

### Scenario: RunStarted with null or empty graph_name
```
Given CXDB contains a context whose first turn is a RunStarted event
  And the RunStarted turn has a valid run_id but graph_name is null or empty string
When the UI runs pipeline discovery
Then the context is excluded from pipeline discovery (cached as a null mapping)
  And it does not match any pipeline tab
  And no error is surfaced to the user
  And the context is not retried on subsequent polls
```

### Scenario: Forked context discovered via parent's RunStarted turn
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

### Scenario: CQL returns empty results, supplemental context list discovers active Kilroy contexts
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

### Scenario: CQL-empty supplemental context list populates cachedContextLists for liveness checks
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

### Scenario: CQL-empty supplemental discovery populates status overlay and liveness
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

---

## Detail Panel

### Scenario: Click a node to see details
```
Given the UI is showing a pipeline graph with CXDB status overlay
When the user clicks on the implement node
Then a sidebar panel opens on the right
  And the panel shows:
    - Node ID: "implement"
    - Type: "LLM Task"
    - Prompt text (scrollable)
  And recent CXDB turns for this node:
    - Turn type (ToolCall, ToolResult, Prompt)
    - Tool name (e.g., "shell", "write_file")
    - Truncated output (expandable)
    - Error flag (highlighted if is_error: true)
```

### Scenario: Click a tool gate node
```
Given the UI is showing a pipeline graph
When the user clicks on a tool gate node (shape=parallelogram)
Then the detail panel shows:
  - Type: "Tool Gate"
  - Tool command from DOT tool_command attribute
  And if CXDB has turns for this node, shows the command output
```

### Scenario: Click a human gate node
```
Given the UI is showing a pipeline graph
When the user clicks on a human gate node (shape=hexagon)
Then the detail panel shows:
  - Type: "Human Gate"
  - Question text from DOT question attribute
  - Available choices from outgoing edge labels
```

### Scenario: Detail panel for early-completed node outside poll window
```
Given node A completed 200+ turns ago
  And node A's turns have fallen outside the 100-turn poll window
When the user clicks node A
Then the detail panel shows node A's DOT attributes (ID, type, prompt)
  And indicates no recent CXDB activity is available in the poll window
```

### Scenario: Close detail panel
```
Given the detail panel is open
When the user clicks outside the panel or clicks the close button
Then the panel closes and the full graph area is restored
```

### Scenario: Human gate interview turns render in detail panel CXDB Activity section
```
Given a pipeline run includes a human gate node (shape=hexagon, id="review_gate")
  And CXDB contains an InterviewStarted turn for review_gate:
    - question_text: "Approve the implementation?"
    - question_type: "SingleSelect"
  And CXDB contains an InterviewCompleted turn for review_gate:
    - answer_value: "YES"
    - duration_ms: 45000
When the user clicks the review_gate node
Then the detail panel's CXDB Activity section shows the InterviewStarted turn
  With Output: "Approve the implementation? [SingleSelect]"
  And the detail panel shows the InterviewCompleted turn
  With Output: "YES (waited 45s)"
```

### Scenario: InterviewTimeout turn renders with error highlight in detail panel
```
Given CXDB contains an InterviewTimeout turn for a human gate node:
    - question_text: "Confirm deployment?"
    - duration_ms: 300000
When the user clicks that node
Then the detail panel shows the InterviewTimeout turn
  With Output: "Confirm deployment?"
  And the Error column is highlighted with "timeout"
```

### Scenario: StageStarted turn renders handler_type in detail panel
```
Given CXDB contains a StageStarted turn for an LLM task node with handler_type: "codergen"
When the user clicks that node
Then the detail panel shows the StageStarted turn
  With Output: "Stage started: codergen"
Given CXDB contains a StageStarted turn for a tool gate node with handler_type: "tool"
When the user clicks that node
Then the detail panel shows the StageStarted turn
  With Output: "Stage started: tool"
Given CXDB contains a StageStarted turn with handler_type: "" (empty)
When the user clicks that node
Then the detail panel shows the StageStarted turn
  With Output: "Stage started" (no colon suffix)
```

### Scenario: StageFinished with suggested_next_ids renders Next line in detail panel
```
Given CXDB contains a StageFinished turn for a conditional node with:
  - status: "pass"
  - preferred_label: "pass"
  - suggested_next_ids: ["check_goal", "finalize"]
When the user clicks that node
Then the detail panel shows the StageFinished turn
  With Output: "Stage finished: pass — pass\nNext: check_goal, finalize"
  And the "\nNext:" portion uses a literal newline before "Next:"
  And the Error column is not highlighted (status is not "fail")
```

### Scenario: StageFinished with empty suggested_next_ids omits Next line
```
Given CXDB contains a StageFinished turn with:
  - status: "pass"
  - preferred_label: "done"
  - suggested_next_ids: [] (empty array) or absent
When the user clicks that node
Then the detail panel shows the StageFinished turn
  With Output: "Stage finished: pass — done"
  And no "\nNext:" line is appended
```

### Scenario: Prompt turn Show more expansion is capped at 8,000 characters with disclosure
```
Given CXDB contains a Prompt turn for an LLM task node
  And the Prompt.text is 50,000 characters (not truncated at source by Kilroy)
  And the detail panel has client-side-truncated the output to 500 characters
When the user clicks "Show more" on that Prompt turn row
Then the expanded output is capped at 8,000 characters (not 50,000)
  And a disclosure note is displayed indicating the content is truncated
    (e.g., "(truncated to 8,000 characters — full prompt available in CXDB)")
  And the expanded output does not inject more than 8,000 characters into the DOM
  And this behaviour matches the expansion cap applied to AssistantMessage,
    ToolCall, and ToolResult turns
```

### Scenario: Human gate choices available on first pipeline without tab switch
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

---

## CXDB Connection Handling

### Scenario: No CXDB instances running
```
Given no configured CXDB instances are running
When the UI attempts to poll
Then the server returns 502 for all /api/cxdb/{i}/ requests
  And the UI shows "CXDB unreachable" with the configured URLs
  And the pipeline graph still renders from the DOT file
  And all nodes show as pending (gray)
  And polling continues at 3-second intervals
```

### Scenario: One of multiple CXDB instances unreachable
```
Given two CXDB instances are configured
  And CXDB-0 is running with active pipeline contexts
  And CXDB-1 is unreachable
When the UI polls
Then CXDB-0's contexts are processed normally
  And the indicator shows partial connectivity (e.g., "1/2 CXDB")
  And status from CXDB-0 is displayed on the graph
  And polling continues for both instances
When CXDB-1 becomes reachable
Then the indicator returns to "CXDB OK"
  And CXDB-1's contexts are discovered and merged
```

### Scenario: CXDB becomes unreachable mid-session
```
Given the UI is showing live pipeline status from a CXDB instance
When that instance becomes unreachable
Then the next poll fails for that instance
  And the last known node status is preserved (not cleared)
When the instance becomes reachable again
Then the status overlay resumes with fresh data
```

### Scenario: Turn fetch fails for one context
```
Given a pipeline run is active across multiple contexts
  And one context returns a non-200 response when fetching turns (e.g., type registry missing)
When the UI polls CXDB
Then the failing context is skipped for that poll cycle
  And its last known node status remains visible
  And other contexts continue to update normally
```

### Scenario: All CXDB instances return empty context lists
```
Given all configured CXDB instances are running but have no contexts
When the UI polls
Then all nodes remain pending (gray)
```

### Scenario: CQL support flag resets on CXDB instance reconnection
```
Given a CXDB instance initially runs an older version without CQL support
  And the UI's CQL search to that instance returned 404
  And the UI is using the context list fallback for that instance
When the CXDB instance becomes unreachable
  And then reconnects after being upgraded to a CQL-supporting version
Then the UI resets the cqlSupported flag for that instance
  And retries CQL search on the next poll cycle
  And discovers CQL is now supported
  And subsequent polls use CQL search instead of the fallback
```

### Scenario: cqlSupported flag resets on reconnection even when instance had no CQL
```
Given a CXDB instance without CQL support (GET /v1/contexts/search returns 404)
  And the UI has set cqlSupported[0] to false for that instance
  And the UI is using the context list fallback
When the CXDB instance becomes unreachable (returns 502) for one poll cycle
  And then reconnects (returns a non-502 response) on the next poll cycle
Then the UI resets cqlSupported[0] to undefined (not false)
  And retries CQL search on the first poll cycle after reconnection
  And the CQL search again returns 404 (instance still lacks CQL)
  And the UI sets cqlSupported[0] back to false
  And falls back to the context list endpoint for that poll cycle
  And discovery continues normally without interruption
```

### Scenario: CXDB downgrades and CQL becomes unavailable mid-session
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

### Scenario: Fallback discovery does not permanently blacklist contexts with null client_tag
```
Given a CXDB instance without CQL support (GET /v1/contexts/search returns 404)
  And the UI is using the context list fallback for that instance
  And CXDB contains a context whose Kilroy session has just disconnected
  And the context list returns that context with client_tag: null
    (because context_to_json's session fallback is no longer available)
When the UI runs pipeline discovery
Then the context with null client_tag is left unmapped (no knownMappings entry)
  And no null mapping is cached for that context
  And the context is retried on the next poll cycle
When the Kilroy session reconnects to CXDB for a new run on the same context
  And the context list now returns client_tag: "kilroy/01KJ7..."
Then the UI proceeds with Phase 2 (fetchFirstTurn) for that context
  And the context is correctly mapped to its pipeline
```

### Scenario: Fallback discovery finds completed run after session disconnect on legacy CXDB
```
Given CXDB lacks CQL support (GET /v1/contexts/search returns 404)
  And the UI is using the context list fallback for that instance
  And a Kilroy run has completed and its session has disconnected
  And the context now appears in GET /v1/contexts with client_tag: null and is_live: false
  And the context has NOT been previously cached in knownMappings
When the UI polls for discovery
Then the context is enqueued in the null-tag backlog (up to NULL_TAG_BATCH_SIZE per cycle)
  And the UI fetches the first turn for that context via fetchFirstTurn
  And the first turn has declared_type "com.kilroy.attractor.RunStarted"
  And the UI decodes graph_name and run_id from the msgpack payload
  And the context is mapped to the correct pipeline tab in knownMappings
  And the status overlay shows the run's final state (e.g., completed or failed nodes)
```

### Scenario: CQL-empty supplemental discovery handles null client_tag after session disconnect
```
Given CXDB supports CQL search but Kilroy contexts omit key 30 metadata
  And GET /v1/contexts/search?q=tag ^= "kilroy/" returns 200 with contexts: []
  And the supplemental GET /v1/contexts?limit=10000 returns a completed Kilroy context with client_tag: null and is_live: false
  And the context has NOT been previously cached in knownMappings
When the UI polls for discovery
Then the context is collected into supplementalNullTagCandidates during the supplemental fetch
  And it is merged into nullTagCandidates despite cqlSupported being true
  And fetchFirstTurn is invoked for that context (up to NULL_TAG_BATCH_SIZE per cycle)
  And the first turn has declared_type "com.kilroy.attractor.RunStarted"
  And the UI decodes graph_name and run_id from the msgpack payload
  And the context is mapped to the correct pipeline tab in knownMappings
  And the status overlay shows the completed run's status
```

### Scenario: Null-tag backlog does not starve older contexts when more than NULL_TAG_BATCH_SIZE candidates exist
```
Given CXDB lacks CQL support (GET /v1/contexts/search returns 404)
  And the UI is using the context list fallback for that instance
  And six completed Kilroy runs have disconnected their sessions
  And all six contexts appear in GET /v1/contexts with client_tag: null and is_live: false
  And the five highest-context_id runs are already cached in knownMappings (positive mappings)
  And the sixth (oldest, lowest context_id) context has NOT been previously cached
When the UI polls for discovery
Then the six null-tag contexts are sorted by descending context_id
  And the five already-cached contexts are each skipped with CONTINUE (not counted toward the batch limit)
  And the uncached sixth context is reached and fetchFirstTurn is invoked for it
  And the batch limit counter reaches 1 (not 0) only after that fetch
  And the sixth context is successfully mapped to its pipeline in knownMappings
```

### Scenario: Supplemental fetch collects null-tag contexts even when CQL returns non-empty results
```
Given CXDB supports CQL search and Kilroy has partially upgraded to emit key 30 metadata
  And GET /v1/contexts/search?q=tag ^= "kilroy/" returns 200 with one modern context (client_tag: "kilroy/01NEW...")
  And GET /v1/contexts?limit=10000 returns both the modern context and a legacy context with client_tag: null and is_live: false
  And the legacy context has NOT been previously cached in knownMappings
When the UI polls for discovery
Then the supplemental context list fetch runs despite CQL returning a non-empty result
  And the legacy null-tag context is collected into supplementalNullTagCandidates
  And it is merged into nullTagCandidates and processed by the null-tag backlog
  And fetchFirstTurn is invoked for the legacy context
  And the legacy context is successfully mapped to its pipeline in knownMappings
  And the modern context (found via CQL) is NOT duplicated in the contexts list
```

### Scenario: CQL returns one context, supplemental finds another active Kilroy context absent from CQL
```
Given CXDB supports CQL search
  And GET /v1/contexts/search?q=tag ^= "kilroy/" returns 200 with one context (context_id: "10", client_tag: "kilroy/01NEW...")
  And GET /v1/contexts?limit=10000 returns context_id "10" plus context_id "7" with client_tag: "kilroy/01OLD..." and is_live: true
  And context_id "7" has a non-null client_tag (resolved from the active session) but lacks key 30 metadata
  And neither context has been previously cached in knownMappings
When the UI polls for discovery
Then the supplemental context list fetch runs despite CQL returning a non-empty result
  And context_id "7" is identified as absent from CQL results (NOT in cqlContextIds)
  And context_id "7" is appended to contexts via the supplemental dedup merge
  And fetchFirstTurn is invoked for context_id "7" (Phase 2 discovery)
  And context_id "7" is successfully mapped to its pipeline in knownMappings
  And context_id "10" is NOT duplicated in the contexts list
  And both contexts are discovered in the same poll cycle
```

### Scenario: Live context only in supplemental response keeps liveness check true
```
Given CXDB supports CQL search
  And GET /v1/contexts/search?q=tag ^= "kilroy/" returns 200 with an empty contexts array
  And GET /v1/contexts?limit=10000 returns one context with client_tag: "kilroy/01RUN..." and is_live: true
  And the context has been previously cached in knownMappings (mapped to pipeline "alpha_pipeline")
When the UI runs checkPipelineLiveness for "alpha_pipeline"
Then cachedContextLists stores the supplemental context list (including the is_live: true context)
  And lookupContext finds the context with is_live: true
  And checkPipelineLiveness returns true
  And running nodes are NOT flipped to stale by applyStaleDetection
```

### Scenario: Fallback discovery still blacklists contexts with wrong-prefix client_tag
```
Given a CXDB instance without CQL support (GET /v1/contexts/search returns 404)
  And the UI is using the context list fallback for that instance
  And CXDB contains a context whose client_tag is "claude/abc123" (not "kilroy/" prefix)
When the UI runs pipeline discovery
Then the context is immediately cached as null (knownMappings[key] = null)
  And the context is NOT retried on subsequent polls
  And no fetchFirstTurn request is issued for that context
```

### Scenario: Pipeline discovery uses view=raw to survive unpublished type registry
```
Given a CXDB instance has a Kilroy pipeline context
  And the Kilroy type registry bundle has NOT yet been published to CXDB
  And GET /turns?view=typed for that context would return a 500 error (unknown types)
When the UI runs pipeline discovery (fetchFirstTurn)
Then the UI requests the first turn with view=raw (not view=typed)
  And the CXDB server returns the raw msgpack payload as bytes_b64
  And the UI decodes the msgpack payload client-side to extract graph_name and run_id
  And the context is successfully mapped to its pipeline
  And no discovery failure occurs due to the missing registry
```

### Scenario: Context exceeding MAX_PAGES pagination cap emits warning and defers discovery
```
Given a CXDB instance has a context whose head_depth exceeds 5000
  And the context has more than 5000 turns (requiring more than MAX_PAGES=50 pages of 100 turns each to reach depth=0)
  And the context has client_tag "kilroy/session-abc" (passes Phase 1 filter)
When the UI runs pipeline discovery for that context (fetchFirstTurn)
Then fetchFirstTurn issues exactly 50 paginated GET /turns requests (one per page, each with limit=100 and view=raw)
  And after exhausting MAX_PAGES without finding a turn at depth=0, returns null
  And the UI emits a warning log containing "discovery deferred" and the context ID
  And the context is NOT cached as a negative result (knownMappings entry is not set)
  And on the next poll cycle the context is retried (fetchFirstTurn is invoked again)
  And no pipeline tab shows the context in its status overlay
```

---

## Server

### Scenario: Start with single DOT file
```
Given Go is installed
When the user runs: go run ui/main.go --dot /path/to/pipeline.dot
Then the server starts on port 9030
  And prints "Kilroy Pipeline UI: http://127.0.0.1:9030"
  And serves the DOT file at /dots/pipeline.dot
```

### Scenario: Start with custom port and CXDB address
```
When the user runs: go run ui/main.go --dot pipeline.dot --port 9035 --cxdb http://10.0.0.5:9010
Then the server starts on port 9035
  And proxies CXDB requests to http://10.0.0.5:9010 at /api/cxdb/0/
```

### Scenario: Start with multiple CXDB instances
```
When the user runs: go run ui/main.go --dot a.dot --dot b.dot --cxdb http://127.0.0.1:9010 --cxdb http://127.0.0.1:9011
Then the server starts on port 9030
  And proxies /api/cxdb/0/* to http://127.0.0.1:9010
  And proxies /api/cxdb/1/* to http://127.0.0.1:9011
  And /api/cxdb/instances returns both URLs
```

### Scenario: No DOT file provided
```
When the user runs: go run ui/main.go
Then the server exits with a non-zero code
  And prints an error message with usage help
```

### Scenario: Unregistered DOT file requested
```
Given the server was started with --dot pipeline-a.dot
When a request is made to /dots/pipeline-b.dot
Then the server returns 404
```

### Scenario: Duplicate DOT basenames rejected
```
When the user runs: go run ui/main.go --dot pipelines/alpha/pipeline.dot --dot pipelines/beta/pipeline.dot
Then the server exits with a non-zero code
  And prints an error identifying the conflicting basename "pipeline.dot"
```

### Scenario: Duplicate graph IDs rejected
```
Given two DOT files with different basenames but both containing "digraph alpha_pipeline {"
When the user runs: go run ui/main.go --dot a.dot --dot b.dot
Then the server exits with a non-zero code
  And prints an error identifying the duplicate graph ID "alpha_pipeline"
```

### Scenario: Path traversal attempt
```
When a request is made to /dots/../../etc/passwd
Then the server returns 404 (filename not registered)
```

### Scenario: DOT file deleted after server startup returns 500
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

### Scenario: Anonymous graph rejected at server startup
```
Given a DOT file contains "digraph {" with no graph identifier
When the user runs: go run ui/main.go --dot /path/to/anonymous.dot
Then the server exits with a non-zero code
  And prints an error stating that named graphs are required for discovery
```
