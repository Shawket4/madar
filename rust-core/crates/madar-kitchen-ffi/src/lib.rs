//! Madar Kitchen's binding to madar-core (uniffi → React Native via ubrn).
//!
//! Binding code only: every call delegates to `MadarCore`. The one thing kept
//! here is what the core's device binding can't hold yet — the kitchen mode
//! (sections or expo) and the extra sections a device covers (spec KB-1, DV-1);
//! it lives in `kitchen-device.json` beside the core's store until the core's
//! `DeviceConfig` grows those fields.

use std::path::PathBuf;
use std::sync::{Arc, OnceLock};

use madar_core::error::CoreError;
use madar_core::realtime::{EventListener, RealtimeEvent, RealtimePlayer};
use madar_core::session::{LoginMode, LoginRequest};
use madar_core::{MadarConfig, MadarCore};

uniffi::setup_scaffolding!();

/// One runtime for the core's supervisors (realtime, outbox drain) and every call.
fn rt() -> &'static tokio::runtime::Runtime {
    static RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .thread_name("madar-kitchen")
            .build()
            .expect("tokio runtime")
    })
}

// ── Errors ───────────────────────────────────────────────────────────────────

#[derive(Debug, uniffi::Error)]
pub enum KitchenError {
    /// `message` is already worded for a person (core-localized or the server's).
    Failed { message: String, offline: bool },
}

impl std::fmt::Display for KitchenError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            KitchenError::Failed { message, .. } => f.write_str(message),
        }
    }
}
impl std::error::Error for KitchenError {}

/// The Flutter bridge's `humanMessage` (ported in the Slint pilot too).
fn human(core: &MadarCore, e: &CoreError) -> KitchenError {
    let or = |detail: &str| if detail.trim().is_empty() { core.tr("err.generic".into()) } else { detail.to_string() };
    let message = match e {
        CoreError::Offline { detail } if detail == madar_core::net::BLOCKED_UPSTREAM => core.tr("err.blocked_upstream".into()),
        CoreError::Offline { .. } => core.tr("err.offline_no_setup".into()),
        CoreError::Unauthenticated { detail } => or(detail),
        CoreError::Validation { field, detail } => {
            if field.trim().is_empty() { or(detail) } else { or(&format!("{} {detail}", field.replace('_', " "))) }
        }
        CoreError::Server { detail, .. } => or(detail),
        CoreError::Transient { .. } => core.tr("err.network".into()),
        CoreError::Forbidden { resource, action }
            if !action.trim().is_empty()
                && resource.len() > 1
                && resource.bytes().all(|b| b.is_ascii_uppercase() || b.is_ascii_digit() || b == b'_') =>
        {
            action.clone()
        }
        CoreError::Forbidden { .. } => core.tr("err.not_allowed".into()),
        CoreError::Internal { detail } => or(detail),
    };
    let offline = matches!(e, CoreError::Offline { .. } | CoreError::Transient { .. });
    KitchenError::Failed { message, offline }
}

fn internal(message: impl ToString) -> KitchenError {
    KitchenError::Failed { message: message.to_string(), offline: false }
}

// ── Views ────────────────────────────────────────────────────────────────────

#[derive(uniffi::Record)]
pub struct KitchenState {
    /// `setup` (no branch) · `login` (nobody signed in) · `sections` (pick what
    /// this screen shows) · `board`.
    pub route: String,
    pub branch_id: Option<String>,
    pub branch_name: Option<String>,
    /// `sections` | `expo`
    pub mode: String,
    pub section_ids: Vec<String>,
    pub user_name: Option<String>,
    pub user_role: Option<String>,
    /// Bumps (and other writes) still in the outbox (KB-7).
    pub pending: u32,
}

#[derive(uniffi::Record)]
pub struct Branch {
    pub id: String,
    pub name: String,
}

#[derive(uniffi::Record)]
pub struct Station {
    pub id: String,
    pub name: String,
    pub is_default: bool,
    pub is_active: bool,
}

#[derive(uniffi::Record)]
pub struct Ticket {
    pub id: String,
    pub kitchen_ref: Option<String>,
    pub table_label: Option<String>,
    pub round_number: i32,
    /// `order` (teller) | `open_ticket` (waiter)
    pub source_type: String,
    /// firing | ready | voided
    pub status: String,
    pub created_at: String,
    pub items: Vec<Line>,
}

