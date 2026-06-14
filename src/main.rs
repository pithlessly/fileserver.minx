use anyhow::anyhow;
use axum::handler::Handler;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::Router;
use tower_http::catch_panic::CatchPanicLayer;
use tower_http::services::ServeFile;

mod response_builder;
use response_builder::ResponseBuilder;

mod filesystem;
use filesystem::FilesystemState;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let ip_and_port = std::env::args().nth(1).expect("please pass [ip]:[port]");
    let addresses: Box<[_]> = tokio::net::lookup_host(&ip_and_port).await?.collect();
    assert!(!addresses.is_empty());
    let filesystem_state = init_filesystem_state()?;
    let app = Router::new()
        .route_service(
            "/file_listing.css",
            ServeFile::new("static/file_listing.css"),
        )
        .route_service(
            "/directory_listing.css",
            ServeFile::new("static/directory_listing.css"),
        )
        .fallback_service(Handler::with_state(
            filesystem::filesystem,
            filesystem_state,
        ))
        .layer(axum::middleware::map_response(
            filesystem::ensure_pdfs_are_inline,
        ))
        .layer(CatchPanicLayer::new());
    let listener = tokio::net::TcpListener::bind(&*addresses).await?;
    eprintln!("listening on {ip_and_port}");
    axum::serve(listener, app).await?;
    Ok(())
}

fn init_filesystem_state() -> anyhow::Result<FilesystemState> {
    let fs_root = std::env::var("MINX_FS_ROOT").map_err(|_| anyhow!("please pass MINX_FS_ROOT"))?;
    let syntax_highlighter = arborium::Highlighter::new();
    let mut templates = minijinja::Environment::new();
    templates.set_loader(minijinja::path_loader("./templates/"));
    let arborium_theme_css = {
        let selector_prefix = "pre";
        arborium_theme::builtin::dayfox().to_css(selector_prefix)
    };
    Ok(FilesystemState {
        fs_root: std::path::PathBuf::from(fs_root).into(),
        syntax_highlighter,
        templates,
        arborium_theme_css,
        max_file_listing_size: 1024 * 1024,
    })
}

#[derive(Debug)]
struct AppError(anyhow::Error);

type Result<T, E = AppError> = std::result::Result<T, E>;

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

fn percent_encode(bytes: &[u8]) -> String {
    percent_encoding::percent_encode(
        bytes,
        &const {
            percent_encoding::NON_ALPHANUMERIC
                .remove(b'_')
                .remove(b'-')
                .remove(b'.')
                .remove(b'/')
        },
    )
    .to_string()
}
