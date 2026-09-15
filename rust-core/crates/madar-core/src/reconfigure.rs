//! Device reconfigure: moving a device to another branch or org is a COMPLETE
//! FRESH INSTALL, and it is only allowed once nothing on the device can be lost.
//!
//! **The gate** ([`MadarCore::reconfigure_readiness`], local only — no network):
//! - the outbox holds no pending, inflight or dead row, `lan_mirror` peer backups
//!   included (a dead row is retried to success or discarded first);
//! - a "Push now" ([`MadarCore::reconfigure_push_now`]) in the last
//!   [`CHECK_FRESH_MS`] reached the server, drained, and ran a final `/sync/pull`
//!   (skipped only when nobody is signed in, since the pull needs a session);
//! - no till is open on this device.
//!
//! **The wipe** ([`MadarCore::start_reconfigure`], refused unless allowed):
//! every table of the store in one transaction, the image / step-animation /
//! asset directories, the session and token, permissions, the offline-auth bundle
//! (PIN hashes + LAN secret), the device binding and device code, and the LAN
//! device id (a new one is minted). The realtime stream and the LAN relay stop;
//! peers are not told — their TTL expires the old id. In-memory state (catalog
//! cache, sync state, fills, alerts, diagnostics) is reset.
//!
//! **Kept:** the printer settings (LAN host/port/brand, transport, the paired
//! Bluetooth printer, paper width). They describe the physical device and its
//! attached hardware, not the branch, and re-pairing a printer after a move is
//! pure friction.
//!
//! **Crash safety:** the wipe first writes a marker file beside the database
//! (carrying the kept printer settings). Boot finds a marker and finishes the
//! wipe before anything reads the store. The store half is one transaction, the
//! file half idempotent, so an interrupted wipe never leaves a half state.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::device::{self, DeviceConfig};
use crate::error::{CoreError, CoreResult};
use crate::store::Store;
use crate::MadarCore;

/// How long a successful "Push now" confirms the device is caught up.
pub(crate) const CHECK_FRESH_MS: i64 = 5 * 60 * 1000;

/// The outcome of the last "Push now".
#[derive(Clone, Copy, Debug)]
pub(crate) struct PushCheck {
    /// `/health` answered.
    pub online: bool,
    /// The final pull succeeded (or there was no session to pull with).
    pub pulled: bool,
    pub at_ms: i64,
}

/// One reason reconfigure is blocked.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq)]
pub struct ReconfigureBlockerView {
    /// `pending` | `inflight` | `dead` | `lan_mirror` | `till_open` | `offline`
    /// | `unconfirmed`.
    pub kind: String,
    /// Rows behind this blocker (1 for a till / offline / unconfirmed).
    pub count: u32,
    /// The localized sentence to show ("3 sales still uploading").
    pub label: String,
    /// The open till (`till_open` only).
    pub till_id: Option<String>,
    /// Who holds that till (`till_open` only).
    pub owner_name: Option<String>,
}

/// Whether the device may be reconfigured, and what stands in the way.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq)]
pub struct ReconfigureReadinessView {
    pub allowed: bool,
    pub blockers: Vec<ReconfigureBlockerView>,
    /// Unsent rows of every kind (the live count beside "Push now").
    pub outbox_total: u32,
}

/// The marker file an unfinished wipe leaves beside the database.
fn marker_path(db_path: &str) -> Option<PathBuf> {
    (!db_path.is_empty()).then(|| PathBuf::from(format!("{db_path}.reconfigure-wipe")))
}

/// What a wipe keeps, carried in the marker so a resumed wipe keeps it too.
#[derive(Serialize, Deserialize, Default)]
struct Kept {
    printer: DeviceConfig,
}

/// Only the printer half of a device config.
fn printer_only(c: &DeviceConfig) -> DeviceConfig {
    DeviceConfig {
        printer_host: c.printer_host.clone(),
        printer_port: c.printer_port,
        printer_brand: c.printer_brand.clone(),
        printer_transport: c.printer_transport.clone(),
        printer_bt_address: c.printer_bt_address.clone(),
        printer_bt_name: c.printer_bt_name.clone(),
        printer_paper_dots: c.printer_paper_dots,
        ..DeviceConfig::default()
    }
}

