//! A minimal HTTP/1.1 front for the model cloud: one request per connection,
//! headers captured (the bearer names the device), a synchronous handler, and
//! answers that can hang up (a network that fails) or stream (SSE).

use std::collections::HashMap;
use std::sync::Arc;

use tokio::io::{AsyncReadExt, AsyncWriteExt};

#[derive(Clone, Debug)]
pub struct HttpReq {
    pub method: String,
    /// Path without the query string.
    pub path: String,
    pub query: HashMap<String, String>,
    pub headers: HashMap<String, String>,
    pub body: String,
}

impl HttpReq {
    pub fn bearer(&self) -> Option<&str> {
        self.headers.get("authorization").and_then(|v| v.strip_prefix("Bearer "))
    }
}

pub enum HttpResp {
    /// Status, extra headers, JSON body.
    Json(u16, Vec<(String, String)>, String),
    /// Close the connection without answering.
    HangUp,
    /// Stream lines as they come (SSE); the connection closes when the sender drops.
    Stream(tokio::sync::mpsc::UnboundedReceiver<String>),
}

pub type Handler = Arc<dyn Fn(HttpReq) -> HttpResp + Send + Sync>;

pub struct HttpServer {
    pub base: String,
    task: tokio::task::JoinHandle<()>,
}

impl Drop for HttpServer {
    fn drop(&mut self) {
        self.task.abort();
    }
}

fn decode(s: &str) -> String {
    let mut out = Vec::new();
    let b = s.as_bytes();
    let mut i = 0;
    while i < b.len() {
        match b[i] {
            b'+' => out.push(b' '),
            b'%' if i + 2 < b.len() => {
                if let Ok(v) = u8::from_str_radix(&s[i + 1..i + 3], 16) {
                    out.push(v);
                    i += 2;
                } else {
                    out.push(b'%');
                }
            }
            c => out.push(c),
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

impl HttpServer {
    pub async fn start(handler: Handler) -> HttpServer {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.expect("bind");
        let base = format!("http://{}", listener.local_addr().unwrap());
        let task = tokio::spawn(async move {
            loop {
                let Ok((mut sock, _)) = listener.accept().await else { return };
                let handler = handler.clone();
                tokio::spawn(async move {
                    let mut buf = Vec::new();
                    let mut chunk = vec![0u8; 65536];
                    let (head_end, len) = loop {
                        let n = match sock.read(&mut chunk).await {
                            Ok(0) | Err(_) => return,
                            Ok(n) => n,
                        };
                        buf.extend_from_slice(&chunk[..n]);
                        if let Some(h) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
                            let head = String::from_utf8_lossy(&buf[..h]).to_string();
                            let len = head
                                .lines()
                                .find_map(|l| l.to_ascii_lowercase().strip_prefix("content-length:").map(|v| v.trim().parse::<usize>().unwrap_or(0)))
                                .unwrap_or(0);
                            if buf.len() >= h + 4 + len {
                                break (h, len);
                            }
                        }
                        if buf.len() > 64 * 1024 * 1024 {
                            return;
                        }
                    };
                    let head = String::from_utf8_lossy(&buf[..head_end]).to_string();
                    let mut lines = head.lines();
                    let first = lines.next().unwrap_or("");
                    let mut parts = first.split_whitespace();
                    let method = parts.next().unwrap_or("").to_string();
                    let target = parts.next().unwrap_or("").to_string();
                    let (path, qs) = target.split_once('?').unwrap_or((target.as_str(), ""));
                    let query = qs
                        .split('&')
                        .filter(|p| !p.is_empty())
                        .map(|p| {
                            let (k, v) = p.split_once('=').unwrap_or((p, ""));
                            (decode(k), decode(v))
                        })
                        .collect();
                    let headers = lines
                        .filter_map(|l| l.split_once(':'))
                        .map(|(k, v)| (k.trim().to_ascii_lowercase(), v.trim().to_string()))
                        .collect();
                    let req = HttpReq {
                        method,
                        path: path.to_string(),
                        query,
                        headers,
                        body: String::from_utf8_lossy(&buf[head_end + 4..head_end + 4 + len]).to_string(),
                    };
                    match handler(req) {
                        HttpResp::HangUp => {}
                        HttpResp::Json(status, extra, body) => {
                            let mut out = format!(
                                "HTTP/1.1 {status} X\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n",
                                body.len()
                            );
                            for (k, v) in extra {
                                out.push_str(&format!("{k}: {v}\r\n"));
                            }
                            out.push_str("\r\n");
                            out.push_str(&body);
                            let _ = sock.write_all(out.as_bytes()).await;
                        }
                        HttpResp::Stream(mut rx) => {
                            let head = "HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\ncache-control: no-cache\r\nconnection: close\r\n\r\n";
                            if sock.write_all(head.as_bytes()).await.is_err() {
                                return;
                            }
                            while let Some(line) = rx.recv().await {
                                if sock.write_all(line.as_bytes()).await.is_err() {
                                    return;
                                }
                                let _ = sock.flush().await;
                            }
                        }
                    }
                });
            }
        });
        HttpServer { base, task }
    }
}
