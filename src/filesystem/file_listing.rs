use axum::response::Response;

use std::os::unix::fs::MetadataExt as _; // Metadata::size
use std::path::Path;

use crate::FilesystemState;
use crate::ResponseBuilder;
use crate::Result;

pub enum ServeFileListingError {
    Io(std::io::Error),
    NoListing,
}

impl From<std::io::Error> for ServeFileListingError {
    fn from(err: std::io::Error) -> Self {
        Self::Io(err)
    }
}

// Returns:
// - Err(e) for an unexpected IO error (HTTP 5xx);
// - Err(Err(()) if a listing cannot be created for this file;
// - Err(Ok(resp)) if a listing was created successfully.
pub fn serve_file_listing(
    state: &FilesystemState,
    rb: ResponseBuilder,
    uri_path: &[u8],
    uri_path_lossy: &str,
    absolute_path: &Path,
) -> Result<Response, ServeFileListingError> {
    rb.ok().try_render("file_listing.html", || {
        use ServeFileListingError as E;
        if !(absolute_path.metadata()?.size() <= state.max_file_listing_size) {
            return Err(E::NoListing);
        }
        let mime = mime_guess::from_path(absolute_path).first_or_text_plain();
        // eprintln!("{}, {:?}", absolute_path.display(), mime);
        let is_textual = mime.type_() == mime_guess::mime::TEXT
            || mime == "application/x-sh"
            || mime == "application/vnd.lotus-screencam" // `.scm` is Scheme
            || mime == "application/xml"
            || mime == "image/svg+xml";
        if !is_textual {
            return Err(E::NoListing);
        }
        let source = std::fs::read(absolute_path).map_err(E::Io)?;
        let source = str::from_utf8(&source).map_err(|_| E::NoListing)?;
        let (highlighted, errors) = syntax_highlighted(state, uri_path, source)?;
        let file_content = match highlighted {
            Some(html) => html,
            None => minijinja::Value::from(source),
        };
        let errors: Vec<_> = errors.into_iter().map(|e| e.to_string()).collect();
        Ok(minijinja::context!(
            path => uri_path_lossy,
            file_content,
            errors,
        ))
    })
}

fn syntax_highlighted(
    state: &FilesystemState,
    uri_path: &[u8],
    source: &str,
) -> std::io::Result<(Option<minijinja::Value>, Option<arborium::Error>)> {
    let Some(language) = str::from_utf8(uri_path)
        .ok()
        .and_then(arborium::detect_language)
    else {
        return Ok((None, None));
    };
    let mut syntax_highlighter = state.syntax_highlighter.fork();
    match syntax_highlighter.highlight(language, source) {
        Ok(html) => Ok((Some(minijinja::Value::from_safe_string(html)), None)),
        Err(arborium::Error::Io(e)) => Err(e),
        Err(arborium::Error::UnsupportedLanguage { .. }) => Ok((None, None)),
        Err(e) => Ok((None, Some(e))),
    }
}
