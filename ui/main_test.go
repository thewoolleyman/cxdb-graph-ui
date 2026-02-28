package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
)

// ─── helpers ────────────────────────────────────────────────────────────────

// writeDot writes content to a file named `name` inside dir and returns the
// absolute path.
func writeDot(t *testing.T, dir, name, content string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("writeDot: %v", err)
	}
	return path
}

// setupGlobals registers dot files for the duration of a test, restoring
// original state in t.Cleanup.
func setupGlobals(t *testing.T, dotFiles map[string]string, cxdbs []string) {
	t.Helper()
	dir := t.TempDir()

	origEntries := dotEntries
	origByName := dotsByName
	origCXDB := cxdbURLs

	dotEntries = nil
	dotsByName = make(map[string]string)

	for name, content := range dotFiles {
		path := writeDot(t, dir, name, content)
		dotEntries = append(dotEntries, dotEntry{name: name, path: path})
		dotsByName[name] = path
	}

	if cxdbs != nil {
		cxdbURLs = cxdbs
	} else {
		cxdbURLs = []string{"http://127.0.0.1:9110"}
	}

	t.Cleanup(func() {
		dotEntries = origEntries
		dotsByName = origByName
		cxdbURLs = origCXDB
	})
}

// get performs a GET request against the given handler and returns the recorder.
func get(t *testing.T, handler http.HandlerFunc, path string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	w := httptest.NewRecorder()
	handler(w, req)
	return w
}

// bodyString returns the response body as a string.
func bodyString(t *testing.T, w *httptest.ResponseRecorder) string {
	t.Helper()
	b, err := io.ReadAll(w.Result().Body)
	if err != nil {
		t.Fatalf("bodyString: %v", err)
	}
	return string(b)
}

// decodeJSON unmarshals the recorder body into v.
func decodeJSON(t *testing.T, w *httptest.ResponseRecorder, v interface{}) {
	t.Helper()
	if err := json.NewDecoder(w.Body).Decode(v); err != nil {
		t.Fatalf("decodeJSON: %v\nbody: %s", err, w.Body.String())
	}
}

// ptr returns a pointer to the given string.
func ptr(s string) *string { return &s }

// ─── /api/dots ──────────────────────────────────────────────────────────────

// Scenario: /api/dots returns list of registered dot filenames.
func TestAPIDots_ReturnsList(t *testing.T) {
	setupGlobals(t, map[string]string{
		"alpha.dot": `digraph alpha { a -> b }`,
		"beta.dot":  `digraph beta  { x -> y }`,
	}, nil)

	w := get(t, handleAPIDots, "/api/dots")
	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", w.Code)
	}

	var resp struct {
		Dots []string `json:"dots"`
	}
	decodeJSON(t, w, &resp)

	got := append([]string(nil), resp.Dots...)
	sort.Strings(got)
	want := []string{"alpha.dot", "beta.dot"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("dots = %v, want %v", got, want)
	}
}

// Scenario: /api/dots preserves --dot flag order.
func TestAPIDots_PreservesOrder(t *testing.T) {
	dir := t.TempDir()

	origEntries := dotEntries
	origByName := dotsByName
	origCXDB := cxdbURLs
	t.Cleanup(func() {
		dotEntries = origEntries
		dotsByName = origByName
		cxdbURLs = origCXDB
	})

	// Register b.dot first, then a.dot — order must be preserved.
	dotEntries = nil
	dotsByName = make(map[string]string)
	cxdbURLs = []string{"http://127.0.0.1:9110"}
	for _, name := range []string{"b.dot", "a.dot"} {
		path := writeDot(t, dir, name, `digraph `+strings.TrimSuffix(name, ".dot")+` {}`)
		dotEntries = append(dotEntries, dotEntry{name: name, path: path})
		dotsByName[name] = path
	}

	w := get(t, handleAPIDots, "/api/dots")
	var resp struct {
		Dots []string `json:"dots"`
	}
	decodeJSON(t, w, &resp)

	if len(resp.Dots) != 2 || resp.Dots[0] != "b.dot" || resp.Dots[1] != "a.dot" {
		t.Fatalf("want [b.dot a.dot], got %v", resp.Dots)
	}
}

// ─── /dots/{name} raw ───────────────────────────────────────────────────────

