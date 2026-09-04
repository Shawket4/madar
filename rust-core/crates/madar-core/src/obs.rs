//! Observability — crash + background-error reporting to Sentry.
//!
//! WHY THIS EXISTS
//! ---------------
//! madar-core is the product: the HTTP client, the money engine, offline sync and
//! EIGHT long-lived background tasks (seven in `lan.rs` for the multi-teller LAN
//! relay, one in `realtime.rs` for the SSE bus). Those tasks own no caller — their
//! errors never return through the FFI, so the Flutter/Dart SDK above us is
//! structurally blind to them. A relay whose mDNS browser died, a beacon socket
//! that stopped receiving, an SSE supervisor stuck in a permanent 403: today all
//! of those fail *silently* on a device sitting on a counter in another city.
//! This module is the only channel through which they can be seen.
//!
//! OFFLINE IS THE NORMAL STATE
//! ---------------------------
//! A POS terminal is offline routinely — that is the whole premise of the core's
//! durable outbox. sentry-rust, however, buffers envelopes only in memory: kill
//! the app (or let it crash — the very case worth reporting) and every report
//! since the last uplink is gone. So error reports get the same treatment as
//! money: [`SqliteTransport`] writes each envelope to SQLite first and a
//! background worker drains it with backoff, bounded by count AND age so a
//! terminal offline for a week can't grow the DB without limit.
//!
//! DISABLED BY DEFAULT
//! -------------------
//! With no DSN configured, [`init`] does nothing at all: no client, no thread, no
//! table writes, no behaviour change anywhere. Sentry is opt-in per build/deploy.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use sentry::protocol::{Event, Level, Value};
use sentry::types::Dsn;
use sentry::{ClientInitGuard, Envelope, Transport, TransportFactory, TransportOptions};

use crate::store::Store;

// ── queue caps ────────────────────────────────────────────────────────────────
// Deliberately small. The point of the disk queue is to survive a normal offline
// stretch (a shift, a night, a bad week of connectivity), NOT to be an archive.
// Past these bounds the OLDEST reports are dropped: on a device that has been
// broken for days the newest errors are the ones worth having.

/// Hard cap on queued envelopes. ~200 reports at a few KB each is well under a MB.
const MAX_QUEUED: u32 = 200;
/// Anything older than this is discarded unsent — a two-week-old stack trace from
/// a build that has since shipped twice is noise, not signal.
const MAX_AGE_MS: i64 = 14 * 24 * 60 * 60 * 1_000;
/// Envelopes larger than this are dropped rather than persisted. A single runaway
/// report must not be able to bloat a terminal's SQLite file.
const MAX_ENVELOPE_BYTES: usize = 512 * 1024;
/// In-memory hand-off depth between `send_envelope` (any thread) and the worker.
/// Bounded + non-blocking: capturing an error must NEVER stall a caller, and in
/// the worst case (a capture storm) we drop reports rather than the sale.
const CHANNEL_DEPTH: usize = 128;
/// Envelopes per drain pass — keeps one pass short so a backlog uploads in slices
/// instead of one long burst on a metered connection.
const DRAIN_BATCH: u32 = 8;

/// Idle wait between drain passes when the queue is empty (the worker also wakes
/// immediately on a new capture).
const IDLE_WAIT: Duration = Duration::from_secs(30);
/// First retry delay after a failed upload; doubles up to [`MAX_BACKOFF`].
const BASE_BACKOFF_MS: i64 = 15_000;
/// Ceiling on the retry delay — an offline terminal retries every 5 min forever,
/// which is cheap and picks up a reconnect quickly enough.
const MAX_BACKOFF_MS: i64 = 5 * 60 * 1_000;
/// Same ceiling, as a `Duration`, for the worker's own sleep.
const MAX_BACKOFF: Duration = Duration::from_millis(MAX_BACKOFF_MS as u64);

/// Minimum gap between two reports from the SAME capture site. The background
/// tasks are LOOPS: a broken socket fails every iteration forever, and without
/// this one dead beacon would emit thousands of identical events a day.
const SITE_COOLDOWN_MS: i64 = 5 * 60 * 1_000;

// ── global state ──────────────────────────────────────────────────────────────

/// The init guard. Held forever on purpose: dropping it shuts the client down and
/// flushes with a short timeout, which is exactly the wrong thing to do on a
/// device that is usually offline. The process exiting is fine — the queue is on
/// disk and the next boot drains it.
static GUARD: OnceLock<ClientInitGuard> = OnceLock::new();
/// `true` once a real (DSN-backed) client is live. Every helper below returns
/// early when this is false, so a no-DSN build pays nothing but an atomic load.
static ENABLED: AtomicBool = AtomicBool::new(false);
/// Last-reported timestamp per capture site, for [`SITE_COOLDOWN_MS`].
static LAST_SEEN: OnceLock<Mutex<HashMap<&'static str, i64>>> = OnceLock::new();
/// The live transport, kept so [`flush`] can reach it without a Hub round-trip.
static TRANSPORT: OnceLock<Arc<SqliteTransport>> = OnceLock::new();

