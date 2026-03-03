use crate::config::Config;
use crate::cxdb_proxy::proxy_to_cxdb;
use crate::dot_parser::{parse_edges, parse_nodes};
use crate::error::{AppError, AppResult};
use axum::body::Body;
use axum::extract::{Path, Request, State};
use axum::http::{HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::{routing::get, Router};
use include_dir::{include_dir, Dir};
use serde_json::json;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

/// Embedded frontend build output from `server/assets/`.
/// This is populated by `pnpm build` from the `frontend/` directory.
static ASSETS: Dir<'static> = include_dir!("$CARGO_MANIFEST_DIR/assets");

/// Shared application state passed to all route handlers.
#[derive(Debug, Clone)]
pub struct AppState {
    /// Ordered list of DOT filenames (basenames), in the order provided on the command line.
    pub dot_names: Vec<String>,
    /// Map from basename to absolute path for DOT files.
    pub dot_paths: HashMap<String, PathBuf>,
    /// Ordered list of CXDB base URLs.
    pub cxdb_urls: Vec<String>,
    /// Whether to serve assets from filesystem instead of embedded.
    pub dev_mode: bool,
    /// Assets directory for dev mode.
    pub assets_dir: PathBuf,
}

impl AppState {
    pub fn from_config(config: &Config) -> AppResult<Self> {
        let mut dot_names = Vec::new();
        let mut dot_paths = HashMap::new();

        for path in &config.dot_files {
            let basename = path
                .file_name()
                .and_then(|n| n.to_str())
                .ok_or_else(|| AppError::CliValidation {
                    detail: format!("invalid path: {}", path.display()),
                })?
                .to_string();

            dot_names.push(basename.clone());
            dot_paths.insert(basename, path.clone());
        }

        Ok(AppState {
            dot_names,
            dot_paths,
            cxdb_urls: config.cxdb_urls.clone(),
            dev_mode: config.dev_mode,
            assets_dir: config.assets_dir.clone(),
        })
    }
}

/// Build the axum router with all routes.
pub fn build_router(state: AppState) -> Router {
    let shared_state = Arc::new(state);

    Router::new()
        .route("/", get(handle_root))
        .route("/assets/*path", get(handle_asset))
        .route("/dots/:name", get(handle_dot_file))
        .route("/dots/:name/nodes", get(handle_dot_nodes))
        .route("/dots/:name/edges", get(handle_dot_edges))
        .route("/api/dots", get(handle_api_dots))
        .route("/api/cxdb/instances", get(handle_api_cxdb_instances))
        .route("/api/cxdb/:index/*path", get(handle_api_cxdb))
        .with_state(shared_state)
}

/// Run the HTTP server with the given configuration.
pub async fn run_server(config: Config) -> AppResult<()> {
    let state = AppState::from_config(&config)?;
    let port = config.port;
    let router = build_router(state);

    let addr = format!("0.0.0.0:{port}");
    let listener = tokio::net::TcpListener::bind(&addr)
        .await
        .map_err(|e| AppError::FileIo {
            path: addr.clone(),
            source: e,
        })?;

    println!("Kilroy Pipeline UI: http://127.0.0.1:{port}");

    axum::serve(listener, router)
        .await
        .map_err(|e| AppError::HttpHandler {
            detail: format!("server error: {e}"),
        })?;

    Ok(())
}

/// GET / — serve the dashboard index.html
async fn handle_root(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    serve_asset(state, "index.html").await
}

/// GET /assets/* — serve hashed build artifacts
async fn handle_asset(
    State(state): State<Arc<AppState>>,
    Path(path): Path<String>,
) -> impl IntoResponse {
    // The embedded directory root is `server/assets/`, so a request to
    // `/assets/foo.js` has `path` = `foo.js` and the embedded path is
    // `assets/foo.js` (i.e. the `assets/` subdirectory within the root).
    serve_asset(state, &format!("assets/{path}")).await
}

/// Serve an embedded or filesystem asset.
async fn serve_asset(state: Arc<AppState>, path: &str) -> Response {
    // Remove leading slash if present
    let path = path.trim_start_matches('/');

    if state.dev_mode {
        // Serve from filesystem in dev mode
        let full_path = state.assets_dir.join(path);
        match tokio::fs::read(&full_path).await {
            Ok(bytes) => {
                let mime = mime_guess::from_path(path).first_or_octet_stream();
                let mut response = Response::new(Body::from(bytes));
                if let Ok(v) = HeaderValue::from_str(mime.as_ref()) {
                    response.headers_mut().insert("content-type", v);
                }
                response
            }
            Err(_) => {
                let err = AppError::Embed {
                    detail: format!("asset not found: {path}"),
                };
                err.into_response()
            }
        }
    } else {
        // Serve from embedded assets
        if let Some(file) = ASSETS.get_file(path) {
            let contents = file.contents();
            let mime = mime_guess::from_path(path).first_or_octet_stream();
            let mut response = Response::new(Body::from(contents));
            if let Ok(v) = HeaderValue::from_str(mime.as_ref()) {
                response.headers_mut().insert("content-type", v);
            }
            response
        } else {
            // Try serving index.html for SPA routing
            if let Some(index) = ASSETS.get_file("index.html") {
                let contents = index.contents();
                let mut response = Response::new(Body::from(contents));
                if let Ok(v) = HeaderValue::from_str("text/html; charset=utf-8") {
                    response.headers_mut().insert("content-type", v);
                }
                response
            } else {
                let err = AppError::Embed {
                    detail: format!("asset not found: {path}"),
                };
                err.into_response()
            }
        }
    }
}

/// GET /dots/{name} — serve a registered DOT file
async fn handle_dot_file(
    State(state): State<Arc<AppState>>,
    Path(name): Path<String>,
) -> impl IntoResponse {
    let path = match state.dot_paths.get(&name) {
        Some(p) => p.clone(),
        None => {
            return (StatusCode::NOT_FOUND, format!("DOT file not found: {name}")).into_response()
        }
    };

    match tokio::fs::read_to_string(&path).await {
        Ok(content) => {
            let mut response = Response::new(Body::from(content));
            if let Ok(v) = HeaderValue::from_str("text/plain; charset=utf-8") {
                response.headers_mut().insert("content-type", v);
            }
            response
        }
        Err(e) => AppError::FileIo {
            path: path.display().to_string(),
            source: e,
        }
        .into_response(),
    }
}

/// GET /dots/{name}/nodes — return parsed node attributes as JSON
async fn handle_dot_nodes(
    State(state): State<Arc<AppState>>,
    Path(name): Path<String>,
) -> impl IntoResponse {
    let path = match state.dot_paths.get(&name) {
        Some(p) => p.clone(),
        None => {
            return (
                StatusCode::NOT_FOUND,
                axum::Json(json!({"error": "DOT file not found"})),
            )
                .into_response()
        }
    };

    let content = match tokio::fs::read_to_string(&path).await {
        Ok(c) => c,
        Err(e) => {
            return AppError::FileIo {
                path: path.display().to_string(),
                source: e,
            }
            .into_response()
        }
    };

    match parse_nodes(&content) {
        Ok(nodes) => axum::Json(nodes).into_response(),
        Err(AppError::DotParse { detail }) => {
            let body = json!({"error": format!("DOT parse error: {detail}")});
            (StatusCode::BAD_REQUEST, axum::Json(body)).into_response()
        }
        Err(e) => e.into_response(),
    }
}

/// GET /dots/{name}/edges — return parsed edge list as JSON
async fn handle_dot_edges(
    State(state): State<Arc<AppState>>,
    Path(name): Path<String>,
) -> impl IntoResponse {
    let path = match state.dot_paths.get(&name) {
        Some(p) => p.clone(),
        None => {
            return (
                StatusCode::NOT_FOUND,
                axum::Json(json!({"error": "DOT file not found"})),
            )
                .into_response()
        }
    };

    let content = match tokio::fs::read_to_string(&path).await {
        Ok(c) => c,
        Err(e) => {
            return AppError::FileIo {
                path: path.display().to_string(),
                source: e,
            }
            .into_response()
        }
    };

    match parse_edges(&content) {
        Ok(edges) => axum::Json(edges).into_response(),
        Err(AppError::DotParse { detail }) => {
            let body = json!({"error": format!("DOT parse error: {detail}")});
            (StatusCode::BAD_REQUEST, axum::Json(body)).into_response()
        }
        Err(e) => e.into_response(),
    }
}

/// GET /api/dots — return the list of registered DOT filenames
async fn handle_api_dots(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    axum::Json(json!({ "dots": state.dot_names }))
}

/// GET /api/cxdb/instances — return the configured CXDB URLs
async fn handle_api_cxdb_instances(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    axum::Json(json!({ "instances": state.cxdb_urls }))
}

/// GET /api/cxdb/{index}/* — reverse proxy to the corresponding CXDB instance
async fn handle_api_cxdb(
    State(state): State<Arc<AppState>>,
    Path((index_str, path)): Path<(String, String)>,
    req: Request,
) -> impl IntoResponse {
    let index: usize = match index_str.parse() {
        Ok(i) => i,
        Err(_) => {
            return (
                StatusCode::NOT_FOUND,
                format!("invalid CXDB index: {index_str}"),
            )
                .into_response()
        }
    };

    let upstream_url = match state.cxdb_urls.get(index) {
        Some(u) => u.clone(),
        None => {
            return (
                StatusCode::NOT_FOUND,
                format!("CXDB instance {index} not found"),
            )
                .into_response()
        }
    };

    // Rebuild path with query string
    let path_and_query = if let Some(q) = req.uri().query() {
        format!("/{path}?{q}")
    } else {
        format!("/{path}")
    };

    // Convert to a plain Body request
    let (parts, body) = req.into_parts();
    let new_req = axum::http::Request::from_parts(parts, body);

    proxy_to_cxdb(&upstream_url, &path_and_query, new_req)
        .await
        .into_response()
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::StatusCode;
    use axum_test::TestServer;
    use std::io::Write;
    use tempfile::NamedTempFile;

    fn make_dot_file(content: &str) -> NamedTempFile {
        let mut f = NamedTempFile::with_suffix(".dot").unwrap();
        f.write_all(content.as_bytes()).unwrap();
        f
    }

    fn make_state(dot_files: Vec<(&str, &str)>) -> AppState {
        // dot_files: Vec<(basename, content)>
        let dir = tempfile::tempdir().unwrap();
        let mut dot_names = Vec::new();
        let mut dot_paths = HashMap::new();

        for (name, content) in dot_files {
            let path = dir.path().join(name);
            std::fs::write(&path, content).unwrap();
            dot_names.push(name.to_string());
            dot_paths.insert(name.to_string(), path);
        }

        // Keep dir alive by leaking it (acceptable in tests)
        std::mem::forget(dir);

        AppState {
            dot_names,
            dot_paths,
            cxdb_urls: vec!["http://127.0.0.1:9110".into()],
            dev_mode: false,
            assets_dir: PathBuf::from("assets"),
        }
    }

    #[tokio::test]
    async fn test_api_dots_returns_ordered_list() {
        let state = make_state(vec![
            ("alpha.dot", "digraph alpha {}"),
            ("beta.dot", "digraph beta {}"),
        ]);
        let app = build_router(state);
        let server = TestServer::new(app).unwrap();

        let resp = server.get("/api/dots").await;
        assert_eq!(resp.status_code(), StatusCode::OK);
        let body: serde_json::Value = resp.json();
        let dots = body["dots"].as_array().unwrap();
        assert_eq!(dots[0], "alpha.dot");
        assert_eq!(dots[1], "beta.dot");
    }

    #[tokio::test]
    async fn test_api_cxdb_instances() {
        let state = make_state(vec![("alpha.dot", "digraph alpha {}")]);
        let app = build_router(state);
        let server = TestServer::new(app).unwrap();

        let resp = server.get("/api/cxdb/instances").await;
        assert_eq!(resp.status_code(), StatusCode::OK);
        let body: serde_json::Value = resp.json();
        let instances = body["instances"].as_array().unwrap();
        assert_eq!(instances[0], "http://127.0.0.1:9110");
    }

    #[tokio::test]
    async fn test_dot_file_not_found() {
        let state = make_state(vec![("alpha.dot", "digraph alpha {}")]);
        let app = build_router(state);
        let server = TestServer::new(app).unwrap();

        let resp = server.get("/dots/nonexistent.dot").await;
        assert_eq!(resp.status_code(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn test_dot_nodes_returns_parsed_attributes() {
        let state = make_state(vec![(
            "alpha.dot",
            r#"digraph alpha {
                implement [shape=box, prompt="Do the work"]
                check_fmt [shape=parallelogram, tool_command="cargo fmt --check"]
            }"#,
        )]);
        let app = build_router(state);
        let server = TestServer::new(app).unwrap();

        let resp = server.get("/dots/alpha.dot/nodes").await;
        assert_eq!(resp.status_code(), StatusCode::OK);
        let body: serde_json::Value = resp.json();
        assert_eq!(body["implement"]["shape"], "box");
        assert_eq!(body["implement"]["prompt"], "Do the work");
        assert_eq!(body["check_fmt"]["shape"], "parallelogram");
        assert_eq!(body["check_fmt"]["tool_command"], "cargo fmt --check");
    }

    #[tokio::test]
    async fn test_dot_nodes_not_found() {
        let state = make_state(vec![("alpha.dot", "digraph alpha {}")]);
        let app = build_router(state);
        let server = TestServer::new(app).unwrap();

        let resp = server.get("/dots/nonexistent.dot/nodes").await;
        assert_eq!(resp.status_code(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn test_dot_edges_returns_parsed_edges() {
        let state = make_state(vec![(
            "alpha.dot",
            r#"digraph alpha {
                implement -> check_fmt [label="ok"]
            }"#,
        )]);
        let app = build_router(state);
        let server = TestServer::new(app).unwrap();

        let resp = server.get("/dots/alpha.dot/edges").await;
        assert_eq!(resp.status_code(), StatusCode::OK);
        let body: serde_json::Value = resp.json();
        let edges = body.as_array().unwrap();
        assert_eq!(edges.len(), 1);
        assert_eq!(edges[0]["source"], "implement");
        assert_eq!(edges[0]["target"], "check_fmt");
        assert_eq!(edges[0]["label"], "ok");
    }

    #[tokio::test]
    async fn test_dot_edges_not_found() {
        let state = make_state(vec![("alpha.dot", "digraph alpha {}")]);
        let app = build_router(state);
        let server = TestServer::new(app).unwrap();

        let resp = server.get("/dots/nonexistent.dot/edges").await;
        assert_eq!(resp.status_code(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn test_dot_file_serves_content() {
        let dot_content = "digraph alpha { start [shape=Mdiamond] }";
        let state = make_state(vec![("alpha.dot", dot_content)]);
        let app = build_router(state);
        let server = TestServer::new(app).unwrap();

        let resp = server.get("/dots/alpha.dot").await;
        assert_eq!(resp.status_code(), StatusCode::OK);
        assert!(resp.text().contains("digraph alpha"));
    }

    #[tokio::test]
    async fn test_dot_parse_error_returns_400() {
        let state = make_state(vec![("bad.dot", "digraph alpha { /* unterminated")]);
        let app = build_router(state);
        let server = TestServer::new(app).unwrap();

        let resp = server.get("/dots/bad.dot/nodes").await;
        assert_eq!(resp.status_code(), StatusCode::BAD_REQUEST);
        let body: serde_json::Value = resp.json();
        assert!(body["error"].as_str().unwrap().contains("DOT parse error"));
    }

    #[tokio::test]
    async fn test_api_cxdb_proxy_unreachable_returns_502() {
        let mut state = make_state(vec![("alpha.dot", "digraph alpha {}")]);
        state.cxdb_urls = vec!["http://127.0.0.1:19999".into()]; // unreachable
        let app = build_router(state);
        let server = TestServer::new(app).unwrap();

        let resp = server.get("/api/cxdb/0/v1/contexts").await;
        assert_eq!(resp.status_code(), StatusCode::BAD_GATEWAY);
    }

    #[tokio::test]
    async fn test_api_cxdb_out_of_range_returns_404() {
        let state = make_state(vec![("alpha.dot", "digraph alpha {}")]);
        let app = build_router(state);
        let server = TestServer::new(app).unwrap();

        let resp = server.get("/api/cxdb/99/v1/contexts").await;
        assert_eq!(resp.status_code(), StatusCode::NOT_FOUND);
    }
}
