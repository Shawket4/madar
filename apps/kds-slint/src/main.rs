//! Madar KDS — standalone Slint kitchen display over madar-core (no FFI).
//!
//! Architecture: the Slint event loop owns the main thread; a multi-thread
//! tokio runtime runs every core call. UI intent (callbacks) hops onto the
//! runtime via `spawn`; results hop back with `invoke_from_event_loop`.
//! Routing mirrors the Flutter shell's `app_route()` switch 1:1.

slint::include_modules!();

mod feature_floor;
mod feature_checkout;
mod feature_incoming;
mod feature_settings;

use madar_core::{
    error::CoreError,
    realtime::{EventListener, RealtimePlayer, RealtimeEvent},
    session::{LoginMode, LoginRequest},
    MadarConfig, MadarCore,
};
use slint::{ComponentHandle, ModelRc, SharedString, VecModel, Weak};
use std::sync::{Arc, Mutex, OnceLock};

/// The one tokio runtime backing every core call.
fn rt() -> &'static tokio::runtime::Runtime {
    static RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("tokio runtime")
    })
}

/// Shared app state reachable from both loops.
struct App {
    core: Arc<MadarCore>,
    ui: Weak<AppWindow>,
    /// PIN buffer — authoritative here (the UI only mirrors dot count).
    pin: Mutex<String>,
    /// The bound station once routed to the board.
    station_id: Mutex<Option<String>>,
    /// Last good board — re-rendered on age ticks without refetching, and
    /// kept on fetch failure (a blip never blanks a busy kitchen).
    last_tickets: Mutex<Vec<madar_core::kds::KdsTicketView>>,
    /// Station directory (names the header).
    stations: Mutex<Vec<madar_core::kds::KdsStationView>>,
    fail_count: Mutex<i32>,
}

/// Port of the Flutter bridge's `humanMessage` — host conditions get
/// core-localized strings; server/validation details pass through verbatim.
fn human_message(core: &MadarCore, e: &CoreError) -> String {
    let or = |detail: &str| {
        if detail.trim().is_empty() { core.tr("err.generic".into()) } else { detail.to_string() }
    };
    match e {
        CoreError::Offline { .. } => core.tr("err.offline_no_setup".into()),
        CoreError::Unauthenticated { detail } => or(detail),
        CoreError::Validation { field, detail } => {
            if field.trim().is_empty() { or(detail) } else { or(&format!("{} {detail}", field.replace('_', " "))) }
        }
        CoreError::Server { detail, .. } => or(detail),
        CoreError::Transient { .. } => core.tr("err.network".into()),
        CoreError::Forbidden { .. } => core.tr("err.not_allowed".into()),
        CoreError::Internal { detail } => or(detail),
    }
}

/// Minutes since an RFC3339 stamp, clamped at 0 (a malformed stamp reads as
/// fresh, never stale — the Flutter/Kotlin `minutesSince`).
fn minutes_since(rfc: &str) -> i32 {
    chrono::DateTime::parse_from_rfc3339(rfc)
        .map(|then| {
            let mins = (chrono::Utc::now() - then.with_timezone(&chrono::Utc)).num_minutes();
            mins.max(0) as i32
        })
        .unwrap_or(0)
}

// ── UI thread helpers ─────────────────────────────────────────────────────────

fn on_ui(app: &Arc<App>, f: impl FnOnce(AppWindow, Arc<App>) + Send + 'static) {
    let ui = app.ui.clone();
    let app = app.clone();
    let _ = slint::invoke_from_event_loop(move || {
        if let Some(ui) = ui.upgrade() {
            f(ui, app);
        }
    });
}

fn set_error(app: &Arc<App>, message: String) {
    on_ui(app, move |ui, _| ui.global::<Auth>().set_error(message.into()));
}

fn set_busy(app: &Arc<App>, busy: bool) {
    on_ui(app, move |ui, _| ui.global::<Auth>().set_busy(busy));
}

fn bump_fail(app: &Arc<App>) {
    let count = {
        let mut fails = app.fail_count.lock().unwrap();
        *fails += 1;
        *fails
    };
    // Failure clears the PIN (the Flutter `_bumpFail` + `pin: ''`).
    app.pin.lock().unwrap().clear();
    on_ui(app, move |ui, _| {
        let auth = ui.global::<Auth>();
        auth.set_pin_length(0);
        auth.set_fail_count(count);
    });
}