// Scenario: GET /dots/{name} serves the raw DOT file content.
func TestDots_RawContent(t *testing.T) {
	content := "digraph mypipeline {\n  a -> b\n}\n"
	setupGlobals(t, map[string]string{"pipeline.dot": content}, nil)

	w := get(t, handleDots, "/dots/pipeline.dot")
	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", w.Code)
	}
	if got := bodyString(t, w); got != content {
		t.Fatalf("body mismatch:\ngot:  %q\nwant: %q", got, content)
	}
	ct := w.Result().Header.Get("Content-Type")
	if !strings.HasPrefix(ct, "text/plain") {
		t.Fatalf("Content-Type want text/plain, got %q", ct)
	}
}

// Scenario: GET /dots/{unknown} returns 404.
func TestDots_UnknownName_404(t *testing.T) {
	setupGlobals(t, map[string]string{
		"real.dot": "digraph real {}",
	}, nil)

	w := get(t, handleDots, "/dots/nonexistent.dot")
	if w.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d", w.Code)
	}
}

// ─── /dots/{name}/nodes ─────────────────────────────────────────────────────

// Scenario: /nodes returns parsed node attributes.
func TestDots_Nodes_BasicAttrs(t *testing.T) {
	dot := `digraph pipeline {
		start  [shape=Mdiamond]
		task   [shape=box, class="llm_task", prompt="do the thing"]
		cond   [shape=diamond]
		finish [shape=Msquare]
	}`
	setupGlobals(t, map[string]string{"p.dot": dot}, nil)

	w := get(t, handleDots, "/dots/p.dot/nodes")
	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", w.Code)
	}

	var nodes map[string]*nodeAttrs
	decodeJSON(t, w, &nodes)

	checkShape := func(id, want string) {
		t.Helper()
		n, ok := nodes[id]
		if !ok {
			t.Errorf("node %q not found in response", id)
			return
		}
		if n.Shape == nil || *n.Shape != want {
			t.Errorf("node %q shape: got %v, want %q", id, n.Shape, want)
		}
	}

	checkShape("start", "Mdiamond")
	checkShape("task", "box")
	checkShape("cond", "diamond")
	checkShape("finish", "Msquare")

	if nodes["task"].Class == nil || *nodes["task"].Class != "llm_task" {
		t.Errorf("task class: got %v, want llm_task", nodes["task"].Class)
	}
	if nodes["task"].Prompt == nil || *nodes["task"].Prompt != "do the thing" {
		t.Errorf("task prompt: got %v, want 'do the thing'", nodes["task"].Prompt)
	}
}

// Scenario: Quoted node IDs normalize correctly (quotes stripped from key).
func TestDots_Nodes_QuotedIDs(t *testing.T) {
	dot := `digraph pipeline {
		"review step" [shape=box, prompt="Review the implementation"]
	}`
	setupGlobals(t, map[string]string{"p.dot": dot}, nil)

	w := get(t, handleDots, "/dots/p.dot/nodes")
	var nodes map[string]*nodeAttrs
	decodeJSON(t, w, &nodes)

	n, ok := nodes["review step"]
	if !ok {
		t.Fatalf("node 'review step' not found; got keys: %v", nodeKeys(nodes))
	}
	if n.Shape == nil || *n.Shape != "box" {
		t.Errorf("shape: got %v, want box", n.Shape)
	}
}

// Scenario: Nodes inside subgraphs are included in /nodes response.
func TestDots_Nodes_Subgraphs(t *testing.T) {
	dot := `digraph pipeline {
		subgraph cluster_a { a [shape=box] }
		subgraph cluster_b { b [shape=diamond] }
	}`
	setupGlobals(t, map[string]string{"p.dot": dot}, nil)

	w := get(t, handleDots, "/dots/p.dot/nodes")
	var nodes map[string]*nodeAttrs
	decodeJSON(t, w, &nodes)

	if _, ok := nodes["a"]; !ok {
		t.Errorf("node 'a' not found in subgraph; got: %v", nodeKeys(nodes))
	}
	if _, ok := nodes["b"]; !ok {
		t.Errorf("node 'b' not found in subgraph; got: %v", nodeKeys(nodes))
	}
	if nodes["a"] != nil && nodes["a"].Shape != nil && *nodes["a"].Shape != "box" {
		t.Errorf("a shape: want box, got %v", nodes["a"].Shape)
	}
	if nodes["b"] != nil && nodes["b"].Shape != nil && *nodes["b"].Shape != "diamond" {
		t.Errorf("b shape: want diamond, got %v", nodes["b"].Shape)
	}
}

