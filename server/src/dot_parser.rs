use crate::error::{AppError, AppResult};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Parsed node attributes from a DOT file.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeAttrs {
    pub shape: Option<String>,
    pub class: Option<String>,
    pub prompt: Option<String>,
    pub tool_command: Option<String>,
    pub question: Option<String>,
    pub goal_gate: Option<String>,
}

/// Parsed edge from a DOT file.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Edge {
    pub source: String,
    pub target: String,
    pub label: Option<String>,
}

/// Strip DOT comments (`//` line comments and `/* */` block comments),
/// while preserving comments inside double-quoted strings.
///
/// Returns an error for unterminated block comments or unterminated strings.
pub fn strip_comments(input: &str) -> AppResult<String> {
    let mut result = String::with_capacity(input.len());
    let chars: Vec<char> = input.chars().collect();
    let len = chars.len();
    let mut i = 0;

    while i < len {
        if chars[i] == '"' {
            // Inside a quoted string — pass through, handling escape sequences
            result.push('"');
            i += 1;
            loop {
                if i >= len {
                    return Err(AppError::DotParse {
                        detail: "unterminated string literal".into(),
                    });
                }
                let c = chars[i];
                if c == '\\' && i + 1 < len {
                    // Escape sequence: pass both characters through
                    result.push('\\');
                    result.push(chars[i + 1]);
                    i += 2;
                } else if c == '"' {
                    result.push('"');
                    i += 1;
                    break;
                } else {
                    result.push(c);
                    i += 1;
                }
            }
        } else if i + 1 < len && chars[i] == '/' && chars[i + 1] == '/' {
            // Line comment: skip to end of line, preserve the newline
            i += 2;
            while i < len && chars[i] != '\n' {
                i += 1;
            }
            // The newline itself is preserved by the main loop
        } else if i + 1 < len && chars[i] == '/' && chars[i + 1] == '*' {
            // Block comment: skip until closing */
            i += 2;
            loop {
                if i + 1 >= len {
                    return Err(AppError::DotParse {
                        detail: "unterminated block comment".into(),
                    });
                }
                if chars[i] == '*' && chars[i + 1] == '/' {
                    i += 2;
                    break;
                }
                i += 1;
            }
        } else {
            result.push(chars[i]);
            i += 1;
        }
    }

    Ok(result)
}

/// Normalize a DOT identifier: strip outer quotes, resolve escape sequences,
/// trim leading/trailing whitespace.
pub fn normalize_id(s: &str) -> String {
    let s = s.trim();
    if s.starts_with('"') && s.ends_with('"') && s.len() >= 2 {
        let inner = &s[1..s.len() - 1];
        unescape_dot_string(inner)
    } else {
        s.to_string()
    }
}

/// Unescape DOT string escape sequences: `\"` → `"`, `\n` → newline, `\\` → `\`.
/// Other sequences are passed through verbatim.
fn unescape_dot_string(s: &str) -> String {
    let mut result = String::with_capacity(s.len());
    let chars: Vec<char> = s.chars().collect();
    let len = chars.len();
    let mut i = 0;

    while i < len {
        if chars[i] == '\\' && i + 1 < len {
            match chars[i + 1] {
                '"' => {
                    result.push('"');
                    i += 2;
                }
                'n' => {
                    result.push('\n');
                    i += 2;
                }
                '\\' => {
                    result.push('\\');
                    i += 2;
                }
                other => {
                    result.push('\\');
                    result.push(other);
                    i += 2;
                }
            }
        } else {
            result.push(chars[i]);
            i += 1;
        }
    }

    result
}

/// Extract the graph ID from a DOT source string.
/// Matches `strict? (di)?graph "quoted_name"|\w+` pattern.
/// Returns an error if no named graph ID is found (anonymous graph).
pub fn extract_graph_id(source: &str) -> AppResult<String> {
    let stripped = strip_comments(source)?;
    let re = regex_graph_id().ok_or_else(|| AppError::DotParse {
        detail: "internal: graph ID regex failed to compile".into(),
    })?;
    if let Some(caps) = re.captures(&stripped) {
        let raw_name = caps.get(3).map(|m| m.as_str()).unwrap_or("");
        let normalized = normalize_id(raw_name);
        if normalized.is_empty() {
            return Err(AppError::DotParse {
                detail: "anonymous graph: no graph ID found".into(),
            });
        }
        Ok(normalized)
    } else {
        Err(AppError::DotParse {
            detail: "anonymous graph: no graph ID found".into(),
        })
    }
}