/// The on-disk caches a fresh install does not have.
fn cache_dirs(db_path: &str) -> Vec<PathBuf> {
    let Some(dir) = Path::new(db_path).parent().filter(|_| !db_path.is_empty()) else {
        return Vec::new();
    };
    ["images", "animations", "assets"].iter().map(|k| dir.join(k)).collect()
}

fn remove_dir(p: &Path) -> CoreResult<()> {
    match std::fs::remove_dir_all(p) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(CoreError::Internal { detail: format!("wipe {}: {e}", p.display()) }),
    }
}

/// The persistent half of the wipe: the store (one transaction) then the cache
/// directories, then the marker goes. Idempotent — boot re-runs it from the marker.
/// Returns the new LAN device id.
fn wipe_persistent(store: &Store, db_path: &str, kept: &Kept, extra_dirs: &[PathBuf]) -> CoreResult<String> {
    let device_id = uuid::Uuid::new_v4().to_string();
    let cfg = serde_json::to_string(&kept.printer)
        .map_err(|e| CoreError::Internal { detail: format!("device cfg: {e}") })?;
    store.wipe_all(&[("device_config", &cfg), ("lan_device_id", &device_id)])?;
    for d in cache_dirs(db_path).iter().chain(extra_dirs) {
        remove_dir(d)?;
    }
    if let Some(m) = marker_path(db_path) {
        let _ = std::fs::remove_file(m);
    }
    Ok(device_id)
}

/// Boot: finish a wipe a crash interrupted. `true` when one was finished.
pub(crate) fn resume_interrupted_wipe(store: &Store, db_path: &str) -> bool {
    let Some(marker) = marker_path(db_path) else { return false };
    let Ok(raw) = std::fs::read_to_string(&marker) else { return false };
    // A torn marker still means "a wipe was starting": finish it, keeping only
    // what the store still says about the printer.
    let kept = serde_json::from_str::<Kept>(&raw)
        .unwrap_or_else(|_| Kept { printer: printer_only(&device::load(store)) });
    wipe_persistent(store, db_path, &kept, &[]).is_ok()
}

/// The localized noun group an outbox op belongs to.
fn noun_of(op_type: &str) -> &'static str {
    match op_type {
        "create_order" | "settle_open_ticket" => "sale",
        "refund_order" => "refund",
        "void_order" | "void_ticket" | "void_ticket_line" => "void",
        "cash_movement" => "cash",
        "open_till" | "close_till" | "open_shift" | "close_shift" => "till",
        _ => "change",
    }
}

/// `{n}` / `{name}` substitution into a localized template.
fn fill(locale: &str, key: &str, n: u32, name: &str) -> String {
    crate::i18n::tr(locale, key).replace("{n}", &n.to_string()).replace("{name}", name)
}