// ── Localization: every string the UI shows, resolved once per locale. ──────

fn apply_strings(ui: &AppWindow, core: &MadarCore) {
    let t = |k: &str| SharedString::from(core.tr(k.into()));
    ui.global::<T>().set_rtl(core.is_rtl());

    let auth = ui.global::<Auth>();
    auth.set_brand_headline(t("brand.headline"));
    auth.set_brand_headline_lines(ModelRc::new(VecModel::from(
        core.tr("brand.headline".into())
            .split('\n')
            .map(SharedString::from)
            .collect::<Vec<_>>(),
    )));
    auth.set_brand_tagline(t("brand.tagline"));
    auth.set_tr_welcome_back(t("login.welcome_back"));
    auth.set_tr_subtitle(t("login.subtitle"));
    auth.set_tr_reconfigure(t("login.reconfigure"));
    auth.set_tr_name(t("login.name"));
    auth.set_tr_sign_in(t("login.sign_in"));
    auth.set_tr_pin_hint(t("login.pin_hint"));
    auth.set_tr_setup_title(t("setup.title"));
    auth.set_tr_setup_desc(t("setup.desc"));
    auth.set_tr_choose_branch(t("setup.choose_branch"));
    auth.set_tr_choose_branch_desc(t("setup.choose_branch_desc"));
    auth.set_tr_email(t("setup.email"));
    auth.set_tr_password(t("setup.password"));
    auth.set_tr_continue(t("setup.continue"));
    auth.set_tr_cancel(t("setup.cancel"));
    auth.set_tr_choose_station(t("setup.choose_station"));
    auth.set_tr_choose_station_desc(t("setup.choose_station_desc"));
    auth.set_tr_stations_section(t("setup.title"));
    auth.set_tr_station_default(t("setup.station_default"));
    auth.set_tr_no_stations(t("setup.no_stations"));
    auth.set_tr_sign_out(t("home.sign_out"));

    let kds = ui.global::<Kds>();
    kds.set_tr_reconnecting(t("kds.reconnecting"));
    kds.set_tr_all_clear(t("kds.all_clear"));

    ui.set_tr_sign_out(t("home.sign_out"));
    ui.set_tr_unsupported_role(t("err.not_allowed"));
    ui.set_tr_settings_title(t("settings.title"));
    ui.set_tr_appearance(t("settings.appearance"));
    ui.set_tr_theme_light(t("settings.theme_light"));
    ui.set_tr_theme_dark(t("settings.theme_dark"));
    ui.set_tr_language(t("settings.language"));
    ui.set_tr_change_station(t("setup.choose_station"));
}

// ── Routing: the Flutter shell's `_screenFor(app_route())` switch. ──────────

fn route_refresh(app: &Arc<App>) {
    on_ui(app, |ui, app| {
        let core = &app.core;
        let route = core.app_route();
        let session = core.current_session();
        let config = core.device_config();
        apply_strings(&ui, core);

        // Branch chip label (login: name, or "Branch <id-prefix-8>").
        let branch_label = {
            let name = config.branch_name.clone().unwrap_or_default();
            if !name.is_empty() {
                name
            } else {
                let id = config.branch_id.clone().unwrap_or_default();
                format!("{} {}", core.tr("login.branch".into()), &id[..id.len().min(8)])
            }
        };
        let auth = ui.global::<Auth>();
        auth.set_tr_branch_label(branch_label.into());
        auth.set_branch_name(config.branch_name.clone().unwrap_or_default().into());
        auth.set_error(SharedString::new());
        auth.set_busy(false);

        use madar_core::AppRoute;
        match route {
            AppRoute::DeviceSetup => {
                if session.as_ref().map(|s| s.role == "kitchen").unwrap_or(false) {
                    ui.set_screen(Screen::Station);
                    load_stations(&app, true);
                } else {
                    auth.set_picking_branch(false);
                    auth.set_show_cancel(
                        config.branch_id.map(|b| !b.is_empty()).unwrap_or(false),
                    );
                    ui.set_screen(Screen::Setup);
                }
            }
            AppRoute::Login => {
                app.pin.lock().unwrap().clear();
                auth.set_pin_length(0);
                ui.set_screen(Screen::Login);
            }
            AppRoute::KitchenDisplay { station_id } => {
                *app.station_id.lock().unwrap() = Some(station_id);
                ui.set_screen(Screen::Board);
                load_stations(&app, false);
                reload_board(&app);
                arm_realtime(&app);
            }
            // A non-kitchen teller on a KDS terminal — plain notice + exit.
            _ => ui.set_screen(Screen::Unsupported),
        }
    });
}

