//! The management dashboard's generic API pass-through (docs/fdash/SPEC.md §3.1).
//!
//! The Flutter dashboard reaches every backend operation through ONE seam: a
//! call (method, path, query pairs, a JSON body or multipart parts) goes out on
//! the core's own HTTP client — the same base URL, bearer, identity headers
//! (`X-Madar-Device`, `X-Madar-Client`), clock observation and staff-token
//! refresh as every other call — plus the org/branch scope headers the web
//! client sends (`X-Org-Id` / `X-Branch-Id`, from the active scope). A 2xx
//! comes back as raw status, headers and bytes; anything else becomes an
//! [`ApiFailure`] carrying the HTTP status, the backend's code and a human
//! sentence in the active language.
//!
//! The refusal rules are the core's (`net::status_to_error`): a 403 without
//! the backend's envelope never came from our server and stays the
//! blocked-upstream case; a 401 without it is a portal, not an expired
//! session. A genuine 401 to a call that carried the bearer parks the session
//! exactly like a refused drain does (`auth_paused`), so the host shows the
//! sign-in prompt.
//!
//! [`MadarCore::api_stream`] opens a server-sent-event stream on the core's
//! streaming client and hands each `data:` frame over, parsed by the same
//! parser the realtime bus uses.
//!
//! Dashboard-only: the POS never calls into this module.

use std::future::Future;

use futures_util::StreamExt;

use crate::error::CoreError;
use crate::realtime::SseParser;
use crate::{i18n, net, ActiveScopeView, MadarCore};

/// One call. `path` has its parameters substituted and starts with `/`.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ApiCall {
    pub method: String,
    pub path: String,
    /// Query pairs in order; a key may repeat (`status=open&status=paid`).
    pub query: Vec<(String, String)>,
    /// Extra request headers. The credential is the core's: an `Authorization`
    /// here is ignored. An explicit `X-Org-Id` / `X-Branch-Id` wins over the
    /// active scope.
    pub headers: Vec<(String, String)>,
    pub body: ApiBody,
}

/// What a call carries.
#[derive(Clone, Debug, Default, PartialEq)]
pub enum ApiBody {
    #[default]
    Empty,
    /// JSON text, sent as `application/json`.
    Json(String),
    /// `multipart/form-data`: plain text fields, then the file parts.
    Multipart {
        fields: Vec<(String, String)>,
        files: Vec<ApiFilePart>,
    },
}

/// One file of a multipart call.
#[derive(Clone, Debug, PartialEq)]
pub struct ApiFilePart {
    pub field: String,
    pub filename: String,
    pub content_type: Option<String>,
    pub bytes: Vec<u8>,
}

/// A 2xx answer, as the server sent it (bodies are already decompressed).
#[derive(Clone, Debug, PartialEq)]
pub struct ApiReply {
    pub status: u16,
    /// Header names in lower case, in the order received (a name may repeat).
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

/// One server-sent event.
#[derive(Clone, Debug, PartialEq)]
pub struct ApiEvent {
    /// The `event:` field (`message` when the frame has none).
    pub event: String,
    /// The `data:` lines, joined by `\n`.
    pub data: String,
    /// The last `id:` seen (sticky across frames, per the SSE rules).
    pub id: Option<String>,
}

/// How a host should react to a failure: the core's `CoreError` classes, with
/// the blocked-upstream 403 kept apart from plain offline.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ApiFailureKind {
    /// The server was not reached (no network, a timeout, a portal's 401).
    Offline,
    /// A 403 without the backend's envelope: a firewall, WAF or shop router
    /// answered in its place. Never "no permission".
    BlockedUpstream,
    /// The backend refused the session (401 with its envelope).
    Unauthenticated,
    /// The backend refused the person (403 with its envelope).
    Forbidden,
    /// 400 / 422: the backend refused what was sent.
    Validation,
    /// Any other 4xx (404, 409, 429, …), or a coded refusal the core keeps.
    Server,
    /// 5xx.
    Transient,
    /// The core could not build the call or read the answer.
    Internal,
}

/// A call that did not come back 2xx.
#[derive(Clone, Debug, PartialEq, thiserror::Error)]
#[error("api {status} {kind:?}: {message}")]
pub struct ApiFailure {
    /// The HTTP status; 0 when the server was never reached.
    pub status: u16,
    /// The backend's machine code (`ErrorBody.code`), when it sent one.
    pub code: Option<String>,
    /// A human sentence in the active language.
    pub message: String,
    pub kind: ApiFailureKind,
    /// The answer as the server sent it (the envelope, with its `vars`), or,
    /// for a call refused before it left, the core's reason.
    pub body: Option<String>,
}

/// Header names a caller may not set: the credential, and the framing the
/// HTTP client owns.
const RESERVED_HEADERS: &[&str] = &[
    "authorization",
    "host",
    "content-length",
    "transfer-encoding",
    "connection",
];

const ORG_HEADER: &str = "X-Org-Id";
const BRANCH_HEADER: &str = "X-Branch-Id";