// Scenario: DOT attribute concatenation via + is resolved in /nodes response.
func TestDots_Nodes_AttrConcatenation(t *testing.T) {
	dot := `digraph pipeline {
		task [shape=box, prompt="first " + "second"]
	}`
	setupGlobals(t, map[string]string{"p.dot": dot}, nil)

	w := get(t, handleDots, "/dots/p.dot/nodes")
	var nodes map[string]*nodeAttrs
	decodeJSON(t, w, &nodes)

	n, ok := nodes["task"]
	if !ok {
		t.Fatal("node 'task' not found")
	}
	if n.Prompt == nil || *n.Prompt != "first second" {
		t.Errorf("prompt: got %v, want 'first second'", n.Prompt)
	}
}

// Scenario: DOT parse error on /nodes returns 400 with JSON error body.
func TestDots_Nodes_ParseError_400(t *testing.T) {
	dot := `digraph pipeline { /* unterminated block comment`
	setupGlobals(t, map[string]string{"p.dot": dot}, nil)

	w := get(t, handleDots, "/dots/p.dot/nodes")
	if w.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d; body: %s", w.Code, w.Body.String())
	}

	var resp map[string]string
	decodeJSON(t, w, &resp)
	if !strings.Contains(resp["error"], "DOT parse error") {
		t.Errorf("error body: got %q, want 'DOT parse error'", resp["error"])
	}
}

// Scenario: Unterminated string literal in DOT returns 400.
func TestDots_Nodes_UnterminatedString_400(t *testing.T) {
	dot := `digraph pipeline { task [shape="unterminated`
	setupGlobals(t, map[string]string{"p.dot": dot}, nil)

	w := get(t, handleDots, "/dots/p.dot/nodes")
	if w.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d", w.Code)
	}
}

// Scenario: DOT with line/block comments parses correctly; URL in quoted string preserved.
func TestDots_Nodes_CommentsStripped(t *testing.T) {
	dot := `digraph pipeline {
		// This is a line comment
		/* This is a
		   block comment */
		task [shape=box, prompt="check http://example.com"]
		// another comment
	}`
	setupGlobals(t, map[string]string{"p.dot": dot}, nil)

	w := get(t, handleDots, "/dots/p.dot/nodes")
	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d; body: %s", w.Code, w.Body.String())
	}

	var nodes map[string]*nodeAttrs
	decodeJSON(t, w, &nodes)

	n, ok := nodes["task"]
	if !ok {
		t.Fatal("node 'task' not found after comment stripping")
	}
	if n.Prompt == nil || *n.Prompt != "check http://example.com" {
		t.Errorf("URL in quoted value should be preserved, got %v", n.Prompt)
	}
}

// Scenario: All Kilroy node attribute fields are parsed and returned.
func TestDots_Nodes_AllFields(t *testing.T) {
	dot := `digraph pipeline {
		gate [shape=hexagon, question="Ready?", goal_gate="goal achieved"]
		tool [shape=parallelogram, tool_command="run_tests", class="tool_gate"]
	}`
	setupGlobals(t, map[string]string{"p.dot": dot}, nil)

	w := get(t, handleDots, "/dots/p.dot/nodes")
	var nodes map[string]*nodeAttrs
	decodeJSON(t, w, &nodes)

	gate := nodes["gate"]
	if gate == nil {
		t.Fatal("node 'gate' not found")
	}
	if gate.Question == nil || *gate.Question != "Ready?" {
		t.Errorf("question: got %v, want 'Ready?'", gate.Question)
	}
	if gate.GoalGate == nil || *gate.GoalGate != "goal achieved" {
		t.Errorf("goal_gate: got %v, want 'goal achieved'", gate.GoalGate)
	}

	tool := nodes["tool"]
	if tool == nil {
		t.Fatal("node 'tool' not found")
	}
	if tool.ToolCommand == nil || *tool.ToolCommand != "run_tests" {
		t.Errorf("tool_command: got %v, want 'run_tests'", tool.ToolCommand)
	}
	if tool.Class == nil || *tool.Class != "tool_gate" {
		t.Errorf("class: got %v, want 'tool_gate'", tool.Class)
	}
}