fn regex_graph_id() -> Option<&'static regex::Regex> {
    static RE: std::sync::OnceLock<Option<regex::Regex>> = std::sync::OnceLock::new();
    RE.get_or_init(|| {
        regex::Regex::new(r#"(?im)^\s*(strict\s+)?(di)?graph\s+("(?:[^"\\]|\\.)*"|\w+)"#).ok()
    })
    .as_ref()
}

/// Parse node IDs and their attributes from a DOT source string.
/// Returns a map from normalized node ID to NodeAttrs.
pub fn parse_nodes(source: &str) -> AppResult<HashMap<String, NodeAttrs>> {
    let stripped = strip_comments(source)?;
    let mut nodes: HashMap<String, NodeAttrs> = HashMap::new();

    // We use a simple state machine to scan for node definitions.
    // A node definition looks like: identifier [ attr=val, ... ]
    // We skip global defaults (node [...], edge [...], graph [...])
    // and edge statements (->).

    let tokens = tokenize(&stripped)?;
    let mut i = 0;

    while i < tokens.len() {
        let tok = &tokens[i];

        // Skip keywords that aren't node IDs
        match tok.as_str() {
            "digraph" | "graph" | "strict" | "subgraph" => {
                // skip the graph/subgraph header
                i += 1;
                // skip optional name
                if i < tokens.len() && tokens[i] != "{" {
                    i += 1;
                }
                continue;
            }
            "node" | "edge" => {
                // global default block - skip the attribute list
                i += 1;
                if i < tokens.len() && tokens[i] == "[" {
                    i = skip_attr_block(&tokens, i);
                }
                continue;
            }
            "{" | "}" | ";" => {
                i += 1;
                continue;
            }
            _ => {}
        }

        // Check if the next meaningful token is `->` or `--` (edge statement) or `[` (node def)
        // or `=` (attribute assignment at graph level)
        let next_non_ws = tokens[i + 1..].iter().position(|t| !t.is_empty());
        let next_idx = next_non_ws.map(|p| i + 1 + p).unwrap_or(tokens.len());

        if next_idx < tokens.len() {
            match tokens[next_idx].as_str() {
                "->" | "--" => {
                    // Edge statement — skip the whole edge chain
                    i = skip_edge_statement(&tokens, i);
                    continue;
                }
                "=" => {
                    // Graph-level attribute assignment, skip
                    i += 3; // skip key, =, value
                    if i < tokens.len() && tokens[i] == ";" {
                        i += 1;
                    }
                    continue;
                }
                "[" => {
                    // Node definition: tok is the node ID
                    let node_id = normalize_id(tok);
                    // Skip global default blocks (node, edge, graph keywords)
                    if node_id == "node" || node_id == "edge" || node_id == "graph" {
                        i = next_idx;
                        i = skip_attr_block(&tokens, i);
                        continue;
                    }
                    i = next_idx; // move to [
                    let (attrs, new_i) = parse_node_attr_block(&tokens, i)?;
                    let node_attrs = NodeAttrs {
                        shape: attrs.get("shape").cloned(),
                        class: attrs.get("class").cloned(),
                        prompt: attrs.get("prompt").cloned(),
                        tool_command: attrs.get("tool_command").cloned(),
                        question: attrs.get("question").cloned(),
                        goal_gate: attrs.get("goal_gate").cloned(),
                    };
                    nodes.insert(node_id, node_attrs);
                    i = new_i;
                    continue;
                }
                _ => {
                    i += 1;
                    continue;
                }
            }
        } else {
            i += 1;
        }
    }

    Ok(nodes)
}

