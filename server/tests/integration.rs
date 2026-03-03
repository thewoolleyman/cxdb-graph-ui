/// Integration tests for the CXDB Graph UI server.
///
/// These tests exercise the full server (via axum-test) and integration
/// with the DOT parser and configuration validation.
use axum::http::StatusCode;
use axum_test::TestServer;
use cxdb_graph_ui::server::{build_router, AppState};
use std::collections::HashMap;
use std::io::Write;
use std::path::PathBuf;
use tempfile::NamedTempFile;

fn write_dot(content: &str) -> NamedTempFile {
    let mut f = NamedTempFile::with_suffix(".dot").unwrap();
    f.write_all(content.as_bytes()).unwrap();
    f
}

fn make_test_state(dot_files: Vec<(&str, &str)>) -> AppState {
    let dir = tempfile::tempdir().unwrap();
    let mut dot_names = Vec::new();
    let mut dot_paths = HashMap::new();

    for (name, content) in dot_files {
        let path = dir.path().join(name);
        std::fs::write(&path, content).unwrap();
        dot_names.push(name.to_string());
        dot_paths.insert(name.to_string(), path);
    }

    std::mem::forget(dir);

    AppState {
        dot_names,
        dot_paths,
        cxdb_urls: vec!["http://127.0.0.1:9110".into()],
        dev_mode: false,
        assets_dir: PathBuf::from("assets"),
    }
}

// ---- /api/dots ----

#[tokio::test]
async fn test_api_dots_empty() {
    let state = make_test_state(vec![]);
    let app = build_router(state);
    let server = TestServer::new(app).unwrap();
    let resp = server.get("/api/dots").await;
    assert_eq!(resp.status_code(), StatusCode::OK);
    let body: serde_json::Value = resp.json();
    assert!(body["dots"].as_array().unwrap().is_empty());
}

#[tokio::test]
async fn test_api_dots_preserves_order() {
    let state = make_test_state(vec![
        ("pipeline-a.dot", "digraph alpha {}"),
        ("pipeline-b.dot", "digraph beta {}"),
        ("pipeline-c.dot", "digraph gamma {}"),
    ]);
    let app = build_router(state);
    let server = TestServer::new(app).unwrap();

    let resp = server.get("/api/dots").await;
    assert_eq!(resp.status_code(), StatusCode::OK);
    let body: serde_json::Value = resp.json();
    let dots = body["dots"].as_array().unwrap();
    assert_eq!(dots[0], "pipeline-a.dot");
    assert_eq!(dots[1], "pipeline-b.dot");
    assert_eq!(dots[2], "pipeline-c.dot");
}

// ---- /api/cxdb/instances ----

#[tokio::test]
async fn test_api_cxdb_instances_multiple() {
    let mut state = make_test_state(vec![("alpha.dot", "digraph alpha {}")]);
    state.cxdb_urls = vec![
        "http://127.0.0.1:9110".into(),
        "http://127.0.0.1:9111".into(),
    ];
    let app = build_router(state);
    let server = TestServer::new(app).unwrap();

    let resp = server.get("/api/cxdb/instances").await;
    assert_eq!(resp.status_code(), StatusCode::OK);
    let body: serde_json::Value = resp.json();
    let instances = body["instances"].as_array().unwrap();
    assert_eq!(instances.len(), 2);
    assert_eq!(instances[0], "http://127.0.0.1:9110");
    assert_eq!(instances[1], "http://127.0.0.1:9111");
}

// ---- /dots/{name} ----

#[tokio::test]
async fn test_dot_file_unregistered_returns_404() {
    let state = make_test_state(vec![("alpha.dot", "digraph alpha {}")]);
    let app = build_router(state);
    let server = TestServer::new(app).unwrap();

    let resp = server.get("/dots/other.dot").await;
    assert_eq!(resp.status_code(), StatusCode::NOT_FOUND);
}

// ---- /dots/{name}/nodes ----

#[tokio::test]
async fn test_nodes_null_fields_for_missing_attrs() {
    let state = make_test_state(vec![(
        "alpha.dot",
        r#"digraph alpha {
            start [shape=Mdiamond]
        }"#,
    )]);
    let app = build_router(state);
    let server = TestServer::new(app).unwrap();

    let resp = server.get("/dots/alpha.dot/nodes").await;
    assert_eq!(resp.status_code(), StatusCode::OK);
    let body: serde_json::Value = resp.json();
    assert_eq!(body["start"]["shape"], "Mdiamond");
    assert!(body["start"]["prompt"].is_null());
    assert!(body["start"]["tool_command"].is_null());
    assert!(body["start"]["question"].is_null());
    assert!(body["start"]["goal_gate"].is_null());
}

