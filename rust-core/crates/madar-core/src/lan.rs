//! LAN offline relay (Phase E) — the second delivery path beside the cloud bus.
//!
//! On a venue's local Wi-Fi, waiters/KDS/tills reach each other directly so a fire,
//! round, or bump is visible instantly even with NO internet. This module is the
//! PURE-RUST core of that relay (works on every target the core compiles to); the
//! only host glue is discovery permissions + keeping the process alive (§5).
//!
//! **THE INVARIANT (do not violate):** the LAN is a *delivery path*, never the
//! source of truth. Every write still hits the durable SQLite outbox FIRST and
//! drains to `POST /sync/replay` on reconnect, deduped on the client-minted id.
//! The LAN just makes it visible NOW; nothing ever lives only on the LAN.
//!
//! This file holds the foundation — the signed message envelope, the per-branch
//! HMAC, and the peer registry. The async embedded relay server + mDNS/beacon
//! discovery + mesh gossip build on top (added next).
//!
//! Vocabulary mirrors the cloud bus (`realtime.rs`): a LAN message carries the same
//! `event_type` ("kitchen.fired", "ticket.fired", …) + `data` (raw JSON payload) the
//! cloud SSE emits, so the unified consumer forwards either path as the SAME
//! [`RealtimeEvent`](crate::realtime::RealtimeEvent) — a duplicate across paths is a
//! free, idempotent snapshot-reload on the host.

use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use hmac::{Hmac, KeyInit, Mac};
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream, UdpSocket};
use tokio::task::JoinHandle;

use crate::error::CoreError;

type HmacSha256 = Hmac<Sha256>;

// ── Message envelope ──────────────────────────────────────────────────────────

/// One relayed event on the LAN. Branch-scoped (a device only accepts messages for
/// its own branch), idempotency-keyed (`msg_id`), hop-bounded (mesh gossip). The
/// `event_type`/`data` pair is byte-for-byte what the cloud bus emits, so a LAN
/// message and its cloud twin reduce to one snapshot-reload on the host.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct LanMessage {
    /// Client-minted UUID — the dedup key across LAN, gossip, and cloud paths.
    pub msg_id: String,
    /// The branch this message belongs to. Receivers drop anything not their own
    /// branch (isolation), and the HMAC key is branch-scoped on top of that.
    pub branch_id: String,
    /// Cloud-bus topic: `kitchen` | `tickets` | `orders` | `delivery`.
    pub topic: String,
    /// Cloud-bus event type, e.g. `kitchen.fired`, `ticket.fired`, `kitchen.item_bumped`.
    pub event_type: String,
    /// The event payload as a raw JSON string (same shape the cloud SSE `data:` carries).
    pub data: String,
    /// Gossip hop count — incremented on each re-relay, dropped past [`MAX_HOPS`].
    pub hop: u8,
    /// The device that originally minted this message (loop-avoidance + logging).
    pub sender_id: String,
    /// Sender's clock-corrected wall time (ms) — staleness/heartbeat, not trusted for ordering.
    pub sent_at_ms: i64,
    /// For a WRITE event (fire/round/bump): the `/sync/replay` envelope JSON, so a
    /// receiver can MIRROR it into its own outbox (robustness #4 — the write reaches
    /// the cloud even if the originating device dies before its outbox drains). `None`
    /// for a pure display event (e.g. one relayed from the cloud). Signed with the rest.
    #[serde(default)]
    pub replay_op: Option<String>,
}

/// Max gossip re-relays before a message is dropped — bounds flooding on a mesh.
pub const MAX_HOPS: u8 = 4;

impl LanMessage {
    /// True once this message has been relayed too many times (drop it).
    pub fn hops_exhausted(&self) -> bool {
        self.hop >= MAX_HOPS
    }

    /// A copy advanced one gossip hop (for re-relay), or `None` if exhausted.
    pub fn relayed(&self) -> Option<LanMessage> {
        if self.hops_exhausted() {
            return None;
        }
        let mut next = self.clone();
        next.hop += 1;
        Some(next)
    }
}

// ── Per-branch HMAC + signed frame ────────────────────────────────────────────

/// The on-wire frame: a [`LanMessage`] serialized verbatim (`msg`) plus an
/// HMAC-SHA256 (`sig`, hex) over those EXACT bytes. Signing the transmitted string —
/// not a re-serialization — sidesteps JSON key-ordering canonicalization entirely:
/// the receiver verifies over the bytes it received, then parses.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct SignedFrame {
    pub sig: String,
    pub msg: String,
}

/// Derive the per-branch LAN key from the org's hex `lan_secret` (shipped in the
/// offline-auth bundle): `HMAC-SHA256(org_secret, branch_id)`. A distinct key per
/// branch means a leak is contained to one branch, and a foreign-branch device
/// (different key) can't forge messages a receiver will accept.
pub fn branch_key(org_secret_hex: &str, branch_id: &str) -> Vec<u8> {
    let secret = from_hex(org_secret_hex).unwrap_or_else(|| org_secret_hex.as_bytes().to_vec());
    let mut mac = HmacSha256::new_from_slice(&secret).expect("HMAC accepts any key length");
    mac.update(branch_id.as_bytes());
    mac.finalize().into_bytes().to_vec()
}

/// Sign an arbitrary string body with the branch key → the on-wire frame. The
/// signature covers the EXACT bytes carried in `msg`, so the receiver verifies what
/// it received (no canonicalization). Used for both [`LanMessage`]s and beacons.
pub fn sign_str(key: &[u8], msg: String) -> SignedFrame {
    let sig = to_hex(&hmac(key, msg.as_bytes()));
    SignedFrame { sig, msg }
}

/// Verify a frame and return its body string, or `None` on a bad signature
/// (foreign-branch / tampered / wrong key). Constant-time compare (`verify_slice`).
pub fn verify_str<'a>(key: &[u8], frame: &'a SignedFrame) -> Option<&'a str> {
    let expected = from_hex(&frame.sig)?;
    let mut mac = HmacSha256::new_from_slice(key).expect("HMAC accepts any key length");
    mac.update(frame.msg.as_bytes());
    mac.verify_slice(&expected).ok()?;
    Some(&frame.msg)
}

/// Sign a [`LanMessage`] with the branch key, producing the on-wire frame.
pub fn sign_frame(key: &[u8], message: &LanMessage) -> SignedFrame {
    sign_str(key, serde_json::to_string(message).unwrap_or_default())
}

/// Verify a received frame and return the parsed message, or `None` if the
/// signature fails or the body doesn't parse.
pub fn verify_frame(key: &[u8], frame: &SignedFrame) -> Option<LanMessage> {
    verify_str(key, frame).and_then(|s| serde_json::from_str(s).ok())
}

fn hmac(key: &[u8], bytes: &[u8]) -> Vec<u8> {
    let mut mac = HmacSha256::new_from_slice(key).expect("HMAC accepts any key length");
    mac.update(bytes);
    mac.finalize().into_bytes().to_vec()
}

fn to_hex(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        use std::fmt::Write;
        let _ = write!(s, "{b:02x}");
    }
    s
}

fn from_hex(s: &str) -> Option<Vec<u8>> {
    if !s.len().is_multiple_of(2) {
        return None;
    }
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(s.get(i..i + 2)?, 16).ok())
        .collect()
}

// ── Peer registry ─────────────────────────────────────────────────────────────

/// A discovered LAN peer (via mDNS, the UDP beacon, or a manual hub-IP). A till that
/// holds an OPEN shift advertises `open_shift_id` — the freshly-heartbeated truth the
/// shift-open gate trusts over the (possibly-behind) backend. Liveness is the
/// `last_seen_ms` heartbeat; a peer that stops advertising expires within [`PEER_TTL_MS`].
#[derive(Clone, Debug, PartialEq)]
pub struct Peer {
    pub device_id: String,
    pub branch_id: String,
    /// `kitchen` | `waiter` | `teller`.
    pub role: String,
    pub host: String,
    pub port: u16,
    /// The station a KDS device shows (None for a waiter/till).
    pub station_id: Option<String>,
    /// `Some(till_id)` when this is a till advertising an OPEN shift — the LAN
    /// shift-open gate's freshest signal. `None` otherwise.
    pub open_shift_id: Option<String>,
    /// The peer's managed device code (`36B`), when it advertises one.
    pub device_code: Option<String>,
    /// Every open till the peer holds, one per person (new beacons only).
    pub open_tills: Vec<BeaconTill>,
    /// Last heartbeat (clock-corrected wall ms); drives TTL expiry.
    pub last_seen_ms: i64,
}

/// One open till in a beacon: whose it is and since when (TILLS_CONTRACT §4.6).
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq, Default)]
pub struct BeaconTill {
    pub till_id: String,
    pub person_id: String,
    #[serde(default)]
    pub person_name: String,
    #[serde(default)]
    pub opened_at: String,
}

/// How long after its last heartbeat a peer is considered gone. Short enough that a
/// till closing its shift stops counting toward "branch operating" within seconds.
pub const PEER_TTL_MS: i64 = 12_000;

/// The live set of discovered peers, keyed by `device_id`. Pure + heartbeat-driven;
/// the async discovery layer feeds it and reads relay targets / the shift gate.
#[derive(Default)]
pub struct PeerRegistry {
    peers: HashMap<String, Peer>,
}