#[derive(uniffi::Record)]
pub struct Line {
    pub id: String,
    pub name: String,
    pub qty: i32,
    pub size_label: Option<String>,
    pub modifiers: Vec<String>,
    pub notes: Option<String>,
    pub station_id: Option<String>,
    pub station_name: Option<String>,
    pub bumped: bool,
    pub combo_name: Option<String>,
}

/// What the host hears from the realtime stream. Must return promptly.
#[uniffi::export(with_foreign)]
pub trait KitchenListener: Send + Sync {
    /// A `kitchen.*` event (or a resync): re-read the board.
    fn on_kitchen_change(&self);
    fn on_connection(&self, connected: bool);
    /// The core decided this deserves the new-order chime (KB-5).
    fn on_ping(&self);
}

struct Bridge(Arc<dyn KitchenListener>);

impl EventListener for Bridge {
    fn on_event(&self, event: RealtimeEvent) {
        if event.event_type.starts_with("kitchen.") || event.event_type.starts_with("ticket.") || event.event_type == "sync.changed" {
            self.0.on_kitchen_change();
        }
    }
    fn on_connection_changed(&self, connected: bool) {
        self.0.on_connection(connected);
    }
}
impl RealtimePlayer for Bridge {
    fn play_ping(&self) {
        self.0.on_ping();
    }
    fn post_notification(&self, _title: String, _body: String, _tag: String) {}
    fn haptic(&self) {}
}

// ── The device's kitchen binding (mode + sections) ───────────────────────────

#[derive(Default)]
struct Binding {
    mode: String,
    section_ids: Vec<String>,
}

fn read_binding(path: &PathBuf) -> Option<Binding> {
    let v: serde_json::Value = serde_json::from_slice(&std::fs::read(path).ok()?).ok()?;
    let mode = v.get("mode")?.as_str()?.to_string();
    let section_ids = v.get("section_ids")?.as_array()?.iter().filter_map(|s| s.as_str().map(String::from)).collect();
    Some(Binding { mode, section_ids })
}

// ── The object ───────────────────────────────────────────────────────────────

#[derive(uniffi::Object)]
pub struct KitchenCore {
    core: Arc<MadarCore>,
    binding_path: PathBuf,
}

/// Runs `f` on the core's runtime and awaits it from whatever executor the host uses.
async fn on_rt<T: Send + 'static>(f: impl std::future::Future<Output = T> + Send + 'static) -> Result<T, KitchenError> {
    rt().spawn(f).await.map_err(internal)
}

#[uniffi::export(async_runtime = "tokio")]
impl KitchenCore {
    /// Boot: open the store under `data_dir` and restore the cached session.
    #[uniffi::constructor]
    pub fn new(data_dir: String, api_url: String, environment: String, locale: String) -> Result<Arc<Self>, KitchenError> {
        let dir = PathBuf::from(data_dir);
        std::fs::create_dir_all(&dir).map_err(internal)?;
        let db_path = dir.join("madar.db").to_string_lossy().to_string();
        let _guard = rt().enter(); // the core spawns its supervisors on this runtime
        let core = MadarCore::new(MadarConfig {
            base_url: api_url,
            environment,
            db_path,
            locale,
            app_version: Some(format!("kitchen/{}", env!("CARGO_PKG_VERSION"))),
        })
        .map_err(|e| internal(format!("{e:?}")))?;
        let _ = core.restore_session_cached();
        Ok(Arc::new(Self { core, binding_path: dir.join("kitchen-device.json") }))
    }

    pub fn state(&self) -> KitchenState {
        let cfg = self.core.device_config();
        let session = self.core.current_session();
        let binding = read_binding(&self.binding_path);
        let route = if cfg.branch_id.as_deref().unwrap_or("").is_empty() {
            "setup"
        } else if session.is_none() {
            "login"
        } else if binding.is_none() {
            "sections"
        } else {
            "board"
        };
        let b = binding.unwrap_or_default();
        KitchenState {
            route: route.into(),
            branch_id: cfg.branch_id,
            branch_name: cfg.branch_name,
            mode: if b.mode.is_empty() { "sections".into() } else { b.mode },
            section_ids: b.section_ids,
            user_name: session.as_ref().map(|s| s.display_name.clone()),
            user_role: session.map(|s| s.role),
            pending: self.core.pending_outbox_count().unwrap_or(0),
        }
    }