/// Whether crash reporting is active. Hosts/tests can branch on this; everything
/// in this module is already a no-op when it is false.
pub fn is_enabled() -> bool {
    ENABLED.load(Ordering::Relaxed)
}

fn now_ms() -> i64 {
    chrono::Utc::now().timestamp_millis()
}

// ── DSN resolution ────────────────────────────────────────────────────────────

/// Resolve the DSN, in precedence order:
///   1. the `MADAR_SENTRY_DSN` process environment variable (a runtime override —
///      lets a support build turn reporting on without a rebuild),
///   2. `MADAR_SENTRY_DSN` baked in at build time from `.env` by `build.rs`
///      (the same mechanism as `MADAR_BASE_URL`, so hosts carry no endpoint
///      knowledge — see the module docs on `crate::config`).
///
/// Anything blank means DISABLED. An unparseable DSN also means disabled: a typo
/// in a config file must degrade to "no telemetry", never to a failed boot.
fn resolve_dsn() -> Option<Dsn> {
    let raw = std::env::var("MADAR_SENTRY_DSN")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .or_else(|| option_env!("MADAR_SENTRY_DSN").map(|s| s.to_string()))?;
    let raw = raw.trim();
    if raw.is_empty() {
        return None;
    }
    raw.parse::<Dsn>().ok()
}

// ── init ──────────────────────────────────────────────────────────────────────

/// Bring Sentry up, if a DSN is configured. Idempotent (later calls are no-ops)
/// and infallible by construction: it never blocks, never does I/O on the calling
/// thread, and never returns an error — a broken telemetry stack must not be able
/// to stop a till from opening. Returns whether reporting ended up active.
///
/// Called from `MadarCore::new` once the store is open, so the very first thing
/// the queue can persist to is the same SQLite file the outbox lives in.
pub fn init(store: Arc<Store>, environment: &str, db_path: &str) -> bool {
    if GUARD.get().is_some() {
        return is_enabled();
    }
    let Some(dsn) = resolve_dsn() else {
        // No DSN → behave exactly as the core did before this module existed.
        return false;
    };

    let transport = Arc::new(SqliteTransport::new(store, dsn.clone()));
    let transport_for_flush = transport.clone();

    let mut options = sentry::ClientOptions::new();
    // Field assignment (not the `.dsn(&str)` builder) because that builder panics
    // on a bad DSN; we already parsed ours fallibly above.
    options.dsn = Some(dsn);
    options.release = Some(format!("madar-core@{}", env!("CARGO_PKG_VERSION")).into());
    options.environment = Some(environment.to_string().into());
    // NEVER. `send_default_pii` would attach usernames, IPs and request bodies —
    // see the scrubbing contract in `scrub_event` below.
    options.send_default_pii = false;
    options.attach_stacktrace = true;
    // PII: pre-empt the `contexts` integration, which fills `server_name` with the
    // machine's HOSTNAME when it is left unset — and a hostname on a personal
    // Android/iPad is very often a person's name ("Ahmed's iPad"). Setting it here
    // means that code path never runs. `device.id` (see `set_device_scope`) is the
    // per-install identifier we actually want, and it names nobody.
    options.server_name = Some("madar-pos-terminal".into());
    // Breadcrumbs are the main accidental-PII surface (they accumulate whatever
    // the app logged). Keep the window short; they are scrubbed too.
    options.max_breadcrumbs = 30;
    options.before_send = Some(Arc::new(|event| Some(scrub_event(event))));
    options.transport = Some(Arc::new(TransportHandle(transport)) as Arc<dyn TransportFactory>);

    // `apply_defaults` installs the integrations the enabled features provide —
    // crucially `PanicIntegration`, which sets the panic hook. That hook is what
    // makes a panic inside a spawned background task visible: tokio catches the
    // unwind and drops the JoinHandle's error on the floor, but the hook has
    // already run by then, so the report is captured before the evidence is lost.
    let guard = sentry::init(sentry::apply_defaults(options));
    let enabled = guard.is_enabled();
    let _ = GUARD.set(guard);
    let _ = TRANSPORT.set(transport_for_flush);
    ENABLED.store(enabled, Ordering::Relaxed);

    if enabled {
        // Non-identifying install context. `db_path` is recorded only as a
        // presence flag — the absolute path leaks the OS user's name on desktop.
        sentry::configure_scope(|scope| {
            scope.set_tag("core.version", env!("CARGO_PKG_VERSION"));
            scope.set_tag(
                "core.storage",
                if db_path.is_empty() { "memory" } else { "file" },
            );
        });
    }
    enabled
}

