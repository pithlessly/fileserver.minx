use axum::body::Body;
use axum::extract::{Query, Request, State};
use axum::http::{HeaderValue, Method, StatusCode, Uri, header};
use axum::response::{IntoResponse as _, Response};
use tower_http::services::ServeFile;

use std::borrow::Cow;
use std::collections::HashMap;
use std::ffi::OsStr;
use std::os::unix::ffi::OsStrExt as _; // OsStr::{from_bytes, as_bytes}
use std::os::unix::fs::MetadataExt as _; // Metadata::size
use std::path::{Path, PathBuf};
use std::sync::Arc;

use crate::ResponseBuilder;
use crate::Result;

mod file_listing;

/// Ensure that responses of type `application/pdf` have `content-disposition: inline` header set.
/// Used as axum middleware via `axum::middleware::map_response`.
pub async fn ensure_pdfs_are_inline(mut response: Response) -> Response {
    let headers = response.headers_mut();
    if let Some(ty) = headers.get(header::CONTENT_TYPE)
        && ty == "application/pdf"
    {
        const INLINE: HeaderValue = HeaderValue::from_static("inline");
        let _ = headers.entry(header::CONTENT_DISPOSITION).or_insert(INLINE);
    }
    response
}

#[derive(Clone)]
pub struct FilesystemState {
    pub fs_root: Arc<Path>,
    pub syntax_highlighter: arborium::Highlighter,
    pub templates: minijinja::Environment<'static>,
    #[allow(dead_code)]
    pub arborium_theme_css: String,
    pub max_file_listing_size: u64,
}

pub async fn filesystem(
    state: State<FilesystemState>,
    method: Method,
    uri: Uri,
    query: Query<HashMap<String, String>>,
    request: Request,
) -> Result<Response> {
    let rb = {
        let have_body = match method {
            // we could also reasonably respond to OPTIONS
            Method::GET => true,
            Method::HEAD => false,
            _ => return Ok(StatusCode::METHOD_NOT_ALLOWED.into_response()),
        };
        ResponseBuilder::new(have_body, &state.templates)
    };
    let listing = query.0.contains_key("listing");
    let uri_path = uri.path();
    let uri_path: Cow<[u8]> = percent_encoding::percent_decode_str(uri_path).into();
    let absolute_path = state.fs_root.join(OsStr::from_bytes(
        uri_path.strip_prefix(b"/").unwrap_or(b""),
    ));
    let uri_path_lossy: Cow<str> = String::from_utf8_lossy(&uri_path);
    let uri_path_lossy = trim_suffix_if_present(&uri_path_lossy, "/");
    let absolute_path = match absolute_path.canonicalize() {
        Ok(p) => p,
        Err(e) => return handle_io_error(rb, e, &uri_path_lossy),
    };
    if !absolute_path.starts_with(&state.fs_root) {
        return Ok(error_page(rb, StatusCode::NOT_FOUND, &uri_path_lossy));
    }
    if absolute_path.is_dir() {
        if !listing {
            let index_html = absolute_path.join("index.html");
            if index_html.is_file() {
                return Ok(serve_file(&index_html, request).await);
            }
        }
        let is_root = absolute_path == *state.fs_root;
        serve_directory_listing(rb, &uri_path, uri_path_lossy, absolute_path, is_root)
    } else {
        serve_file_or_listing(
            &state,
            rb,
            listing,
            &uri_path,
            uri_path_lossy,
            &absolute_path,
            request,
        )
        .await
    }
}

fn trim_suffix_if_present<'a, 'b>(haystack: &'a str, needle: &'b str) -> &'a str {
    haystack.strip_suffix(needle).unwrap_or(haystack)
}

async fn serve_file_or_listing(
    state: &FilesystemState,
    rb: ResponseBuilder<'_>,
    listing: bool,
    uri_path: &[u8],
    uri_path_lossy: &str,
    absolute_path: &Path,
    request: Request,
) -> Result<Response> {
    use file_listing::ServeFileListingError as E;
    let result = if listing {
        file_listing::serve_file_listing(state, rb, uri_path, uri_path_lossy, absolute_path)
    } else {
        Err(E::NoListing)
    };
    match result {
        Ok(resp) => Ok(resp),
        Err(E::Io(e)) => Err(e.into()),
        Err(E::NoListing) => Ok(serve_file(&absolute_path, request).await),
    }
}

