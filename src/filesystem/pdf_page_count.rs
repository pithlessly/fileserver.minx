use axum::http;

use std::path::Path;

pub fn pdf_page_count(path: &Path) -> Option<usize> {
    Some(lopdf::Document::load(path).ok()?.get_pages().len())
}

pub fn add_header<T>(response: &mut http::Response<T>, count: Option<usize>) {
    if let Some(count) = count {
        response
            .headers_mut()
            .insert("Minx-Page-Count", http::HeaderValue::from(count));
    }
}
