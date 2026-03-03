use crate::error::{AppError, AppResult};
use axum::body::Body;
use axum::http::{Request, Response, StatusCode};
use axum::response::IntoResponse;

/// Forward an HTTP request to an upstream CXDB instance.
/// Returns a 502 if the upstream is unreachable.
pub async fn proxy_to_cxdb(
    upstream_url: &str,
    path_and_query: &str,
    original_req: Request<Body>,
) -> impl IntoResponse {
    let target_url = format!("{}{}", upstream_url.trim_end_matches('/'), path_and_query);

    match proxy_request(original_req, &target_url).await {
        Ok(response) => response,
        Err(e) => {
            let body = serde_json::json!({ "error": format!("CXDB proxy error: {e}") });
            (StatusCode::BAD_GATEWAY, axum::Json(body)).into_response()
        }
    }
}

async fn proxy_request(req: Request<Body>, target_url: &str) -> AppResult<Response<Body>> {
    let client = reqwest::Client::builder()
        .build()
        .map_err(|e| AppError::CxdbProxy {
            detail: format!("failed to build HTTP client: {e}"),
        })?;

    let method = reqwest::Method::from_bytes(req.method().as_str().as_bytes()).map_err(|e| {
        AppError::CxdbProxy {
            detail: format!("invalid method: {e}"),
        }
    })?;

    let body_bytes = axum::body::to_bytes(req.into_body(), usize::MAX)
        .await
        .map_err(|e| AppError::CxdbProxy {
            detail: format!("failed to read request body: {e}"),
        })?;

    let upstream_req = client
        .request(method, target_url)
        .body(body_bytes)
        .build()
        .map_err(|e| AppError::CxdbProxy {
            detail: format!("failed to build upstream request: {e}"),
        })?;

    let upstream_resp = client
        .execute(upstream_req)
        .await
        .map_err(|e| AppError::CxdbProxy {
            detail: format!("upstream unreachable: {e}"),
        })?;

    let status =
        StatusCode::from_u16(upstream_resp.status().as_u16()).map_err(|e| AppError::CxdbProxy {
            detail: format!("invalid status code from upstream: {e}"),
        })?;

    let mut response_builder = Response::builder().status(status);

    // Forward response headers
    for (name, value) in upstream_resp.headers() {
        if let (Ok(n), Ok(v)) = (
            axum::http::HeaderName::from_bytes(name.as_str().as_bytes()),
            axum::http::HeaderValue::from_bytes(value.as_bytes()),
        ) {
            response_builder = response_builder.header(n, v);
        }
    }

    let body_bytes = upstream_resp
        .bytes()
        .await
        .map_err(|e| AppError::CxdbProxy {
            detail: format!("failed to read upstream response: {e}"),
        })?;

    let response =
        response_builder
            .body(Body::from(body_bytes))
            .map_err(|e| AppError::CxdbProxy {
                detail: format!("failed to build response: {e}"),
            })?;

    Ok(response)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_proxy_module_exists() {
        // Basic smoke test that the module compiles
        let _ = std::mem::size_of::<AppError>();
    }

    #[tokio::test]
    async fn test_proxy_unreachable_returns_502() {
        use axum::http::Request;
        let req = Request::builder()
            .method("GET")
            .uri("/v1/contexts")
            .body(Body::empty())
            .unwrap();

        let response = proxy_to_cxdb("http://127.0.0.1:19999", "/v1/contexts", req).await;
        let resp = response.into_response();
        assert_eq!(resp.status(), StatusCode::BAD_GATEWAY);
    }
}