// ── Board data flow ──────────────────────────────────────────────────────────

fn render_board(app: &Arc<App>) {
    on_ui(app, |ui, app| {
        let tickets = app.last_tickets.lock().unwrap().clone();
        let station_id = app.station_id.lock().unwrap().clone();
        let stations = app.stations.lock().unwrap();
        let station_name = station_id
            .as_deref()
            .and_then(|id| stations.iter().find(|s| s.id == id))
            .map(|s| s.name.clone())
            .unwrap_or_else(|| app.core.tr("kds.title".into()));

        let rows: Vec<KdsTicketData> = tickets
            .iter()
            .map(|t| KdsTicketData {
                id: t.id.clone().into(),
                title: t
                    .table_label
                    .clone()
                    .or_else(|| t.kitchen_ref.clone())
                    .unwrap_or_else(|| format!("#{}", t.round_number))
                    .into(),
                age_minutes: minutes_since(&t.created_at),
                ready: t.status == "ready",
                open_ticket: t.source_type == "open_ticket",
                lines: ModelRc::new(VecModel::from(
                    t.items
                        .iter()
                        .map(|l| KdsLineData {
                            id: l.id.clone().into(),
                            title: {
                                let size = l
                                    .size_label
                                    .as_deref()
                                    .map(|s| format!(" · {s}"))
                                    .unwrap_or_default();
                                format!("{}× {}{}", l.qty, l.name, size).into()
                            },
                            modifiers: l.modifiers.join(", ").into(),
                            notes: l.notes.clone().unwrap_or_default().trim().into(),
                            station: l
                                .station_name
                                .clone()
                                .unwrap_or_default()
                                .trim()
                                .to_uppercase()
                                .into(),
                            bumped: l.bumped,
                        })
                        .collect::<Vec<_>>(),
                )),
            })
            .collect();

        let kds = ui.global::<Kds>();
        kds.set_station_name(station_name.into());
        kds.set_tickets(ModelRc::new(VecModel::from(rows)));
    });
}

/// Fetch the board; a failed fetch keeps the last good tickets on screen.
fn reload_board(app: &Arc<App>) {
    let app = app.clone();
    rt().spawn(async move {
        let station = app.station_id.lock().unwrap().clone();
        if let Ok(tickets) = app.core.kds_list(station).await {
            *app.last_tickets.lock().unwrap() = tickets;
        }
        render_board(&app);
    });
}

/// Fetch the station directory (station-picker list / board header name).
fn load_stations(app: &Arc<App>, for_picker: bool) {
    let app = app.clone();
    rt().spawn(async move {
        if for_picker {
            on_ui(&app, |ui, _| ui.global::<Auth>().set_stations_loading(true));
        }
        let result = app.core.kds_list_stations().await;
        match result {
            Ok(stations) => {
                *app.stations.lock().unwrap() = stations.clone();
                if for_picker {
                    on_ui(&app, move |ui, _| {
                        let auth = ui.global::<Auth>();
                        auth.set_stations_loading(false);
                        auth.set_stations(ModelRc::new(VecModel::from(
                            stations
                                .iter()
                                .map(|s| StationData {
                                    id: s.id.clone().into(),
                                    name: s.name.clone().into(),
                                    is_default: s.is_default,
                                })
                                .collect::<Vec<_>>(),
                        )));
                    });
                } else {
                    render_board(&app);
                }
            }
            Err(e) => {
                let msg = human_message(&app.core, &e);
                on_ui(&app, move |ui, _| {
                    let auth = ui.global::<Auth>();
                    auth.set_stations_loading(false);
                    if for_picker {
                        auth.set_error(msg.into());
                    }
                });
            }
        }
    });
}