/// Attach the device's operating identity to every subsequent event. All three
/// values are OPERATIONAL ids, never personal data: `device_id` is the core's own
/// randomly-minted install uuid (`lan_device_id`), `branch_id` is a tenant id, and
/// `role` is `teller`/`kitchen`/`waiter`. No teller name, no user id, no address.
///
/// Called whenever the device binding changes, so a report from a terminal can be
/// traced to a branch and a station without identifying a person.
pub fn set_device_scope(device_id: Option<&str>, branch_id: Option<&str>, role: Option<&str>) {
    if !is_enabled() {
        return;
    }
    sentry::configure_scope(|scope| {
        if let Some(v) = device_id {
            scope.set_tag("device.id", v);
        }
        if let Some(v) = branch_id {
            scope.set_tag("branch.id", v);
        }
        if let Some(v) = role {
            scope.set_tag("device.role", v);
        }
    });
}

/// Block until the queue is empty or `timeout` elapses; `true` if it drained.
/// Only worth calling on a deliberate shutdown — a POS is usually offline, so a
/// `false` here is the expected answer, not a failure.
pub fn flush(timeout: Duration) -> bool {
    match TRANSPORT.get() {
        Some(t) => Transport::flush(t.as_ref(), timeout),
        None => true,
    }
}

// ── capture helpers for the background tasks ──────────────────────────────────

/// Report a failure from a background task, at most once per [`SITE_COOLDOWN_MS`]
/// per `site`.
///
/// `site` is a stable, hand-written id for the capture point (e.g.
/// `"lan.accept"`), NOT a message — it is both the dedup key and the Sentry
/// fingerprint. The cooldown exists because every one of these call sites lives
/// inside an infinite loop: a permanently broken socket would otherwise emit an
/// identical event on every iteration until the battery died.
///
/// `detail` should describe the OPERATION and the OS/protocol error. It must not
/// carry order contents, customer data or tokens — and it is scrubbed anyway.
pub fn capture_bg_error(site: &'static str, detail: impl AsRef<str>) {
    capture_bg(site, Level::Error, detail.as_ref());
}

/// As [`capture_bg_error`], for degraded-but-not-broken conditions (a discovery
/// layer that gave up, a stream that a server told us to stop retrying).
pub fn capture_bg_warning(site: &'static str, detail: impl AsRef<str>) {
    capture_bg(site, Level::Warning, detail.as_ref());
}

fn capture_bg(site: &'static str, level: Level, detail: &str) {
    if !is_enabled() || !cooldown_elapsed(site) {
        return;
    }
    let mut event = Event {
        level,
        // Group by capture site, not by the (varying) OS error text — one issue
        // per broken subsystem instead of one per distinct errno.
        fingerprint: vec![std::borrow::Cow::Borrowed(site)].into(),
        message: Some(format!("{site}: {detail}")),
        logger: Some("madar-core.background".into()),
        ..Default::default()
    };
    event.tags.insert("bg.site".into(), site.into());
    // `subsystem` = the module that owns the failing task, so the LAN relay and
    // the realtime bus can be triaged separately.
    if let Some((subsystem, _)) = site.split_once('.') {
        event.tags.insert("bg.subsystem".into(), subsystem.into());
    }
    sentry::capture_event(event);
}

/// `true` if `site` has not reported within the cooldown window (and records the
/// attempt). Cheap: one mutex + one map lookup, only reached when Sentry is on.
fn cooldown_elapsed(site: &'static str) -> bool {
    let map = LAST_SEEN.get_or_init(|| Mutex::new(HashMap::new()));
    let mut guard = map.lock().unwrap_or_else(|e| e.into_inner());
    let now = now_ms();
    match guard.get(site) {
        Some(&last) if now.saturating_sub(last) < SITE_COOLDOWN_MS => false,
        _ => {
            guard.insert(site, now);
            true
        }
    }
}

// ── PII scrubbing ─────────────────────────────────────────────────────────────
//
// COMPLIANCE CONTROL — NOT AN OPTIMISATION. Madar's published privacy policy
// states that error reports exclude personal data, and this hook is the technical
// measure that makes that statement true. The core handles customer names, phone
// numbers, delivery addresses, staff records and payroll, so an unscrubbed stack
// trace or breadcrumb payload is a live route for that data to leave the device.
//
// The design is DENY-BY-DEFAULT on key names, applied recursively so a redacted
// key nested inside an order payload is caught as reliably as a top-level one,
// plus a value-level pass over free text (error messages routinely interpolate a
// customer name or a phone number into a string, where no key name protects it).
//
// If you add a field to a payload that could reach an event, add its key here.
// Over-redacting is cheap; a leak is not.