/// The gate itself, over plain inputs: unsent rows `(op_type, status, count)`,
/// the open tills `(id, owner)`, the last push check and the clock.
pub(crate) fn readiness(
    locale: &str,
    rows: &[(String, String, u32)],
    open_tills: &[(String, String)],
    check: Option<PushCheck>,
    now_ms: i64,
) -> ReconfigureReadinessView {
    use std::collections::BTreeMap;
    let mut blockers = Vec::new();
    let mut groups: BTreeMap<(u8, &str, &'static str), u32> = BTreeMap::new();
    let mut outbox_total = 0;
    for (op, status, n) in rows {
        outbox_total += n;
        let (order, kind) = match status.as_str() {
            _ if op == "lan_mirror" => (3, "lan_mirror"),
            "dead" => (0, "dead"),
            "inflight" => (2, "inflight"),
            _ => (1, "pending"),
        };
        let noun = if kind == "lan_mirror" { "backup" } else { noun_of(op) };
        *groups.entry((order, kind, noun)).or_default() += n;
    }
    for ((_, kind, noun), n) in groups {
        let number = if n == 1 { "one" } else { "many" };
        let key = format!("reconfigure.block.{kind}.{noun}.{number}");
        blockers.push(ReconfigureBlockerView {
            kind: kind.into(),
            count: n,
            label: fill(locale, &key, n, ""),
            till_id: None,
            owner_name: None,
        });
    }
    for (id, owner) in open_tills {
        let (key, name) = if owner.trim().is_empty() {
            ("reconfigure.block.till_open_unnamed", "")
        } else {
            ("reconfigure.block.till_open", owner.as_str())
        };
        blockers.push(ReconfigureBlockerView {
            kind: "till_open".into(),
            count: 1,
            label: fill(locale, key, 1, name),
            till_id: Some(id.clone()),
            owner_name: Some(owner.clone()).filter(|o| !o.trim().is_empty()),
        });
    }
    let fresh = check.filter(|c| now_ms - c.at_ms <= CHECK_FRESH_MS);
    let gate = match fresh {
        Some(c) if !c.online => Some("offline"),
        Some(c) if c.pulled => None,
        _ => Some("unconfirmed"),
    };
    if let Some(kind) = gate {
        blockers.push(ReconfigureBlockerView {
            kind: kind.into(),
            count: 1,
            label: crate::i18n::tr(locale, &format!("reconfigure.block.{kind}")),
            till_id: None,
            owner_name: None,
        });
    }
    ReconfigureReadinessView { allowed: blockers.is_empty(), blockers, outbox_total }
}

impl MadarCore {
    fn unsent_rows(&self) -> CoreResult<Vec<(String, String, u32)>> {
        self.store.with_conn(|c| {
            let rows = c
                .prepare(
                    "SELECT op_type, status, COUNT(*) FROM outbox
                     WHERE status IN ('pending','inflight','dead') GROUP BY op_type, status",
                )?
                .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get::<_, i64>(2)? as u32)))?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
    }

    /// Every till open on this device, with its holder.
    fn open_tills_here(&self) -> Vec<(String, String)> {
        let mut out: Vec<(String, String)> = self
            .store
            .kv_list_prefix(crate::till::DEVICE_TILL_PREFIX)
            .unwrap_or_default()
            .into_iter()
            .filter_map(|(_, till_id)| crate::till::record(&self.store, &till_id))
            .filter(|t| t.status == "open")
            .map(|t| (t.id, t.teller_name))
            .collect();
        out.sort();
        out.dedup_by(|a, b| a.0 == b.0);
        out
    }

    pub(crate) fn set_reconfigure_check(&self, check: Option<PushCheck>) {
        *self.reconfigure_check.lock().unwrap_or_else(|e| e.into_inner()) = check;
    }

    fn readiness_now(&self) -> CoreResult<ReconfigureReadinessView> {
        let check = *self.reconfigure_check.lock().unwrap_or_else(|e| e.into_inner());
        let locale = self.locale.read().unwrap_or_else(|e| e.into_inner()).clone();
        Ok(readiness(
            &locale,
            &self.unsent_rows()?,
            &self.open_tills_here(),
            check,
            chrono::Utc::now().timestamp_millis(),
        ))
    }
}

#[cfg_attr(feature = "uniffi-ffi", uniffi::export)]
impl MadarCore {
    /// Whether this device may be reconfigured right now, and every reason it
    /// may not, with live counts. Local only: safe to call on a tick.
    pub fn reconfigure_readiness(&self) -> ReconfigureReadinessView {
        self.readiness_now().unwrap_or_else(|e| ReconfigureReadinessView {
            allowed: false,
            blockers: vec![ReconfigureBlockerView {
                kind: "unconfirmed".into(),
                count: 1,
                label: e.to_string(),
                till_id: None,
                owner_name: None,
            }],
            outbox_total: 0,
        })
    }

    /// Reconfigure: the gated fresh install. Refused (`Validation`, field
    /// `reconfigure`) unless [`Self::reconfigure_readiness`] allows it. On
    /// success the device is exactly a first launch (route `DeviceSetup`) with
    /// only its printer settings kept.
    pub fn start_reconfigure(&self) -> Result<(), CoreError> {
        let ready = self.readiness_now()?;
        if !ready.allowed {
            let detail = ready.blockers.iter().map(|b| b.label.as_str()).collect::<Vec<_>>().join("; ");
            return Err(CoreError::Validation { field: "reconfigure".into(), detail });
        }
        self.wipe_device()
    }
}