/// Build the request for `call` on `client`: the method and URL, the query,
/// the caller's headers, the scope headers, the bearer, and the body. Pure
/// over its inputs (the client's default identity headers are added when it
/// is sent).
pub(crate) fn build_request(
    client: &reqwest::Client,
    base_url: &str,
    call: &ApiCall,
    bearer: Option<&str>,
    scope: Option<&ActiveScopeView>,
    accept: Option<&str>,
) -> Result<reqwest::RequestBuilder, CoreError> {
    let method = reqwest::Method::from_bytes(call.method.trim().to_ascii_uppercase().as_bytes())
        .map_err(|_| CoreError::Validation {
            field: "method".into(),
            detail: format!("not an HTTP method: {:?}", call.method),
        })?;
    if !call.path.starts_with('/') {
        return Err(CoreError::Validation {
            field: "path".into(),
            detail: format!("must start with '/': {:?}", call.path),
        });
    }
    let url = format!("{}{}", base_url.trim_end_matches('/'), call.path);
    let mut rb = client.request(method, &url);
    if !call.query.is_empty() {
        rb = rb.query(&call.query);
    }

    let multipart = matches!(call.body, ApiBody::Multipart { .. });
    let has = |name: &str| {
        call.headers
            .iter()
            .any(|(k, _)| k.trim().eq_ignore_ascii_case(name))
    };
    for (name, value) in &call.headers {
        let lower = name.trim().to_ascii_lowercase();
        // The multipart boundary is the client's to write.
        if RESERVED_HEADERS.contains(&lower.as_str()) || (multipart && lower == "content-type") {
            continue;
        }
        let name = reqwest::header::HeaderName::from_bytes(lower.as_bytes()).map_err(|_| {
            CoreError::Validation {
                field: "headers".into(),
                detail: format!("not a header name: {name:?}"),
            }
        })?;
        let value =
            reqwest::header::HeaderValue::from_str(value).map_err(|_| CoreError::Validation {
                field: "headers".into(),
                detail: format!("not a header value for {name}"),
            })?;
        rb = rb.header(name, value);
    }
    if let Some(scope) = scope {
        let ids = [
            (ORG_HEADER, scope.org_id.as_deref()),
            (BRANCH_HEADER, scope.branch_id.as_deref()),
        ];
        for (header, id) in ids {
            if let Some(id) = id.map(str::trim).filter(|id| !id.is_empty()) {
                if !has(header) {
                    rb = rb.header(header, id);
                }
            }
        }
    }
    if let Some(token) = bearer {
        rb = rb.bearer_auth(token);
    }
    if let Some(accept) = accept {
        if !has("accept") {
            rb = rb.header(reqwest::header::ACCEPT, accept);
        }
    }
    match &call.body {
        ApiBody::Empty => {}
        ApiBody::Json(text) => {
            if !has("content-type") {
                rb = rb.header(reqwest::header::CONTENT_TYPE, "application/json");
            }
            rb = rb.body(text.clone());
        }
        ApiBody::Multipart { fields, files } => {
            let mut form = reqwest::multipart::Form::new();
            for (name, value) in fields {
                form = form.text(name.clone(), value.clone());
            }
            for file in files {
                let mut part = reqwest::multipart::Part::bytes(file.bytes.clone())
                    .file_name(file.filename.clone());
                if let Some(ct) = file
                    .content_type
                    .as_deref()
                    .filter(|ct| !ct.trim().is_empty())
                {
                    part = part.mime_str(ct).map_err(|_| CoreError::Validation {
                        field: "files".into(),
                        detail: format!("not a media type: {ct:?}"),
                    })?;
                }
                form = form.part(file.field.clone(), part);
            }
            rb = rb.multipart(form);
        }
    }
    Ok(rb)
}

/// The class of a `CoreError` for the host.
pub(crate) fn kind_of(e: &CoreError) -> ApiFailureKind {
    match e {
        CoreError::Offline { detail } if detail == net::BLOCKED_UPSTREAM => {
            ApiFailureKind::BlockedUpstream
        }
        CoreError::Offline { .. } => ApiFailureKind::Offline,
        CoreError::Unauthenticated { .. } => ApiFailureKind::Unauthenticated,
        CoreError::Forbidden { .. } => ApiFailureKind::Forbidden,
        CoreError::Validation { .. } => ApiFailureKind::Validation,
        CoreError::Server { .. } => ApiFailureKind::Server,
        CoreError::Transient { .. } => ApiFailureKind::Transient,
        CoreError::Internal { .. } => ApiFailureKind::Internal,
    }
}

/// A non-2xx answer as a failure: classified by the core's own rule
/// (`net::status_to_error`), worded by [`answer_words`].
pub(crate) fn failure_from_answer(locale: &str, status: u16, body: &str) -> ApiFailure {
    let kind = kind_of(&net::status_to_error(status, body));
    ApiFailure {
        status,
        code: net::extract_error_code(body),
        message: answer_words(locale, status, body, kind),
        kind,
        body: (!body.is_empty()).then(|| body.to_string()),
    }
}

/// A call that never got an answer from our server (transport, a refused
/// staff refresh, a call the core could not build).
pub(crate) fn failure_unreached(locale: &str, e: &CoreError) -> ApiFailure {
    let kind = kind_of(e);
    let (status, message, body) = match e {
        CoreError::Offline { detail } if kind == ApiFailureKind::BlockedUpstream => (
            403,
            i18n::tr(locale, "err.blocked_upstream"),
            Some(detail.clone()),
        ),
        CoreError::Offline { .. } | CoreError::Transient { .. } => {
            (0, words(locale, Words::Network), None)
        }
        CoreError::Unauthenticated { detail } => (
            401,
            words(locale, Words::SessionExpired),
            Some(detail.clone()),
        ),
        CoreError::Forbidden { resource, action } => (
            403,
            words(locale, Words::Unauthorized),
            Some(format!("{resource}: {action}")),
        ),
        CoreError::Validation { field, detail } => (
            0,
            words(locale, Words::Unknown),
            Some(format!("{field}: {detail}")),
        ),
        CoreError::Server { status, detail, .. } => {
            (*status, words(locale, Words::Unknown), Some(detail.clone()))
        }
        CoreError::Internal { detail } => (0, words(locale, Words::Unknown), Some(detail.clone())),
    };
    let code = match e {
        // A staff refusal keeps its code (`DEVICE_REVOKED`).
        CoreError::Unauthenticated { detail } if is_code(detail) => Some(detail.clone()),
        _ => None,
    };
    ApiFailure {
        status,
        code,
        message,
        kind,
        body,
    }
}