/// Parse edges from a DOT source string.
/// Returns a list of Edge structs.
pub fn parse_edges(source: &str) -> AppResult<Vec<Edge>> {
    let stripped = strip_comments(source)?;
    let mut edges: Vec<Edge> = Vec::new();

    let tokens = tokenize(&stripped)?;
    let mut i = 0;

    while i < tokens.len() {
        let tok = &tokens[i];

        match tok.as_str() {
            "digraph" | "graph" | "strict" | "subgraph" => {
                i += 1;
                if i < tokens.len() && tokens[i] != "{" {
                    i += 1;
                }
                continue;
            }
            "node" | "edge" => {
                i += 1;
                if i < tokens.len() && tokens[i] == "[" {
                    i = skip_attr_block(&tokens, i);
                }
                continue;
            }
            "{" | "}" | ";" => {
                i += 1;
                continue;
            }
            _ => {}
        }

        // Check next token
        let next_idx = i + 1;
        if next_idx < tokens.len() && (tokens[next_idx] == "->" || tokens[next_idx] == "--") {
            // Edge chain: collect all nodes in chain and optional attr block
            let mut chain: Vec<String> = vec![strip_port(tok)];
            let mut j = next_idx;

            while j < tokens.len() && (tokens[j] == "->" || tokens[j] == "--") {
                j += 1; // skip ->
                if j < tokens.len() && tokens[j] != "[" && tokens[j] != ";" {
                    chain.push(strip_port(&tokens[j]));
                    j += 1;
                } else {
                    break;
                }
            }

            // Optional attribute block
            let mut label: Option<String> = None;
            if j < tokens.len() && tokens[j] == "[" {
                let (attrs, new_j) = parse_node_attr_block(&tokens, j)?;
                label = attrs.get("label").cloned();
                j = new_j;
            }

            // Emit edges for each consecutive pair in chain
            for pair in chain.windows(2) {
                edges.push(Edge {
                    source: normalize_id(&pair[0]),
                    target: normalize_id(&pair[1]),
                    label: label.clone(),
                });
            }

            // Skip optional semicolon
            if j < tokens.len() && tokens[j] == ";" {
                j += 1;
            }
            i = j;
        } else {
            i += 1;
        }
    }

    Ok(edges)
}

/// Strip port suffix from a node ID token: `node_id:port:compass` → `node_id`
fn strip_port(s: &str) -> String {
    // The token may be a quoted string (with possible colons inside) or unquoted.
    // For unquoted tokens, colon separates port/compass.
    let s = s.trim();
    if s.starts_with('"') {
        // Quoted ID — no port stripping needed (ports not used with quoted IDs in Kilroy)
        s.to_string()
    } else {
        // Unquoted: take everything before first colon
        s.split(':').next().unwrap_or(s).to_string()
    }
}

/// Tokenize a DOT source string into meaningful tokens.
/// This is a simplified tokenizer that handles quoted strings, identifiers, and symbols.
fn tokenize(source: &str) -> AppResult<Vec<String>> {
    let mut tokens = Vec::new();
    let chars: Vec<char> = source.chars().collect();
    let len = chars.len();
    let mut i = 0;

    while i < len {
        let c = chars[i];

        // Skip whitespace
        if c.is_whitespace() {
            i += 1;
            continue;
        }

        // Quoted string (possibly multi-line)
        if c == '"' {
            let mut s = String::new();
            s.push('"');
            i += 1;
            loop {
                if i >= len {
                    return Err(AppError::DotParse {
                        detail: "unterminated string literal in tokenizer".into(),
                    });
                }
                let ch = chars[i];
                if ch == '\\' && i + 1 < len {
                    s.push('\\');
                    s.push(chars[i + 1]);
                    i += 2;
                } else if ch == '"' {
                    s.push('"');
                    i += 1;
                    break;
                } else {
                    s.push(ch);
                    i += 1;
                }
            }
            tokens.push(s);
            continue;
        }

        // Two-character operators
        if i + 1 < len {
            let two: String = chars[i..i + 2].iter().collect();
            if two == "->" || two == "--" {
                tokens.push(two);
                i += 2;
                continue;
            }
        }

        // Single-character tokens
        if "{}[];,=+".contains(c) {
            tokens.push(c.to_string());
            i += 1;
            continue;
        }

        // Identifier or unquoted number
        let mut id = String::new();
        while i < len {
            let ch = chars[i];
            if ch.is_whitespace() || "{}[];,=+\"".contains(ch) {
                break;
            }
            // Stop at -> and --
            if i + 1 < len && (chars[i] == '-' && (chars[i + 1] == '>' || chars[i + 1] == '-')) {
                break;
            }
            id.push(ch);
            i += 1;
        }
        if !id.is_empty() {
            tokens.push(id);
        }
    }

    Ok(tokens)
}