#[cfg_attr(feature = "uniffi-ffi", uniffi::export(async_runtime = "tokio"))]
impl MadarCore {
    /// "Push now": confirm connectivity, drain the outbox, run the final
    /// `/sync/pull`, drain the acks it folded in, and record the outcome the gate
    /// reads. Returns the readiness after it.
    pub async fn reconfigure_push_now(&self) -> ReconfigureReadinessView {
        let online = self.api.ping().await.is_ok();
        let mut pulled = false;
        if online {
            self.set_online(true);
            let _ = self.store.clear_network_backoff();
            let _ = self.drain_outbox().await;
            pulled = match self.current_session().and_then(|s| s.branch_id) {
                Some(_) => self.pull(false).await.is_ok(),
                None => true,
            };
            let _ = self.drain_outbox().await;
        }
        self.set_reconfigure_check(Some(PushCheck {
            online,
            pulled,
            at_ms: chrono::Utc::now().timestamp_millis(),
        }));
        self.reconfigure_readiness()
    }
}

impl MadarCore {
    /// The wipe itself (no gate — `start_reconfigure` is the only caller).
    pub(crate) fn wipe_device(&self) -> CoreResult<()> {
        let kept = Kept { printer: printer_only(&device::load(&self.store)) };
        let db_path = self.config.db_path.clone();
        if let Some(m) = marker_path(&db_path) {
            let json = serde_json::to_string(&kept)
                .map_err(|e| CoreError::Internal { detail: format!("marker: {e}") })?;
            std::fs::write(&m, json).map_err(|e| CoreError::Internal { detail: format!("marker: {e}") })?;
        }
        // Stop everything that could write while the store empties.
        self.unsubscribe_realtime();
        *self.unified_listener.lock().unwrap_or_else(|e| e.into_inner()) = None;
        self.lan_stop();
        self.api.set_bearer(None);
        *self.session.write().unwrap_or_else(|e| e.into_inner()) = None;
        // The in-memory store's asset dir is keyed by the OLD device id.
        let extra = if db_path.is_empty() { vec![self.assets_dir()] } else { Vec::new() };
        let device_id = wipe_persistent(&self.store, &db_path, &kept, &extra)?;
        let _ = self.api.set_device_id(&device_id);
        self.reset_memory();
        Ok(())
    }