/// `PIN_WRONG_BRANCH`, as opposed to a sentence.
fn is_code(s: &str) -> bool {
    let mut chars = s.chars();
    chars.next().is_some_and(|c| c.is_ascii_uppercase())
        && chars.all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_')
}

/// The sentence for a refusal, in `locale`. The web dashboard's ladder
/// (`getErrorMessage`), minus its table of coded sentences, which the host
/// applies from the web's own words when it has them for `code`:
///   - not our server: the blocked-upstream sentence, or the network one;
///   - a code the core has words for (`err.<code>`);
///   - an uncoded 429 or 403: too many requests / no permission;
///   - on an English device, the server's own sentence without the kind it
///     leads with ("Conflict: …"); an Arabic device never reads the server's
///     English (the core's B-POS-6 rule) and gets the sentence for the kind;
///   - else the sentence for the status.
pub(crate) fn answer_words(locale: &str, status: u16, body: &str, kind: ApiFailureKind) -> String {
    match kind {
        ApiFailureKind::BlockedUpstream => return i18n::tr(locale, "err.blocked_upstream"),
        // A captive portal's 401: our server never answered.
        ApiFailureKind::Offline => return words(locale, Words::Network),
        _ => {}
    }
    let code = net::extract_error_code(body);
    if let Some(said) = code.as_deref().and_then(|c| core_code_words(locale, c)) {
        return said;
    }
    if code.is_none() {
        match status {
            429 => return words(locale, Words::TooMany),
            403 => return words(locale, Words::Unauthorized),
            _ => {}
        }
    }
    if !i18n::is_arabic(locale) {
        if let Some(said) = net::extract_error_message(body).and_then(|m| server_sentence(&m)) {
            return said;
        }
    }
    words(
        locale,
        match status {
            401 => Words::SessionExpired,
            403 => Words::Unauthorized,
            404 => Words::NotFound,
            409 => Words::Conflict,
            400 | 422 => Words::Validation,
            429 => Words::TooMany,
            s if s >= 500 => Words::Server,
            _ => Words::Unknown,
        },
    )
}

/// The core's words for a backend code (`err.<code>`), when it has them in
/// this language and they need no figures.
fn core_code_words(locale: &str, code: &str) -> Option<String> {
    let key = format!("err.{}", code.to_ascii_lowercase());
    let said = i18n::tr(locale, &key);
    if said == key || said.contains('{') {
        return None;
    }
    // `tr` falls back to English: an Arabic reader gets Arabic or nothing.
    if i18n::is_arabic(locale) && said == i18n::tr("en", &key) {
        return None;
    }
    Some(said)
}

/// The kinds the backend's `AppError` writes before its sentence (the web's
/// `SERVER_KIND_PREFIX`).
const SERVER_KIND_PREFIXES: &[&str] = &[
    "Unauthorized: ",
    "Forbidden: ",
    "Not found: ",
    "Bad request: ",
    "Conflict: ",
    "Service unavailable: ",
    "Database error: ",
];

/// The server's sentence without its kind, unless it is empty or nothing but
/// an HTTP reason (a proxy's page).
fn server_sentence(said: &str) -> Option<String> {
    let said = said.trim();
    let said = SERVER_KIND_PREFIXES
        .iter()
        .find_map(|p| said.strip_prefix(p))
        .unwrap_or(said)
        .trim();
    (!said.is_empty() && !net::is_reason_phrase(said)).then(|| said.to_string())
}

#[derive(Clone, Copy, Debug)]
enum Words {
    SessionExpired,
    Network,
    Unauthorized,
    NotFound,
    Conflict,
    Validation,
    Server,
    TooMany,
    Unknown,
}

/// The web dashboard's own sentences for these (`errors.*` in
/// MadarDashboard's `en.json` / `ar.json`), so a refusal reads the same in
/// both dashboards.
fn words(locale: &str, w: Words) -> String {
    let (en, ar) = match w {
        Words::SessionExpired => (
            "Your session has expired. Please sign in again.",
            "انتهت جلستك. الرجاء تسجيل الدخول مجدداً.",
        ),
        Words::Network => (
            "Network error — please check your connection.",
            "خطأ في الشبكة — يرجى التحقق من الاتصال.",
        ),
        Words::Unauthorized => (
            "You don't have permission to perform this action.",
            "ليس لديك صلاحية لتنفيذ هذا الإجراء.",
        ),
        Words::NotFound => ("Not found.", "غير موجود."),
        Words::Conflict => (
            "This action conflicts with the current state.",
            "هذا الإجراء يتعارض مع الحالة الحالية.",
        ),
        Words::Validation => (
            "Please check the highlighted fields.",
            "يرجى مراجعة الحقول المظللة.",
        ),
        Words::Server => (
            "Server error — please try again later.",
            "خطأ في الخادم — حاول مرة أخرى لاحقاً.",
        ),
        Words::TooMany => (
            "Too many requests just now. Try again in a moment.",
            "طلبات كثيرة في الوقت الحالي. حاول مرة أخرى بعد لحظات.",
        ),
        Words::Unknown => ("An unexpected error occurred.", "حدث خطأ غير متوقع."),
    };
    if i18n::is_arabic(locale) { ar } else { en }.to_string()
}