/// Skip an attribute block `[ ... ]`, returning the index after the closing `]`.
fn skip_attr_block(tokens: &[String], start: usize) -> usize {
    let mut i = start;
    if i < tokens.len() && tokens[i] == "[" {
        i += 1;
        let mut depth = 1;
        while i < tokens.len() && depth > 0 {
            if tokens[i] == "[" {
                depth += 1;
            } else if tokens[i] == "]" {
                depth -= 1;
            }
            i += 1;
        }
    }
    i
}

/// Skip an entire edge statement (including any trailing attribute block and semicolon).
fn skip_edge_statement(tokens: &[String], start: usize) -> usize {
    let mut i = start + 1; // skip source node
                           // Skip -> target -> target ...
    while i < tokens.len() && (tokens[i] == "->" || tokens[i] == "--") {
        i += 1; // skip ->
        if i < tokens.len() && tokens[i] != "[" && tokens[i] != ";" {
            i += 1; // skip target
        }
    }
    // Optional attr block
    if i < tokens.len() && tokens[i] == "[" {
        i = skip_attr_block(tokens, i);
    }
    // Optional semicolon
    if i < tokens.len() && tokens[i] == ";" {
        i += 1;
    }
    i
}

/// Parse an attribute block `[ key=value, key=value, ... ]`.
/// Returns a map of attribute names to values, and the index after `]`.
fn parse_node_attr_block(
    tokens: &[String],
    start: usize,
) -> AppResult<(HashMap<String, String>, usize)> {
    let mut attrs = HashMap::new();
    let mut i = start;

    if i >= tokens.len() || tokens[i] != "[" {
        return Ok((attrs, i));
    }
    i += 1; // skip [

    while i < tokens.len() && tokens[i] != "]" {
        if tokens[i] == "," || tokens[i] == ";" {
            i += 1;
            continue;
        }

        // key
        let key = tokens[i].trim_matches('"').to_string();
        i += 1;

        if i >= tokens.len() {
            break;
        }

        if tokens[i] != "=" {
            // Skip stray tokens
            continue;
        }
        i += 1; // skip =

        if i >= tokens.len() {
            break;
        }

        // Value may be one or more quoted strings concatenated with +
        let value = parse_attr_value(tokens, i)?;
        let (val_str, new_i) = value;
        attrs.insert(key, val_str);
        i = new_i;
    }

    if i < tokens.len() && tokens[i] == "]" {
        i += 1; // skip ]
    }

    Ok((attrs, i))
}

/// Parse an attribute value, handling + concatenation of quoted strings.
/// Returns (value, new_index).
fn parse_attr_value(tokens: &[String], start: usize) -> AppResult<(String, usize)> {
    let mut i = start;
    let mut result = String::new();

    // Collect the first value token
    if i >= tokens.len() {
        return Ok((result, i));
    }

    let first = &tokens[i];
    let first_val = decode_token_value(first);
    result.push_str(&first_val);
    i += 1;

    // Handle + concatenation
    while i < tokens.len() && tokens[i] == "+" {
        i += 1; // skip +
        if i < tokens.len() {
            let next = &tokens[i];
            let next_val = decode_token_value(next);
            result.push_str(&next_val);
            i += 1;
        }
    }

    Ok((result, i))
}

