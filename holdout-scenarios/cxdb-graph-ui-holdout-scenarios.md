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
Given the UI has rendered a pipeline graph
Then start nodes (shape=Mdiamond) display as diamonds
  And exit nodes (shape=Msquare) display as squares
  And LLM task nodes (shape=box) display as rectangles
  And conditional nodes (shape=diamond) display as diamonds
  And tool gate nodes (shape=parallelogram) display as parallelograms
  And human gate nodes (shape=hexagon) display as hexagons
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

### Scenario: Agent stuck in error loop
```
Given a pipeline run is active
  And the most recent 3+ turns on a node have is_error: true
When the UI polls CXDB
Then that node is colored red (error)
```

### Scenario: Pipeline completed successfully
```
Given a pipeline run completed with all nodes successful
When the UI polls CXDB
Then all traversed nodes are colored green (complete)
  And no node is pulsing
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

### Scenario: Second run of same pipeline while first run data exists
```
Given CXDB contains contexts from a completed run of alpha_pipeline (run_id A)
  And a new run of alpha_pipeline starts (run_id B)
  And run B has only completed the first two nodes
When the UI polls CXDB
Then only contexts with run_id B are used for the status overlay
  And nodes completed in run A but not yet reached in run B show as pending
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

### Scenario: Close detail panel
```
Given the detail panel is open
When the user clicks outside the panel or clicks the close button
Then the panel closes and the full graph area is restored
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

### Scenario: All CXDB instances return empty context lists
```
Given all configured CXDB instances are running but have no contexts
When the UI polls
Then all nodes remain pending (gray)
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

### Scenario: Path traversal attempt
```
When a request is made to /dots/../../etc/passwd
Then the server returns 404 (filename not registered)
```
