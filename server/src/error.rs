use thiserror::Error;

/// Application-level error type for all fallible operations.
#[derive(Debug, Error)]
pub enum AppError {
    /// DOT file parsing error
    #[error("DOT parse error: {detail}")]
    DotParse { detail: String },

    /// File I/O error
    #[error("File I/O error for '{path}': {source}")]
    FileIo {
        path: String,
        #[source]
        source: std::io::Error,
    },

    /// CXDB proxy error
    #[error("CXDB proxy error: {detail}")]
    CxdbProxy { detail: String },

    /// CLI validation error
    #[error("CLI validation error: {detail}")]
    CliValidation { detail: String },

    /// HTTP handler error
    #[error("HTTP handler error: {detail}")]
    HttpHandler { detail: String },

    /// Embedded asset error
    #[error("Embedded asset error: {detail}")]
    Embed { detail: String },

    /// Reqwest HTTP client error
    #[error("HTTP client error: {0}")]
    Reqwest(#[from] reqwest::Error),
}

/// Type alias for Results with AppError.
pub type AppResult<T> = Result<T, AppError>;

impl axum::response::IntoResponse for AppError {
    fn into_response(self) -> axum::response::Response {
        use axum::http::StatusCode;
        use axum::Json;

        let (status, message) = match &self {
            AppError::DotParse { detail } => (
                StatusCode::BAD_REQUEST,
                format!("DOT parse error: {detail}"),
            ),
            AppError::FileIo { path, source } => (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("File I/O error for '{path}': {source}"),
            ),
            AppError::CxdbProxy { detail } => (
                StatusCode::BAD_GATEWAY,
                format!("CXDB proxy error: {detail}"),
            ),
            AppError::CliValidation { detail } => (
                StatusCode::BAD_REQUEST,
                format!("CLI validation error: {detail}"),
            ),
            AppError::HttpHandler { detail } => (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("HTTP handler error: {detail}"),
            ),
            AppError::Embed { detail } => (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Embedded asset error: {detail}"),
            ),
            AppError::Reqwest(e) => (StatusCode::BAD_GATEWAY, format!("HTTP client error: {e}")),
        };

        let body = serde_json::json!({ "error": message });
        (status, Json(body)).into_response()
    }
}

impl From<std::io::Error> for AppError {
    fn from(e: std::io::Error) -> Self {
        AppError::FileIo {
            path: String::new(),
            source: e,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::response::IntoResponse;

    #[test]
    fn test_dot_parse_error_status() {
        let err = AppError::DotParse {
            detail: "unexpected token".into(),
        };
        let response = err.into_response();
        assert_eq!(response.status(), axum::http::StatusCode::BAD_REQUEST);
    }

    #[test]
    fn test_file_io_error_status() {
        let err = AppError::FileIo {
            path: "/some/path".into(),
            source: std::io::Error::new(std::io::ErrorKind::NotFound, "not found"),
        };
        let response = err.into_response();
        assert_eq!(
            response.status(),
            axum::http::StatusCode::INTERNAL_SERVER_ERROR
        );
    }

    #[test]
    fn test_cxdb_proxy_error_status() {
        let err = AppError::CxdbProxy {
            detail: "upstream unreachable".into(),
        };
        let response = err.into_response();
        assert_eq!(response.status(), axum::http::StatusCode::BAD_GATEWAY);
    }

    #[test]
    fn test_embed_error_status() {
        let err = AppError::Embed {
            detail: "asset not found".into(),
        };
        let response = err.into_response();
        assert_eq!(
            response.status(),
            axum::http::StatusCode::INTERNAL_SERVER_ERROR
        );
    }

    #[test]
    fn test_app_result_type_alias() {
        fn returns_ok() -> AppResult<i32> {
            Ok(42)
        }
        fn returns_err() -> AppResult<i32> {
            Err(AppError::HttpHandler {
                detail: "test".into(),
            })
        }
        assert!(returns_ok().is_ok());
        assert!(returns_err().is_err());
    }
}