impl PeerRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Insert or refresh a peer (its `last_seen_ms` heartbeat).
    pub fn upsert(&mut self, peer: Peer) {
        self.peers.insert(peer.device_id.clone(), peer);
    }

    /// Drop a peer outright (e.g. an mDNS "service removed").
    pub fn remove(&mut self, device_id: &str) {
        self.peers.remove(device_id);
    }

    /// Evict peers whose last heartbeat is older than the TTL at `now_ms`.
    pub fn prune(&mut self, now_ms: i64) {
        self.peers
            .retain(|_, p| now_ms - p.last_seen_ms <= PEER_TTL_MS);
    }

    /// The still-live peers for a branch at `now_ms` (TTL applied on read, so a
    /// stale-but-not-yet-pruned peer never counts).
    pub fn live_for_branch(&self, branch_id: &str, now_ms: i64) -> Vec<&Peer> {
        self.peers
            .values()
            .filter(|p| p.branch_id == branch_id && now_ms - p.last_seen_ms <= PEER_TTL_MS)
            .collect()
    }

    /// `(host, port)` of every live peer in the branch except `self_id` — the mesh
    /// fan-out targets a waiter/teller pushes a fire/round/bump to.
    pub fn relay_targets(&self, branch_id: &str, self_id: &str, now_ms: i64) -> Vec<(String, u16)> {
        self.live_for_branch(branch_id, now_ms)
            .into_iter()
            .filter(|p| p.device_id != self_id)
            .map(|p| (p.host.clone(), p.port))
            .collect()
    }

    /// The LAN shift-open gate: is a till at this branch advertising a FRESH open
    /// shift? `true` means "the branch is operating" per the most current signal —
    /// it beats the backend, which may not yet know a till closed (or opened) if
    /// that change hasn't synced. A closed till stops advertising and expires within
    /// the TTL, so this reflects reality, not a stale cache.
    pub fn branch_has_open_till(&self, branch_id: &str, now_ms: i64) -> bool {
        self.live_for_branch(branch_id, now_ms)
            .iter()
            .any(|p| p.open_shift_id.is_some() || !p.open_tills.is_empty())
    }

    /// A live peer at the branch advertising `person_id`'s open till — the LAN half
    /// of "one open till per person" (an old peer's bare `open_shift_id` names no
    /// person, so it can never block anyone).
    pub fn person_open_till(
        &self,
        branch_id: &str,
        person_id: &str,
        now_ms: i64,
    ) -> Option<(Peer, BeaconTill)> {
        self.live_for_branch(branch_id, now_ms)
            .into_iter()
            .find_map(|p| {
                p.open_tills
                    .iter()
                    .find(|t| t.person_id == person_id && !t.till_id.is_empty())
                    .map(|t| (p.clone(), t.clone()))
            })
    }

    /// At least one live TELLER peer at the branch (a LAN verification is only
    /// meaningful when someone who could hold a till is listening).
    pub fn has_live_teller_peer(&self, branch_id: &str, now_ms: i64) -> bool {
        self.live_for_branch(branch_id, now_ms)
            .iter()
            .any(|p| p.role == "teller")
    }

    /// Every open till advertised at the branch: `(peer, till)`.
    pub fn branch_open_tills(&self, branch_id: &str, now_ms: i64) -> Vec<(Peer, BeaconTill)> {
        let mut out = Vec::new();
        for p in self.live_for_branch(branch_id, now_ms) {
            for t in &p.open_tills {
                out.push((p.clone(), t.clone()));
            }
        }
        out
    }
}

// ── The running relay (async) ─────────────────────────────────────────────────

/// Local wall-clock in ms — relative liveness/heartbeat timing (not order_ref math).
fn now_ms() -> i64 {
    chrono::Utc::now().timestamp_millis()
}

/// mDNS service type for Madar LAN peers.
const SERVICE_TYPE: &str = "_madar._tcp.local.";
/// Default TCP relay port (fixed so a manual hub-IP needs only the host typed in).
pub const DEFAULT_TCP_PORT: u16 = 47600;
/// Default UDP beacon port (shared across a branch's devices).
pub const DEFAULT_BEACON_PORT: u16 = 47601;
/// Cap on a single relay frame (bytes) — refuse oversized lines (abuse guard).
const MAX_FRAME: usize = 256 * 1024;
/// How many recent `msg_id`s to remember for dedup (mesh gossip de-storm).
const SEEN_CAP: usize = 4096;
/// Beacon cadence — re-advertise + heartbeat every few seconds (< PEER_TTL_MS).
const BEACON_EVERY: Duration = Duration::from_millis(3_000);

/// What the relay does with a verified, deduped inbound message — implemented by
/// `MadarCore`: forward it to the unified realtime listener (instant board update)
/// and, for a write event carrying a replay op, mirror that op into the outbox
/// (robustness #4 — the fire reaches the cloud even if the originator dies first).
pub trait LanInbound: Send + Sync {
    fn on_lan_message(&self, msg: &LanMessage);
    /// This device's catch-up digest (`lan_sync::SyncBody::Digest`), if any.
    fn lan_digest(&self) -> Option<serde_json::Value> {
        None
    }
    /// Handle one catch-up message from a peer; the replies go back to it.
    fn lan_sync(&self, _body: &serde_json::Value) -> Vec<serde_json::Value> {
        Vec::new()
    }
}

/// A catch-up frame: point-to-point between two devices of a branch (never
/// gossiped). Signed like every other frame.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct SyncEnvelope {
    pub branch_id: String,
    pub from: String,
    /// The addressee (`None`: any device of the branch — a broadcast digest).
    #[serde(default)]
    pub to: Option<String>,
    pub sent_at_ms: i64,
    pub body: serde_json::Value,
}

/// How a relay moves lines: real sockets, or an in-process network (the
/// simulation harness drives it and decides delivery, loss, delay and order).
pub trait LanTransport: Send + Sync {
    /// Deliver `line` to the device at `host` (a device id in a simulation).
    fn send(&self, host: &str, port: u16, line: String);
}

/// Catch-up digest cadence (and on every newly discovered peer).
pub const SYNC_EVERY: Duration = Duration::from_millis(10_000);
/// A catch-up frame older than this is dropped (a replayed capture).
pub const SYNC_MAX_AGE_MS: i64 = 10 * 60 * 1000;
/// Most reply lines read back from one catch-up exchange.
const MAX_REPLY_LINES: usize = 256;
/// Nested exchanges one digest may trigger (HAVE → WANT → OFFER, ROWS pages).
const MAX_EXCHANGE_DEPTH: usize = 64;

/// Bounded recent-id set for at-least-once dedup across LAN + gossip + cloud.
struct SeenSet {
    ids: HashSet<String>,
    order: VecDeque<String>,
}
impl SeenSet {
    fn new() -> Self {
        Self {
            ids: HashSet::new(),
            order: VecDeque::new(),
        }
    }
    /// Record `id`; returns `true` if it was NOT seen before (i.e. process it).
    fn insert(&mut self, id: &str) -> bool {
        if self.ids.contains(id) {
            return false;
        }
        self.ids.insert(id.to_string());
        self.order.push_back(id.to_string());
        if self.order.len() > SEEN_CAP {
            if let Some(old) = self.order.pop_front() {
                self.ids.remove(&old);
            }
        }
        true
    }
}

/// This device's relay identity + crypto + ports.
#[derive(Clone)]
pub struct LanConfig {
    pub device_id: String,
    pub branch_id: String,
    pub role: String,
    pub station_id: Option<String>,
    /// Per-branch HMAC key (from [`branch_key`]).
    pub key: Vec<u8>,
    /// TCP relay port (0 = OS-assigned; read back via [`LanRelay::tcp_port`]).
    pub tcp_port: u16,
    /// UDP beacon port (shared across the branch's devices).
    pub beacon_port: u16,
}

/// The signed UDP discovery/heartbeat beacon. The source IP is taken from
/// `recv_from` (no local-IP detection needed), so the payload carries only the TCP
/// port + identity + the open-shift advert (the LAN shift-open gate's signal).
#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct Beacon {
    pub(crate) device_id: String,
    pub(crate) branch_id: String,
    pub(crate) role: String,
    pub(crate) station_id: Option<String>,
    /// KEPT for old peers: the first open till id on this device.
    pub(crate) open_shift_id: Option<String>,
    #[serde(default)]
    pub(crate) device_code: Option<String>,
    #[serde(default)]
    pub(crate) open_tills: Vec<BeaconTill>,
    pub(crate) tcp_port: u16,
    pub(crate) sent_at_ms: i64,
}

/// State shared with the spawned relay tasks.
struct RelayShared {
    cfg: LanConfig,
    registry: Mutex<PeerRegistry>,
    seen: Mutex<SeenSet>,
    inbound: Arc<dyn LanInbound>,
    /// This device's open tills (one per person), advertised in the beacon.
    open_tills: Mutex<Vec<BeaconTill>>,
    /// This device's managed code, advertised in the beacon + mDNS TXT.
    device_code: Mutex<Option<String>>,
    /// The actually-bound TCP port (after OS assignment), advertised in the beacon.
    bound_tcp_port: Mutex<u16>,
    /// Manually-configured hub peers (`host`, `port`) — the always-works fallback
    /// when discovery is filtered. Unlike registry peers these never TTL-expire; we
    /// always push to them (and receive from them via our own signed server).
    manual: Mutex<Vec<(String, u16)>>,
    /// `None`: real sockets. `Some`: an in-process network.
    transport: Option<Arc<dyn LanTransport>>,
    /// Frames accepted / refused (diagnostics and the adversarial tests).
    stats: Mutex<RelayStats>,
    /// Which discovery layers actually came up (the LAN status view).
    discovery: Mutex<DiscoveryState>,
}

/// Which discovery layers are live on this relay.
#[derive(Default, Clone, Debug, PartialEq, Eq)]
pub struct DiscoveryState {
    /// The UDP broadcast beacon socket is bound and running.
    pub beacon: bool,
    /// The raw mDNS daemon is advertising + browsing.
    pub mdns: bool,
    /// Last time the host's native Bonjour/NSD layer noted a peer (0 = never).
    pub native_last_ms: i64,
}