// ─── /dots/{name}/edges ─────────────────────────────────────────────────────

// Scenario: /edges returns basic edge list.
func TestDots_Edges_Basic(t *testing.T) {
	dot := `digraph pipeline {
		a -> b
		b -> c [label="next"]
	}`
	setupGlobals(t, map[string]string{"p.dot": dot}, nil)

	w := get(t, handleDots, "/dots/p.dot/edges")
	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", w.Code)
	}

	var edges []edge
	decodeJSON(t, w, &edges)

	if len(edges) != 2 {
		t.Fatalf("want 2 edges, got %d: %v", len(edges), edges)
	}

	findEdge := func(src, tgt string) *edge {
		for i := range edges {
			if edges[i].Source == src && edges[i].Target == tgt {
				return &edges[i]
			}
		}
		return nil
	}

	if e := findEdge("a", "b"); e == nil {
		t.Error("edge (a, b) not found")
	}
	if e := findEdge("b", "c"); e == nil {
		t.Error("edge (b, c) not found")
	} else if e.Label == nil || *e.Label != "next" {
		t.Errorf("edge (b,c) label: got %v, want 'next'", e.Label)
	}
}

// Scenario: Edge chain a -> b -> c [label="x"] expands to two edges.
func TestDots_Edges_ChainExpansion(t *testing.T) {
	dot := `digraph pipeline {
		a -> b -> c [label="x"]
	}`
	setupGlobals(t, map[string]string{"p.dot": dot}, nil)

	w := get(t, handleDots, "/dots/p.dot/edges")
	var edges []edge
	decodeJSON(t, w, &edges)

	if len(edges) != 2 {
		t.Fatalf("want 2 edges from chain, got %d: %v", len(edges), edges)
	}

	// Both edges should carry the label "x"
	for _, e := range edges {
		if e.Label == nil || *e.Label != "x" {
			t.Errorf("edge (%s→%s) label: got %v, want 'x'", e.Source, e.Target, e.Label)
		}
	}

	// Should be (a,b) and (b,c), not (a,c)
	findEdge := func(src, tgt string) bool {
		for _, e := range edges {
			if e.Source == src && e.Target == tgt {
				return true
			}
		}
		return false
	}

	if !findEdge("a", "b") {
		t.Error("missing edge (a, b)")
	}
	if !findEdge("b", "c") {
		t.Error("missing edge (b, c)")
	}
	if findEdge("a", "c") {
		t.Error("spurious edge (a, c) — chain not properly expanded")
	}
}

// Scenario: Port suffixes stripped from edge node IDs.
func TestDots_Edges_PortStripping(t *testing.T) {
	dot := `digraph pipeline {
		a:out -> b:in
	}`
	setupGlobals(t, map[string]string{"p.dot": dot}, nil)

	w := get(t, handleDots, "/dots/p.dot/edges")
	var edges []edge
	decodeJSON(t, w, &edges)

	if len(edges) != 1 {
		t.Fatalf("want 1 edge, got %d", len(edges))
	}
	e := edges[0]
	if e.Source != "a" {
		t.Errorf("source: got %q, want 'a'", e.Source)
	}
	if e.Target != "b" {
		t.Errorf("target: got %q, want 'b'", e.Target)
	}
	if e.Label != nil {
		t.Errorf("label: got %v, want nil", e.Label)
	}
}

// Scenario: Quoted node IDs in edges normalize correctly.
func TestDots_Edges_QuotedNodeIDs(t *testing.T) {
	dot := `digraph pipeline {
		"review step" -> done [label="pass"]
	}`
	setupGlobals(t, map[string]string{"p.dot": dot}, nil)

	w := get(t, handleDots, "/dots/p.dot/edges")
	var edges []edge
	decodeJSON(t, w, &edges)

	if len(edges) != 1 {
		t.Fatalf("want 1 edge, got %d: %v", len(edges), edges)
	}
	e := edges[0]
	if e.Source != "review step" {
		t.Errorf("source: got %q, want 'review step'", e.Source)
	}
	if e.Target != "done" {
		t.Errorf("target: got %q, want 'done'", e.Target)
	}
	if e.Label == nil || *e.Label != "pass" {
		t.Errorf("label: got %v, want 'pass'", e.Label)
	}
}

