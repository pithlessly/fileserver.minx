use anyhow::anyhow;
use axum::handler::Handler;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::Router;
use tower_http::catch_panic::CatchPanicLayer;

mod response_builder;
use response_builder::ResponseBuilder;

mod filesystem;
use filesystem::FilesystemState;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let filesystem_state = init_filesystem_state()?;
    let app = Router::new()
        // .route("/",        get(|| route("head"))
        // .route("/{*path}", get(|| async { "bar" }))
        .fallback_service(Handler::with_state(
            filesystem::filesystem,
            filesystem_state,
        ))
        .layer(axum::middleware::map_response(
            filesystem::ensure_pdfs_are_inline,
        ))
        .layer(CatchPanicLayer::new());
    let listener = tokio::net::TcpListener::bind("0.0.0.0:8041").await?;
    axum::serve(listener, app).await?;
    Ok(())
}

fn init_filesystem_state() -> anyhow::Result<FilesystemState> {
    let fs_root = std::env::var("MINX_FS_ROOT").map_err(|_| anyhow!("please pass MINX_FS_ROOT"))?;
    let mut templates = minijinja::Environment::new();
    templates.set_loader(minijinja::path_loader("./templates/"));
    Ok(FilesystemState {
        fs_root: std::path::PathBuf::from(fs_root).into(),
        templates,
    })
}

#[derive(Debug)]
struct AppError(anyhow::Error);

type Result<T> = std::result::Result<T, AppError>;

impl<E: Into<anyhow::Error>> From<E> for AppError {
    fn from(err: E) -> Self {
        Self(err.into())
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Internal server error: {}", self.0),
        )
            .into_response()
    }
}