    fn reset_memory(&self) {
        use std::sync::atomic::Ordering::Relaxed;
        self.invalidate_catalog_cache();
        *self.sync_state.lock().unwrap_or_else(|e| e.into_inner()) = Default::default();
        self.branch_fills.reset();
        self.auth_paused.store(false, Relaxed);
        self.borrowed_token.store(false, Relaxed);
        self.offline_probe_fails.store(0, Relaxed);
        self.realtime_connected.store(false, Relaxed);
        self.diag.lock().unwrap_or_else(|e| e.into_inner()).clear();
        *self.alert_memory.lock().unwrap_or_else(|e| e.into_inner()) = crate::realtime::AlertDedup::new();
        *self.lan_last_error.lock().unwrap_or_else(|e| e.into_inner()) = None;
        *self.active_scope.write().unwrap_or_else(|e| e.into_inner()) = None;
        self.set_reconfigure_check(None);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::MadarConfig;
    use crate::store::NewOutboxOp;
    use std::sync::Arc;

    fn core_at(db: &str) -> Arc<MadarCore> {
        MadarCore::new(MadarConfig {
            base_url: "http://127.0.0.1:1".into(),
            environment: "dev".into(),
            db_path: db.into(),
            locale: "en".into(),
            app_version: None,
        })
        .unwrap()
    }

    fn temp_db() -> (PathBuf, String) {
        let dir = std::env::temp_dir().join(format!("madar-reconf-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let db = dir.join("madar.db").to_string_lossy().into_owned();
        (dir, db)
    }

    fn confirmed() -> Option<PushCheck> {
        Some(PushCheck { online: true, pulled: true, at_ms: chrono::Utc::now().timestamp_millis() })
    }

    fn enqueue(core: &MadarCore, op: &str) -> i64 {
        core.store
            .enqueue(&NewOutboxOp {
                id: uuid::Uuid::new_v4().to_string(),
                op_type: op.into(),
                idempotency_key: uuid::Uuid::new_v4().to_string(),
                payload: "{}".into(),
                event_at: "2026-01-01T00:00:00Z".into(),
                ..Default::default()
            })
            .unwrap()
    }

    fn kinds(v: &ReconfigureReadinessView) -> Vec<&str> {
        v.blockers.iter().map(|b| b.kind.as_str()).collect()
    }

    fn open_till(core: &MadarCore, teller: &str, name: &str) {
        let rec = serde_json::json!({
            "id": "00000000-0000-0000-0000-00000000c001", "teller_id": teller,
            "teller_name": name, "status": "open", "opened_at": "2026-01-01T00:00:00Z"
        });
        let rec: crate::till::TillRecord = serde_json::from_value(rec).unwrap();
        crate::till::save(&core.store, &rec).unwrap();
    }

    #[test]
    fn pure_gate_blocks_on_each_condition() {
        let now = 10_000_000;
        let ok = Some(PushCheck { online: true, pulled: true, at_ms: now });
        let row = |op: &str, st: &str, n| vec![(op.to_string(), st.to_string(), n)];
        assert!(readiness("en", &[], &[], ok, now).allowed);
        for (rows, kind) in [
            (row("create_order", "pending", 3), "pending"),
            (row("create_order", "inflight", 1), "inflight"),
            (row("refund_order", "dead", 1), "dead"),
            (row("lan_mirror", "pending", 2), "lan_mirror"),
            (row("lan_mirror", "dead", 1), "lan_mirror"),
        ] {
            let v = readiness("en", &rows, &[], ok, now);
            assert!(!v.allowed);
            assert_eq!(kinds(&v), vec![kind]);
        }
        let v = readiness("en", &row("create_order", "pending", 3), &[], ok, now);
        assert_eq!(v.blockers[0].label, "3 sales still uploading");
        let v = readiness("en", &row("refund_order", "dead", 1), &[], ok, now);
        assert_eq!(v.blockers[0].label, "1 failed refund — retry or discard");
        let v = readiness("en", &[], &[("t1".into(), "Sara".into())], ok, now);
        assert_eq!(kinds(&v), vec!["till_open"]);
        assert_eq!(v.blockers[0].label, "Close Sara's till first");
        assert_eq!(v.blockers[0].owner_name.as_deref(), Some("Sara"));
        let off = Some(PushCheck { online: false, pulled: false, at_ms: now });
        assert_eq!(kinds(&readiness("en", &[], &[], off, now)), vec!["offline"]);
        assert_eq!(kinds(&readiness("en", &[], &[], None, now)), vec!["unconfirmed"]);
        let stale = Some(PushCheck { online: true, pulled: true, at_ms: now - CHECK_FRESH_MS - 1 });
        assert_eq!(kinds(&readiness("en", &[], &[], stale, now)), vec!["unconfirmed"]);
        let no_pull = Some(PushCheck { online: true, pulled: false, at_ms: now });
        assert_eq!(kinds(&readiness("en", &[], &[], no_pull, now)), vec!["unconfirmed"]);
        let ar = readiness("ar", &row("create_order", "pending", 3), &[], ok, now);
        assert!(!ar.blockers[0].label.contains("sales"), "arabic label");
    }

    #[test]
    fn core_readiness_reads_outbox_and_tills() {
        let core = core_at("");
        core.set_reconfigure_check(confirmed());
        assert!(core.reconfigure_readiness().allowed);
        let seq = enqueue(&core, "create_order");
        assert_eq!(kinds(&core.reconfigure_readiness()), vec!["pending"]);
        core.store.mark_inflight(seq).unwrap();
        assert_eq!(kinds(&core.reconfigure_readiness()), vec!["inflight"]);
        core.store.mark_dead(seq, "boom").unwrap();
        assert_eq!(kinds(&core.reconfigure_readiness()), vec!["dead"]);
        core.store.mark_acked(seq, None).unwrap();
        assert!(core.reconfigure_readiness().allowed, "acked rows do not block");
        let m = enqueue(&core, "lan_mirror");
        assert_eq!(kinds(&core.reconfigure_readiness()), vec!["lan_mirror"]);
        core.store.mark_acked(m, None).unwrap();
        open_till(&core, "00000000-0000-0000-0000-0000000000bb", "Sara");
        let v = core.reconfigure_readiness();
        assert_eq!(kinds(&v), vec!["till_open"]);
        assert_eq!(v.blockers[0].label, "Close Sara's till first");
    }

    #[tokio::test]
    async fn push_now_offline_blocks() {
        let core = core_at("");
        let v = core.reconfigure_push_now().await;
        assert!(!v.allowed);
        assert_eq!(kinds(&v), vec!["offline"]);
    }

    #[test]
    fn wipe_refuses_when_not_allowed() {
        let core = core_at("");
        enqueue(&core, "create_order");
        assert!(core.start_reconfigure().is_err(), "unconfirmed + pending");
        core.set_reconfigure_check(confirmed());
        let err = core.start_reconfigure().unwrap_err();
        assert!(matches!(err, CoreError::Validation { ref field, .. } if field == "reconfigure"));
        assert_eq!(core.store.pending_count().unwrap(), 1, "nothing wiped");
    }

    fn populate(core: &MadarCore, dir: &Path) {
        core.persist_and_set(crate::session::SessionState {
            snapshot: crate::session::SessionSnapshot {
                user_id: "00000000-0000-0000-0000-0000000000bb".into(),
                display_name: "Sara".into(),
                role: "teller".into(),
                org_id: Some("00000000-0000-0000-0000-0000000000aa".into()),
                branch_id: Some("00000000-0000-0000-0000-000000000001".into()),
                currency_code: "EGP".into(),
                tax_rate: 0.14,
                tax_inclusive: false,
                service_charge_rate: 0.0,
                service_charge_taxable: true,
                require_table_for_orders: false,
                online: false,
                permissions_loaded: true,
            },
            permissions: Vec::new(),
            token: None,
            authz: None,
        });
        core.set_device_branch("00000000-0000-0000-0000-000000000001".into(), Some("Downtown".into())).unwrap();
        core.set_device_printer(Some("10.0.0.9".into()), Some(9100), Some("star".into())).unwrap();
        core.set_device_printer_paper(Some(384)).unwrap();
        core.set_device_lan_hub(Some("10.0.0.2".into())).unwrap();
        core.store.kv_put(crate::session::BUNDLE_KEY, r#"{"lan_secret":"00"}"#).unwrap();
        core.store.kv_put("catalog:menu", "[]").unwrap();
        core.store.blob_put("logo", b"png").unwrap();
        core.store.cursor_set("orders", 7).unwrap();
        let seq = enqueue(core, "create_order");
        core.store.mark_acked(seq, Some("srv")).unwrap();
        core.store.with_conn(|c| {
            c.execute("INSERT INTO sync_rows (type,id,branch_id,seq,data) VALUES ('menu','m1','b',1,'{}')", [])?;
            Ok(())
        }).unwrap();
        for d in ["images", "animations", "assets"] {
            std::fs::create_dir_all(dir.join(d)).unwrap();
            std::fs::write(dir.join(d).join("f.bin"), b"x").unwrap();
        }
    }

    fn assert_fresh(core: &MadarCore, dir: &Path, old_id: &str) {
        let non_empty: Vec<String> = core
            .store
            .with_conn(|c| {
                let names: Vec<String> = c
                    .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")?
                    .query_map([], |r| r.get(0))?
                    .collect::<Result<_, _>>()?;
                let mut out = Vec::new();
                for n in names {
                    let q = if n == "kv" {
                        "SELECT COUNT(*) FROM kv WHERE k NOT IN ('device_config','lan_device_id') AND k NOT LIKE 'migr:%' AND k NOT LIKE 'store:%'".to_string()
                    } else {
                        format!("SELECT COUNT(*) FROM \"{n}\"")
                    };
                    let cnt: i64 = c.query_row(&q, [], |r| r.get(0))?;
                    if cnt > 0 {
                        out.push(n);
                    }
                }
                Ok(out)
            })
            .unwrap();
        // The integrity check may have queued its own kv stamp after boot.
        assert!(non_empty.iter().all(|n| n == "sentry_outbox"), "rows left in {non_empty:?}");
        for d in ["images", "animations", "assets"] {
            assert!(!dir.join(d).exists() || std::fs::read_dir(dir.join(d)).unwrap().next().is_none(), "{d} not empty");
        }
        assert!(core.current_session().is_none());
        assert!(core.store.kv_get(crate::session::BUNDLE_KEY).unwrap().is_none());
        assert!(core.store.blob_get(crate::session::K_SESSION_BLOB).unwrap().is_none());
        let new_id = core.store.kv_get("lan_device_id").unwrap().unwrap();
        assert_ne!(new_id, old_id);
        let cfg = core.device_config();
        assert!(cfg.branch_id.is_none() && !cfg.configured && cfg.lan_hub.is_none());
        assert_eq!(cfg.printer_host.as_deref(), Some("10.0.0.9"));
        assert_eq!(cfg.printer_brand.as_deref(), Some("star"));
        assert_eq!(cfg.printer_paper_dots, Some(384));
        assert_eq!(core.app_route(), crate::AppRoute::DeviceSetup);
        assert!(!marker_path(&core.config.db_path).unwrap().exists());
    }

    #[test]
    fn wipe_is_a_fresh_install_keeping_the_printer() {
        let (dir, db) = temp_db();
        let core = core_at(&db);
        populate(&core, &dir);
        let old_id = core.store.kv_get("lan_device_id").unwrap().unwrap();
        core.set_reconfigure_check(confirmed());
        core.start_reconfigure().unwrap();
        assert_fresh(&core, &dir, &old_id);
        assert!(!core.reconfigure_readiness().allowed, "the check is spent");
        drop(core);
        let core = core_at(&db);
        assert!(core.restore_session_cached().is_none());
        assert_fresh(&core, &dir, &old_id);
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn interrupted_wipe_finishes_on_boot() {
        let (dir, db) = temp_db();
        let core = core_at(&db);
        populate(&core, &dir);
        let old_id = core.store.kv_get("lan_device_id").unwrap().unwrap();
        // Crash right after the marker, before the store emptied.
        let kept = Kept { printer: printer_only(&device::load(&core.store)) };
        std::fs::write(marker_path(&db).unwrap(), serde_json::to_string(&kept).unwrap()).unwrap();
        drop(core);
        let core = core_at(&db);
        assert_fresh(&core, &dir, &old_id);
        drop(core);
        // A torn marker still finishes the wipe from what the store holds.
        let core = core_at(&db);
        populate(&core, &dir);
        let old_id = core.store.kv_get("lan_device_id").unwrap().unwrap();
        std::fs::write(marker_path(&db).unwrap(), "{\"prin").unwrap();
        drop(core);
        let core = core_at(&db);
        assert_fresh(&core, &dir, &old_id);
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn store_wipe_is_all_or_nothing() {
        let core = core_at("");
        enqueue(&core, "create_order");
        core.store.kv_put("catalog:menu", "[]").unwrap();
        core.store.inject_fault(0, crate::store::FaultKind::Interrupt { steps: 1 });
        let res = core.store.wipe_all(&[("device_config", "{}")]);
        core.store.clear_faults();
        if res.is_err() {
            assert_eq!(core.store.pending_count().unwrap(), 1, "rolled back whole");
            assert!(core.store.kv_get("catalog:menu").unwrap().is_some());
        } else {
            assert_eq!(core.store.pending_count().unwrap(), 0);
        }
    }
}