    /// Device setup, step 1 (DV-1): a manager's email sign-in, then the org's branches.
    pub async fn manager_login(&self, email: String, password: String) -> Result<Vec<Branch>, KitchenError> {
        let core = self.core.clone();
        on_rt(async move {
            core.login(LoginRequest {
                mode: LoginMode::Email,
                email: Some(email.trim().to_string()),
                password: Some(password),
                name: None,
                pin: None,
                branch_id: None,
                org_id: None,
            })
            .await
            .map_err(|e| human(&core, &e))?;
            let branches = core.list_branches().await.map_err(|e| human(&core, &e))?;
            Ok(branches.into_iter().filter(|b| b.is_active).map(|b| Branch { id: b.id, name: b.name }).collect())
        })
        .await?
    }

    /// Device setup, step 2: bind the branch; the manager is signed out and the
    /// device goes to the staff PIN screen.
    pub fn choose_branch(&self, id: String, name: String) -> Result<(), KitchenError> {
        self.core.set_device_branch(id, Some(name)).map_err(|e| human(&self.core, &e))?;
        let _ = std::fs::remove_file(&self.binding_path);
        self.core.logout(false).map_err(|e| human(&self.core, &e))
    }

    /// Staff sign-in with name + PIN on the bound branch (DV-2).
    pub async fn sign_in(&self, name: String, pin: String) -> Result<(), KitchenError> {
        let core = self.core.clone();
        on_rt(async move {
            let branch_id = core.device_config().branch_id;
            core.sign_in(LoginRequest {
                mode: LoginMode::Pin,
                name: Some(name.trim().to_string()),
                pin: Some(pin),
                branch_id,
                email: None,
                password: None,
                org_id: None,
            })
            .await
            .map(|_| ())
            .map_err(|e| human(&core, &e))
        })
        .await?
    }

    pub fn sign_out(&self) -> Result<(), KitchenError> {
        self.core.unsubscribe_realtime();
        self.core.logout(false).map_err(|e| human(&self.core, &e))
    }

    /// The branch's sections (`kitchen_stations`), from the synced settings.
    /// A device bound a moment ago may not hold them yet: wait briefly for the fill.
    pub async fn stations(&self) -> Result<Vec<Station>, KitchenError> {
        let core = self.core.clone();
        on_rt(async move {
            // ponytail: polls up to ~5 s for the background fill; a proper "wait for
            // branch settings" signal from the core would replace it.
            for _ in 0..10 {
                let list = core.kds_list_stations().await.map_err(|e| human(&core, &e))?;
                if !list.is_empty() {
                    return Ok(list
                        .into_iter()
                        .map(|s| Station { id: s.id, name: s.name, is_default: s.is_default, is_active: s.is_active })
                        .collect());
                }
                tokio::time::sleep(std::time::Duration::from_millis(500)).await;
            }
            Ok(vec![])
        })
        .await?
    }

    /// What this screen shows (KB-1, EX-1). The core keeps one station; for expo
    /// it is the first id given (the default section).
    pub fn set_sections(&self, mode: String, section_ids: Vec<String>) -> Result<(), KitchenError> {
        self.core
            .set_device_station(section_ids.first().cloned())
            .map_err(|e| human(&self.core, &e))?;
        let json = serde_json::json!({ "mode": mode, "section_ids": section_ids });
        std::fs::write(&self.binding_path, json.to_string()).map_err(internal)
    }

    /// Back to choosing sections (keeps the branch and the signed-in person).
    pub fn clear_sections(&self) -> Result<(), KitchenError> {
        let _ = std::fs::remove_file(&self.binding_path);
        Ok(())
    }

    /// Full reset to a first launch (new branch). The core refuses while work is unsynced.
    pub fn reset_device(&self) -> Result<(), KitchenError> {
        self.core.unsubscribe_realtime();
        self.core.start_reconfigure().map_err(|e| human(&self.core, &e))?;
        let _ = std::fs::remove_file(&self.binding_path);
        Ok(())
    }

    /// Open kitchen tickets; `station_id` limits to those with work left there.
    /// Local rows only, with queued bumps and LAN fires overlaid (no network).
    pub async fn tickets(&self, station_id: Option<String>) -> Result<Vec<Ticket>, KitchenError> {
        let core = self.core.clone();
        on_rt(async move {
            let list = core.kds_list(station_id).await.map_err(|e| human(&core, &e))?;
            Ok(list
                .into_iter()
                .map(|t| Ticket {
                    id: t.id,
                    kitchen_ref: t.kitchen_ref,
                    table_label: t.table_label,
                    round_number: t.round_number,
                    source_type: t.source_type,
                    status: t.status,
                    created_at: t.created_at,
                    items: t
                        .items
                        .into_iter()
                        .map(|l| Line {
                            id: l.id,
                            name: l.name,
                            qty: l.qty,
                            size_label: l.size_label,
                            modifiers: l.modifiers,
                            notes: l.notes,
                            station_id: l.station_id,
                            station_name: l.station_name,
                            bumped: l.bumped,
                            combo_name: l.combo.map(|c| c.name),
                        })
                        .collect(),
                })
                .collect())
        })
        .await?
    }