/// Where a noted peer came from (only the logging/status differs).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PeerSource {
    /// The Rust mdns-sd daemon.
    Mdns,
    /// The host's native Bonjour (NWBrowser) / NsdManager, via the bridge.
    Native,
}

/// An unsigned discovery record (mDNS TXT or native Bonjour TXT): identity and
/// address only. Never carries the shift advert — only the signed beacon does.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PeerNote {
    pub device_id: String,
    pub branch_id: String,
    pub host: String,
    pub port: u16,
    pub role: String,
    pub station_id: Option<String>,
    pub device_code: Option<String>,
}

/// What this device advertises over native Bonjour: the same TXT fields the Rust
/// mDNS advert carries (`branch_id`, `device_id`, `role`, `station_id`,
/// `device_code`, `tcp_port`).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LanAdvertView {
    pub device_id: String,
    pub branch_id: String,
    pub role: String,
    pub station_id: Option<String>,
    pub device_code: Option<String>,
    pub tcp_port: u16,
}

/// The LAN relay's health, for Settings and the retry loop.
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct LanStatusView {
    pub running: bool,
    /// Live discovered peers + manual hubs.
    pub peer_count: u32,
    pub manual_hub_count: u32,
    /// Why the last `lan_start` failed (`None` after a successful start).
    pub last_error: Option<String>,
    /// The actually-bound TCP relay port (`None` when not running).
    pub tcp_port: Option<u16>,
    pub beacon_active: bool,
    pub mdns_active: bool,
    /// The host's native Bonjour/NSD noted a peer within the peer TTL.
    pub native_discovery_active: bool,
}

/// What the relay did with inbound frames.
#[derive(Default, Clone, Debug, PartialEq, Eq)]
pub struct RelayStats {
    pub accepted: u64,
    pub malformed: u64,
    pub bad_signature: u64,
    pub foreign_branch: u64,
    pub duplicate: u64,
    pub hops_exhausted: u64,
    pub stale: u64,
    pub oversized: u64,
    pub sync_frames: u64,
}

/// A running LAN relay: an embedded TCP server (accepts signed pushes → forwards +
/// gossips), a UDP beacon (discovery + heartbeat + shift advert), optional mDNS, and
/// a TTL pruner. Pure tokio — cancellable, non-blocking, cross-compiles everywhere.
pub struct LanRelay {
    shared: Arc<RelayShared>,
    handles: Mutex<Vec<JoinHandle<()>>>,
    mdns: Mutex<Option<mdns_sd::ServiceDaemon>>,
}

impl LanRelay {
    pub fn new(cfg: LanConfig, inbound: Arc<dyn LanInbound>) -> Self {
        Self::with_transport(cfg, inbound, None)
    }

    /// A relay on an in-process network: nothing binds, nothing is spawned; the
    /// owner delivers inbound lines ([`Self::deliver_line`]) and calls
    /// [`Self::heartbeat`].
    pub fn new_virtual(cfg: LanConfig, inbound: Arc<dyn LanInbound>, transport: Arc<dyn LanTransport>) -> Self {
        Self::with_transport(cfg, inbound, Some(transport))
    }

    fn with_transport(cfg: LanConfig, inbound: Arc<dyn LanInbound>, transport: Option<Arc<dyn LanTransport>>) -> Self {
        let bound = cfg.tcp_port;
        Self {
            shared: Arc::new(RelayShared {
                cfg,
                registry: Mutex::new(PeerRegistry::new()),
                seen: Mutex::new(SeenSet::new()),
                inbound,
                open_tills: Mutex::new(Vec::new()),
                device_code: Mutex::new(None),
                bound_tcp_port: Mutex::new(bound),
                manual: Mutex::new(Vec::new()),
                transport,
                stats: Mutex::new(RelayStats::default()),
                discovery: Mutex::new(DiscoveryState::default()),
            }),
            handles: Mutex::new(Vec::new()),
            mdns: Mutex::new(None),
        }
    }

    /// Inbound frame statistics.
    pub fn stats(&self) -> RelayStats {
        self.shared.stats.lock().unwrap().clone()
    }

    /// Deliver one inbound line (`VERB payload`) as if it arrived on the socket;
    /// returns the reply lines (a real socket writes them back to the caller; the
    /// in-process network routes them itself, see [`Self::heartbeat`]).
    pub async fn deliver_line(&self, line: &str) -> Vec<String> {
        dispatch_line(&self.shared, line).await
    }

    /// Send this device's catch-up digest to every peer (the timer does this on
    /// sockets; a simulation calls it).
    pub async fn heartbeat(&self) {
        send_digest(&self.shared, None).await;
    }

    /// Send the digest to one peer (a newly discovered one).
    pub async fn heartbeat_to(&self, device_id: &str) {
        send_digest(&self.shared, Some(device_id.to_string())).await;
    }

    /// The actually-bound TCP relay port (meaningful after [`start`](Self::start)).
    pub fn tcp_port(&self) -> u16 {
        *self.shared.bound_tcp_port.lock().unwrap()
    }

    /// Update the advertised open-shift (the LAN shift-open gate's truth). Pass the
    /// open shift's id when this till opens, `None` when it closes.
    pub fn set_open_tills(&self, tills: Vec<BeaconTill>) {
        *self.shared.open_tills.lock().unwrap() = tills;
    }

    /// Set the device code advertised in the beacon (and mDNS on next start).
    pub fn set_device_code(&self, code: Option<String>) {
        *self.shared.device_code.lock().unwrap() = code;
    }

    /// See [`PeerRegistry::person_open_till`].
    pub fn person_open_till(&self, person_id: &str) -> Option<(Peer, BeaconTill)> {
        self.shared.registry.lock().unwrap().person_open_till(
            &self.shared.cfg.branch_id,
            person_id,
            now_ms(),
        )
    }

    /// See [`PeerRegistry::has_live_teller_peer`].
    pub fn has_live_teller_peer(&self) -> bool {
        self.shared
            .registry
            .lock()
            .unwrap()
            .has_live_teller_peer(&self.shared.cfg.branch_id, now_ms())
    }

    /// See [`PeerRegistry::branch_open_tills`].
    pub fn branch_open_tills(&self) -> Vec<(Peer, BeaconTill)> {
        self.shared
            .registry
            .lock()
            .unwrap()
            .branch_open_tills(&self.shared.cfg.branch_id, now_ms())
    }

    /// Inject a discovered peer (TTL-tracked) — the iOS-Bonjour bridge feeds peers
    /// resolved via Network.framework in here; the host re-injects on each refresh.
    /// A peer not seen before gets this device's catch-up digest at once.
    pub fn add_peer(&self, peer: Peer) {
        let id = peer.device_id.clone();
        let fresh = upsert_peer(&self.shared, peer);
        if fresh && self.shared.transport.is_none() {
            let shared = self.shared.clone();
            if let Ok(h) = tokio::runtime::Handle::try_current() {
                h.spawn(async move { send_digest(&shared, Some(id)).await });
            }
        }
    }

    /// Fold an unsigned discovery record (native Bonjour/NSD) into the registry:
    /// branch-filtered, self-skipped, TTL-refreshed. A host re-notes live peers
    /// periodically so pruning never drops one that is still advertising.
    /// Returns `true` when the peer was accepted.
    pub fn note_peer(&self, note: PeerNote, source: PeerSource) -> bool {
        match note_peer(&self.shared, note, source) {
            NoteOutcome::Fresh(id) => {
                if self.shared.transport.is_none() {
                    let shared = self.shared.clone();
                    if let Ok(h) = tokio::runtime::Handle::try_current() {
                        h.spawn(async move { send_digest(&shared, Some(id)).await });
                    }
                }
                true
            }
            NoteOutcome::Refreshed => true,
            NoteOutcome::Ignored => false,
        }
    }

    /// Which discovery layers are live.
    pub fn discovery(&self) -> DiscoveryState {
        self.shared.discovery.lock().unwrap().clone()
    }

    /// Count of manual hubs.
    pub fn manual_hub_count(&self) -> u32 {
        self.shared.manual.lock().unwrap().len() as u32
    }

    /// This device's advert (for the host's native Bonjour broadcast).
    pub fn advert(&self) -> LanAdvertView {
        LanAdvertView {
            device_id: self.shared.cfg.device_id.clone(),
            branch_id: self.shared.cfg.branch_id.clone(),
            role: self.shared.cfg.role.clone(),
            station_id: self.shared.cfg.station_id.clone(),
            device_code: self.shared.device_code.lock().unwrap().clone(),
            tcp_port: self.tcp_port(),
        }
    }

    /// Register a manual hub peer (`host`, `port`) — the always-works fallback. Never
    /// TTL-expires; we always push to it. Idempotent (no duplicate host:port).
    pub fn add_manual_hub(&self, host: String, port: u16) {
        let mut m = self.shared.manual.lock().unwrap();
        if !m.iter().any(|(h, p)| *h == host && *p == port) {
            m.push((host, port));
        }
    }

    /// Count of currently-live discovered peers + manual hubs (a diagnostics signal).
    pub fn peer_count(&self) -> u32 {
        let live = self
            .shared
            .registry
            .lock()
            .unwrap()
            .live_for_branch(&self.shared.cfg.branch_id, now_ms())
            .len();
        let manual = self.shared.manual.lock().unwrap().len();
        (live + manual) as u32
    }

    /// The LAN shift-open gate for this branch (a fresh-advertising open till).
    pub fn branch_has_open_till(&self) -> bool {
        self.shared
            .registry
            .lock()
            .unwrap()
            .branch_has_open_till(&self.shared.cfg.branch_id, now_ms())
    }

