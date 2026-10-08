//! The dashboard's generic API transport (docs/fdash/SPEC.md §3.1): every
//! generated Dart API call reaches the backend through `api_request` /
//! `api_stream`, on the core's client (token, identity and scope headers,
//! refresh, the EN/AR refusal words — `madar_core::api_raw`). Binding code
//! only: these types are FFI-friendly copies of the core's, converted 1:1.
use flutter_rust_bridge::frb;
use madar_core::api_raw;

use crate::api::bridge::MadarBridge;
use crate::frb_generated::StreamSink;

/// One key/value pair: a query parameter, a header or a form field.
#[derive(Clone, Debug)]
pub struct ApiPair {
    pub key: String,
    pub value: String,
}

/// One file of a multipart call.
#[derive(Clone, Debug)]
pub struct ApiFile {
    pub field: String,
    pub filename: String,
    pub content_type: Option<String>,
    pub bytes: Vec<u8>,
}

/// One call. With `files`, the call is `multipart/form-data` carrying
/// `form_fields` and the files (`json_body` is not sent); otherwise
/// `json_body`, when present, is sent as `application/json`.
#[derive(Clone, Debug)]
pub struct ApiCall {
    pub method: String,
    /// Parameters substituted, starting with `/`.
    pub path: String,
    /// In order; a key may repeat.
    pub query: Vec<ApiPair>,
    pub headers: Vec<ApiPair>,
    pub json_body: Option<String>,
    pub form_fields: Vec<ApiPair>,
    pub files: Vec<ApiFile>,
}

/// A 2xx answer: status, headers (lower-case names, in order) and the body.
#[derive(Clone, Debug)]
pub struct ApiReply {
    pub status: u16,
    pub headers: Vec<ApiPair>,
    pub body: Vec<u8>,
}

/// How the host should react (`madar_core::api_raw::ApiFailureKind`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ApiFailureKind {
    /// The server was not reached.
    Offline,
    /// A 403 that did not come from the Madar server (a firewall answered).
    BlockedUpstream,
    /// The backend refused the session: sign in again.
    Unauthenticated,
    /// The backend refused the person.
    Forbidden,
    /// 400 / 422.
    Validation,
    /// Any other 4xx.
    Server,
    /// 5xx.
    Transient,
    /// The core could not build the call or read the answer.
    Internal,
}

/// A call that did not come back 2xx. `message` is human, in the active
/// language; `status` is 0 when the server was never reached; `body` is the
/// server's answer (its error envelope, with `vars`) when there was one.
#[derive(Clone, Debug, thiserror::Error)]
#[error("api {status}: {message}")]
pub struct ApiFailure {
    pub status: u16,
    pub code: Option<String>,
    pub message: String,
    pub kind: ApiFailureKind,
    pub body: Option<String>,
}

/// One item of an event stream: first `opened` (the server accepted it),
/// then a frame per item (`event`, `data`, `id`), or, as the last item, the
/// `failure` that ended it.
#[derive(Clone, Debug)]
pub struct ApiStreamItem {
    pub opened: bool,
    pub event: String,
    pub data: String,
    pub id: Option<String>,
    pub failure: Option<ApiFailure>,
}

fn pairs(v: Vec<ApiPair>) -> Vec<(String, String)> {
    v.into_iter().map(|p| (p.key, p.value)).collect()
}

impl From<ApiCall> for api_raw::ApiCall {
    fn from(c: ApiCall) -> Self {
        let body = if !c.files.is_empty() {
            api_raw::ApiBody::Multipart {
                fields: pairs(c.form_fields),
                files: c
                    .files
                    .into_iter()
                    .map(|f| api_raw::ApiFilePart {
                        field: f.field,
                        filename: f.filename,
                        content_type: f.content_type,
                        bytes: f.bytes,
                    })
                    .collect(),
            }
        } else {
            match c.json_body {
                Some(text) => api_raw::ApiBody::Json(text),
                None => api_raw::ApiBody::Empty,
            }
        };
        api_raw::ApiCall {
            method: c.method,
            path: c.path,
            query: pairs(c.query),
            headers: pairs(c.headers),
            body,
        }
    }
}

impl From<api_raw::ApiReply> for ApiReply {
    fn from(r: api_raw::ApiReply) -> Self {
        ApiReply {
            status: r.status,
            headers: r
                .headers
                .into_iter()
                .map(|(key, value)| ApiPair { key, value })
                .collect(),
            body: r.body,
        }
    }
}

impl From<api_raw::ApiFailureKind> for ApiFailureKind {
    fn from(k: api_raw::ApiFailureKind) -> Self {
        use api_raw::ApiFailureKind as K;
        match k {
            K::Offline => Self::Offline,
            K::BlockedUpstream => Self::BlockedUpstream,
            K::Unauthenticated => Self::Unauthenticated,
            K::Forbidden => Self::Forbidden,
            K::Validation => Self::Validation,
            K::Server => Self::Server,
            K::Transient => Self::Transient,
            K::Internal => Self::Internal,
        }
    }
}