/// Substrings that mark a key as personal/sensitive. Matched case-insensitively
/// against the whole key, so `customer_name`, `deliveryAddress` and
/// `staff.phone_number` all hit.
const DENY_KEY_SUBSTRINGS: &[&str] = &[
    // Identity
    "name",
    "customer",
    "contact",
    "person",
    "employee",
    "staff",
    "teller",
    "email",
    "phone",
    "mobile",
    "tel",
    "whatsapp",
    "dob",
    "birth",
    "gender",
    "national",
    "passport",
    "ssn",
    // Location
    "address",
    "street",
    "building",
    "apartment",
    "apt",
    "floor",
    "landmark",
    "district",
    "zone_note",
    "latitude",
    "longitude",
    "lat",
    "lng",
    "lon",
    "geo",
    "coords",
    "coordinate",
    // Credentials / secrets
    "pin",
    "password",
    "passwd",
    "secret",
    "token",
    "bearer",
    "auth",
    "key",
    "credential",
    "otp",
    "signature",
    "hmac",
    "cookie",
    "session",
    // Payment
    "card",
    "pan",
    "cvv",
    "iban",
    "account_number",
    "wallet",
    // Free text a human typed (the classic accidental-PII field)
    "note",
    "notes",
    "comment",
    "remark",
    "instruction",
    "reason_text",
    // Employment / payroll
    "salary",
    "wage",
    "payroll",
    "payslip",
    "deduction_note",
    "bank",
];

/// Whether `key` names something that must never leave the device.
fn is_denied_key(key: &str) -> bool {
    let lower = key.to_ascii_lowercase();
    DENY_KEY_SUBSTRINGS.iter().any(|d| lower.contains(d))
}

const REDACTED: &str = "[redacted]";

/// Recursively redact a JSON value: denied keys lose their value entirely,
/// everything else keeps its shape but has its free text scrubbed. Structure is
/// preserved on purpose — knowing that an order had 4 items and a redacted
/// customer is diagnostically useful; knowing the customer is not.
fn redact_value(value: &mut Value) {
    match value {
        Value::Object(map) => {
            for (k, v) in map.iter_mut() {
                if is_denied_key(k) {
                    *v = Value::String(REDACTED.into());
                } else {
                    redact_value(v);
                }
            }
        }
        Value::Array(items) => {
            for v in items.iter_mut() {
                redact_value(v);
            }
        }
        Value::String(s) => {
            if let Some(clean) = scrub_text(s) {
                *s = clean;
            }
        }
        _ => {}
    }
}

/// Value-level scrub for free text. Catches the two things that leak through a
/// key-name denylist because they are interpolated INTO a message: email
/// addresses, and long digit runs (Egyptian mobile numbers are 11 digits, card
/// PANs 13–19). Returns `None` when nothing changed, so the common case allocates
/// nothing.
///
/// Deliberately conservative and dependency-free (no regex crate): a false
/// positive costs us a timestamp in a log line, a false negative costs a person
/// their phone number.
fn scrub_text(input: &str) -> Option<String> {
    const MIN_DIGIT_RUN: usize = 7;
    let has_at = input.contains('@');
    let mut run = 0usize;
    let mut long_run = false;
    for b in input.bytes() {
        if b.is_ascii_digit() {
            run += 1;
            if run >= MIN_DIGIT_RUN {
                long_run = true;
                break;
            }
        } else {
            run = 0;
        }
    }
    if !has_at && !long_run {
        return None;
    }

    let mut out = String::with_capacity(input.len());
    for token in input.split_inclusive(|c: char| c.is_whitespace()) {
        let (word, trailing) = match token.chars().last() {
            Some(c) if c.is_whitespace() => token.split_at(token.len() - c.len_utf8()),
            _ => (token, ""),
        };
        // An email-looking token goes entirely; partial masking still identifies.
        let looks_email = word.contains('@') && word.contains('.');
        let digits = word.chars().filter(|c| c.is_ascii_digit()).count();
        let looks_number = digits >= MIN_DIGIT_RUN
            && word
                .chars()
                .all(|c| c.is_ascii_digit() || matches!(c, '+' | '-' | ' ' | '(' | ')' | '.'));
        if looks_email {
            out.push_str("[redacted-email]");
        } else if looks_number {
            out.push_str("[redacted-number]");
        } else {
            out.push_str(word);
        }
        out.push_str(trailing);
    }
    Some(out)
}