/// What one send resolved to.
enum Sent {
    Reply(ApiReply),
    /// Our server (or something in its place) answered non-2xx.
    Refused {
        status: u16,
        body: String,
    },
    Unreached(CoreError),
}

impl MadarCore {
    /// One API call on the core's client (see the module docs). A staff token
    /// about to run out is refreshed first, and one refused as expired is
    /// refreshed and the call sent once more, as every other call does.
    pub async fn api_request(&self, call: ApiCall) -> Result<ApiReply, ApiFailure> {
        let locale = self.current_locale();
        if self.api.staff_refresh_due() {
            if let Err(e @ CoreError::Unauthenticated { .. }) =
                self.api.refresh_staff(self.api.bearer().as_deref()).await
            {
                return Err(failure_unreached(&locale, &e));
            }
        }
        let sent = self.api.bearer();
        let mut outcome = self.api_send(&call, sent.as_deref()).await;
        if let Sent::Refused { status: 401, body } = &outcome {
            let expired = net::extract_error_code(body).as_deref() == Some(net::TOKEN_EXPIRED);
            if self.api.is_staff()
                && expired
                && self.api.refresh_staff(sent.as_deref()).await.is_ok()
            {
                outcome = self.api_send(&call, self.api.bearer().as_deref()).await;
            }
        }
        match outcome {
            Sent::Reply(reply) => Ok(reply),
            Sent::Refused { status, body } => {
                let failure = failure_from_answer(&locale, status, &body);
                self.note_api_refusal(&failure, sent.is_some(), &call.path);
                Err(failure)
            }
            Sent::Unreached(e) => Err(failure_unreached(&locale, &e)),
        }
    }

    /// Open a server-sent-event stream for `call` on the core's streaming
    /// client. `on_open` runs once the server has accepted it (a 2xx); then
    /// every frame goes to `on_event` (as the web's parser yields them: a
    /// keepalive comment is no frame, a bare `id:` or a data-less `resync`
    /// is), until the server ends the stream (`Ok`), `on_event` answers
    /// `false` (`Ok`), `cancel` resolves (`Ok`), or the stream fails (`Err`).
    /// A refusal to open is worded like [`Self::api_request`]'s.
    pub async fn api_stream(
        &self,
        call: ApiCall,
        cancel: impl Future<Output = ()>,
        on_open: impl FnOnce(),
        mut on_event: impl FnMut(ApiEvent) -> bool,
    ) -> Result<(), ApiFailure> {
        let locale = self.current_locale();
        let sent = self.api.bearer();
        let scope = self.active_scope();
        let rb = build_request(
            &self.api.stream_client(),
            self.api.base_url(),
            &call,
            sent.as_deref(),
            scope.as_ref(),
            Some("text/event-stream"),
        )
        .map_err(|e| failure_unreached(&locale, &e))?;
        let run = async {
            let resp = rb
                .send()
                .await
                .map_err(|e| failure_unreached(&locale, &net::classify_reqwest(&e)))?;
            self.api.observe_response(&resp);
            let status = resp.status().as_u16();
            if !resp.status().is_success() {
                let body = resp.text().await.unwrap_or_default();
                let failure = failure_from_answer(&locale, status, &body);
                self.note_api_refusal(&failure, sent.is_some(), &call.path);
                return Err(failure);
            }
            on_open();
            let mut parser = SseParser::new();
            let mut chunks = resp.bytes_stream();
            while let Some(chunk) = chunks.next().await {
                let chunk =
                    chunk.map_err(|e| failure_unreached(&locale, &net::classify_reqwest(&e)))?;
                for frame in parser.push(&chunk) {
                    let event = ApiEvent {
                        event: frame.event_type,
                        data: frame.data,
                        id: frame.id,
                    };
                    if !on_event(event) {
                        return Ok(());
                    }
                }
            }
            Ok(())
        };
        tokio::select! {
            out = run => out,
            _ = cancel => Ok(()),
        }
    }

    /// Send `call` once with `bearer` and the active scope.
    async fn api_send(&self, call: &ApiCall, bearer: Option<&str>) -> Sent {
        let scope = self.active_scope();
        let rb = match build_request(
            &self.api.request_client(),
            self.api.base_url(),
            call,
            bearer,
            scope.as_ref(),
            None,
        ) {
            Ok(rb) => rb,
            Err(e) => return Sent::Unreached(e),
        };
        let resp = match rb.send().await {
            Ok(resp) => resp,
            Err(e) => return Sent::Unreached(net::classify_reqwest(&e)),
        };
        self.api.observe_response(&resp);
        let status = resp.status();
        let headers = resp
            .headers()
            .iter()
            .map(|(k, v)| {
                (
                    k.as_str().to_string(),
                    String::from_utf8_lossy(v.as_bytes()).into_owned(),
                )
            })
            .collect();
        let body = match resp.bytes().await {
            Ok(b) => b.to_vec(),
            Err(e) => return Sent::Unreached(net::classify_reqwest(&e)),
        };
        if status.is_success() {
            Sent::Reply(ApiReply {
                status: status.as_u16(),
                headers,
                body,
            })
        } else {
            Sent::Refused {
                status: status.as_u16(),
                body: String::from_utf8_lossy(&body).into_owned(),
            }
        }
    }