async fn serve_file(path: &Path, request: Request) -> Response {
    use http_body_util::BodyExt as _;
    use tower::util::ServiceExt as _;
    let Ok(response) = ServeFile::new(path).oneshot(request).await;
    response.map(|body| Body::new(body.boxed_unsync()))
}

fn serve_directory_listing(
    rb: ResponseBuilder,
    uri_path: &[u8],
    uri_path_lossy: &str,
    absolute_path: PathBuf,
    is_root: bool,
) -> Result<Response> {
    rb.ok().try_render("directory.html", || {
        let mut uri_path_encoded = crate::percent_encode(uri_path);
        if !uri_path_encoded.ends_with('/') {
            uri_path_encoded.push('/');
        }
        Ok(minijinja::context!(
            uri_path_lossy,
            uri_path_encoded,
            is_root,
            entries => read_entries(&absolute_path)?,
        ))
    })
}

#[derive(serde::Serialize)]
struct DirEntry {
    is_dir: bool,
    name: String,
    name_encoded: String,  // percent-encoded
    listing: &'static str, // either "" or "?listing"
    mtime: minijinja::Value,
    size: Cow<'static, str>,
}

// Sources of errors:
// - read_dir() fails (we should have already checked that this is a directory)
// - read_dir() returns a failing item
fn read_entries(absolute_path: &Path) -> Result<Vec<DirEntry>> {
    let mut entries: Vec<DirEntry> = std::fs::read_dir(absolute_path)?
        .map(|entry| {
            let entry = entry?;
            let (is_dir, mtime, size): (bool, std::io::Result<String>, Option<Cow<str>>) =
                match entry.metadata() {
                    Ok(d) => {
                        let is_dir = d.is_dir();
                        let mtime = d.modified().map(|time| {
                            chrono::DateTime::<chrono::Local>::from(time)
                                .format("%Y %b %d %H:%M")
                                .to_string()
                        });
                        let size = (!is_dir).then(|| d.size().to_string().into());
                        (is_dir, mtime, size)
                    }
                    Err(e) => (false, Err(e), None),
                };
            let name = entry.file_name();
            let mut name_encoded = crate::percent_encode(OsStr::as_bytes(&name));
            let mut name: String = name.to_string_lossy().to_string();
            if is_dir {
                name_encoded.push('/');
                name.push('/');
            }
            let listing =
                if !is_dir && (name.ends_with(".html") || is_definitely_a_binary_format(&name)) {
                    ""
                } else {
                    "?listing"
                };
            Ok(DirEntry {
                is_dir,
                name,
                name_encoded,
                listing,
                mtime: match mtime {
                    Ok(mtime) => mtime.into(),
                    Err(e) => minijinja::Value::from_safe_string(format!(
                        "<span class='e'>{}</span>",
                        e.kind()
                    )),
                },
                size: size.unwrap_or("-".into()),
            })
        })
        .collect::<Result<_>>()?;
    entries.sort_by(|e1, e2| Ord::cmp(&e1.order(), &e2.order()));
    Ok(entries)
}

fn is_definitely_a_binary_format(name: &str) -> bool {
    let Some(guess) = mime_guess::from_path(name).first() else {
        return false;
    };
    guess == mime_guess::mime::APPLICATION_PDF || guess.type_() == mime_guess::mime::IMAGE
}

impl DirEntry {
    fn order(&self) -> (u8, &str) {
        let priority = if self.is_dir {
            2
        } else if self.name == "index.html" {
            0
        } else if self.name.ends_with(".html") {
            1
        } else {
            3
        };
        (priority, &self.name)
    }
}

fn handle_io_error(rb: ResponseBuilder, err: std::io::Error, message: &str) -> Result<Response> {
    use std::io::ErrorKind as K;
    match err.kind() {
        K::NotFound | K::NotADirectory => Ok(error_page(rb, StatusCode::NOT_FOUND, message)),
        K::PermissionDenied => Ok(error_page(rb, StatusCode::FORBIDDEN, message)),
        _ => Err(err.into()),
    }
}

fn error_page(rb: ResponseBuilder, code: StatusCode, message: &str) -> Response {
    rb.status(code).render("error.html", || {
        minijinja::context!(
            code => code.to_string(),
            message,
        )
    })
}
