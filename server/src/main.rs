use cxdb_graph_ui::{config::Config, server::run_server};

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .init();

    let config = <Config as clap::Parser>::parse();

    if let Err(e) = config.validate() {
        eprintln!("Error: {e}");
        std::process::exit(1);
    }

    let port = config.port;

    match run_server(config).await {
        Ok(()) => {}
        Err(e) => {
            eprintln!("Server error: {e}");
            std::process::exit(1);
        }
    }

    println!("Server on port {port} shut down");
}