    /// Bump a line: outbox first, then drained (offline-safe, AT-2).
    pub async fn bump(&self, item_id: String) -> Result<(), KitchenError> {
        let core = self.core.clone();
        on_rt(async move { core.kds_bump(item_id).await.map_err(|e| human(&core, &e)) }).await?
    }

    pub async fn unbump(&self, item_id: String) -> Result<(), KitchenError> {
        let core = self.core.clone();
        on_rt(async move { core.kds_unbump(item_id).await.map_err(|e| human(&core, &e)) }).await?
    }

    /// Pull the branch now (boot, manual refresh). Errors are worded; offline is not fatal.
    pub async fn sync_now(&self) -> Result<(), KitchenError> {
        let core = self.core.clone();
        on_rt(async move { core.sync_now().await.map(|_| ()).map_err(|e| human(&core, &e)) }).await?
    }

    /// Subscribe to the branch's realtime stream. Idempotent in the core.
    pub async fn start_realtime(&self, listener: Arc<dyn KitchenListener>) -> Result<(), KitchenError> {
        let core = self.core.clone();
        on_rt(async move {
            let bridge = Arc::new(Bridge(listener));
            core.start_realtime(Box::new(Bridge(bridge.0.clone())), Box::new(Bridge(bridge.0.clone())))
                .await
                .map_err(|e| human(&core, &e))
        })
        .await?
    }

    pub fn stop_realtime(&self) {
        self.core.unsubscribe_realtime();
    }

    /// `ar` / `en`: item names and core messages re-resolve on the next read.
    pub fn set_locale(&self, locale: String) {
        self.core.set_locale(locale);
    }

    // ── LAN (spec LN-1..5) ──────────────────────────────────────────────────
    // The core's LAN relay: fires from a POS on the same network reach this
    // board with no internet, and bumps go back the same way. The LAN is a
    // delivery path only — every bump is still outbox-first and synced later.

    /// Start the relay for the signed-in branch. Idempotent. The LAN key comes
    /// only to a registered device, so the first start registers this screen
    /// (online) and fetches it; the host's retry covers a start made offline.
    pub async fn lan_start(&self) -> Result<(), KitchenError> {
        let core = self.core.clone();
        on_rt(async move {
            if core.lan_start().await.is_ok() {
                return Ok(());
            }
            core.register_kitchen_screen().await.map_err(|e| human(&core, &e))?;
            core.lan_start().await.map_err(|e| human(&core, &e))
        })
        .await?
    }

    pub fn lan_stop(&self) {
        self.core.lan_stop();
    }

    pub fn lan_status(&self) -> LanStatus {
        let s = self.core.lan_status();
        LanStatus { running: s.running, peer_count: s.peer_count, last_error: s.last_error }
    }

    /// What to advertise over the system's Bonjour (`_madar._tcp`); `None`
    /// while the relay is down. iOS blocks the core's own multicast discovery
    /// without a restricted entitlement, so the host advertises and browses.
    pub fn lan_advert(&self) -> Option<LanAdvert> {
        self.core.lan_advert().map(|a| LanAdvert {
            device_id: a.device_id,
            branch_id: a.branch_id,
            role: a.role,
            station_id: a.station_id,
            device_code: a.device_code,
            tcp_port: a.tcp_port,
        })
    }

    /// A peer the host's Bonjour resolved. The core filters by branch and
    /// skips this device; re-note live peers every few seconds (12 s TTL).
    #[allow(clippy::too_many_arguments)]
    pub fn lan_note_peer(
        &self,
        device_id: String,
        branch_id: String,
        host: String,
        port: u16,
        role: String,
        station_id: Option<String>,
        device_code: Option<String>,
    ) -> bool {
        self.core.lan_note_peer(device_id, branch_id, host, port, role, station_id, device_code)
    }
}

#[derive(uniffi::Record)]
pub struct LanStatus {
    pub running: bool,
    /// Live discovered peers + manual hubs.
    pub peer_count: u32,
    pub last_error: Option<String>,
}

#[derive(uniffi::Record)]
pub struct LanAdvert {
    pub device_id: String,
    pub branch_id: String,
    pub role: String,
    pub station_id: Option<String>,
    pub device_code: Option<String>,
    pub tcp_port: u16,
}