// Scenario: Edges inside subgraphs are included in /edges response.
func TestDots_Edges_Subgraphs(t *testing.T) {
	dot := `digraph pipeline {
		subgraph cluster_a { a [shape=box] }
		subgraph cluster_b { b [shape=diamond] }
		a -> b [label="go"]
	}`
	setupGlobals(t, map[string]string{"p.dot": dot}, nil)

	w := get(t, handleDots, "/dots/p.dot/edges")
	var edges []edge
	decodeJSON(t, w, &edges)

	found := false
	for _, e := range edges {
		if e.Source == "a" && e.Target == "b" {
			found = true
			if e.Label == nil || *e.Label != "go" {
				t.Errorf("label: got %v, want 'go'", e.Label)
			}
		}
	}
	if !found {
		t.Errorf("edge (a, b) not found; got: %v", edges)
	}
}

// Scenario: /edges returns 400 on DOT parse error.
func TestDots_Edges_ParseError_400(t *testing.T) {
	dot := `digraph pipeline { /* unterminated`
	setupGlobals(t, map[string]string{"p.dot": dot}, nil)

	w := get(t, handleDots, "/dots/p.dot/edges")
	if w.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d", w.Code)
	}
	var resp map[string]string
	decodeJSON(t, w, &resp)
	if !strings.Contains(resp["error"], "DOT parse error") {
		t.Errorf("error body: got %q", resp["error"])
	}
}

// ─── /api/cxdb/instances ────────────────────────────────────────────────────

// Scenario: /api/cxdb/instances returns configured CXDB URLs.
func TestAPICXDB_Instances(t *testing.T) {
	setupGlobals(t, map[string]string{"p.dot": "digraph x {}"}, []string{
		"http://127.0.0.1:9110",
		"http://127.0.0.1:9111",
	})

	req := httptest.NewRequest(http.MethodGet, "/api/cxdb/instances", nil)
	w := httptest.NewRecorder()
	handleAPICXDB(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", w.Code)
	}

	var resp struct {
		Instances []string `json:"instances"`
	}
	decodeJSON(t, w, &resp)

	want := []string{"http://127.0.0.1:9110", "http://127.0.0.1:9111"}
	if !reflect.DeepEqual(resp.Instances, want) {
		t.Errorf("instances: got %v, want %v", resp.Instances, want)
	}
}