    /// A session the backend refused (a 401 with its envelope, to a call that
    /// carried our bearer, on a non-public path) parks it like a refused drain:
    /// a borrowed token is dropped, our own is marked for re-sign-in.
    fn note_api_refusal(&self, failure: &ApiFailure, carried_bearer: bool, path: &str) {
        use std::sync::atomic::Ordering::Relaxed;
        if failure.kind != ApiFailureKind::Unauthenticated
            || !carried_bearer
            || path.contains("/public/")
        {
            return;
        }
        if self.borrowed_token.load(Relaxed) {
            self.invalidate_borrowed_token();
        } else {
            self.auth_paused.store(true, Relaxed);
        }
        self.push_diag(
            "warn",
            format!("dashboard call refused the session: {path}"),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testkit::{Stub, StubResponse};

    fn call(method: &str, path: &str) -> ApiCall {
        ApiCall {
            method: method.into(),
            path: path.into(),
            ..ApiCall::default()
        }
    }

    /// A client on the core's own TLS stack (no default crypto provider here).
    fn client() -> reqwest::Client {
        reqwest::Client::builder()
            .use_preconfigured_tls(net::default_tls_config())
            .build()
            .unwrap()
    }

    fn built(
        call: &ApiCall,
        bearer: Option<&str>,
        scope: Option<&ActiveScopeView>,
    ) -> reqwest::Request {
        build_request(&client(), "https://api.example/", call, bearer, scope, None)
            .unwrap()
            .build()
            .unwrap()
    }

    fn header(req: &reqwest::Request, name: &str) -> Option<String> {
        req.headers()
            .get(name)
            .map(|v| v.to_str().unwrap().to_string())
    }

    // ── request building ─────────────────────────────────────────────────

    #[test]
    fn a_call_carries_its_query_bearer_and_scope() {
        let mut c = call("get", "/orders");
        c.query = vec![
            ("status".into(), "open".into()),
            ("status".into(), "paid".into()),
            ("q".into(), "قهوة & tea".into()),
        ];
        let scope = ActiveScopeView {
            org_id: Some("org-1".into()),
            branch_id: Some("br-2".into()),
        };
        let req = built(&c, Some("tok"), Some(&scope));
        assert_eq!(req.method(), reqwest::Method::GET);
        assert_eq!(req.url().path(), "/orders");
        let pairs: Vec<(String, String)> = req.url().query_pairs().into_owned().collect();
        assert_eq!(
            pairs,
            vec![
                ("status".to_string(), "open".to_string()),
                ("status".to_string(), "paid".to_string()),
                ("q".to_string(), "قهوة & tea".to_string()),
            ]
        );
        assert_eq!(header(&req, "authorization").as_deref(), Some("Bearer tok"));
        assert_eq!(header(&req, "x-org-id").as_deref(), Some("org-1"));
        assert_eq!(header(&req, "x-branch-id").as_deref(), Some("br-2"));
        assert!(req.body().is_none());
    }

    #[test]
    fn no_scope_and_no_bearer_send_neither() {
        let empty = ActiveScopeView {
            org_id: None,
            branch_id: Some("  ".into()),
        };
        let req = built(&call("GET", "/auth/me"), None, Some(&empty));
        assert!(header(&req, "authorization").is_none());
        assert!(header(&req, "x-org-id").is_none());
        assert!(header(&req, "x-branch-id").is_none());
        assert_eq!(req.url().query(), None);
    }

    #[test]
    fn an_explicit_scope_header_wins_and_the_credential_stays_the_cores() {
        let mut c = call("POST", "/menu-items");
        c.headers = vec![
            ("X-Branch-Id".into(), "explicit".into()),
            ("Authorization".into(), "Bearer someone-else".into()),
            ("Host".into(), "evil.example".into()),
        ];
        let scope = ActiveScopeView {
            org_id: Some("org-1".into()),
            branch_id: Some("scoped".into()),
        };
        let req = built(&c, Some("ours"), Some(&scope));
        let branches: Vec<_> = req.headers().get_all("x-branch-id").iter().collect();
        assert_eq!(branches.len(), 1);
        assert_eq!(branches[0], "explicit");
        let auth: Vec<_> = req.headers().get_all("authorization").iter().collect();
        assert_eq!(auth.len(), 1);
        assert_eq!(auth[0], "Bearer ours");
        assert!(header(&req, "host").is_none());
    }

    #[test]
    fn a_json_body_is_sent_as_json() {
        let mut c = call("PATCH", "/branches/b1");
        c.body = ApiBody::Json(r#"{"name":"المعادي"}"#.into());
        let req = built(&c, None, None);
        assert_eq!(req.method(), reqwest::Method::PATCH);
        assert_eq!(
            header(&req, "content-type").as_deref(),
            Some("application/json")
        );
        assert_eq!(
            req.body().and_then(|b| b.as_bytes()),
            Some(r#"{"name":"المعادي"}"#.as_bytes())
        );
    }

    #[test]
    fn a_multipart_body_writes_its_own_boundary() {
        let mut c = call("POST", "/menu-items/m1/image");
        c.headers = vec![("Content-Type".into(), "application/json".into())];
        c.body = ApiBody::Multipart {
            fields: vec![("kind".into(), "cover".into())],
            files: vec![ApiFilePart {
                field: "file".into(),
                filename: "latte.png".into(),
                content_type: Some("image/png".into()),
                bytes: vec![1, 2, 3],
            }],
        };
        let req = built(&c, None, None);
        let types: Vec<_> = req.headers().get_all("content-type").iter().collect();
        assert_eq!(types.len(), 1, "the caller's content type is dropped");
        assert!(types[0]
            .to_str()
            .unwrap()
            .starts_with("multipart/form-data; boundary="));
    }

    #[test]
    fn a_call_the_core_cannot_build_is_refused_before_it_leaves() {
        let client = client();
        let bad_method = build_request(&client, "https://x", &call("GE T", "/a"), None, None, None);
        assert!(
            matches!(bad_method, Err(CoreError::Validation { ref field, .. }) if field == "method")
        );
        let relative = build_request(
            &client,
            "https://x",
            &call("GET", "orders"),
            None,
            None,
            None,
        );
        assert!(
            matches!(relative, Err(CoreError::Validation { ref field, .. }) if field == "path")
        );
        let mut bad_header = call("GET", "/a");
        bad_header.headers = vec![("X-Note".into(), "line\nbreak".into())];
        let refused = build_request(&client, "https://x", &bad_header, None, None, None);
        assert!(
            matches!(refused, Err(CoreError::Validation { ref field, .. }) if field == "headers")
        );
        let f = failure_unreached("ar", &relative.err().unwrap());
        assert_eq!((f.status, f.kind), (0, ApiFailureKind::Validation));
        assert_eq!(f.message, words("ar", Words::Unknown));
    }

    // ── error mapping and wording ────────────────────────────────────────

    #[test]
    fn an_english_device_reads_the_servers_sentence_without_its_kind() {
        let body =
            r#"{"error":"Conflict: A group with this name already exists","code":"NAME_TAKEN"}"#;
        let f = failure_from_answer("en", 409, body);
        assert_eq!(f.status, 409);
        assert_eq!(f.code.as_deref(), Some("NAME_TAKEN"));
        assert_eq!(f.kind, ApiFailureKind::Server);
        assert_eq!(f.message, "A group with this name already exists");
        assert_eq!(f.body.as_deref(), Some(body));
    }

    #[test]
    fn an_arabic_device_never_reads_the_servers_english() {
        let conflict = r#"{"error":"Conflict: A group with this name already exists"}"#;
        assert_eq!(
            failure_from_answer("ar", 409, conflict).message,
            words("ar", Words::Conflict)
        );
        let invalid = r#"{"error":"Bad request: price must be positive"}"#;
        let f = failure_from_answer("ar", 422, invalid);
        assert_eq!(f.kind, ApiFailureKind::Validation);
        assert_eq!(f.message, "يرجى مراجعة الحقول المظللة.");
        let gone = r#"{"error":"Not found: Employee not found"}"#;
        assert_eq!(
            failure_from_answer("ar", 404, gone).message,
            words("ar", Words::NotFound)
        );
        assert_eq!(
            failure_from_answer("en", 404, gone).message,
            "Employee not found"
        );
    }

    #[test]
    fn a_code_the_core_has_words_for_is_said_in_them() {
        let body = r#"{"error":"Pick another method","code":"PAYMENT_METHOD_UNAVAILABLE"}"#;
        for locale in ["en", "ar"] {
            let f = failure_from_answer(locale, 422, body);
            assert_eq!(
                f.message,
                i18n::tr(locale, "err.payment_method_unavailable")
            );
            assert_eq!(f.code.as_deref(), Some("PAYMENT_METHOD_UNAVAILABLE"));
        }
    }

    #[test]
    fn a_403_without_our_envelope_is_the_blocked_upstream_case() {
        let f = failure_from_answer("en", 403, "<html>Access denied by policy</html>");
        assert_eq!(f.kind, ApiFailureKind::BlockedUpstream);
        assert_eq!(f.status, 403);
        assert_eq!(f.message, i18n::tr("en", "err.blocked_upstream"));
        assert_ne!(f.message, words("en", Words::Unauthorized));
        let ar = failure_from_answer("ar", 403, "");
        assert_eq!(ar.message, i18n::tr("ar", "err.blocked_upstream"));
    }

    #[test]
    fn a_403_from_our_server_is_no_permission() {
        let f = failure_from_answer("en", 403, r#"{"error":"Forbidden: missing capability"}"#);
        assert_eq!(f.kind, ApiFailureKind::Forbidden);
        assert_eq!(f.message, words("en", Words::Unauthorized));
        assert_eq!(
            failure_from_answer("ar", 403, r#"{"error":"x"}"#).message,
            words("ar", Words::Unauthorized)
        );
    }

    #[test]
    fn a_401_is_the_session_unless_a_portal_said_it() {
        let ours = failure_from_answer("ar", 401, r#"{"error":"Unauthorized: token expired"}"#);
        assert_eq!(ours.kind, ApiFailureKind::Unauthenticated);
        assert_eq!(ours.message, words("ar", Words::SessionExpired));
        let portal = failure_from_answer("en", 401, "<html>Sign in to the Wi-Fi</html>");
        assert_eq!(portal.kind, ApiFailureKind::Offline);
        assert_eq!(portal.message, words("en", Words::Network));
    }

    #[test]
    fn the_limiter_and_the_server_have_their_own_words() {
        let limited = failure_from_answer("en", 429, r#"{"error":"Too many requests, slow down"}"#);
        assert_eq!(limited.message, words("en", Words::TooMany));
        let down = failure_from_answer("ar", 503, "");
        assert_eq!(down.kind, ApiFailureKind::Transient);
        assert_eq!(down.message, words("ar", Words::Server));
        // Nothing but an HTTP reason is not the server's sentence.
        let bare = failure_from_answer("en", 500, r#"{"error":"Internal Server Error"}"#);
        assert_eq!(bare.message, words("en", Words::Server));
        assert_eq!(
            failure_from_answer("en", 418, "").message,
            words("en", Words::Unknown)
        );
    }

    #[test]
    fn a_call_that_never_reached_the_server_says_network() {
        let f = failure_unreached(
            "ar",
            &CoreError::Offline {
                detail: "connect refused".into(),
            },
        );
        assert_eq!((f.status, f.kind), (0, ApiFailureKind::Offline));
        assert_eq!(f.message, "خطأ في الشبكة — يرجى التحقق من الاتصال.");
        let revoked = failure_unreached(
            "en",
            &CoreError::Unauthenticated {
                detail: "DEVICE_REVOKED".into(),
            },
        );
        assert_eq!(
            (revoked.status, revoked.code.as_deref()),
            (401, Some("DEVICE_REVOKED"))
        );
    }

    // ── against a local server ───────────────────────────────────────────

    #[tokio::test]
    async fn a_reply_comes_back_raw_with_the_cores_headers() {
        let stub = Stub::start(|req| {
            req.path.starts_with("/orders").then(|| {
                StubResponse::text(200, r#"{"items":[],"total":0}"#)
                    .with_header("x-total-count", "0")
            })
        })
        .await;
        let core = crate::testkit::online_core(&stub.base, "").await;
        core.set_active_scope(None, Some("br-9".into()));
        let mut c = call("GET", "/orders");
        c.query = vec![("page".into(), "2".into())];
        let reply = core.api_request(c).await.unwrap();
        assert_eq!(reply.status, 200);
        assert_eq!(reply.body, br#"{"items":[],"total":0}"#.to_vec());
        assert!(reply
            .headers
            .iter()
            .any(|(k, v)| k == "x-total-count" && v == "0"));
        let seen = stub.requests("/orders");
        assert_eq!(seen.len(), 1);
        assert_eq!(seen[0].path, "/orders?page=2");
        assert_eq!(
            seen[0].header("authorization").as_deref(),
            Some("Bearer test-token")
        );
        assert_eq!(seen[0].header("x-branch-id").as_deref(), Some("br-9"));
        assert!(
            seen[0].header("x-org-id").is_none(),
            "no org picked, none sent (the web's rule)"
        );
        assert!(seen[0]
            .header("x-madar-client")
            .is_some_and(|v| v.starts_with("pos/")));
    }

    #[tokio::test]
    async fn a_refusal_carries_status_code_and_words() {
        let stub = Stub::start(|req| {
            (req.path == "/menu-items").then(|| {
                StubResponse::text(422, r#"{"error":"Bad request: name is required","code":"FIELD_REQUIRED","vars":{"field":"name"}}"#)
            })
        })
        .await;
        let core = crate::testkit::online_core(&stub.base, "").await;
        let mut c = call("POST", "/menu-items");
        c.body = ApiBody::Json(r#"{"price":100}"#.into());
        let f = core.api_request(c).await.unwrap_err();
        assert_eq!(f.status, 422);
        assert_eq!(f.code.as_deref(), Some("FIELD_REQUIRED"));
        assert_eq!(f.kind, ApiFailureKind::Validation);
        assert_eq!(f.message, "name is required");
        assert!(f.body.unwrap().contains(r#""vars":{"field":"name"}"#));
        let seen = stub.requests("/menu-items");
        assert_eq!(seen[0].json(), serde_json::json!({ "price": 100 }));
        assert_eq!(
            seen[0].header("content-type").as_deref(),
            Some("application/json")
        );
        core.set_locale("ar".into());
        let ar = core
            .api_request(call("POST", "/menu-items"))
            .await
            .unwrap_err();
        assert_eq!(ar.message, words("ar", Words::Validation));
    }

    #[tokio::test]
    async fn a_refused_session_parks_like_a_refused_drain() {
        use std::sync::atomic::Ordering::Relaxed;
        let stub = Stub::start(|req| {
            Some(match req.path.as_str() {
                "/orders" => StubResponse::text(401, r#"{"error":"Unauthorized: invalid token"}"#),
                _ => StubResponse::text(401, r#"{"error":"Unauthorized: no guest token"}"#),
            })
        })
        .await;
        let core = crate::testkit::online_core(&stub.base, "").await;
        // A public path's 401 is not the dashboard session (the web's guard).
        let public = core
            .api_request(call("GET", "/public/orders/x"))
            .await
            .unwrap_err();
        assert_eq!(public.kind, ApiFailureKind::Unauthenticated);
        assert!(!core.auth_paused.load(Relaxed));
        let f = core.api_request(call("GET", "/orders")).await.unwrap_err();
        assert_eq!((f.status, f.kind), (401, ApiFailureKind::Unauthenticated));
        assert!(
            core.auth_paused.load(Relaxed),
            "the host is told to sign in again"
        );
    }

    #[tokio::test]
    async fn a_server_that_hangs_up_reads_as_offline() {
        let stub = Stub::start(|_| Some(StubResponse::hangup())).await;
        let core = crate::testkit::online_core(&stub.base, "").await;
        let f = core.api_request(call("GET", "/orders")).await.unwrap_err();
        assert_eq!((f.status, f.kind), (0, ApiFailureKind::Offline));
        assert_eq!(f.message, words("en", Words::Network));
    }

    #[tokio::test]
    async fn a_multipart_call_reaches_the_server_whole() {
        let stub = Stub::start(|req| {
            (req.path == "/uploads").then(|| StubResponse::text(201, r#"{"url":"/u/1.png"}"#))
        })
        .await;
        let core = crate::testkit::online_core(&stub.base, "").await;
        let mut c = call("POST", "/uploads");
        c.body = ApiBody::Multipart {
            fields: vec![("purpose".into(), "logo".into())],
            files: vec![ApiFilePart {
                field: "file".into(),
                filename: "logo.png".into(),
                content_type: Some("image/png".into()),
                bytes: b"PNGDATA".to_vec(),
            }],
        };
        let reply = core.api_request(c).await.unwrap();
        assert_eq!(reply.status, 201);
        let seen = &stub.requests("/uploads")[0];
        assert!(seen
            .header("content-type")
            .unwrap()
            .starts_with("multipart/form-data; boundary="));
        assert!(seen.body.contains(r#"name="purpose""#) && seen.body.contains("logo"));
        assert!(seen.body.contains(r#"filename="logo.png""#) && seen.body.contains("PNGDATA"));
    }

    // ── event streams ────────────────────────────────────────────────────

    #[tokio::test]
    async fn every_frame_reaches_the_host() {
        let stub = Stub::start(|req| {
            (req.path.starts_with("/realtime/stream")).then(|| {
                StubResponse::text(
                    200,
                    "id: 7\nevent: booking.created\ndata: {\"id\":\"b1\"}\n\n: ping\n\ndata: line one\r\ndata: سطر\r\n\r\nid: 8\n\n",
                )
            })
        })
        .await;
        let core = crate::testkit::online_core(&stub.base, "").await;
        let mut c = call("GET", "/realtime/stream");
        c.query = vec![("branch_id".into(), "b".into())];
        let mut got = Vec::new();
        let mut opened = 0;
        core.api_stream(
            c,
            std::future::pending(),
            || opened += 1,
            |e| {
                got.push(e);
                true
            },
        )
        .await
        .unwrap();
        assert_eq!(opened, 1);
        assert_eq!(
            got,
            vec![
                ApiEvent {
                    event: "booking.created".into(),
                    data: r#"{"id":"b1"}"#.into(),
                    id: Some("7".into())
                },
                ApiEvent {
                    event: "message".into(),
                    data: "line one\nسطر".into(),
                    id: Some("7".into())
                },
                // A bare `id:` is a frame too (the web's parser yields it): the
                // resume cursor moves.
                ApiEvent {
                    event: "message".into(),
                    data: String::new(),
                    id: Some("8".into())
                },
            ]
        );
        let seen = &stub.requests("/realtime/stream")[0];
        assert_eq!(seen.header("accept").as_deref(), Some("text/event-stream"));
        assert_eq!(
            seen.header("authorization").as_deref(),
            Some("Bearer test-token")
        );
    }

    #[tokio::test]
    async fn the_host_can_stop_listening() {
        let stub =
            Stub::start(|_| Some(StubResponse::text(200, "data: a\n\ndata: b\n\ndata: c\n\n")))
                .await;
        let core = crate::testkit::online_core(&stub.base, "").await;
        let mut got = Vec::new();
        core.api_stream(
            call("GET", "/stream"),
            std::future::pending(),
            || {},
            |e| {
                got.push(e.data);
                got.len() < 2
            },
        )
        .await
        .unwrap();
        assert_eq!(got, vec!["a", "b"]);
    }

    #[tokio::test]
    async fn a_stream_refused_at_open_is_a_worded_failure() {
        let stub = Stub::start(|_| {
            Some(StubResponse::text(
                403,
                r#"{"error":"no topics","code":"NO_TOPICS"}"#,
            ))
        })
        .await;
        let core = crate::testkit::online_core(&stub.base, "").await;
        let mut opened = false;
        let f = core
            .api_stream(
                call("GET", "/realtime/stream"),
                std::future::pending(),
                || opened = true,
                |_| true,
            )
            .await
            .unwrap_err();
        assert!(!opened, "a refused stream never opened");
        assert_eq!(
            (f.status, f.kind, f.code.as_deref()),
            (403, ApiFailureKind::Forbidden, Some("NO_TOPICS"))
        );
        assert_eq!(f.message, "no topics");
    }

    /// A stream that stays open ends the moment the host cancels it.
    #[tokio::test]
    async fn cancelling_an_open_stream_ends_it() {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        tokio::spawn(async move {
            loop {
                let Ok((mut sock, _)) = listener.accept().await else {
                    return;
                };
                tokio::spawn(async move {
                    let mut buf = [0u8; 4096];
                    let n = sock.read(&mut buf).await.unwrap_or(0);
                    // Anything but the stream (the test core's sign-in) is hung up on.
                    if !String::from_utf8_lossy(&buf[..n]).starts_with("GET /stream") {
                        return;
                    }
                    let _ = sock
                        .write_all(b"HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\n\r\ndata: first\n\n")
                        .await;
                    // Hold the connection open, sending nothing more.
                    tokio::time::sleep(std::time::Duration::from_secs(30)).await;
                });
            }
        });
        let core = crate::testkit::online_core(&base, "").await;
        let (stop, stopped) = tokio::sync::oneshot::channel::<()>();
        let mut stop = Some(stop);
        let mut got = Vec::new();
        let out = tokio::time::timeout(
            std::time::Duration::from_secs(5),
            core.api_stream(
                call("GET", "/stream"),
                async {
                    let _ = stopped.await;
                },
                || {},
                |e| {
                    got.push(e.data);
                    if let Some(stop) = stop.take() {
                        let _ = stop.send(());
                    }
                    true
                },
            ),
        )
        .await
        .expect("the cancel ends the stream at once");
        assert!(out.is_ok());
        assert_eq!(got, vec!["first"]);
    }
}
