package main

import (
	_ "embed"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

//go:embed index.html
var indexHTML []byte

// multiFlag allows a flag to be specified multiple times.
type multiFlag []string

func (m *multiFlag) String() string {
	return strings.Join(*m, ", ")
}

func (m *multiFlag) Set(v string) error {
	*m = append(*m, v)
	return nil
}

// dotEntry holds a registered DOT file.
type dotEntry struct {
	name string // base filename
	path string // absolute path
}

// nodeAttrs holds parsed node attributes.
type nodeAttrs struct {
	Shape       *string `json:"shape"`
	Class       *string `json:"class"`
	Prompt      *string `json:"prompt"`
	ToolCommand *string `json:"tool_command"`
	Question    *string `json:"question"`
	GoalGate    *string `json:"goal_gate"`
}

// edge holds a parsed edge.
type edge struct {
	Source string  `json:"source"`
	Target string  `json:"target"`
	Label  *string `json:"label"`
}

var (
	dotEntries   []dotEntry
	dotsByName   map[string]string // name -> path
	cxdbURLs     []string
	graphIDRegex = regexp.MustCompile(`(?m)^\s*(strict\s+)?(di)?graph\s+("(?:[^"\\]|\\.)*"|\w+)`)
)

func main() {
	var port int
	var cxdbFlags multiFlag
	var dotFlags multiFlag

	flag.IntVar(&port, "port", 9030, "TCP port for the UI server")
	flag.Var(&cxdbFlags, "cxdb", "CXDB HTTP API base URL (repeatable)")
	flag.Var(&dotFlags, "dot", "Path to a pipeline DOT file (repeatable, required)")
	flag.Parse()

	if len(dotFlags) == 0 {
		fmt.Fprintf(os.Stderr, "Error: at least one --dot flag is required\n\n")
		flag.Usage()
		os.Exit(1)
	}

	if len(cxdbFlags) == 0 {
		cxdbURLs = []string{"http://127.0.0.1:9110"}
	} else {
		cxdbURLs = []string(cxdbFlags)
	}

	// Build dot entries, check for duplicate base filenames.
	dotsByName = make(map[string]string)
	nameToPath := make(map[string]string) // name -> first seen path (for error msgs)
	for _, p := range dotFlags {
		abs, err := filepath.Abs(p)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error resolving path %q: %v\n", p, err)
			os.Exit(1)
		}
		name := filepath.Base(abs)
		if existing, ok := nameToPath[name]; ok {
			fmt.Fprintf(os.Stderr, "Error: duplicate DOT base filename %q from %q and %q\n", name, existing, abs)
			os.Exit(1)
		}
		nameToPath[name] = abs
		dotEntries = append(dotEntries, dotEntry{name: name, path: abs})
		dotsByName[name] = abs
	}

	// Check for duplicate graph IDs across registered DOT files.
	graphIDToPath := make(map[string]string) // normalized graph ID -> path
	for _, entry := range dotEntries {
		data, err := os.ReadFile(entry.path)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading DOT file %q: %v\n", entry.path, err)
			os.Exit(1)
		}
		gid, err := extractGraphID(string(data))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: DOT file %q: %v\n", entry.path, err)
			os.Exit(1)
		}
		if existing, ok := graphIDToPath[gid]; ok {
			fmt.Fprintf(os.Stderr, "Error: duplicate graph ID %q in %q and %q\n", gid, existing, entry.path)
			os.Exit(1)
		}
		graphIDToPath[gid] = entry.path
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", handleRoot)
	mux.HandleFunc("/dots/", handleDots)
	mux.HandleFunc("/api/dots", handleAPIDots)
	mux.HandleFunc("/api/cxdb/", handleAPICXDB)

	addr := fmt.Sprintf("0.0.0.0:%d", port)
	fmt.Printf("Kilroy Pipeline UI: http://127.0.0.1:%d\n", port)
	if err := http.ListenAndServe(addr, mux); err != nil {
		fmt.Fprintf(os.Stderr, "Server error: %v\n", err)
		os.Exit(1)
	}
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write(indexHTML)
}

func handleAPIDots(w http.ResponseWriter, r *http.Request) {
	names := make([]string, len(dotEntries))
	for i, e := range dotEntries {
		names[i] = e.name
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"dots": names})
}