    /// Start the embedded server + discovery + pruner. Binds the TCP relay (fatal if
    /// it can't); the beacon + mDNS degrade gracefully (logged, not fatal) so a relay
    /// still works on a network that filters one discovery layer but not unicast.
    pub async fn start(&self) -> Result<(), CoreError> {
        let listener = bind_tcp_with_fallback(self.shared.cfg.tcp_port)
            .await
            .map_err(|e| CoreError::Internal {
                detail: format!("lan tcp bind: {e}"),
            })?;
        if let Ok(addr) = listener.local_addr() {
            *self.shared.bound_tcp_port.lock().unwrap() = addr.port();
        }

        // 1. TCP relay accept loop.
        let shared = self.shared.clone();
        self.spawn(tokio::spawn(async move {
            loop {
                match listener.accept().await {
                    Ok((stream, _)) => {
                        let s = shared.clone();
                        tokio::spawn(async move { handle_conn(s, stream).await });
                    }
                    Err(e) => {
                        // A failing accept is NOT routine: it means fd exhaustion
                        // or the socket going away, i.e. this till has silently
                        // stopped receiving every peer's relay traffic. Nothing
                        // above returns from this loop, so without a report the
                        // failure is invisible until someone notices missing
                        // kitchen chits. (Rate-limited per site by `obs`.)
                        crate::obs::capture_bg_error("lan.accept", format!("tcp accept: {e}"));
                        tokio::time::sleep(Duration::from_millis(50)).await
                    }
                }
            }
        }));

        // 2. UDP beacon (send + receive). Best-effort — but "best-effort" has
        //    meant "fails in total silence": without the beacon this device is
        //    invisible to its peers AND can't see their open-shift adverts, which
        //    degrades the LAN shift-open gate. Report the bind failure.
        // iOS blocks broadcast + multicast without Apple's restricted multicast
        // entitlement: the host's native Bonjour is the discovery path there, so
        // don't start (and log-spam) layers that can only fail.
        #[cfg(target_os = "ios")]
        let beacon: std::io::Result<UdpSocket> =
            Err(std::io::Error::new(std::io::ErrorKind::Unsupported, "ios"));
        #[cfg(not(target_os = "ios"))]
        let beacon = bind_beacon(self.shared.cfg.beacon_port).await;
        #[cfg(not(target_os = "ios"))]
        if let Err(ref e) = beacon {
            crate::obs::capture_bg_warning(
                "lan.beacon_bind",
                format!("udp beacon bind on {}: {e}", self.shared.cfg.beacon_port),
            );
        }
        if let Ok(sock) = beacon {
            self.shared.discovery.lock().unwrap().beacon = true;
            let sock = Arc::new(sock);
            let send_shared = self.shared.clone();
            let send_sock = sock.clone();
            self.spawn(tokio::spawn(async move {
                beacon_send_loop(send_shared, send_sock).await;
            }));
            let recv_shared = self.shared.clone();
            self.spawn(tokio::spawn(async move {
                beacon_recv_loop(recv_shared, sock).await;
            }));
        }

        // 3. mDNS advertise + browse. Best-effort; skipped on iOS (see above).
        #[cfg(not(target_os = "ios"))]
        self.start_mdns();

        // 4. TTL pruner.
        let prune_shared = self.shared.clone();
        self.spawn(tokio::spawn(async move {
            loop {
                tokio::time::sleep(Duration::from_millis(4_000)).await;
                prune_shared.registry.lock().unwrap().prune(now_ms());
            }
        }));

        // 5. Catch-up digests (anti-entropy): every peer hears what this device
        //    holds, so whatever it missed is exchanged.
        let sync_shared = self.shared.clone();
        self.spawn(tokio::spawn(async move {
            loop {
                tokio::time::sleep(SYNC_EVERY).await;
                send_digest(&sync_shared, None).await;
            }
        }));

        Ok(())
    }

    /// Publish a local event to every discovered peer (hop 0). The originator records
    /// its own `msg_id` so a gossip bounce-back is deduped. Fire-and-forget per peer.
    /// `replay_op` carries the `/sync/replay` envelope for a write (mirror-relay), or
    /// `None` for a pure display trigger.
    pub async fn publish(
        &self,
        topic: &str,
        event_type: &str,
        data: String,
        replay_op: Option<String>,
        sent_at_ms: i64,
    ) {
        self.publish_with_id(
            uuid::Uuid::new_v4().to_string(),
            topic,
            event_type,
            data,
            replay_op,
            sent_at_ms,
        )
        .await;
    }

    /// Publish with a CALLER-CHOSEN `msg_id`. Used to rebroadcast a cloud-only
    /// event (an online order, a booking) onto the LAN: every till that holds a
    /// cloud connection re-publishes it under the SAME deterministic id
    /// (`cloud:<branch>:<event id>`), so a waiter tablet without internet hears
    /// it exactly once no matter how many tills relayed it. A `msg_id` this
    /// device already saw (a peer beat us to it) is not re-sent.
    pub async fn publish_with_id(
        &self,
        msg_id: String,
        topic: &str,
        event_type: &str,
        data: String,
        replay_op: Option<String>,
        sent_at_ms: i64,
    ) {
        if !self.shared.seen.lock().unwrap().insert(&msg_id) {
            return;
        }
        let msg = LanMessage {
            msg_id,
            branch_id: self.shared.cfg.branch_id.clone(),
            topic: topic.to_string(),
            event_type: event_type.to_string(),
            data,
            hop: 0,
            sender_id: self.shared.cfg.device_id.clone(),
            sent_at_ms,
            replay_op,
        };
        let frame = sign_frame(&self.shared.cfg.key, &msg);
        if let Ok(json) = serde_json::to_string(&frame) {
            fanout(&self.shared, format!("MSG {json}")).await;
        }
    }

    /// Abort every spawned task + shut the mDNS daemon — idempotent.
    pub fn stop(&self) {
        for h in self.handles.lock().unwrap().drain(..) {
            h.abort();
        }
        if let Some(d) = self.mdns.lock().unwrap().take() {
            let _ = d.shutdown();
        }
        *self.shared.discovery.lock().unwrap() = DiscoveryState::default();
    }

    fn spawn(&self, h: JoinHandle<()>) {
        self.handles.lock().unwrap().push(h);
    }

    /// Advertise `_madar._tcp` + browse for peers, feeding resolved services into the
    /// registry. Unsigned TXT (discovery only) — message acceptance is still HMAC-gated,
    /// and the shift gate trusts only the SIGNED beacon, so mDNS can't spoof either.
    #[cfg(not(target_os = "ios"))]
    fn start_mdns(&self) {
        let daemon = match mdns_sd::ServiceDaemon::new() {
            Ok(d) => d,
            Err(e) => {
                crate::obs::capture_bg_warning("lan.mdns_daemon", format!("mdns daemon: {e}"));
                return;
            }
        };
        let port = self.tcp_port();
        let code_txt = self.shared.device_code.lock().unwrap().clone().unwrap_or_default();
        // `open_shift_id` stays in TXT for old peers; `open_tills` is beacon-only (size).
        let open_txt = self
            .shared
            .open_tills
            .lock()
            .unwrap()
            .first()
            .map(|t| t.till_id.clone())
            .unwrap_or_default();
        let props: HashMap<String, String> = [
            ("open_shift_id", open_txt.as_str()),
            ("device_id", self.shared.cfg.device_id.as_str()),
            ("branch_id", self.shared.cfg.branch_id.as_str()),
            ("role", self.shared.cfg.role.as_str()),
            (
                "station_id",
                self.shared.cfg.station_id.as_deref().unwrap_or(""),
            ),
            ("tcp_port", &port.to_string()),
            ("device_code", &code_txt),
        ]
        .iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect();
        let instance = format!("madar-{}", self.shared.cfg.device_id);
        let host = format!("{}.local.", self.shared.cfg.device_id);
        if let Ok(info) = mdns_sd::ServiceInfo::new(SERVICE_TYPE, &instance, &host, "", port, props)
            .map(|i| i.enable_addr_auto())
        {
            let _ = daemon.register(info);
        }
        match daemon.browse(SERVICE_TYPE) {
            Ok(rx) => {
                self.shared.discovery.lock().unwrap().mdns = true;
                let shared = self.shared.clone();
                self.spawn(tokio::spawn(async move {
                    while let Ok(event) = rx.recv_async().await {
                        if let mdns_sd::ServiceEvent::ServiceResolved(info) = event {
                            ingest_mdns(&shared, &info);
                        }
                    }
                    shared.discovery.lock().unwrap().mdns = false;
                    // Falling out of the loop means the daemon channel closed:
                    // mDNS discovery is dead for the rest of this process and will
                    // never recover on its own. The relay keeps limping on the UDP
                    // beacon + manual hub, so the degradation is invisible locally.
                    crate::obs::capture_bg_warning(
                        "lan.mdns_browse",
                        "mdns browse channel closed — discovery is down for this session",
                    );
                }));
            }
            Err(e) => {
                crate::obs::capture_bg_warning("lan.mdns_browse", format!("mdns browse: {e}"))
            }
        }
        *self.mdns.lock().unwrap() = Some(daemon);
    }
}