impl From<api_raw::ApiFailure> for ApiFailure {
    fn from(f: api_raw::ApiFailure) -> Self {
        ApiFailure {
            status: f.status,
            code: f.code,
            message: f.message,
            kind: f.kind.into(),
            body: f.body,
        }
    }
}

impl ApiStreamItem {
    /// The server accepted the stream.
    fn opened() -> Self {
        ApiStreamItem {
            opened: true,
            event: String::new(),
            data: String::new(),
            id: None,
            failure: None,
        }
    }
}

impl From<api_raw::ApiEvent> for ApiStreamItem {
    fn from(e: api_raw::ApiEvent) -> Self {
        ApiStreamItem {
            opened: false,
            event: e.event,
            data: e.data,
            id: e.id,
            failure: None,
        }
    }
}

impl From<ApiFailure> for ApiStreamItem {
    fn from(f: ApiFailure) -> Self {
        ApiStreamItem {
            opened: false,
            event: String::new(),
            data: String::new(),
            id: None,
            failure: Some(f),
        }
    }
}

impl MadarBridge {
    /// One API call on the core's client. A non-2xx answer (or no answer) is
    /// an [`ApiFailure`] worded in the active language.
    pub async fn api_request(&self, call: ApiCall) -> Result<ApiReply, ApiFailure> {
        self.inner
            .api_request(call.into())
            .await
            .map(ApiReply::from)
            .map_err(ApiFailure::from)
    }

    /// Open a server-sent-event stream: an `opened` item arrives once the
    /// server accepted it, then each frame; a failure (refused at open, or the
    /// connection lost) arrives as a last item with `failure`, then the stream
    /// closes. It also closes when
    /// the server ends it, or when the host calls [`Self::api_stream_cancel`]
    /// with the same `stream_id` (the host's own unique name for it).
    pub async fn api_stream(
        &self,
        call: ApiCall,
        stream_id: String,
        sink: StreamSink<ApiStreamItem>,
    ) {
        let (stop, stopped) = tokio::sync::oneshot::channel::<()>();
        // A stream already open under this name is replaced (its sender is
        // dropped, which ends it).
        self.streams
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(stream_id.clone(), stop);
        let cancel = async move {
            let _ = stopped.await;
        };
        let out = self
            .inner
            .api_stream(
                call.into(),
                cancel,
                || {
                    let _ = sink.add(ApiStreamItem::opened());
                },
                |event| sink.add(ApiStreamItem::from(event)).is_ok(),
            )
            .await;
        if let Err(failure) = out {
            let _ = sink.add(ApiStreamItem::from(ApiFailure::from(failure)));
        }
        // Forget our handle, unless a newer stream took the name meanwhile.
        let mut streams = self.streams.lock().unwrap_or_else(|e| e.into_inner());
        if streams.get(&stream_id).is_some_and(|s| s.is_closed()) {
            streams.remove(&stream_id);
        }
    }

    /// Stop the stream opened under `stream_id` (idempotent).
    #[frb(sync)]
    pub fn api_stream_cancel(&self, stream_id: String) {
        let stop = self
            .streams
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(&stream_id);
        if let Some(stop) = stop {
            let _ = stop.send(());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn call() -> ApiCall {
        ApiCall {
            method: "POST".into(),
            path: "/menu-items/m1/image".into(),
            query: vec![ApiPair {
                key: "a".into(),
                value: "1".into(),
            }],
            headers: vec![],
            json_body: Some(r#"{"x":1}"#.into()),
            form_fields: vec![ApiPair {
                key: "kind".into(),
                value: "cover".into(),
            }],
            files: vec![],
        }
    }

    #[test]
    fn a_call_without_files_is_json_and_with_files_is_multipart() {
        let json: api_raw::ApiCall = call().into();
        assert_eq!(json.body, api_raw::ApiBody::Json(r#"{"x":1}"#.into()));
        assert_eq!(json.query, vec![("a".to_string(), "1".to_string())]);

        let mut c = call();
        c.files = vec![ApiFile {
            field: "file".into(),
            filename: "a.png".into(),
            content_type: None,
            bytes: vec![1],
        }];
        let multipart: api_raw::ApiCall = c.into();
        match multipart.body {
            api_raw::ApiBody::Multipart { fields, files } => {
                assert_eq!(fields, vec![("kind".to_string(), "cover".to_string())]);
                assert_eq!(files[0].filename, "a.png");
            }
            other => panic!("multipart expected, got {other:?}"),
        }

        let mut empty = call();
        empty.json_body = None;
        let empty: api_raw::ApiCall = empty.into();
        assert_eq!(empty.body, api_raw::ApiBody::Empty);
    }

    #[test]
    fn a_failure_crosses_whole() {
        let f = ApiFailure::from(api_raw::ApiFailure {
            status: 403,
            code: None,
            message: "blocked".into(),
            kind: api_raw::ApiFailureKind::BlockedUpstream,
            body: Some("<html/>".into()),
        });
        assert_eq!((f.status, f.kind), (403, ApiFailureKind::BlockedUpstream));
        let item = ApiStreamItem::from(f);
        assert!(item.failure.is_some() && item.data.is_empty());
    }
}