// ── Realtime: the shell's RealtimeArmer — kitchen.* events reload the board;
// connection changes drive the header dot + reconnecting banner. ────────────

struct Listener {
    app: Arc<App>,
}

impl EventListener for Listener {
    fn on_event(&self, event: RealtimeEvent) {
        if event.event_type.starts_with("kitchen.") {
            reload_board(&self.app);
        }
    }
    fn on_connection_changed(&self, connected: bool) {
        on_ui(&self.app, move |ui, _| ui.global::<Kds>().set_connected(connected));
    }
}

/// Desktop player: no ping asset / notification center wired yet — the core
/// still decides WHEN to alert; the sinks are just quiet here.
struct Player;
impl RealtimePlayer for Player {
    fn play_ping(&self) {}
    fn post_notification(&self, _title: String, _body: String, _tag: String) {}
    fn haptic(&self) {}
}

fn arm_realtime(app: &Arc<App>) {
    let app = app.clone();
    rt().spawn(async move {
        // Idempotent in the core — safe to call on every board entry.
        let listener = Box::new(Listener { app: app.clone() });
        let _ = app.core.start_realtime(listener, Box::new(Player)).await;
    });
}

// ── Auth intents ─────────────────────────────────────────────────────────────

fn sign_in_teller(app: &Arc<App>, name: String) {
    let trimmed = name.trim().to_string();
    let pin = app.pin.lock().unwrap().clone();
    if trimmed.is_empty() || pin.len() < 4 {
        bump_fail(app);
        return;
    }
    let app = app.clone();
    set_busy(&app, true);
    rt().spawn(async move {
        let branch = app.core.device_config().branch_id;
        let result = app
            .core
            .sign_in(LoginRequest {
                mode: LoginMode::Pin,
                name: Some(trimmed),
                pin: Some(pin),
                branch_id: branch,
                email: None,
                password: None,
                org_id: None,
            })
            .await;
        match result {
            Ok(_) => route_refresh(&app),
            Err(e) => {
                let msg = human_message(&app.core, &e);
                set_busy(&app, false);
                set_error(&app, msg);
                bump_fail(&app);
            }
        }
    });
}

fn authenticate_manager(app: &Arc<App>, email: String, password: String) {
    if email.trim().is_empty() || password.is_empty() {
        return;
    }
    let app = app.clone();
    set_busy(&app, true);
    rt().spawn(async move {
        let login = app
            .core
            .login(LoginRequest {
                mode: LoginMode::Email,
                email: Some(email.trim().to_string()),
                password: Some(password),
                name: None,
                pin: None,
                branch_id: None,
                org_id: None,
            })
            .await;
        if let Err(e) = login {
            let msg = human_message(&app.core, &e);
            set_busy(&app, false);
            set_error(&app, msg);
            return;
        }
        match app.core.list_branches().await {
            Ok(branches) => on_ui(&app, move |ui, _| {
                let auth = ui.global::<Auth>();
                auth.set_busy(false);
                auth.set_error(SharedString::new());
                auth.set_picking_branch(true);
                auth.set_branches(ModelRc::new(VecModel::from(
                    branches
                        .iter()
                        .filter(|b| b.is_active)
                        .map(|b| BranchData { id: b.id.clone().into(), name: b.name.clone().into() })
                        .collect::<Vec<_>>(),
                )));
            }),
            Err(e) => {
                let msg = human_message(&app.core, &e);
                set_busy(&app, false);
                set_error(&app, msg);
            }
        }
    });
}

fn bind_branch(app: &Arc<App>, id: String, name: String) {
    let app = app.clone();
    rt().spawn(async move {
        let bound = app.core.set_device_branch(id, Some(name));
        if let Err(e) = bound {
            let msg = human_message(&app.core, &e);
            set_error(&app, msg);
            return;
        }
        // Manager signs out; the route recomputes to the teller login.
        let _ = app.core.logout(false);
        on_ui(&app, |ui, _| ui.global::<Auth>().set_picking_branch(false));
        route_refresh(&app);
    });
}