func handleAPICXDB(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path // e.g. /api/cxdb/instances or /api/cxdb/0/v1/contexts

	// /api/cxdb/instances
	if path == "/api/cxdb/instances" {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{"instances": cxdbURLs})
		return
	}

	// /api/cxdb/{index}/...
	// Strip /api/cxdb/ prefix
	rest := strings.TrimPrefix(path, "/api/cxdb/")
	// rest should be "{index}/..." or "{index}"
	slashIdx := strings.Index(rest, "/")
	var indexStr, subPath string
	if slashIdx < 0 {
		indexStr = rest
		subPath = "/"
	} else {
		indexStr = rest[:slashIdx]
		subPath = rest[slashIdx:] // includes leading /
	}

	// Parse index
	var idx int
	if _, err := fmt.Sscanf(indexStr, "%d", &idx); err != nil || idx < 0 || idx >= len(cxdbURLs) {
		http.NotFound(w, r)
		return
	}

	// Forward to CXDB
	target := cxdbURLs[idx]
	targetURL, err := url.Parse(target)
	if err != nil {
		http.Error(w, "Bad CXDB URL", http.StatusInternalServerError)
		return
	}

	proxyURL := *targetURL
	proxyURL.Path = strings.TrimRight(targetURL.Path, "/") + subPath
	proxyURL.RawQuery = r.URL.RawQuery

	proxyReq, err := http.NewRequestWithContext(r.Context(), r.Method, proxyURL.String(), r.Body)
	if err != nil {
		http.Error(w, "Failed to create proxy request", http.StatusBadGateway)
		return
	}
	// Copy headers
	for k, vv := range r.Header {
		for _, v := range vv {
			proxyReq.Header.Add(k, v)
		}
	}

	client := &http.Client{}
	resp, err := client.Do(proxyReq)
	if err != nil {
		http.Error(w, "CXDB unreachable: "+err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	// Copy response headers
	for k, vv := range resp.Header {
		for _, v := range vv {
			w.Header().Add(k, v)
		}
	}
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

func handleDots(w http.ResponseWriter, r *http.Request) {
	// Path: /dots/{name} or /dots/{name}/nodes or /dots/{name}/edges
	rest := strings.TrimPrefix(r.URL.Path, "/dots/")
	// rest = "{name}" or "{name}/nodes" or "{name}/edges"
	parts := strings.SplitN(rest, "/", 2)
	name := parts[0]
	var suffix string
	if len(parts) == 2 {
		suffix = parts[1]
	}

	dotPath, ok := dotsByName[name]
	if !ok {
		http.NotFound(w, r)
		return
	}

	data, err := os.ReadFile(dotPath)
	if err != nil {
		http.Error(w, "Failed to read DOT file: "+err.Error(), http.StatusInternalServerError)
		return
	}
	dotSrc := string(data)

	switch suffix {
	case "":
		// Serve raw DOT file
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Write(data)
	case "nodes":
		// Parse and return node attributes as JSON
		nodes, err := parseNodes(dotSrc)
		if err != nil {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(map[string]string{"error": "DOT parse error: " + err.Error()})
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(nodes)
	case "edges":
		// Parse and return edge list as JSON
		edges, err := parseEdges(dotSrc)
		if err != nil {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(map[string]string{"error": "DOT parse error: " + err.Error()})
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(edges)
	default:
		http.NotFound(w, r)
	}
}

// extractGraphID extracts and normalizes the graph ID from DOT source.
// Returns an error if no named graph is found.
func extractGraphID(src string) (string, error) {
	stripped, err := stripComments(src)
	if err != nil {
		return "", err
	}
	m := graphIDRegex.FindStringSubmatch(stripped)
	if m == nil {
		return "", fmt.Errorf("no named graph found (anonymous graphs are not supported)")
	}
	id := m[3]
	return normalizeID(id), nil
}

// normalizeID strips outer quotes and unescapes a DOT identifier.
func normalizeID(id string) string {
	id = strings.TrimSpace(id)
	if len(id) >= 2 && id[0] == '"' && id[len(id)-1] == '"' {
		id = id[1 : len(id)-1]
		id = unescapeDotString(id)
	}
	return id
}

// unescapeDotString handles DOT escape sequences inside a quoted string.
func unescapeDotString(s string) string {
	var sb strings.Builder
	i := 0
	for i < len(s) {
		if s[i] == '\\' && i+1 < len(s) {
			switch s[i+1] {
			case '"':
				sb.WriteByte('"')
			case '\\':
				sb.WriteByte('\\')
			case 'n':
				sb.WriteByte('\n')
			default:
				sb.WriteByte('\\')
				sb.WriteByte(s[i+1])
			}
			i += 2
		} else {
			sb.WriteByte(s[i])
			i++
		}
	}
	return sb.String()
}

// stripComments removes DOT // line comments and /* */ block comments,
// being careful not to strip comment syntax inside quoted strings.
func stripComments(src string) (string, error) {
	var out strings.Builder
	i := 0
	for i < len(src) {
		// Inside a quoted string?
		if src[i] == '"' {
			out.WriteByte('"')
			i++
			for {
				if i >= len(src) {
					return "", fmt.Errorf("unterminated string")
				}
				if src[i] == '\\' && i+1 < len(src) {
					out.WriteByte(src[i])
					out.WriteByte(src[i+1])
					i += 2
				} else if src[i] == '"' {
					out.WriteByte('"')
					i++
					break
				} else {
					out.WriteByte(src[i])
					i++
				}
			}
			continue
		}
		// Line comment?
		if i+1 < len(src) && src[i] == '/' && src[i+1] == '/' {
			// Skip to end of line, preserve the newline
			i += 2
			for i < len(src) && src[i] != '\n' {
				i++
			}
			continue
		}
		// Block comment?
		if i+1 < len(src) && src[i] == '/' && src[i+1] == '*' {
			i += 2
			for {
				if i+1 >= len(src) {
					return "", fmt.Errorf("unterminated block comment")
				}
				if src[i] == '*' && src[i+1] == '/' {
					i += 2
					break
				}
				i++
			}
			continue
		}
		out.WriteByte(src[i])
		i++
	}
	return out.String(), nil
}

// parseAttrList parses a DOT attribute list from pos (after the opening '[')
// and returns the attributes map plus the position after the closing ']'.
func parseAttrList(src string, pos int) (map[string]string, int, error) {
	attrs := make(map[string]string)
	// skip '['
	if pos < len(src) && src[pos] == '[' {
		pos++
	}
	for pos < len(src) {
		// Skip whitespace and commas
		for pos < len(src) && (src[pos] == ' ' || src[pos] == '\t' || src[pos] == '\n' || src[pos] == '\r' || src[pos] == ',') {
			pos++
		}
		if pos >= len(src) {
			return attrs, pos, nil
		}
		if src[pos] == ']' {
			pos++
			return attrs, pos, nil
		}
		// Parse key
		key, newPos, err := parseDotToken(src, pos)
		if err != nil {
			return nil, pos, err
		}
		key = normalizeID(key)
		pos = newPos
		// Skip whitespace
		for pos < len(src) && (src[pos] == ' ' || src[pos] == '\t') {
			pos++
		}
		if pos >= len(src) || src[pos] != '=' {
			// No value, skip
			continue
		}
		pos++ // skip '='
		// Skip whitespace
		for pos < len(src) && (src[pos] == ' ' || src[pos] == '\t') {
			pos++
		}
		// Parse value (may be + concatenation of quoted strings)
		val, newPos2, err := parseAttrValue(src, pos)
		if err != nil {
			return nil, pos, err
		}
		pos = newPos2
		attrs[key] = val
	}
	return attrs, pos, nil
}

// parseDotToken parses a single token (quoted or unquoted identifier).
func parseDotToken(src string, pos int) (string, int, error) {
	if pos >= len(src) {
		return "", pos, fmt.Errorf("unexpected end of input")
	}
	if src[pos] == '"' {
		// Quoted string
		var sb strings.Builder
		sb.WriteByte('"')
		pos++
		for pos < len(src) {
			if src[pos] == '\\' && pos+1 < len(src) {
				sb.WriteByte('\\')
				sb.WriteByte(src[pos+1])
				pos += 2
			} else if src[pos] == '"' {
				sb.WriteByte('"')
				pos++
				break
			} else {
				sb.WriteByte(src[pos])
				pos++
			}
		}
		return sb.String(), pos, nil
	}
	// Unquoted token: read until whitespace, '=', ',', ']', '[', ';', '-'
	start := pos
	for pos < len(src) {
		c := src[pos]
		if c == ' ' || c == '\t' || c == '\n' || c == '\r' ||
			c == '=' || c == ',' || c == ']' || c == '[' || c == ';' ||
			c == '-' || c == '{' || c == '}' {
			break
		}
		pos++
	}
	return src[start:pos], pos, nil
}

// parseAttrValue parses an attribute value, handling + concatenation of quoted strings.
func parseAttrValue(src string, pos int) (string, int, error) {
	var result strings.Builder
	for {
		// Skip whitespace
		for pos < len(src) && (src[pos] == ' ' || src[pos] == '\t' || src[pos] == '\n' || src[pos] == '\r') {
			pos++
		}
		if pos >= len(src) {
			break
		}
		token, newPos, err := parseDotToken(src, pos)
		if err != nil {
			return "", pos, err
		}
		pos = newPos
		// Decode the token
		if len(token) >= 2 && token[0] == '"' && token[len(token)-1] == '"' {
			inner := token[1 : len(token)-1]
			result.WriteString(unescapeDotString(inner))
		} else {
			result.WriteString(token)
		}
		// Skip whitespace
		for pos < len(src) && (src[pos] == ' ' || src[pos] == '\t' || src[pos] == '\n' || src[pos] == '\r') {
			pos++
		}
		// Check for + concatenation
		if pos < len(src) && src[pos] == '+' {
			pos++
			continue
		}
		break
	}
	return result.String(), pos, nil
}

// parseNodes parses node attribute blocks from a DOT source, returning a map of
// normalized node ID -> nodeAttrs. Only named node statements are included.
func parseNodes(src string) (map[string]*nodeAttrs, error) {
	stripped, err := stripComments(src)
	if err != nil {
		return nil, err
	}

	nodes := make(map[string]*nodeAttrs)
	// We scan the stripped source for patterns like: identifier [ ... ]
	// We need to differentiate node statements from edge statements.
	// Strategy: tokenize and look for: ID '[' attrs ']' without '->' before '['.
	pos := 0
	n := len(stripped)

	// Skip past the opening "digraph ..." or "graph ..." header including the opening {
	// but we actually just scan the whole body for node statements.
	for pos < n {
		// Skip whitespace
		for pos < n && isSpace(stripped[pos]) {
			pos++
		}
		if pos >= n {
			break
		}

		// Try to read an identifier
		if !isIDStart(stripped[pos]) {
			// Skip this character
			pos++
			continue
		}

		idStart := pos
		// Read the identifier (possibly quoted)
		tok, newPos, err := parseDotToken(stripped, pos)
		if err != nil {
			pos++
			continue
		}
		_ = idStart
		pos = newPos

		// Skip whitespace
		for pos < n && isSpace(stripped[pos]) {
			pos++
		}

		// If followed by '->' or '--', this is an edge statement. Skip the whole statement.
		if pos+1 < n && stripped[pos] == '-' && (stripped[pos+1] == '>' || stripped[pos+1] == '-') {
			// Edge statement - skip to ';' or newline-after-closing-bracket
			pos = skipToStatementEnd(stripped, pos)
			continue
		}

		// If followed by '[', this could be a node statement (with attributes)
		if pos < n && stripped[pos] == '[' {
			// Check it's not a keyword
			nodeID := normalizeID(tok)
			if isKeyword(nodeID) {
				// This is a default attribute block (node [...], edge [...], graph [...])
				// Skip it
				attrs, newPos2, _ := parseAttrList(stripped, pos)
				_ = attrs
				pos = newPos2
				continue
			}

			// Parse attribute list
			attrs, newPos2, err := parseAttrList(stripped, pos)
			if err != nil {
				return nil, err
			}
			pos = newPos2

			na := &nodeAttrs{}
			if v, ok := attrs["shape"]; ok {
				na.Shape = strPtr(v)
			}
			if v, ok := attrs["class"]; ok {
				na.Class = strPtr(v)
			}
			if v, ok := attrs["prompt"]; ok {
				na.Prompt = strPtr(v)
			}
			if v, ok := attrs["tool_command"]; ok {
				na.ToolCommand = strPtr(v)
			}
			if v, ok := attrs["question"]; ok {
				na.Question = strPtr(v)
			}
			if v, ok := attrs["goal_gate"]; ok {
				na.GoalGate = strPtr(v)
			}
			nodes[nodeID] = na
			continue
		}

		// If followed by '{', this is a subgraph opening or graph body - skip the '{'
		if pos < n && stripped[pos] == '{' {
			pos++
			continue
		}

		// If followed by '}', skip
		if pos < n && stripped[pos] == '}' {
			pos++
			continue
		}

		// Otherwise skip ';' and continue
		if pos < n && stripped[pos] == ';' {
			pos++
		}
	}

	return nodes, nil
}

// parseEdges parses edge statements from a DOT source.
func parseEdges(src string) ([]edge, error) {
	stripped, err := stripComments(src)
	if err != nil {
		return nil, err
	}

	var edges []edge
	pos := 0
	n := len(stripped)

	for pos < n {
		// Skip whitespace
		for pos < n && isSpace(stripped[pos]) {
			pos++
		}
		if pos >= n {
			break
		}

		if !isIDStart(stripped[pos]) {
			pos++
			continue
		}

		// Read first node ID
		tok, newPos, err := parseDotToken(stripped, pos)
		if err != nil {
			pos++
			continue
		}
		pos = newPos

		// Skip whitespace
		for pos < n && isSpace(stripped[pos]) {
			pos++
		}

		// Check for edge arrow
		if pos+1 < n && stripped[pos] == '-' && (stripped[pos+1] == '>' || stripped[pos+1] == '-') {
			// This is an edge chain: tok -> tok2 -> tok3 [attrs]
			nodeID := stripPort(normalizeID(tok))
			chain := []string{nodeID}
			for pos+1 < n && stripped[pos] == '-' && (stripped[pos+1] == '>' || stripped[pos+1] == '-') {
				pos += 2 // skip -> or --
				// Skip whitespace
				for pos < n && isSpace(stripped[pos]) {
					pos++
				}
				nextTok, nextPos, err := parseDotToken(stripped, pos)
				if err != nil {
					break
				}
				pos = nextPos
				chain = append(chain, stripPort(normalizeID(nextTok)))
				// Skip whitespace
				for pos < n && isSpace(stripped[pos]) {
					pos++
				}
			}

			// Parse optional attribute list
			var label *string
			if pos < n && stripped[pos] == '[' {
				attrs, newPos2, _ := parseAttrList(stripped, pos)
				pos = newPos2
				if v, ok := attrs["label"]; ok {
					label = strPtr(v)
				}
			}

			// Emit edges for each segment of the chain
			for i := 0; i < len(chain)-1; i++ {
				edges = append(edges, edge{
					Source: chain[i],
					Target: chain[i+1],
					Label:  label,
				})
			}
			// Skip to end of statement
			if pos < n && stripped[pos] == ';' {
				pos++
			}
			continue
		}

		// Not an edge - handle various non-edge statement endings.
		// We must NOT call skipToStatementEnd here because it would skip
		// past '}' and consume the entire graph body (e.g., when reading
		// "digraph" followed by "pipeline" before the opening "{").
		if pos < n {
			c := stripped[pos]
			if c == '{' || c == '}' || c == ';' {
				pos++
			} else if c == '[' {
				// Skip a node attribute block
				_, newPos2, _ := parseAttrList(stripped, pos)
				pos = newPos2
			}
			// Otherwise (another token follows, e.g. "pipeline" after "digraph"):
			// just continue — the outer loop will pick up the next token.
		}
	}

	return edges, nil
}

// stripPort removes port suffix from a node ID (e.g., "node:port" -> "node").
func stripPort(id string) string {
	idx := strings.Index(id, ":")
	if idx >= 0 {
		return id[:idx]
	}
	return id
}

// skipToStatementEnd skips to the end of a statement (';', or '}').
func skipToStatementEnd(src string, pos int) int {
	n := len(src)
	for pos < n {
		c := src[pos]
		if c == ';' {
			return pos + 1
		}
		if c == '}' {
			return pos
		}
		// Skip over quoted strings
		if c == '"' {
			pos++
			for pos < n {
				if src[pos] == '\\' && pos+1 < n {
					pos += 2
				} else if src[pos] == '"' {
					pos++
					break
				} else {
					pos++
				}
			}
			continue
		}
		// Skip over attribute lists
		if c == '[' {
			pos++
			depth := 1
			for pos < n && depth > 0 {
				if src[pos] == '"' {
					pos++
					for pos < n {
						if src[pos] == '\\' && pos+1 < n {
							pos += 2
						} else if src[pos] == '"' {
							pos++
							break
						} else {
							pos++
						}
					}
					continue
				}
				if src[pos] == '[' {
					depth++
				} else if src[pos] == ']' {
					depth--
				}
				pos++
			}
			continue
		}
		pos++
	}
	return pos
}

func isSpace(c byte) bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

func isIDStart(c byte) bool {
	return c == '"' || c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

func isKeyword(s string) bool {
	switch strings.ToLower(s) {
	case "node", "edge", "graph", "digraph", "subgraph", "strict":
		return true
	}
	return false
}

func strPtr(s string) *string {
	return &s
}