/// The `before_send` hook. Every event — ours, a panic, or anything an
/// integration produced — passes through here before it can reach the transport.
fn scrub_event(mut event: Event<'static>) -> Event<'static> {
    // `user` may only ever carry a non-identifying id. Email/username/IP are the
    // fields Sentry's own UI surfaces as "who", and we promise not to send them.
    if let Some(user) = event.user.as_mut() {
        user.email = None;
        user.username = None;
        user.ip_address = None;
        user.other.clear();
    }
    // Arbitrary structured payloads attached by capture sites.
    for (key, value) in event.extra.iter_mut() {
        if is_denied_key(key) {
            *value = Value::String(REDACTED.into());
        } else {
            redact_value(value);
        }
    }
    // Tag VALUES are free text (and tags are indexed + searchable in Sentry, so a
    // leak here is maximally exposed).
    for (key, value) in event.tags.iter_mut() {
        if is_denied_key(key) {
            *value = REDACTED.to_string();
        } else if let Some(clean) = scrub_text(value) {
            *value = clean;
        }
    }
    // Breadcrumbs accumulate whatever the app was doing before the failure —
    // historically the single richest accidental-PII source in a crash report.
    for crumb in event.breadcrumbs.iter_mut() {
        if let Some(msg) = crumb.message.as_mut() {
            if let Some(clean) = scrub_text(msg) {
                *msg = clean;
            }
        }
        for (key, value) in crumb.data.iter_mut() {
            if is_denied_key(key) {
                *value = Value::String(REDACTED.into());
            } else {
                redact_value(value);
            }
        }
    }
    // The message itself + exception values (a panic payload can interpolate
    // anything the panicking code was holding).
    if let Some(msg) = event.message.as_mut() {
        if let Some(clean) = scrub_text(msg) {
            *msg = clean;
        }
    }
    for exception in event.exception.iter_mut() {
        if let Some(value) = exception.value.as_mut() {
            if let Some(clean) = scrub_text(value) {
                *value = clean;
            }
        }
    }
    // Defence in depth against the hostname leak closed in `init`: if anything
    // ever populates `server_name` again (an SDK upgrade, a new integration), it
    // dies here rather than reaching the wire.
    event.server_name = Some("madar-pos-terminal".into());
    // A marker so it is visible IN Sentry that the control ran — if this tag ever
    // stops appearing on events, the compliance control has silently regressed.
    event.tags.insert("pii.scrubbed".into(), "true".into());
    event
}

// ── the disk-backed transport ─────────────────────────────────────────────────

/// A [`TransportFactory`] that always hands back the one transport we built at
/// [`init`] time (it owns the store handle and the worker thread, so it must not
/// be recreated per client).
struct TransportHandle(Arc<SqliteTransport>);

impl TransportFactory for TransportHandle {
    fn create_transport_with_options(&self, _options: TransportOptions) -> Arc<dyn Transport> {
        self.0.clone()
    }
}

/// Envelope persistence + upload.
///
/// `send_envelope` is called on whatever thread captured the event — including,
/// via the panic hook, a thread that may be holding the [`Store`]'s single-writer
/// mutex. So it does NOT touch SQLite: it serializes and hands the bytes to a
/// bounded channel, and the worker thread does the write. That keeps capture
/// non-blocking on the hot path and, more importantly, makes it impossible for a
/// panic inside a store operation to deadlock on the very mutex it was holding.
pub struct SqliteTransport {
    tx: std::sync::mpsc::SyncSender<Vec<u8>>,
    store: Arc<Store>,
}

impl SqliteTransport {
    fn new(store: Arc<Store>, dsn: Dsn) -> Self {
        let (tx, rx) = std::sync::mpsc::sync_channel::<Vec<u8>>(CHANNEL_DEPTH);
        let worker_store = store.clone();
        // A dedicated OS thread with its own single-threaded tokio runtime rather
        // than `tokio::spawn`: `init` runs from `MadarCore::new`, which the hosts
        // call from a plain (non-async) context, so there may be no runtime to
        // spawn onto — and telemetry must never contend with the app's runtime for
        // worker threads anyway.
        let _ = std::thread::Builder::new()
            .name("madar-sentry".into())
            .spawn(move || {
                let rt = match tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                {
                    Ok(rt) => rt,
                    // No runtime → no uploads. Reports still land on disk via the
                    // channel? No: without this thread nothing drains the channel.
                    // Failing here is effectively "telemetry off", which is the
                    // correct degradation — never a crash.
                    Err(_) => return,
                };
                rt.block_on(worker_loop(worker_store, dsn, rx));
            });
        Self { tx, store }
    }
}

impl Transport for SqliteTransport {
    fn send_envelope(&self, envelope: Envelope) {
        let mut bytes = Vec::new();
        if envelope.to_writer(&mut bytes).is_err() || bytes.is_empty() {
            return;
        }
        if bytes.len() > MAX_ENVELOPE_BYTES {
            return;
        }
        // `try_send`, never `send`: a full channel means the worker is behind, and
        // dropping a report is strictly better than blocking a teller's thread.
        let _ = self.tx.try_send(bytes);
    }

    fn flush(&self, timeout: Duration) -> bool {
        // Poll the durable queue — the worker owns the sending, so "flushed" means
        // "the table is empty". On an offline terminal this legitimately times out.
        let deadline = std::time::Instant::now() + timeout;
        loop {
            if self.store.sentry_pending_count().unwrap_or(0) == 0 {
                return true;
            }
            if std::time::Instant::now() >= deadline {
                return false;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
    }
}

/// Persist → prune → drain, forever.
///
/// Ordering matters: newly captured envelopes are written to disk BEFORE any
/// upload is attempted, so a crash mid-drain can only ever cause a resend (Sentry
/// dedupes by event id), never a loss.
async fn worker_loop(store: Arc<Store>, dsn: Dsn, rx: std::sync::mpsc::Receiver<Vec<u8>>) {
    let client = match build_uploader() {
        Some(c) => c,
        None => return,
    };
    let auth = dsn.to_auth(Some(&user_agent())).to_string();
    let url = dsn.envelope_api_url().to_string();
    let mut wait = IDLE_WAIT;

    loop {
        // 1. Absorb captures. Blocking `recv_timeout` on a dedicated thread is the
        //    wake-up path: a new report drains immediately instead of waiting out
        //    the idle interval.
        match rx.recv_timeout(wait) {
            Ok(bytes) => {
                persist(&store, bytes);
                // Grab anything else already queued in the same pass.
                while let Ok(more) = rx.try_recv() {
                    persist(&store, more);
                }
            }
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {}
            // Every sender is gone (only possible if the transport was dropped) —
            // make one last delivery attempt, then let the thread end.
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
                let _ = drain_once(&store, &client, &url, &auth).await;
                return;
            }
        }

        // 2. Enforce the caps before sending, so a huge backlog is trimmed to the
        //    newest slice rather than uploaded in full over someone's 3G.
        let _ = store.sentry_prune(now_ms() - MAX_AGE_MS, MAX_QUEUED);

        // 3. Drain a batch. Progress resets the backoff; a stall widens it.
        match drain_once(&store, &client, &url, &auth).await {
            DrainOutcome::Idle => wait = IDLE_WAIT,
            DrainOutcome::Progress => wait = Duration::from_millis(250),
            DrainOutcome::Stalled => {
                wait = (wait * 2).min(MAX_BACKOFF).max(Duration::from_secs(15));
            }
        }
    }
}

/// Write one envelope to the durable queue. Errors are swallowed by design: if
/// telemetry can't write, telemetry is lost — nothing else changes.
fn persist(store: &Store, bytes: Vec<u8>) {
    let _ = store.sentry_enqueue(&bytes, now_ms());
}

/// What one drain pass achieved (drives the backoff).
enum DrainOutcome {
    /// Nothing was due.
    Idle,
    /// At least one envelope left the device (or was permanently discarded).
    Progress,
    /// Everything failed — offline, 5xx, or rate-limited.
    Stalled,
}

async fn drain_once(
    store: &Store,
    client: &reqwest::Client,
    url: &str,
    auth: &str,
) -> DrainOutcome {
    let due = match store.sentry_due(now_ms(), DRAIN_BATCH) {
        Ok(rows) if !rows.is_empty() => rows,
        _ => return DrainOutcome::Idle,
    };
    let mut progress = false;
    for row in due {
        let id = row.id;
        let response = client
            .post(url)
            .header("X-Sentry-Auth", auth)
            .header(
                reqwest::header::CONTENT_TYPE,
                "application/x-sentry-envelope",
            )
            .body(row.envelope)
            .send()
            .await;
        match response {
            Ok(resp) if resp.status().is_success() => {
                let _ = store.sentry_drop(id);
                progress = true;
            }
            // Rate limited: the ceiling applies to the whole project, so park the
            // ENTIRE queue rather than hammering it row by row.
            Ok(resp) if resp.status().as_u16() == 429 => {
                let retry_after_ms = resp
                    .headers()
                    .get(reqwest::header::RETRY_AFTER)
                    .and_then(|v| v.to_str().ok())
                    .and_then(|v| v.trim().parse::<i64>().ok())
                    .map(|secs| secs.clamp(1, 3600) * 1_000)
                    .unwrap_or(60_000);
                let _ = store.sentry_defer_all(now_ms() + retry_after_ms);
                return DrainOutcome::Stalled;
            }
            // Any other 4xx is a permanent rejection (malformed envelope, bad DSN,
            // event too large). Retrying can only ever fail again — drop it, and
            // count that as progress so the queue keeps moving.
            Ok(resp) if resp.status().is_client_error() => {
                let _ = store.sentry_drop(id);
                progress = true;
            }
            // 5xx or a transport error: the normal offline path. Back the row off
            // and stop the pass — the rest of the batch would fail identically.
            _ => {
                let backoff = (BASE_BACKOFF_MS.saturating_mul(1i64 << row.attempts.clamp(0, 5)))
                    .min(MAX_BACKOFF_MS);
                let _ = store.sentry_defer(id, now_ms() + backoff);
                return if progress {
                    DrainOutcome::Progress
                } else {
                    DrainOutcome::Stalled
                };
            }
        }
    }
    if progress {
        DrainOutcome::Progress
    } else {
        DrainOutcome::Idle
    }
}

fn user_agent() -> String {
    format!("madar-core/{}", env!("CARGO_PKG_VERSION"))
}

/// The envelope uploader. Same ring-backed rustls + bundled Mozilla roots as
/// `net.rs` — one TLS story for the whole core, and no OpenSSL anywhere near the
/// Android/iOS cross-builds. Kept separate from `ApiClient`'s pool so telemetry
/// can never consume a connection the POS needs to place an order.
fn build_uploader() -> Option<reqwest::Client> {
    reqwest::Client::builder()
        .use_preconfigured_tls(crate::net::default_tls_config())
        .connect_timeout(Duration::from_secs(5))
        .timeout(Duration::from_secs(20))
        .user_agent(user_agent())
        .build()
        .ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── scrubbing (the compliance control) ────────────────────────────────

    #[test]
    fn denies_the_pii_key_families_this_system_actually_handles() {
        for key in [
            "customer_name",
            "customerName",
            "phone",
            "customer_phone_number",
            "delivery_address",
            "street",
            "latitude",
            "lng",
            "staff_id",
            "employee_code",
            "salary",
            "access_token",
            "password",
            "offline_pin",
            "note",
            "card_last4",
        ] {
            assert!(is_denied_key(key), "{key} must be denied");
        }
    }

    #[test]
    fn allows_the_operational_ids_we_need_for_triage() {
        for key in [
            "order_id",
            "branch_id",
            "device_id",
            "msg_id",
            "op_type",
            "status",
            "attempts",
            "seq",
            "hop",
        ] {
            assert!(!is_denied_key(key), "{key} must NOT be denied");
        }
    }

    #[test]
    fn redacts_nested_structures_not_just_top_level_keys() {
        let mut v: Value = serde_json::json!({
            "order": {
                "id": "abc-123",
                "customer": { "name": "Ahmed", "phone": "01001234567" },
                "items": [{ "sku": "burger", "note": "no onions" }]
            }
        });
        redact_value(&mut v);
        let s = serde_json::to_string(&v).unwrap();
        assert!(s.contains("abc-123"), "operational ids survive: {s}");
        assert!(s.contains("burger"));
        assert!(!s.contains("Ahmed"), "nested name leaked: {s}");
        assert!(!s.contains("01001234567"), "nested phone leaked: {s}");
        assert!(!s.contains("no onions"), "nested free text leaked: {s}");
    }

    #[test]
    fn scrubs_pii_interpolated_into_free_text() {
        let out = scrub_text("failed to notify 01001234567 at a.customer@example.com").unwrap();
        assert!(!out.contains("01001234567"), "{out}");
        assert!(!out.contains("example.com"), "{out}");
        assert!(out.contains("failed to notify"), "{out}");
    }

    #[test]
    fn leaves_ordinary_diagnostics_untouched() {
        // No allocation, no change — the overwhelmingly common case.
        assert!(scrub_text("lan.accept: too many open files (os error 24)").is_none());
        assert!(scrub_text("sse reconnect attempt 12").is_none());
    }

    #[test]
    fn event_scrub_strips_user_identity_but_keeps_the_id() {
        let event = Event {
            user: Some(sentry::User {
                id: Some("device-7".into()),
                email: Some("teller@madar-pos.cloud".into()),
                username: Some("ahmed".into()),
                ip_address: Some(sentry::protocol::IpAddress::Auto),
                ..Default::default()
            }),
            ..Default::default()
        };
        let scrubbed = scrub_event(event);
        let user = scrubbed.user.unwrap();
        assert_eq!(user.id.as_deref(), Some("device-7"));
        assert!(user.email.is_none());
        assert!(user.username.is_none());
        assert!(user.ip_address.is_none());
    }

    #[test]
    fn event_scrub_never_lets_the_device_hostname_through() {
        // sentry's own `contexts` integration defaults `server_name` to the
        // hostname, which on a personal device is frequently a person's name.
        let event = Event {
            server_name: Some("Ahmeds-iPad".into()),
            ..Default::default()
        };
        let scrubbed = scrub_event(event);
        assert_eq!(scrubbed.server_name.as_deref(), Some("madar-pos-terminal"));
    }

    #[test]
    fn event_scrub_marks_that_the_control_ran() {
        let scrubbed = scrub_event(Event::default());
        assert_eq!(
            scrubbed.tags.get("pii.scrubbed").map(String::as_str),
            Some("true")
        );
    }

    #[test]
    fn event_scrub_redacts_extra_and_tag_values() {
        let mut event = Event::default();
        event
            .extra
            .insert("customer_phone".into(), Value::String("01001234567".into()));
        event.extra.insert(
            "payload".into(),
            serde_json::json!({ "delivery_address": "12 Nile St" }),
        );
        event.tags.insert("op".into(), "notify 01001234567".into());
        let scrubbed = scrub_event(event);
        let dump = serde_json::to_string(&scrubbed.extra).unwrap();
        assert!(!dump.contains("01001234567"), "{dump}");
        assert!(!dump.contains("Nile St"), "{dump}");
        assert!(!scrubbed.tags["op"].contains("01001234567"));
    }

    // ── disabled-by-default behaviour ─────────────────────────────────────

    #[test]
    fn no_dsn_configured_means_completely_disabled() {
        // The test process has no MADAR_SENTRY_DSN, so the core must behave
        // exactly as it did before this module existed.
        assert!(resolve_dsn().is_none());
        assert!(!is_enabled());
        // Every helper must be a safe no-op in that state.
        capture_bg_error("test.site", "should be dropped on the floor");
        set_device_scope(Some("d"), Some("b"), Some("teller"));
        assert!(flush(Duration::from_millis(1)));
    }

    #[test]
    fn a_malformed_dsn_disables_rather_than_panicking() {
        // Safety property: a typo in config degrades to "no telemetry".
        assert!("not-a-dsn".parse::<Dsn>().is_err());
    }

    // ── the disk queue ────────────────────────────────────────────────────

    #[test]
    fn queue_is_fifo_and_acks_by_deletion() {
        let s = Store::open("").unwrap();
        s.sentry_enqueue(b"one", 1_000).unwrap();
        let second = s.sentry_enqueue(b"two", 2_000).unwrap();
        let due = s.sentry_due(3_000, 10).unwrap();
        assert_eq!(due.len(), 2);
        assert_eq!(due[0].envelope, b"one".to_vec());
        s.sentry_drop(second).unwrap();
        assert_eq!(s.sentry_pending_count().unwrap(), 1);
    }

    #[test]
    fn deferred_envelopes_are_gated_until_their_backoff_expires() {
        let s = Store::open("").unwrap();
        let id = s.sentry_enqueue(b"env", 0).unwrap();
        s.sentry_defer(id, 10_000).unwrap();
        assert!(s.sentry_due(9_999, 10).unwrap().is_empty());
        assert_eq!(s.sentry_due(10_000, 10).unwrap().len(), 1);
    }

    #[test]
    fn a_rate_limit_parks_the_whole_queue() {
        let s = Store::open("").unwrap();
        for i in 0..5 {
            s.sentry_enqueue(format!("e{i}").as_bytes(), 0).unwrap();
        }
        s.sentry_defer_all(50_000).unwrap();
        assert!(s.sentry_due(49_999, 10).unwrap().is_empty());
    }

    #[test]
    fn caps_bound_the_queue_by_age_and_by_count() {
        let s = Store::open("").unwrap();
        // Two ancient reports + 250 recent ones.
        s.sentry_enqueue(b"ancient-a", 0).unwrap();
        s.sentry_enqueue(b"ancient-b", 10).unwrap();
        for i in 0..250 {
            s.sentry_enqueue(format!("recent-{i}").as_bytes(), 1_000_000)
                .unwrap();
        }
        s.sentry_prune(500_000, MAX_QUEUED).unwrap();
        // A terminal offline for days can never grow this table without bound.
        assert_eq!(s.sentry_pending_count().unwrap(), MAX_QUEUED);
        // And what survived is the NEWEST slice — the useful part.
        let kept = s.sentry_due(2_000_000, 1).unwrap();
        assert!(String::from_utf8_lossy(&kept[0].envelope).starts_with("recent-"));
    }

    #[test]
    fn the_queue_survives_a_process_restart() {
        // The whole point: a crash report captured offline must still be there
        // after the app is relaunched.
        let path = std::env::temp_dir().join(format!("madar_sentry_{}.db", std::process::id()));
        let _ = std::fs::remove_file(&path);
        let p = path.to_string_lossy().to_string();
        {
            let s = Store::open(&p).unwrap();
            s.sentry_enqueue(b"crash-report", 1).unwrap();
        }
        {
            let s = Store::open(&p).unwrap();
            assert_eq!(s.sentry_pending_count().unwrap(), 1);
        }
        let _ = std::fs::remove_file(&path);
    }

    // ── capture-site cooldown ─────────────────────────────────────────────

    #[test]
    fn a_looping_task_reports_once_per_window_not_once_per_iteration() {
        assert!(cooldown_elapsed("test.cooldown.site"));
        for _ in 0..1_000 {
            assert!(!cooldown_elapsed("test.cooldown.site"));
        }
        // A different site is tracked independently.
        assert!(cooldown_elapsed("test.cooldown.other"));
    }
}
