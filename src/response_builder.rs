use std::convert::Infallible;

use axum::body::Body;
use axum::http::{self, HeaderName, HeaderValue, StatusCode, header};
use axum::response::Response;

/// Wrapper around `http::response::Builder()` that can be configured to not actually construct the
/// body. This accelerates HTTP HEAD queries.
#[derive(Clone)]
pub struct ResponseBuilder<'a> {
    have_body: bool,
    templates: &'a minijinja::Environment<'static>,
}

impl<'a> ResponseBuilder<'a> {
    pub fn new(have_body: bool, templates: &'a minijinja::Environment<'static>) -> Self {
        Self {
            have_body,
            templates,
        }
    }

    pub fn status(&self, code: StatusCode) -> ResponseBuilderWithStatus {
        ResponseBuilderWithStatus {
            have_body: self.have_body,
            templates: self.templates,
            inner: http::response::Builder::new().status(code),
        }
    }

    pub fn ok(&self) -> ResponseBuilderWithStatus {
        self.status(StatusCode::OK)
    }
}

pub struct ResponseBuilderWithStatus<'a> {
    have_body: bool,
    templates: &'a minijinja::Environment<'static>,
    inner: http::response::Builder,
}

impl<'a> ResponseBuilderWithStatus<'a> {
    pub fn header<K, V>(mut self, name: K, value: V) -> Self
    where
        K: TryInto<HeaderName>,
        <K as TryInto<HeaderName>>::Error: Into<http::Error>,
        V: TryInto<HeaderValue>,
        <V as TryInto<HeaderValue>>::Error: Into<http::Error>,
    {
        self.inner = self.inner.header(name, value);
        self
    }

    pub fn content_type<V>(self, value: V) -> Self
    where
        V: TryInto<HeaderValue>,
        <V as TryInto<HeaderValue>>::Error: Into<http::Error>,
    {
        self.header(header::CONTENT_TYPE, value)
    }

    pub fn content_type_html(self) -> Self {
        self.content_type("text/html; charset=utf-8")
    }

    fn try_body_with_templates<E>(
        self,
        f: impl FnOnce(&minijinja::Environment<'static>) -> Result<Body, E>,
    ) -> Result<Response, E> {
        Ok(self
            .inner
            .body(if self.have_body {
                f(self.templates)?
            } else {
                Body::empty()
            })
            .expect("invalid invocation of ResponseBuilder"))
    }

    pub fn try_body<E>(self, f: impl FnOnce() -> Result<Body, E>) -> Result<Response, E> {
        self.try_body_with_templates(|_| f())
    }

    pub fn body(self, f: impl FnOnce() -> Body) -> Response {
        let Ok(response) = self.try_body::<Infallible>(|| Ok(f()));
        response
    }

    pub fn try_render<E, Ctx: serde::Serialize>(
        self,
        template_name: &str,
        f: impl FnOnce() -> Result<Ctx, E>,
    ) -> Result<Response, E> {
        self.content_type_html()
            .try_body_with_templates(|templates| {
                Ok(render_template(templates, template_name, f()?).into())
            })
    }

    pub fn render<Ctx: serde::Serialize>(
        self,
        template_name: &str,
        f: impl FnOnce() -> Ctx,
    ) -> Response {
        let Ok(response) = self.try_render::<Infallible, _>(template_name, || Ok(f()));
        response
    }
}

fn render_template(
    env: &minijinja::Environment,
    template_name: &str,
    context: impl serde::Serialize,
) -> String {
    env.get_template(template_name)
        .expect("cannot find template")
        .render(context)
        .expect("template error")
}