fn cancel_setup(app: &Arc<App>) {
    let app = app.clone();
    rt().spawn(async move {
        // The Flutter `cancelReconfigure`: re-binding the SAME branch clears
        // the reconfiguring flag; then drop any manager session.
        let config = app.core.device_config();
        if let Some(branch_id) = config.branch_id.filter(|b| !b.is_empty()) {
            let _ = app.core.set_device_branch(branch_id, config.branch_name);
        }
        let _ = app.core.logout(false);
        on_ui(&app, |ui, _| ui.global::<Auth>().set_picking_branch(false));
        route_refresh(&app);
    });
}

fn main() {
    let app_window = AppWindow::new().expect("window");

    // ── Boot: mirror app/boot.dart — config → core → cached session. ──────
    let base_url =
        std::env::var("MADAR_API").unwrap_or_else(|_| "https://api.madar-pos.cloud".into());
    let environment = std::env::var("MADAR_ENV").unwrap_or_else(|_| "prod".into());
    let data_dir = dirs::data_local_dir()
        .unwrap_or_else(|| std::path::PathBuf::from("."))
        .join("madar-kds");
    std::fs::create_dir_all(&data_dir).expect("data dir");
    let db_path = data_dir.join("madar.db").to_string_lossy().to_string();
    let locale = std::env::var("MADAR_LOCALE").unwrap_or_else(|_| "en".into());

    let core = {
        let _guard = rt().enter(); // core spawns supervisors on this runtime
        MadarCore::new(MadarConfig { base_url, environment, db_path, locale })
            .expect("core boot")
    };
    let _ = core.restore_session_cached();

    if std::env::var("MADAR_THEME").as_deref() == Ok("dark") {
        app_window.global::<T>().set_dark(true);
    }

    let app = Arc::new(App {
        core,
        ui: app_window.as_weak(),
        pin: Mutex::new(String::new()),
        station_id: Mutex::new(None),
        last_tickets: Mutex::new(Vec::new()),
        stations: Mutex::new(Vec::new()),
        fail_count: Mutex::new(0),
    });

    // ── Wire intents ───────────────────────────────────────────────────────
    {
        let a = app.clone();
        app_window.on_push_digit(move |digit| {
            let ui = a.ui.upgrade().unwrap();
            let auth = ui.global::<Auth>();
            if auth.get_busy() {
                return;
            }
            let full = {
                let mut pin = a.pin.lock().unwrap();
                if pin.len() >= 6 {
                    return;
                }
                pin.push_str(digit.as_str());
                auth.set_error(SharedString::new());
                auth.set_pin_length(pin.len() as i32);
                pin.len() == 6
            };
            // Auto-submit at 6 digits with the live name field.
            if full {
                sign_in_teller(&a, auth.get_login_name().to_string());
            }
        });
    }
    {
        let a = app.clone();
        app_window.on_pop_digit(move || {
            let mut pin = a.pin.lock().unwrap();
            pin.pop();
            let len = pin.len() as i32;
            drop(pin);
            if let Some(ui) = a.ui.upgrade() {
                ui.global::<Auth>().set_pin_length(len);
            }
        });
    }
    {
        let a = app.clone();
        app_window.on_submit_login(move |name| sign_in_teller(&a, name.to_string()));
    }
    {
        let a = app.clone();
        app_window.on_begin_reconfigure(move || {
            let _ = a.core.start_reconfigure();
            route_refresh(&a);
        });
    }
    {
        let a = app.clone();
        app_window
            .on_authenticate(move |email, pw| authenticate_manager(&a, email.to_string(), pw.to_string()));
    }
    {
        let a = app.clone();
        app_window
            .on_pick_branch(move |id, name| bind_branch(&a, id.to_string(), name.to_string()));
    }
    {
        let a = app.clone();
        app_window.on_cancel_setup(move || cancel_setup(&a));
    }
    {
        let a = app.clone();
        app_window.on_pick_station(move |id| {
            let _ = a.core.set_device_station(Some(id.to_string()));
            route_refresh(&a);
        });
    }
    {
        let a = app.clone();
        app_window.on_sign_out(move || {
            a.core.unsubscribe_realtime();
            let _ = a.core.logout(false);
            route_refresh(&a);
        });
    }
    {
        let a = app.clone();
        app_window.on_toggle_line(move |id, bumped| {
            let a = a.clone();
            rt().spawn(async move {
                // bump ⇄ recall, then reload; failures are silent — the next
                // tick reconciles (the Flutter KdsNotifier.toggleLine).
                let id = id.to_string();
                let _ = if bumped {
                    a.core.kds_unbump(id).await
                } else {
                    a.core.kds_bump(id).await
                };
                reload_board(&a);
            });
        });
    }
    {
        // Age escalation re-render every 30s; while realtime is down it also
        // refetches (the Flutter safety poll).
        let a = app.clone();
        app_window.on_tick(move || {
            let connected = a
                .ui
                .upgrade()
                .map(|ui| ui.global::<Kds>().get_connected())
                .unwrap_or(true);
            if connected {
                render_board(&a);
            } else {
                reload_board(&a);
            }
        });
    }
    {
        // Locale flip — the core re-resolves every string; the board
        // re-renders so ticket content picks up the new translations too.
        let a = app.clone();
        app_window.on_set_locale(move |locale| {
            a.core.set_locale(locale.to_string());
            on_ui(&a, |ui, app| apply_strings(&ui, &app.core));
            render_board(&a);
            reload_board(&a);
        });
    }
    {
        // Re-commission: unpin the station → app_route recomputes to the
        // station picker (the Flutter settings' station row behavior).
        let a = app.clone();
        app_window.on_change_station(move || {
            let _ = a.core.set_device_station(None);
            route_refresh(&a);
        });
    }

    // Dev-only screen preview (`MADAR_PREVIEW=login|station|board`): forces a
    // screen with sample data so every surface is reviewable without a
    // provisioned backend. Never set in production.
    if let Ok(preview) = std::env::var("MADAR_PREVIEW") {
        apply_strings(&app_window, &app.core);
        preview_screen(&app_window, &preview);
    } else {
        route_refresh(&app);
    }
    app_window.run().expect("event loop");
}