#[tokio::test]
async fn test_nodes_parse_error_returns_400_json() {
    let state = make_test_state(vec![("bad.dot", "digraph alpha { /* unterminated")]);
    let app = build_router(state);
    let server = TestServer::new(app).unwrap();

    let resp = server.get("/dots/bad.dot/nodes").await;
    assert_eq!(resp.status_code(), StatusCode::BAD_REQUEST);
    let body: serde_json::Value = resp.json();
    assert!(body["error"].as_str().is_some());
    assert!(body["error"].as_str().unwrap().contains("DOT parse error"));
}

// ---- /dots/{name}/edges ----

#[tokio::test]
async fn test_edges_chain_expansion() {
    let state = make_test_state(vec![(
        "alpha.dot",
        r#"digraph alpha {
            a -> b -> c [label="x"]
        }"#,
    )]);
    let app = build_router(state);
    let server = TestServer::new(app).unwrap();

    let resp = server.get("/dots/alpha.dot/edges").await;
    assert_eq!(resp.status_code(), StatusCode::OK);
    let body: serde_json::Value = resp.json();
    let edges = body.as_array().unwrap();
    assert_eq!(edges.len(), 2);

    let has_ab = edges
        .iter()
        .any(|e| e["source"] == "a" && e["target"] == "b" && e["label"] == "x");
    let has_bc = edges
        .iter()
        .any(|e| e["source"] == "b" && e["target"] == "c" && e["label"] == "x");
    assert!(has_ab, "expected a->b edge");
    assert!(has_bc, "expected b->c edge");
}

#[tokio::test]
async fn test_edges_port_stripping() {
    let state = make_test_state(vec![(
        "alpha.dot",
        r#"digraph alpha {
            a:out -> b:in
        }"#,
    )]);
    let app = build_router(state);
    let server = TestServer::new(app).unwrap();

    let resp = server.get("/dots/alpha.dot/edges").await;
    assert_eq!(resp.status_code(), StatusCode::OK);
    let body: serde_json::Value = resp.json();
    let edges = body.as_array().unwrap();
    assert_eq!(edges.len(), 1);
    assert_eq!(edges[0]["source"], "a");
    assert_eq!(edges[0]["target"], "b");
}

#[tokio::test]
async fn test_edges_parse_error_returns_400_json() {
    let state = make_test_state(vec![("bad.dot", "digraph alpha { /* unterminated")]);
    let app = build_router(state);
    let server = TestServer::new(app).unwrap();

    let resp = server.get("/dots/bad.dot/edges").await;
    assert_eq!(resp.status_code(), StatusCode::BAD_REQUEST);
    let body: serde_json::Value = resp.json();
    assert!(body["error"].as_str().is_some());
    assert!(body["error"].as_str().unwrap().contains("DOT parse error"));
}

// ---- configuration validation ----

#[test]
fn test_config_validate_duplicate_basename() {
    use cxdb_graph_ui::config::Config;
    use std::path::PathBuf;

    let _f1 = write_dot("digraph alpha {}");
    let _f2 = write_dot("digraph beta {}");
    let dir = tempfile::tempdir().unwrap();
    let p1 = dir.path().join("pipeline.dot");
    let p2 = dir.path().join("sub").join("pipeline.dot");
    std::fs::create_dir_all(p2.parent().unwrap()).unwrap();
    std::fs::write(&p1, "digraph alpha {}").unwrap();
    std::fs::write(&p2, "digraph beta {}").unwrap();

    let config = Config {
        port: 9030,
        cxdb_urls: vec!["http://127.0.0.1:9110".into()],
        dot_files: vec![p1, p2],
        dev_mode: false,
        assets_dir: PathBuf::from("assets"),
    };
    assert!(config.validate().is_err());
}

#[test]
fn test_config_validate_anonymous_graph() {
    use cxdb_graph_ui::config::Config;

    let f = write_dot("digraph { start [shape=Mdiamond] }");
    let config = Config {
        port: 9030,
        cxdb_urls: vec!["http://127.0.0.1:9110".into()],
        dot_files: vec![f.path().to_path_buf()],
        dev_mode: false,
        assets_dir: PathBuf::from("assets"),
    };
    assert!(config.validate().is_err());
}

#[test]
fn test_config_validate_duplicate_graph_id() {
    use cxdb_graph_ui::config::Config;

    let f1 = write_dot("digraph same_pipeline { start [shape=Mdiamond] }");
    let f2 = write_dot("digraph same_pipeline { end [shape=Msquare] }");
    let config = Config {
        port: 9030,
        cxdb_urls: vec!["http://127.0.0.1:9110".into()],
        dot_files: vec![f1.path().to_path_buf(), f2.path().to_path_buf()],
        dev_mode: false,
        assets_dir: PathBuf::from("assets"),
    };
    assert!(config.validate().is_err());
}
