use crate::error::{AppError, AppResult};
use clap::Parser;
use std::path::PathBuf;

/// CXDB Graph UI server — renders Attractor pipeline DOT files as interactive SVGs
/// with real-time CXDB execution status overlays.
#[derive(Debug, Parser, Clone)]
#[command(name = "cxdb-graph-ui")]
#[command(
    about = "Local web dashboard for Attractor pipeline visualization with CXDB status overlays"
)]
pub struct Config {
    /// TCP port for the UI server
    #[arg(long, default_value = "9030")]
    pub port: u16,

    /// CXDB HTTP API base URL (repeatable for multiple instances)
    #[arg(long = "cxdb", default_value = "http://127.0.0.1:9110")]
    pub cxdb_urls: Vec<String>,

    /// Path to a pipeline DOT file (repeatable for multiple pipelines)
    #[arg(long = "dot", required = true)]
    pub dot_files: Vec<PathBuf>,

    /// Serve assets from filesystem instead of embedded (development mode)
    #[arg(long = "dev", default_value = "false")]
    pub dev_mode: bool,

    /// Assets directory for dev mode
    #[arg(long = "assets-dir", default_value = "assets")]
    pub assets_dir: PathBuf,
}

impl Config {
    /// Validate configuration after parsing.
    ///
    /// Checks:
    /// - At least one --dot file provided (enforced by clap `required = true`, but double-check)
    /// - No duplicate basenames
    /// - No duplicate graph IDs
    /// - No anonymous graphs (must have a named graph ID)
    pub fn validate(&self) -> AppResult<()> {
        if self.dot_files.is_empty() {
            return Err(AppError::CliValidation {
                detail: "at least one --dot file is required".into(),
            });
        }

        // Check for duplicate basenames
        let mut basenames = std::collections::HashMap::new();
        for path in &self.dot_files {
            let basename = path.file_name().and_then(|n| n.to_str()).ok_or_else(|| {
                AppError::CliValidation {
                    detail: format!("invalid path: {}", path.display()),
                }
            })?;
            if let Some(existing) = basenames.insert(basename.to_string(), path.clone()) {
                return Err(AppError::CliValidation {
                    detail: format!(
                        "duplicate basename '{}': '{}' and '{}'",
                        basename,
                        existing.display(),
                        path.display()
                    ),
                });
            }
        }

        // Check for duplicate graph IDs and anonymous graphs
        let mut graph_ids: std::collections::HashMap<String, PathBuf> =
            std::collections::HashMap::new();
        for path in &self.dot_files {
            let content = std::fs::read_to_string(path).map_err(|e| AppError::FileIo {
                path: path.display().to_string(),
                source: e,
            })?;

            let graph_id = crate::dot_parser::extract_graph_id(&content).map_err(|_| {
                AppError::CliValidation {
                    detail: format!(
                        "anonymous graph in '{}': named graphs are required for pipeline discovery",
                        path.display()
                    ),
                }
            })?;

            if let Some(existing) = graph_ids.insert(graph_id.clone(), path.clone()) {
                return Err(AppError::CliValidation {
                    detail: format!(
                        "duplicate graph ID '{}' in '{}' and '{}'",
                        graph_id,
                        existing.display(),
                        path.display()
                    ),
                });
            }
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;

    fn write_dot(content: &str) -> NamedTempFile {
        let mut f = NamedTempFile::new().unwrap();
        f.write_all(content.as_bytes()).unwrap();
        f
    }

    #[test]
    fn test_validate_no_dots_fails() {
        let config = Config {
            port: 9030,
            cxdb_urls: vec!["http://127.0.0.1:9110".into()],
            dot_files: vec![],
            dev_mode: false,
            assets_dir: PathBuf::from("assets"),
        };
        assert!(config.validate().is_err());
    }

    #[test]
    fn test_validate_duplicate_basename_fails() {
        let f1 = write_dot("digraph alpha {}");
        let f2 = write_dot("digraph beta {}");
        // Create two paths with the same basename by using the same filename
        let dir = tempfile::tempdir().unwrap();
        let p1 = dir.path().join("pipeline.dot");
        let p2 = dir.path().join("sub").join("pipeline.dot");
        std::fs::create_dir_all(p2.parent().unwrap()).unwrap();
        std::fs::copy(f1.path(), &p1).unwrap();
        std::fs::copy(f2.path(), &p2).unwrap();

        let config = Config {
            port: 9030,
            cxdb_urls: vec!["http://127.0.0.1:9110".into()],
            dot_files: vec![p1, p2],
            dev_mode: false,
            assets_dir: PathBuf::from("assets"),
        };
        let result = config.validate();
        assert!(result.is_err());
        let msg = result.err().unwrap().to_string();
        assert!(msg.contains("duplicate basename"));
    }

    #[test]
    fn test_validate_duplicate_graph_id_fails() {
        let f1 = write_dot("digraph my_pipeline { start [shape=Mdiamond] }");
        let f2 = write_dot("digraph my_pipeline { end [shape=Msquare] }");

        let config = Config {
            port: 9030,
            cxdb_urls: vec!["http://127.0.0.1:9110".into()],
            dot_files: vec![f1.path().to_path_buf(), f2.path().to_path_buf()],
            dev_mode: false,
            assets_dir: PathBuf::from("assets"),
        };
        let result = config.validate();
        assert!(result.is_err());
        let msg = result.err().unwrap().to_string();
        assert!(msg.contains("duplicate graph ID"));
    }

    #[test]
    fn test_validate_anonymous_graph_fails() {
        let f = write_dot("digraph { start [shape=Mdiamond] }");
        let config = Config {
            port: 9030,
            cxdb_urls: vec!["http://127.0.0.1:9110".into()],
            dot_files: vec![f.path().to_path_buf()],
            dev_mode: false,
            assets_dir: PathBuf::from("assets"),
        };
        let result = config.validate();
        assert!(result.is_err());
        let msg = result.err().unwrap().to_string();
        assert!(msg.contains("anonymous graph") || msg.contains("named graphs"));
    }

    #[test]
    fn test_validate_valid_config_succeeds() {
        let f1 = write_dot("digraph alpha_pipeline { start [shape=Mdiamond] }");
        let f2 = write_dot("digraph beta_pipeline { start [shape=Mdiamond] }");

        let config = Config {
            port: 9030,
            cxdb_urls: vec!["http://127.0.0.1:9110".into()],
            dot_files: vec![f1.path().to_path_buf(), f2.path().to_path_buf()],
            dev_mode: false,
            assets_dir: PathBuf::from("assets"),
        };
        assert!(config.validate().is_ok());
    }
}