fn preview_screen(ui: &AppWindow, which: &str) {
    let auth = ui.global::<Auth>();
    auth.set_tr_branch_label("Downtown Branch".into());
    auth.set_branch_name("Downtown Branch".into());
    match which {
        "login" => ui.set_screen(Screen::Login),
        "station" => {
            auth.set_stations(ModelRc::new(VecModel::from(vec![
                StationData { id: "1".into(), name: "Main Kitchen".into(), is_default: true },
                StationData { id: "2".into(), name: "المشروبات".into(), is_default: false },
                StationData { id: "3".into(), name: "Grill".into(), is_default: false },
            ])));
            ui.set_screen(Screen::Station);
        }
        "board" => {
            let line = |id: &str, title: &str, modifiers: &str, notes: &str, station: &str, bumped: bool| KdsLineData {
                id: id.into(),
                title: title.into(),
                modifiers: modifiers.into(),
                notes: notes.into(),
                station: station.into(),
                bumped,
            };
            let mk = |id: &str, title: &str, age: i32, ready: bool, open: bool, lines: Vec<KdsLineData>| KdsTicketData {
                id: id.into(),
                title: title.into(),
                age_minutes: age,
                ready,
                open_ticket: open,
                lines: ModelRc::new(VecModel::from(lines)),
            };
            let tickets = vec![
                mk("t1", "طاولة ٤", 2, false, true, vec![
                    line("l1", "2× شاورما دجاج · وسط", "جبنة إضافية, بدون بصل", "", "GRILL", false),
                    line("l2", "1× بطاطس كبير", "", "بدون ملح", "FRYER", false),
                ]),
                mk("t2", "#18", 7, false, false, vec![
                    line("l3", "1× Chicken Burger", "Extra pickles", "", "", true),
                    line("l4", "2× Turkish Coffee", "", "no sugar", "BAR", false),
                ]),
                mk("t3", "Table 12", 12, false, false, vec![
                    line("l5", "3× Margherita Pizza · L", "Extra basil", "table is waiting long", "OVEN", false),
                ]),
                mk("t4", "#21", 4, true, false, vec![
                    line("l6", "1× قهوة تركية", "", "", "", true),
                    line("l7", "1× Cheesecake", "", "", "", true),
                ]),
            ];
            let kds = ui.global::<Kds>();
            kds.set_station_name("Main Kitchen".into());
            kds.set_connected(true);
            kds.set_tickets(ModelRc::new(VecModel::from(tickets)));
            ui.set_screen(Screen::Board);
        }
        _ => {}
    }
}