impl Drop for LanRelay {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Fan a signed line out to every live same-branch peer (excluding self), each send
/// independent so a slow/dead peer can't stall the others.
async fn fanout(shared: &Arc<RelayShared>, line: String) {
    let mut targets = {
        let reg = shared.registry.lock().unwrap();
        reg.relay_targets(&shared.cfg.branch_id, &shared.cfg.device_id, now_ms())
    };
    // Always include manual hubs (no TTL), de-duped against discovered peers.
    for (host, port) in shared.manual.lock().unwrap().iter() {
        if !targets.iter().any(|(h, p)| h == host && p == port) {
            targets.push((host.clone(), *port));
        }
    }
    for (host, port) in targets {
        if let Some(t) = &shared.transport {
            t.send(&host, port, line.clone());
            continue;
        }
        let line = line.clone();
        tokio::spawn(async move {
            send_frame(&host, port, &line).await;
        });
    }
}

/// Registry upsert; `true` when the device was not known (or had expired).
fn upsert_peer(shared: &Arc<RelayShared>, peer: Peer) -> bool {
    let mut reg = shared.registry.lock().unwrap();
    let known = reg.live_for_branch(&peer.branch_id, now_ms()).iter().any(|p| p.device_id == peer.device_id);
    reg.upsert(peer);
    !known
}

/// Where a device id is reachable, if known.
fn address_of(shared: &Arc<RelayShared>, device_id: &str) -> Option<(String, u16)> {
    shared
        .registry
        .lock()
        .unwrap()
        .live_for_branch(&shared.cfg.branch_id, now_ms())
        .into_iter()
        .find(|p| p.device_id == device_id)
        .map(|p| (p.host.clone(), p.port))
}

fn sync_line(shared: &Arc<RelayShared>, to: Option<String>, body: serde_json::Value) -> Option<String> {
    let env = SyncEnvelope {
        branch_id: shared.cfg.branch_id.clone(),
        from: shared.cfg.device_id.clone(),
        to,
        sent_at_ms: now_ms(),
        body,
    };
    let frame = sign_str(&shared.cfg.key, serde_json::to_string(&env).ok()?);
    serde_json::to_string(&frame).ok().map(|j| format!("SYNC {j}"))
}

/// Send the digest to one peer or to all (manual hubs included).
async fn send_digest(shared: &Arc<RelayShared>, to: Option<String>) {
    let Some(body) = shared.inbound.lan_digest() else { return };
    let Some(line) = sync_line(shared, to.clone(), body) else { return };
    let targets: Vec<(String, u16)> = match &to {
        Some(id) => address_of(shared, id).into_iter().collect(),
        None => {
            let mut t = shared.registry.lock().unwrap().relay_targets(&shared.cfg.branch_id, &shared.cfg.device_id, now_ms());
            for (h, p) in shared.manual.lock().unwrap().iter() {
                if !t.iter().any(|(th, tp)| th == h && tp == p) {
                    t.push((h.clone(), *p));
                }
            }
            t
        }
    };
    for (host, port) in targets {
        if let Some(tr) = &shared.transport {
            tr.send(&host, port, line.clone());
            continue;
        }
        let shared = shared.clone();
        let line = line.clone();
        tokio::spawn(async move { sync_exchange(&shared, &host, port, line, 0).await });
    }
}

/// One catch-up exchange over a socket: write the frame, read the peer's reply
/// frames back on the same connection, handle them, and carry the resulting
/// frames to the same peer — bounded in depth and lines.
fn sync_exchange<'a>(
    shared: &'a Arc<RelayShared>,
    host: &'a str,
    port: u16,
    line: String,
    depth: usize,
) -> std::pin::Pin<Box<dyn std::future::Future<Output = ()> + Send + 'a>> {
    Box::pin(async move {
        if depth > MAX_EXCHANGE_DEPTH {
            return;
        }
        let attempt = async {
            let mut stream = TcpStream::connect((host, port)).await.ok()?;
            stream.write_all(line.as_bytes()).await.ok()?;
            stream.write_all(b"\n").await.ok()?;
            stream.flush().await.ok()?;
            let mut replies = Vec::new();
            while replies.len() < MAX_REPLY_LINES {
                match read_line(&mut stream).await {
                    Some(l) if l != "ok" => replies.push(l),
                    Some(_) => {}
                    None => break,
                }
            }
            Some(replies)
        };
        let Ok(Some(replies)) = tokio::time::timeout(Duration::from_millis(5_000), attempt).await else { return };
        for reply in replies {
            for next in dispatch_line(shared, &reply).await {
                sync_exchange(shared, host, port, next, depth + 1).await;
            }
        }
    })
}

/// One outbound push: connect, write `line\n`, done. Bounded by a short timeout so a
/// dead peer fails fast (LAN round-trips are sub-ms).
async fn send_frame(host: &str, port: u16, line: &str) {
    let attempt = async {
        let mut stream = TcpStream::connect((host, port)).await.ok()?;
        stream.write_all(line.as_bytes()).await.ok()?;
        stream.write_all(b"\n").await.ok()?;
        stream.flush().await.ok()?;
        Some(())
    };
    let _ = tokio::time::timeout(Duration::from_millis(1_500), attempt).await;
}

/// Handle one inbound relay connection: read one `VERB payload` line and dispatch;
/// a catch-up frame's replies are written back on the same connection.
async fn handle_conn(shared: Arc<RelayShared>, mut stream: TcpStream) {
    let Some(line) = read_line(&mut stream).await else {
        shared.stats.lock().unwrap().oversized += 1;
        return;
    };
    if line.starts_with("PING") {
        let _ = stream.write_all(b"pong\n").await;
        return;
    }
    let replies = dispatch_line(&shared, &line).await;
    for r in replies {
        if stream.write_all(r.as_bytes()).await.is_err() || stream.write_all(b"\n").await.is_err() {
            return;
        }
    }
    let _ = stream.write_all(b"ok\n").await;
}

/// One inbound line, whatever carried it. Returns reply lines for the sender.
async fn dispatch_line(shared: &Arc<RelayShared>, line: &str) -> Vec<String> {
    if line.len() > MAX_FRAME {
        shared.stats.lock().unwrap().oversized += 1;
        return Vec::new();
    }
    let (verb, payload) = line.split_once(' ').unwrap_or((line, ""));
    match verb {
        "MSG" => {
            handle_msg(shared, payload).await;
            Vec::new()
        }
        "SYNC" => handle_sync(shared, payload),
        _ => {
            shared.stats.lock().unwrap().malformed += 1;
            Vec::new()
        }
    }
}

/// Verify and handle a catch-up frame; replies are addressed back to its sender.
fn handle_sync(shared: &Arc<RelayShared>, payload: &str) -> Vec<String> {
    let Ok(frame) = serde_json::from_str::<SignedFrame>(payload) else {
        shared.stats.lock().unwrap().malformed += 1;
        return Vec::new();
    };
    let Some(body) = verify_str(&shared.cfg.key, &frame) else {
        shared.stats.lock().unwrap().bad_signature += 1;
        return Vec::new();
    };
    let Ok(env) = serde_json::from_str::<SyncEnvelope>(body) else {
        shared.stats.lock().unwrap().malformed += 1;
        return Vec::new();
    };
    if env.branch_id != shared.cfg.branch_id {
        shared.stats.lock().unwrap().foreign_branch += 1;
        return Vec::new();
    }
    if env.from == shared.cfg.device_id || env.to.as_ref().is_some_and(|t| t != &shared.cfg.device_id) {
        return Vec::new();
    }
    if (now_ms() - env.sent_at_ms).abs() > SYNC_MAX_AGE_MS {
        shared.stats.lock().unwrap().stale += 1;
        return Vec::new();
    }
    {
        let mut st = shared.stats.lock().unwrap();
        st.sync_frames += 1;
    }
    let replies = shared.inbound.lan_sync(&env.body);
    let lines: Vec<String> = replies.into_iter().filter_map(|b| sync_line(shared, Some(env.from.clone()), b)).collect();
    // On an in-process network the replies travel as messages to the sender.
    if let Some(t) = &shared.transport {
        for l in &lines {
            t.send(&env.from, 0, l.clone());
        }
        return Vec::new();
    }
    lines
}

/// Verify, branch-gate, dedup, forward to the host, then gossip one hop further.
async fn handle_msg(shared: &Arc<RelayShared>, payload: &str) {
    let Ok(frame) = serde_json::from_str::<SignedFrame>(payload) else {
        shared.stats.lock().unwrap().malformed += 1;
        // Something on this LAN is speaking our protocol badly. Either a version
        // skew between devices (real bug, real lost kitchen events) or a probe.
        // The payload itself is NEVER attached — it can contain order contents.
        crate::obs::capture_bg_warning(
            "lan.frame_malformed",
            format!("undecodable relay frame ({} bytes)", payload.len()),
        );
        return;
    };
    let Some(msg) = verify_frame(&shared.cfg.key, &frame) else {
        shared.stats.lock().unwrap().bad_signature += 1;
        // HMAC mismatch: a device holding a STALE branch key (its bundle wasn't
        // refreshed — its events are being dropped branch-wide and it has no way
        // to find out), or an unprovisioned device pushing at us. Worth seeing.
        crate::obs::capture_bg_warning(
            "lan.frame_unsigned",
            "relay frame failed HMAC verification",
        );
        return;
    };
    // Branch isolation + ignore our own gossip echo.
    if msg.branch_id != shared.cfg.branch_id {
        shared.stats.lock().unwrap().foreign_branch += 1;
        return;
    }
    if msg.sender_id == shared.cfg.device_id {
        return;
    }
    if msg.hop > MAX_HOPS {
        shared.stats.lock().unwrap().hops_exhausted += 1;
        return;
    }
    let is_new = shared.seen.lock().unwrap().insert(&msg.msg_id);
    if !is_new {
        shared.stats.lock().unwrap().duplicate += 1;
        return;
    }
    shared.stats.lock().unwrap().accepted += 1;
    shared.inbound.on_lan_message(&msg);
    // Mesh gossip: re-relay one hop so it reaches peers we can't directly see.
    if let Some(relayed) = msg.relayed() {
        let frame = sign_frame(&shared.cfg.key, &relayed);
        if let Ok(json) = serde_json::to_string(&frame) {
            fanout(shared, format!("MSG {json}")).await;
        }
    }
}

