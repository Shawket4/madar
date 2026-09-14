//! Test support: a tiny programmable HTTP server and a signed-in offline core.
//! `#[cfg(test)]` only.

use std::sync::{Arc, Mutex};

use crate::{session, MadarConfig, MadarCore};

/// One request the stub saw.
#[derive(Clone, Debug)]
pub(crate) struct SeenRequest {
    pub method: String,
    /// Path including the query string.
    pub path: String,
    pub body: String,
}

impl SeenRequest {
    pub fn json(&self) -> serde_json::Value {
        serde_json::from_str(&self.body).unwrap_or(serde_json::Value::Null)
    }
}

/// What the handler answers.
pub(crate) struct StubResponse {
    pub status: u16,
    pub body: String,
}

impl StubResponse {
    pub fn json(status: u16, v: serde_json::Value) -> Self {
        Self { status, body: v.to_string() }
    }
    pub fn text(status: u16, body: &str) -> Self {
        Self { status, body: body.to_string() }
    }
    /// Close the connection without answering (reads as "offline" to the core).
    pub fn hangup() -> Self {
        Self { status: 0, body: String::new() }
    }
}

type Handler = dyn Fn(&SeenRequest) -> Option<StubResponse> + Send + Sync;

/// A local HTTP/1.1 server answering from `handler` (`None` = 404).
pub(crate) struct Stub {
    pub base: String,
    pub seen: Arc<Mutex<Vec<SeenRequest>>>,
}

impl Stub {
    pub async fn start(handler: impl Fn(&SeenRequest) -> Option<StubResponse> + Send + Sync + 'static) -> Stub {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let seen: Arc<Mutex<Vec<SeenRequest>>> = Arc::new(Mutex::new(Vec::new()));
        let sink = seen.clone();
        let handler: Arc<Handler> = Arc::new(handler);
        tokio::spawn(async move {
            loop {
                let Ok((mut sock, _)) = listener.accept().await else { return };
                let sink = sink.clone();
                let handler = handler.clone();
                tokio::spawn(async move {
                    let mut buf = Vec::new();
                    let mut chunk = vec![0u8; 65536];
                    let (head_end, len) = loop {
                        let n = sock.read(&mut chunk).await.unwrap_or(0);
                        if n == 0 {
                            return;
                        }
                        buf.extend_from_slice(&chunk[..n]);
                        let text = String::from_utf8_lossy(&buf).to_string();
                        if let Some(h) = text.find("\r\n\r\n") {
                            let len = text[..h]
                                .lines()
                                .find_map(|l| {
                                    l.to_ascii_lowercase()
                                        .strip_prefix("content-length:")
                                        .map(|v| v.trim().parse::<usize>().unwrap_or(0))
                                })
                                .unwrap_or(0);
                            if buf.len() >= h + 4 + len {
                                break (h, len);
                            }
                        }
                    };
                    let text = String::from_utf8_lossy(&buf).to_string();
                    let first = text.lines().next().unwrap_or("").to_string();
                    let mut parts = first.split_whitespace();
                    let req = SeenRequest {
                        method: parts.next().unwrap_or("").to_string(),
                        path: parts.next().unwrap_or("").to_string(),
                        body: text[head_end + 4..head_end + 4 + len].to_string(),
                    };
                    sink.lock().unwrap().push(req.clone());
                    // Sign-in always reads as offline, so a test core unlocks with
                    // the cached bundle whatever else the stub serves.
                    let resp = if req.path.starts_with("/auth/") {
                        StubResponse::hangup()
                    } else {
                        handler(&req).unwrap_or(StubResponse::text(404, r#"{"error":"not found"}"#))
                    };
                    if resp.status == 0 {
                        return;
                    }
                    let out = format!(
                        "HTTP/1.1 {} X\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{}",
                        resp.status,
                        resp.body.len(),
                        resp.body
                    );
                    let _ = sock.write_all(out.as_bytes()).await;
                });
            }
        });
        Stub { base: format!("http://{addr}"), seen }
    }

    pub fn requests(&self, path_prefix: &str) -> Vec<SeenRequest> {
        self.seen
            .lock()
            .unwrap()
            .iter()
            .filter(|r| r.path.starts_with(path_prefix))
            .cloned()
            .collect()
    }
}

pub(crate) const ORG: &str = "00000000-0000-0000-0000-0000000000aa";
pub(crate) const TELLER: &str = "00000000-0000-0000-0000-0000000000bb";
pub(crate) const BRANCH: &str = "00000000-0000-0000-0000-000000000001";

/// A core at `base`, signed in offline as teller Sara (PIN 1234) at [`BRANCH`].
/// `db_path` empty = in memory.
pub(crate) async fn offline_core(base: &str, db_path: &str) -> Arc<MadarCore> {
    use argon2::password_hash::SaltString;
    use argon2::{Argon2, PasswordHasher};
    let core = MadarCore::new(MadarConfig {
        base_url: base.to_string(),
        environment: "dev".into(),
        db_path: db_path.to_string(),
        locale: "en".into(),
        app_version: None,
    })
    .unwrap();
    // The scenario tests exercise the local-first reads, so they run with every
    // area on `new` (the product default is `shadow`; see readpath.rs and
    // `a_fresh_device_shadows_every_read`).
    for area in crate::readpath::AREAS {
        crate::readpath::set_mode(&core.store, area, crate::readpath::ReadPathMode::New).unwrap();
    }
    let salt = SaltString::encode_b64(b"madar-test-salt").unwrap();
    let phc = Argon2::default().hash_password(b"1234", &salt).unwrap().to_string();
    core.store
        .kv_put(
            session::BUNDLE_KEY,
            &serde_json::json!({
                "org_id": ORG, "generated_at": "2026-06-19T10:00:00Z",
                "lan_secret": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
                "tellers": [{ "user_id": TELLER, "name": "Sara", "role": "teller", "is_active": true, "offline_pin_hash": phc }]
            })
            .to_string(),
        )
        .unwrap();
    core.store
        .kv_put(
            session::ORG_CONFIG_KEY,
            &format!(r#"{{"org_id":"{ORG}","currency_code":"EGP","tax_rate":0.14}}"#),
        )
        .unwrap();
    core.sign_in(session::LoginRequest {
        mode: session::LoginMode::Pin,
        name: Some("Sara".into()),
        pin: Some("1234".into()),
        branch_id: Some(BRANCH.into()),
        email: None,
        password: None,
        org_id: None,
    })
    .await
    .unwrap();
    core
}

/// [`offline_core`] holding a bearer, so it drains and pulls.
pub(crate) async fn online_core(base: &str, db_path: &str) -> Arc<MadarCore> {
    let core = offline_core(base, db_path).await;
    core.api.set_bearer(Some("test-token".into()));
    core
}