/// Decode a token's value:
/// - Quoted strings: strip outer quotes, unescape
/// - Unquoted tokens: return as-is
fn decode_token_value(tok: &str) -> String {
    let tok = tok.trim();
    if tok.starts_with('"') && tok.ends_with('"') && tok.len() >= 2 {
        let inner = &tok[1..tok.len() - 1];
        unescape_dot_string(inner)
    } else {
        tok.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ---- strip_comments tests ----

    #[test]
    fn test_strip_line_comment() {
        let input = "digraph { // this is a comment\n  node1\n}";
        let result = strip_comments(input).unwrap();
        assert!(!result.contains("this is a comment"));
        assert!(result.contains("node1"));
    }

    #[test]
    fn test_strip_block_comment() {
        let input = "digraph { /* block comment */ node1 }";
        let result = strip_comments(input).unwrap();
        assert!(!result.contains("block comment"));
        assert!(result.contains("node1"));
    }

    #[test]
    fn test_url_in_string_not_stripped() {
        let input = r#"digraph { node1 [prompt="check http://example.com"] }"#;
        let result = strip_comments(input).unwrap();
        assert!(result.contains("http://example.com"));
    }

    #[test]
    fn test_unterminated_block_comment_error() {
        let input = "digraph { /* unterminated";
        assert!(strip_comments(input).is_err());
    }

    #[test]
    fn test_unterminated_string_error() {
        let input = "digraph { node1 [prompt=\"unterminated] }";
        assert!(strip_comments(input).is_err());
    }

    #[test]
    fn test_escaped_quote_in_string() {
        let input = r#"digraph { node1 [prompt="say \"hello\""] }"#;
        let result = strip_comments(input).unwrap();
        assert!(result.contains(r#"say \"hello\""#));
    }

    // ---- normalize_id tests ----

    #[test]
    fn test_normalize_unquoted() {
        assert_eq!(normalize_id("  implement  "), "implement");
    }

    #[test]
    fn test_normalize_quoted() {
        assert_eq!(normalize_id(r#""implement""#), "implement");
    }

    #[test]
    fn test_normalize_quoted_with_escapes() {
        assert_eq!(normalize_id(r#""say \"hi\"""#), r#"say "hi""#);
    }

    #[test]
    fn test_normalize_quoted_newline() {
        assert_eq!(normalize_id(r#""line1\nline2""#), "line1\nline2");
    }

    // ---- extract_graph_id tests ----

    #[test]
    fn test_extract_simple_graph_id() {
        let dot = "digraph my_pipeline { }";
        assert_eq!(extract_graph_id(dot).unwrap(), "my_pipeline");
    }

    #[test]
    fn test_extract_graph_id_with_strict() {
        let dot = "strict digraph my_pipeline { }";
        assert_eq!(extract_graph_id(dot).unwrap(), "my_pipeline");
    }

    #[test]
    fn test_extract_graph_id_quoted() {
        let dot = r#"digraph "my pipeline" { }"#;
        assert_eq!(extract_graph_id(dot).unwrap(), "my pipeline");
    }

    #[test]
    fn test_extract_anonymous_graph_fails() {
        let dot = "digraph { }";
        assert!(extract_graph_id(dot).is_err());
    }

    // ---- parse_nodes tests ----

    #[test]
    fn test_parse_basic_node() {
        let dot = r#"digraph alpha {
            implement [shape=box, prompt="Do the work"]
        }"#;
        let nodes = parse_nodes(dot).unwrap();
        let node = nodes.get("implement").unwrap();
        assert_eq!(node.shape, Some("box".into()));
        assert_eq!(node.prompt, Some("Do the work".into()));
    }

    #[test]
    fn test_parse_node_tool_command() {
        let dot = r#"digraph alpha {
            check_fmt [shape=parallelogram, tool_command="cargo fmt --check"]
        }"#;
        let nodes = parse_nodes(dot).unwrap();
        let node = nodes.get("check_fmt").unwrap();
        assert_eq!(node.shape, Some("parallelogram".into()));
        assert_eq!(node.tool_command, Some("cargo fmt --check".into()));
    }

    #[test]
    fn test_parse_node_plus_concatenation() {
        let dot = r#"digraph alpha {
            node1 [prompt="first " + "second"]
        }"#;
        let nodes = parse_nodes(dot).unwrap();
        let node = nodes.get("node1").unwrap();
        assert_eq!(node.prompt, Some("first second".into()));
    }

    #[test]
    fn test_parse_node_escape_sequences() {
        let dot = r#"digraph alpha {
            node1 [prompt="line1\nline2"]
        }"#;
        let nodes = parse_nodes(dot).unwrap();
        let node = nodes.get("node1").unwrap();
        assert_eq!(node.prompt, Some("line1\nline2".into()));
    }

    #[test]
    fn test_parse_skips_global_defaults() {
        let dot = r#"digraph alpha {
            node [shape=box]
            implement [shape=parallelogram]
        }"#;
        let nodes = parse_nodes(dot).unwrap();
        assert!(!nodes.contains_key("node"));
        assert!(nodes.contains_key("implement"));
    }

    #[test]
    fn test_parse_skips_edges() {
        let dot = r#"digraph alpha {
            implement [shape=box]
            implement -> check_fmt [label="ok"]
        }"#;
        let nodes = parse_nodes(dot).unwrap();
        // implement should be a node, check_fmt should not (it has no attr block)
        assert!(nodes.contains_key("implement"));
    }

    #[test]
    fn test_parse_multiline_prompt() {
        let dot = "digraph alpha {\n    node1 [prompt=\"line1\nline2\"]\n}";
        let nodes = parse_nodes(dot).unwrap();
        let node = nodes.get("node1").unwrap();
        assert!(node.prompt.as_deref().unwrap_or("").contains('\n'));
    }

    // ---- parse_edges tests ----

    #[test]
    fn test_parse_simple_edge() {
        let dot = r#"digraph alpha {
            implement -> check_fmt
        }"#;
        let edges = parse_edges(dot).unwrap();
        assert_eq!(edges.len(), 1);
        assert_eq!(edges[0].source, "implement");
        assert_eq!(edges[0].target, "check_fmt");
        assert_eq!(edges[0].label, None);
    }

    #[test]
    fn test_parse_edge_with_label() {
        let dot = r#"digraph alpha {
            check_goal -> implement [label="fail"]
            check_goal -> done [label="pass"]
        }"#;
        let edges = parse_edges(dot).unwrap();
        assert_eq!(edges.len(), 2);
        let fail_edge = edges
            .iter()
            .find(|e| e.label.as_deref() == Some("fail"))
            .unwrap();
        assert_eq!(fail_edge.source, "check_goal");
        assert_eq!(fail_edge.target, "implement");
    }

    #[test]
    fn test_parse_edge_chain() {
        let dot = r#"digraph alpha {
            a -> b -> c [label="x"]
        }"#;
        let edges = parse_edges(dot).unwrap();
        assert_eq!(edges.len(), 2);
        // Both edges should have label "x"
        assert!(edges.iter().all(|e| e.label.as_deref() == Some("x")));
        // Check a->b and b->c
        let ab = edges.iter().find(|e| e.source == "a" && e.target == "b");
        let bc = edges.iter().find(|e| e.source == "b" && e.target == "c");
        assert!(ab.is_some());
        assert!(bc.is_some());
    }

    #[test]
    fn test_parse_edge_port_stripping() {
        let dot = r#"digraph alpha {
            a:out -> b:in
        }"#;
        let edges = parse_edges(dot).unwrap();
        assert_eq!(edges.len(), 1);
        assert_eq!(edges[0].source, "a");
        assert_eq!(edges[0].target, "b");
    }

    #[test]
    fn test_parse_comment_in_url_not_stripped_for_edges() {
        let dot = r#"digraph alpha {
            node1 [prompt="see http://example.com for details"]
            node1 -> node2
        }"#;
        let edges = parse_edges(dot).unwrap();
        assert_eq!(edges.len(), 1);
    }

    #[test]
    fn test_parse_error_unterminated_comment_nodes() {
        let dot = "digraph alpha { /* unterminated\nnode1 [shape=box] }";
        assert!(parse_nodes(dot).is_err());
    }

    #[test]
    fn test_parse_error_unterminated_comment_edges() {
        let dot = "digraph alpha { /* unterminated\na -> b }";
        assert!(parse_edges(dot).is_err());
    }

    #[test]
    fn test_parse_goal_gate() {
        let dot = r#"digraph alpha {
            check_goal [shape=diamond, goal_gate="true"]
        }"#;
        let nodes = parse_nodes(dot).unwrap();
        let node = nodes.get("check_goal").unwrap();
        assert_eq!(node.goal_gate, Some("true".into()));
    }
}