/// Read a single `\n`-terminated line (frames are single-line JSON), capped.
async fn read_line(stream: &mut TcpStream) -> Option<String> {
    let mut buf = Vec::new();
    let mut chunk = [0u8; 2048];
    loop {
        let n = stream.read(&mut chunk).await.ok()?;
        if n == 0 {
            break;
        }
        if let Some(pos) = chunk[..n].iter().position(|&b| b == b'\n') {
            buf.extend_from_slice(&chunk[..pos]);
            break;
        }
        buf.extend_from_slice(&chunk[..n]);
        if buf.len() > MAX_FRAME {
            return None;
        }
    }
    if buf.is_empty() {
        return None;
    }
    String::from_utf8(buf).ok()
}

/// Bind the relay's TCP listener on `port`; if that port is taken (a second
/// local instance, another app), fall back to an OS-assigned port. The actual
/// port is read back by the caller and advertised in the beacon + mDNS TXT +
/// the native Bonjour advert, so peers never need the fixed default.
pub(crate) async fn bind_tcp_with_fallback(port: u16) -> std::io::Result<TcpListener> {
    match TcpListener::bind(("0.0.0.0", port)).await {
        Ok(l) => Ok(l),
        Err(e) if port != 0 => {
            crate::obs::capture_bg_warning(
                "lan.tcp_fallback",
                format!("tcp {port} unavailable ({e}); using an OS-assigned port"),
            );
            TcpListener::bind(("0.0.0.0", 0)).await
        }
        Err(e) => Err(e),
    }
}

/// Bind the UDP beacon socket (broadcast-enabled) with SO_REUSEADDR (+
/// SO_REUSEPORT on unix) so several instances on one machine share the beacon
/// port. Fails gracefully (Err → no beacon).
pub(crate) async fn bind_beacon(port: u16) -> std::io::Result<UdpSocket> {
    use socket2::{Domain, Protocol, Socket, Type};
    let sock = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
    sock.set_reuse_address(true)?;
    #[cfg(all(unix, not(any(target_os = "solaris", target_os = "illumos"))))]
    sock.set_reuse_port(true)?;
    sock.set_broadcast(true)?;
    sock.set_nonblocking(true)?;
    let addr: std::net::SocketAddr = ([0, 0, 0, 0], port).into();
    sock.bind(&addr.into())?;
    UdpSocket::from_std(sock.into())
}

/// Broadcast a signed beacon every [`BEACON_EVERY`] — discovery + heartbeat + the
/// open-shift advert (refreshed each tick so a closed till stops counting fast).
async fn beacon_send_loop(shared: Arc<RelayShared>, sock: Arc<UdpSocket>) {
    loop {
        let open_tills = shared.open_tills.lock().unwrap().clone();
        let beacon = Beacon {
            device_id: shared.cfg.device_id.clone(),
            branch_id: shared.cfg.branch_id.clone(),
            role: shared.cfg.role.clone(),
            station_id: shared.cfg.station_id.clone(),
            open_shift_id: open_tills.first().map(|t| t.till_id.clone()),
            device_code: shared.device_code.lock().unwrap().clone(),
            open_tills,
            tcp_port: *shared.bound_tcp_port.lock().unwrap(),
            sent_at_ms: now_ms(),
        };
        if let Ok(body) = serde_json::to_string(&beacon) {
            let frame = sign_str(&shared.cfg.key, body);
            if let Ok(json) = serde_json::to_string(&frame) {
                // A broadcast that keeps failing (a network that blocks
                // 255.255.255.255, a socket that died) means this till stops
                // advertising forever — peers TTL it out and the shift gate
                // stops seeing it. Previously `let _ =`: nobody ever knew.
                if let Err(e) = sock
                    .send_to(json.as_bytes(), ("255.255.255.255", shared.cfg.beacon_port))
                    .await
                {
                    crate::obs::capture_bg_error("lan.beacon_send", format!("udp broadcast: {e}"));
                }
            }
        }
        tokio::time::sleep(BEACON_EVERY).await;
    }
}

/// Receive beacons; verify the signature + branch, then upsert the peer using the
/// SOURCE IP (no local-IP detection needed) and the advertised TCP port.
async fn beacon_recv_loop(shared: Arc<RelayShared>, sock: Arc<UdpSocket>) {
    let mut buf = vec![0u8; 8192];
    loop {
        let (n, src) = match sock.recv_from(&mut buf).await {
            Ok(v) => v,
            Err(e) => {
                // The loop retries forever, so a permanently broken socket burns
                // CPU in silence and this device never discovers another peer again.
                crate::obs::capture_bg_error("lan.beacon_recv", format!("udp recv: {e}"));
                tokio::time::sleep(Duration::from_millis(200)).await;
                continue;
            }
        };
        let Ok(text) = std::str::from_utf8(&buf[..n]) else {
            continue;
        };
        let Ok(frame) = serde_json::from_str::<SignedFrame>(text) else {
            continue;
        };
        let Some(body) = verify_str(&shared.cfg.key, &frame) else {
            continue;
        };
        let Ok(beacon) = serde_json::from_str::<Beacon>(body) else {
            continue;
        };
        if beacon.branch_id != shared.cfg.branch_id || beacon.device_id == shared.cfg.device_id {
            continue;
        }
        let newly = upsert_peer(&shared, Peer {
            device_id: beacon.device_id.clone(),
            branch_id: beacon.branch_id,
            role: beacon.role,
            host: src.ip().to_string(),
            port: beacon.tcp_port,
            station_id: beacon.station_id,
            open_shift_id: beacon.open_shift_id,
            device_code: beacon.device_code,
            open_tills: beacon.open_tills,
            last_seen_ms: now_ms(),
        });
        if newly {
            let s = shared.clone();
            let id = beacon.device_id;
            tokio::spawn(async move { send_digest(&s, Some(id)).await });
        }
    }
}

/// What [`note_peer`] did with a record.
#[derive(Debug, PartialEq, Eq)]
enum NoteOutcome {
    /// A device not known (or expired) — the caller sends it a digest.
    Fresh(String),
    /// A live peer's heartbeat refreshed.
    Refreshed,
    /// Foreign branch, self, or an unusable record.
    Ignored,
}

/// Fold an unsigned discovery record (mDNS TXT or native Bonjour TXT) into the
/// registry — the ONE path both discovery layers share. Discovery only: the
/// shift adverts a signed beacon set are preserved, never erased.
fn note_peer(shared: &Arc<RelayShared>, note: PeerNote, source: PeerSource) -> NoteOutcome {
    note_peer_at(shared, note, source, now_ms())
}

fn note_peer_at(shared: &Arc<RelayShared>, note: PeerNote, source: PeerSource, now: i64) -> NoteOutcome {
    if note.branch_id != shared.cfg.branch_id
        || note.device_id.is_empty()
        || note.device_id == shared.cfg.device_id
        || note.host.is_empty()
        || note.port == 0
    {
        return NoteOutcome::Ignored;
    }
    if source == PeerSource::Native {
        shared.discovery.lock().unwrap().native_last_ms = now;
    }
    let mut reg = shared.registry.lock().unwrap();
    let known = reg
        .live_for_branch(&note.branch_id, now)
        .into_iter()
        .find(|p| p.device_id == note.device_id)
        .map(|p| (p.open_shift_id.clone(), p.open_tills.clone()));
    let fresh = known.is_none();
    let (open_shift_id, open_tills) = known.unwrap_or((None, Vec::new()));
    let id = note.device_id.clone();
    reg.upsert(Peer {
        device_id: note.device_id,
        branch_id: note.branch_id,
        role: note.role,
        host: note.host,
        port: note.port,
        station_id: note.station_id.filter(|s| !s.is_empty()),
        open_shift_id,
        device_code: note.device_code.filter(|s| !s.is_empty()),
        open_tills,
        last_seen_ms: now,
    });
    if fresh { NoteOutcome::Fresh(id) } else { NoteOutcome::Refreshed }
}