// Scenario: /api/cxdb/{index}/... proxies to the correct CXDB instance.
func TestAPICXDB_Proxy(t *testing.T) {
	// Spin up a fake CXDB backend.
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"ok":true,"path":"` + r.URL.Path + `"}`))
	}))
	t.Cleanup(backend.Close)

	setupGlobals(t, map[string]string{"p.dot": "digraph x {}"}, []string{backend.URL})

	req := httptest.NewRequest(http.MethodGet, "/api/cxdb/0/v1/contexts", nil)
	w := httptest.NewRecorder()
	handleAPICXDB(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d; body: %s", w.Code, w.Body.String())
	}

	var resp map[string]interface{}
	decodeJSON(t, w, &resp)
	if resp["ok"] != true {
		t.Errorf("proxy response missing ok=true: %v", resp)
	}
}

// Scenario: /api/cxdb/{bad-index}/... returns 404.
func TestAPICXDB_BadIndex_404(t *testing.T) {
	setupGlobals(t, map[string]string{"p.dot": "digraph x {}"}, []string{"http://127.0.0.1:9110"})

	req := httptest.NewRequest(http.MethodGet, "/api/cxdb/99/v1/contexts", nil)
	w := httptest.NewRecorder()
	handleAPICXDB(w, req)

	if w.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d", w.Code)
	}
}

// ─── extractGraphID ──────────────────────────────────────────────────────────

func TestExtractGraphID(t *testing.T) {
	cases := []struct {
		name    string
		src     string
		want    string
		wantErr bool
	}{
		{
			name: "simple unquoted id",
			src:  `digraph alpha_pipeline { a -> b }`,
			want: "alpha_pipeline",
		},
		{
			name: "quoted id",
			src:  `digraph "my pipeline" { }`,
			want: "my pipeline",
		},
		{
			name: "quoted id with escape",
			src:  `digraph "my \"quoted\" pipeline" { }`,
			want: `my "quoted" pipeline`,
		},
		{
			name: "strict digraph",
			src:  `strict digraph mypipe { }`,
			want: "mypipe",
		},
		{
			name: "graph (undirected)",
			src:  `graph mygraph { }`,
			want: "mygraph",
		},
		{
			name:    "no id (anonymous)",
			src:     `digraph { a -> b }`,
			wantErr: true,
		},
		{
			name: "id after line comment",
			src:  "// comment\ndigraph pipeline { }",
			want: "pipeline",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := extractGraphID(tc.src)
			if tc.wantErr {
				if err == nil {
					t.Fatalf("want error, got %q", got)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
		})
	}
}

// ─── stripComments ───────────────────────────────────────────────────────────

func TestStripComments(t *testing.T) {
	cases := []struct {
		name    string
		src     string
		want    string
		wantErr bool
	}{
		{
			name: "line comment removed",
			src:  "a // comment\nb",
			want: "a \nb",
		},
		{
			name: "block comment removed",
			src:  "a /* block */ b",
			want: "a  b",
		},
		{
			name: "url in quoted string preserved",
			src:  `prompt="http://example.com"`,
			want: `prompt="http://example.com"`,
		},
		{
			name: "double-slash inside quoted string preserved",
			src:  `x="a // not a comment"`,
			want: `x="a // not a comment"`,
		},
		{
			name:    "unterminated block comment → error",
			src:     "a /* no close",
			wantErr: true,
		},
		{
			name:    "unterminated string → error",
			src:     `a "unterminated`,
			wantErr: true,
		},
		{
			name: "newline preserved after line comment",
			src:  "a // comment\nb",
			want: "a \nb",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := stripComments(tc.src)
			if tc.wantErr {
				if err == nil {
					t.Fatalf("want error, got %q", got)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
		})
	}
}

// ─── parseNodes unit tests ───────────────────────────────────────────────────

func TestParseNodes_MultilinePrompt(t *testing.T) {
	dot := "digraph p {\n\ttask [shape=box, prompt=\"line1\nline2\"]\n}"
	nodes, err := parseNodes(dot)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	n, ok := nodes["task"]
	if !ok {
		t.Fatal("task not found")
	}
	if n.Prompt == nil || !strings.Contains(*n.Prompt, "\n") {
		t.Errorf("multiline prompt not preserved: %v", n.Prompt)
	}
}

// ─── parseEdges unit tests ───────────────────────────────────────────────────

func TestParseEdges_LongChain(t *testing.T) {
	dot := `digraph p { a -> b -> c -> d }`
	edges, err := parseEdges(dot)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(edges) != 3 {
		t.Fatalf("want 3 edges, got %d: %v", len(edges), edges)
	}
}

func TestParseEdges_NoLabel(t *testing.T) {
	dot := `digraph p { a -> b }`
	edges, err := parseEdges(dot)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(edges) != 1 {
		t.Fatalf("want 1 edge, got %d", len(edges))
	}
	if edges[0].Label != nil {
		t.Errorf("label should be nil for unlabelled edge, got %v", edges[0].Label)
	}
}

// ─── integration: GET / ──────────────────────────────────────────────────────

func TestRoot_ServesHTML(t *testing.T) {
	setupGlobals(t, map[string]string{"p.dot": "digraph x {}"}, nil)

	w := get(t, handleRoot, "/")
	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", w.Code)
	}
	ct := w.Result().Header.Get("Content-Type")
	if !strings.HasPrefix(ct, "text/html") {
		t.Errorf("Content-Type: want text/html, got %q", ct)
	}
}

func TestRoot_NonRoot_404(t *testing.T) {
	setupGlobals(t, map[string]string{"p.dot": "digraph x {}"}, nil)

	w := get(t, handleRoot, "/notroot")
	if w.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d", w.Code)
	}
}

// ─── helpers ─────────────────────────────────────────────────────────────────

func nodeKeys(m map[string]*nodeAttrs) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