/// Fold an mDNS-resolved service into the registry via [`note_peer`].
#[cfg(not(target_os = "ios"))]
fn ingest_mdns(shared: &Arc<RelayShared>, info: &mdns_sd::ResolvedService) {
    let prop = |k: &str| info.get_property_val_str(k).map(|s| s.to_string());
    let Some(host) = info.get_addresses_v4().iter().next().map(|ip| ip.to_string()) else {
        return;
    };
    let port = prop("tcp_port")
        .and_then(|p| p.parse::<u16>().ok())
        .unwrap_or_else(|| info.get_port());
    let note = PeerNote {
        device_id: prop("device_id").unwrap_or_default(),
        branch_id: prop("branch_id").unwrap_or_default(),
        host,
        port,
        role: prop("role").unwrap_or_default(),
        station_id: prop("station_id"),
        device_code: prop("device_code"),
    };
    if let NoteOutcome::Fresh(id) = note_peer(shared, note, PeerSource::Mdns) {
        let s = shared.clone();
        tokio::spawn(async move { send_digest(&s, Some(id)).await });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The exact beacon body a pre-rework (v0.6) peer sends: no device_code, no
    /// open_tills.
    const OLD_BEACON: &str = r#"{"device_id":"old-dev","branch_id":"B1","role":"teller","station_id":null,
        "open_shift_id":"S-OLD","tcp_port":7431,"sent_at_ms":1}"#;

    /// The v0.6 `Beacon` struct, verbatim, so the test proves an OLD peer can read a
    /// NEW beacon (serde ignores the new fields).
    #[derive(serde::Deserialize)]
    #[allow(dead_code)]
    struct OldBeacon {
        device_id: String,
        branch_id: String,
        role: String,
        station_id: Option<String>,
        open_shift_id: Option<String>,
        tcp_port: u16,
        sent_at_ms: i64,
    }

    #[test]
    fn beacon_backward_compat_old_peer_parses_new() {
        let new = Beacon {
            device_id: "new-dev".into(),
            branch_id: "B1".into(),
            role: "teller".into(),
            station_id: None,
            open_shift_id: Some("T1".into()),
            device_code: Some("36B".into()),
            open_tills: vec![
                BeaconTill {
                    till_id: "T1".into(),
                    person_id: "U1".into(),
                    person_name: "Sara".into(),
                    opened_at: "2026-09-13T09:00:00Z".into(),
                },
                BeaconTill {
                    till_id: "T2".into(),
                    person_id: "U2".into(),
                    person_name: "Omar".into(),
                    opened_at: "2026-09-13T10:00:00Z".into(),
                },
            ],
            tcp_port: 7431,
            sent_at_ms: 5,
        };
        let json = serde_json::to_string(&new).unwrap();
        let old: OldBeacon = serde_json::from_str(&json).expect("old peer parses a new beacon");
        assert_eq!(old.open_shift_id.as_deref(), Some("T1"), "old gate still sees an open till");
    }

    #[test]
    fn beacon_new_peer_parses_old() {
        let b: Beacon = serde_json::from_str(OLD_BEACON).expect("new peer parses an old beacon");
        assert_eq!(b.open_shift_id.as_deref(), Some("S-OLD"));
        assert!(b.open_tills.is_empty());
        assert!(b.device_code.is_none());
        // An old peer's bare open shift keeps the branch "operating" but names no
        // person, so it never blocks anyone's open.
        let mut reg = PeerRegistry::new();
        reg.upsert(Peer {
            device_id: b.device_id,
            branch_id: b.branch_id,
            role: b.role,
            host: "10.0.0.2".into(),
            port: b.tcp_port,
            station_id: None,
            open_shift_id: b.open_shift_id,
            device_code: b.device_code,
            open_tills: b.open_tills,
            last_seen_ms: 1_000,
        });
        assert!(reg.branch_has_open_till("B1", 1_500));
        assert!(reg.person_open_till("B1", "U1", 1_500).is_none());
        assert!(reg.has_live_teller_peer("B1", 1_500));
    }

    #[test]
    fn person_open_till_finds_the_person_on_a_live_peer_only() {
        let mut reg = PeerRegistry::new();
        let till = BeaconTill {
            till_id: "T7".into(),
            person_id: "U1".into(),
            person_name: "Sara".into(),
            opened_at: "x".into(),
        };
        reg.upsert(Peer {
            device_id: "d2".into(),
            branch_id: "B1".into(),
            role: "teller".into(),
            host: "h".into(),
            port: 1,
            station_id: None,
            open_shift_id: Some("T7".into()),
            device_code: Some("K2".into()),
            open_tills: vec![till.clone()],
            last_seen_ms: 1_000,
        });
        let (peer, t) = reg.person_open_till("B1", "U1", 1_000).unwrap();
        assert_eq!(peer.device_code.as_deref(), Some("K2"));
        assert_eq!(t, till);
        assert!(reg.person_open_till("B1", "U2", 1_000).is_none());
        // Expired peer no longer counts.
        assert!(reg.person_open_till("B1", "U1", 1_000 + PEER_TTL_MS + 1).is_none());
        assert_eq!(reg.branch_open_tills("B1", 1_000).len(), 1);
    }

    fn msg(id: &str, branch: &str) -> LanMessage {
        LanMessage {
            msg_id: id.into(),
            branch_id: branch.into(),
            topic: "kitchen".into(),
            event_type: "kitchen.fired".into(),
            data: r#"{"id":"k1","items":[]}"#.into(),
            hop: 0,
            sender_id: "devA".into(),
            sent_at_ms: 1_700_000_000_000,
            replay_op: None,
        }
    }

    #[test]
    fn hex_roundtrips() {
        let bytes = vec![0u8, 1, 15, 16, 127, 128, 255];
        assert_eq!(from_hex(&to_hex(&bytes)).unwrap(), bytes);
        assert!(from_hex("xyz").is_none());
        assert!(from_hex("abc").is_none()); // odd length
    }

    #[test]
    fn sign_then_verify_roundtrips() {
        let key = branch_key("00ff00ff00ff00ff", "branch-1");
        let m = msg("m1", "branch-1");
        let frame = sign_frame(&key, &m);
        assert_eq!(verify_frame(&key, &frame), Some(m));
    }

    #[test]
    fn verify_rejects_tampered_body() {
        let key = branch_key("deadbeef", "branch-1");
        let mut frame = sign_frame(&key, &msg("m1", "branch-1"));
        frame.msg = frame.msg.replace("kitchen.fired", "kitchen.voided");
        assert!(
            verify_frame(&key, &frame).is_none(),
            "tampered body fails HMAC"
        );
    }

    #[test]
    fn verify_rejects_foreign_branch_key() {
        // A different branch derives a different key from the same org secret, so it
        // can neither forge a message this branch accepts nor read this one's intent.
        let key_a = branch_key("cafebabecafebabe", "branch-A");
        let key_b = branch_key("cafebabecafebabe", "branch-B");
        let frame = sign_frame(&key_a, &msg("m1", "branch-A"));
        assert!(
            verify_frame(&key_b, &frame).is_none(),
            "branch-B key rejects branch-A's frame"
        );
        assert!(
            verify_frame(&key_a, &frame).is_some(),
            "branch-A key accepts its own"
        );
    }

    #[test]
    fn branch_key_is_deterministic_and_branch_specific() {
        assert_eq!(
            branch_key("aa", "b1"),
            branch_key("aa", "b1"),
            "same inputs → same key"
        );
        assert_ne!(
            branch_key("aa", "b1"),
            branch_key("aa", "b2"),
            "branch-scoped"
        );
        assert_ne!(
            branch_key("aa", "b1"),
            branch_key("bb", "b1"),
            "secret-scoped"
        );
    }

    #[test]
    fn gossip_hop_bounds_relay() {
        let mut m = msg("m1", "b1");
        let mut relays = 0;
        while let Some(next) = m.relayed() {
            m = next;
            relays += 1;
            if relays > 100 {
                break;
            }
        }
        assert_eq!(relays, MAX_HOPS as i32, "relay stops at MAX_HOPS");
        assert!(m.hops_exhausted());
    }

    fn peer(id: &str, branch: &str, open_till: Option<&str>, last_seen_ms: i64) -> Peer {
        Peer {
            device_id: id.into(),
            branch_id: branch.into(),
            role: "kitchen".into(),
            host: format!("10.0.0.{}", id.len()),
            port: 7777,
            station_id: None,
            open_shift_id: open_till.map(|s| s.into()),
            device_code: None,
            open_tills: Vec::new(),
            last_seen_ms,
        }
    }

    #[test]
    fn registry_prunes_and_reads_by_ttl() {
        let now = 1_000_000;
        let mut reg = PeerRegistry::new();
        reg.upsert(peer("fresh", "b1", None, now - 1_000));
        reg.upsert(peer("stale", "b1", None, now - (PEER_TTL_MS + 1)));
        // Read-time TTL hides the stale peer even before prune.
        assert_eq!(reg.live_for_branch("b1", now).len(), 1);
        reg.prune(now);
        assert_eq!(reg.live_for_branch("b1", now).len(), 1, "stale evicted");
        assert!(reg
            .live_for_branch("b1", now)
            .iter()
            .any(|p| p.device_id == "fresh"));
    }

    #[test]
    fn relay_targets_exclude_self_and_other_branches() {
        let now = 1_000_000;
        let mut reg = PeerRegistry::new();
        reg.upsert(peer("self", "b1", None, now));
        reg.upsert(peer("peer", "b1", None, now));
        reg.upsert(peer("other", "b2", None, now));
        let targets = reg.relay_targets("b1", "self", now);
        assert_eq!(targets.len(), 1, "only the same-branch non-self peer");
    }

    #[test]
    fn shift_gate_tracks_fresh_open_tills_only() {
        let now = 1_000_000;
        let mut reg = PeerRegistry::new();
        assert!(!reg.branch_has_open_till("b1", now), "no peers → closed");
        // A KDS (no shift) doesn't make the branch "operating".
        reg.upsert(peer("kds", "b1", None, now));
        assert!(!reg.branch_has_open_till("b1", now));
        // A till advertising an open shift does.
        reg.upsert(peer("till", "b1", Some("shift-1"), now));
        assert!(reg.branch_has_open_till("b1", now));
        // …until its advert goes stale (the till closed and stopped advertising).
        reg.upsert(peer("till", "b1", Some("shift-1"), now - (PEER_TTL_MS + 1)));
        assert!(
            !reg.branch_has_open_till("b1", now),
            "stale open-till advert no longer counts"
        );
    }

    // ── Live relay (loopback) ────────────────────────────────────────────────

    struct Recorder(Mutex<Vec<LanMessage>>);
    impl LanInbound for Recorder {
        fn on_lan_message(&self, msg: &LanMessage) {
            self.0.lock().unwrap().push(msg.clone());
        }
    }
    fn rec() -> Arc<Recorder> {
        Arc::new(Recorder(Mutex::new(Vec::new())))
    }
    fn lan_cfg(id: &str, key: Vec<u8>) -> LanConfig {
        // beacon_port 0 → OS-assigned, so two relays in one test never collide; the
        // tests drive delivery via manual peer injection, not the beacon.
        LanConfig {
            device_id: id.into(),
            branch_id: "b1".into(),
            role: "kitchen".into(),
            station_id: None,
            key,
            tcp_port: 0,
            beacon_port: 0,
        }
    }
    fn loopback_peer(id: &str, port: u16) -> Peer {
        Peer {
            device_id: id.into(),
            branch_id: "b1".into(),
            role: "kitchen".into(),
            host: "127.0.0.1".into(),
            port,
            station_id: None,
            open_shift_id: None,
            device_code: None,
            open_tills: Vec::new(),
            last_seen_ms: now_ms(),
        }
    }
    async fn wait_until<F: Fn() -> bool>(f: F) {
        for _ in 0..100 {
            if f() {
                return;
            }
            tokio::time::sleep(Duration::from_millis(15)).await;
        }
    }

    #[tokio::test]
    async fn relay_delivers_signed_message_to_a_peer() {
        let key = branch_key("aabbccdd", "b1");
        let rec_b = rec();
        let a = LanRelay::new(lan_cfg("A", key.clone()), rec());
        let b = LanRelay::new(lan_cfg("B", key.clone()), rec_b.clone());
        a.start().await.unwrap();
        b.start().await.unwrap();
        a.add_peer(loopback_peer("B", b.tcp_port()));

        a.publish(
            "kitchen",
            "kitchen.fired",
            r#"{"id":"k1"}"#.into(),
            None,
            now_ms(),
        )
        .await;
        wait_until(|| !rec_b.0.lock().unwrap().is_empty()).await;

        let got = rec_b.0.lock().unwrap();
        assert_eq!(got.len(), 1, "B received exactly one message");
        assert_eq!(got[0].event_type, "kitchen.fired");
        assert_eq!(got[0].sender_id, "A");
        assert_eq!(got[0].data, r#"{"id":"k1"}"#);
    }

    #[tokio::test]
    async fn relay_rejects_foreign_branch_key_on_the_wire() {
        // B holds a different secret → a different branch key → it must drop A's frame.
        let rec_b = rec();
        let a = LanRelay::new(lan_cfg("A", branch_key("1111", "b1")), rec());
        let b = LanRelay::new(lan_cfg("B", branch_key("2222", "b1")), rec_b.clone());
        a.start().await.unwrap();
        b.start().await.unwrap();
        a.add_peer(loopback_peer("B", b.tcp_port()));

        a.publish("kitchen", "kitchen.fired", "{}".into(), None, now_ms())
            .await;
        tokio::time::sleep(Duration::from_millis(150)).await;
        assert!(
            rec_b.0.lock().unwrap().is_empty(),
            "foreign-key frame is rejected, not delivered"
        );
    }

    /// Two tills that both heard a cloud event re-publish it under the SAME
    /// deterministic id; the LAN-only peer hears it once.
    #[tokio::test]
    async fn cloud_rebroadcast_with_one_id_reaches_a_peer_once() {
        let key = branch_key("aabbccdd", "b1");
        let rec_b = rec();
        let a = LanRelay::new(lan_cfg("A", key.clone()), rec());
        let c = LanRelay::new(lan_cfg("C", key.clone()), rec());
        let b = LanRelay::new(lan_cfg("B", key.clone()), rec_b.clone());
        a.start().await.unwrap();
        b.start().await.unwrap();
        c.start().await.unwrap();
        a.add_peer(loopback_peer("B", b.tcp_port()));
        c.add_peer(loopback_peer("B", b.tcp_port()));
        for relay in [&a, &c] {
            relay
                .publish_with_id(
                    "cloud:b1:42".into(),
                    "bookings",
                    "booking.created",
                    r#"{"id":"bk1"}"#.into(),
                    None,
                    now_ms(),
                )
                .await;
        }
        wait_until(|| !rec_b.0.lock().unwrap().is_empty()).await;
        tokio::time::sleep(Duration::from_millis(150)).await;
        let got = rec_b.0.lock().unwrap();
        assert_eq!(got.len(), 1, "B heard the cloud event exactly once");
        assert_eq!(got[0].msg_id, "cloud:b1:42");
        assert_eq!(got[0].event_type, "booking.created");
        assert!(
            got[0].replay_op.is_none(),
            "display-only: the write lives in the cloud"
        );
    }

    fn note(id: &str, branch: &str) -> PeerNote {
        PeerNote {
            device_id: id.into(),
            branch_id: branch.into(),
            host: "10.0.0.9".into(),
            port: 47600,
            role: "waiter".into(),
            station_id: Some(String::new()),
            device_code: Some("12A".into()),
        }
    }

    #[test]
    fn note_peer_filters_branch_and_self() {
        let relay = LanRelay::new(lan_cfg("SELF", branch_key("aa", "b1")), rec());
        let sh = &relay.shared;
        let now = now_ms();
        assert_eq!(note_peer_at(sh, note("X", "b2"), PeerSource::Native, now), NoteOutcome::Ignored);
        assert_eq!(note_peer_at(sh, note("SELF", "b1"), PeerSource::Native, now), NoteOutcome::Ignored);
        assert_eq!(note_peer_at(sh, note("", "b1"), PeerSource::Native, now), NoteOutcome::Ignored);
        let mut bad_port = note("P", "b1");
        bad_port.port = 0;
        assert_eq!(note_peer_at(sh, bad_port, PeerSource::Native, now), NoteOutcome::Ignored);
        assert_eq!(relay.peer_count(), 0);
        assert_eq!(relay.discovery().native_last_ms, 0, "an ignored record doesn't count as native discovery");
        assert_eq!(note_peer_at(sh, note("P", "b1"), PeerSource::Native, now), NoteOutcome::Fresh("P".into()));
        assert_eq!(relay.peer_count(), 1);
        let reg = sh.registry.lock().unwrap();
        let p = reg.live_for_branch("b1", now)[0].clone();
        assert_eq!(p.station_id, None, "empty TXT becomes None");
        assert_eq!(p.device_code.as_deref(), Some("12A"));
        assert_eq!(relay.discovery().native_last_ms, now);
    }

    #[test]
    fn note_peer_refreshes_ttl_and_keeps_signed_adverts() {
        let relay = LanRelay::new(lan_cfg("SELF", branch_key("aa", "b1")), rec());
        let sh = &relay.shared;
        let t0 = 1_000_000;
        // A signed beacon told us P holds an open till.
        let mut from_beacon = peer("P", "b1", Some("T1"), t0);
        from_beacon.role = "teller".into();
        sh.registry.lock().unwrap().upsert(from_beacon);
        // Re-noted just before expiry: refreshed, advert kept.
        let t1 = t0 + PEER_TTL_MS - 1;
        assert_eq!(note_peer_at(sh, note("P", "b1"), PeerSource::Mdns, t1), NoteOutcome::Refreshed);
        let t2 = t1 + PEER_TTL_MS - 1;
        {
            let reg = sh.registry.lock().unwrap();
            let live = reg.live_for_branch("b1", t2);
            assert_eq!(live.len(), 1, "a re-noted peer outlives the original TTL");
            assert_eq!(live[0].open_shift_id.as_deref(), Some("T1"), "unsigned TXT never erases the beacon advert");
        }
        assert_eq!(relay.discovery().native_last_ms, 0, "mDNS is not the native path");
        // Not re-noted: it expires, and the next note is fresh again.
        let t3 = t1 + PEER_TTL_MS + 1;
        assert!(sh.registry.lock().unwrap().live_for_branch("b1", t3).is_empty());
        assert_eq!(note_peer_at(sh, note("P", "b1"), PeerSource::Native, t3), NoteOutcome::Fresh("P".into()));
    }

    /// A busy fixed port no longer kills the relay: two relays configured for
    /// the SAME taken port both start, on distinct OS-assigned ports.
    #[tokio::test]
    async fn two_relays_on_a_busy_port_both_bind() {
        let squatter = std::net::TcpListener::bind(("0.0.0.0", 0)).unwrap();
        let busy = squatter.local_addr().unwrap().port();
        let key = branch_key("aabbccdd", "b1");
        let mut ca = lan_cfg("A", key.clone());
        ca.tcp_port = busy;
        let mut cb = lan_cfg("B", key.clone());
        cb.tcp_port = busy;
        let rec_b = rec();
        let a = LanRelay::new(ca, rec());
        let b = LanRelay::new(cb, rec_b.clone());
        a.start().await.expect("A binds despite the busy port");
        b.start().await.expect("B binds despite the busy port");
        assert_ne!(a.tcp_port(), busy);
        assert_ne!(b.tcp_port(), busy);
        assert_ne!(a.tcp_port(), b.tcp_port());
        // And the advertised port really works.
        a.add_peer(loopback_peer("B", b.tcp_port()));
        a.publish("kitchen", "kitchen.fired", "{}".into(), None, now_ms()).await;
        wait_until(|| !rec_b.0.lock().unwrap().is_empty()).await;
        assert_eq!(rec_b.0.lock().unwrap().len(), 1);
        drop(squatter);
    }

    /// Two instances share one beacon port (SO_REUSEADDR/SO_REUSEPORT).
    #[tokio::test]
    async fn beacon_port_is_shareable() {
        let first = bind_beacon(0).await.unwrap();
        let port = first.local_addr().unwrap().port();
        let second = bind_beacon(port).await;
        assert!(second.is_ok(), "second bind on the beacon port: {second:?}");
    }

    #[tokio::test]
    async fn relay_dedups_a_repeated_msg_id() {
        let key = branch_key("aabbccdd", "b1");
        let rec_b = rec();
        let b = LanRelay::new(lan_cfg("B", key.clone()), rec_b.clone());
        b.start().await.unwrap();
        let m = LanMessage {
            msg_id: "dup-1".into(),
            branch_id: "b1".into(),
            topic: "kitchen".into(),
            event_type: "kitchen.fired".into(),
            data: "{}".into(),
            hop: 0,
            sender_id: "A".into(),
            sent_at_ms: now_ms(),
            replay_op: None,
        };
        let line = format!(
            "MSG {}",
            serde_json::to_string(&sign_frame(&key, &m)).unwrap()
        );
        send_frame("127.0.0.1", b.tcp_port(), &line).await;
        send_frame("127.0.0.1", b.tcp_port(), &line).await;
        tokio::time::sleep(Duration::from_millis(150)).await;
        assert_eq!(
            rec_b.0.lock().unwrap().len(),
            1,
            "the second identical msg_id is deduped"
        );
    }
}
