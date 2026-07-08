//! Settings + Sync feature glue — the Rust spine behind
//! `ui/feature_settings.slint`, porting the Flutter feature_settings package
//! (settings_provider.dart + sync_provider.dart): the device-config mirror
//! (custody lives in the CORE; the globals only mirror), printer brand +
//! test-print lifecycle, till/station binding, the LAN hub, the diagnostics
//! feed, and the durable-outbox inspector (load / retry / force-push /
//! discard).
//!
//! Integration (see NOTES-settings.md): `mod feature_settings;` in main.rs,
//! call `wire_settings(&app_window, &app)` once at boot, `open_settings(&app)`
//! / `open_sync(&app)` when routing to the screens, and
//! `apply_settings_strings(&ui, core)` from the locale-flip path.

use crate::{
    human_message, on_ui, rt, App, AppWindow, SettingsDiagData, SettingsState,
    SettingsStationData, SettingsTillData, SyncOutboxData, SyncState, T,
};
use madar_core::{
    checkout::{ReceiptLineView, ReceiptView},
    receipt::PrinterBrand,
    MadarCore,
};
use slint::{ComponentHandle, ModelRc, SharedString, VecModel};
use std::sync::Arc;

/// Default JetDirect (raw-TCP) printer port — the natives' `parsePrinter`
/// fallback.
const JETDIRECT_PORT: u16 = 9100;

/// Receipt column width (feature_checkout's `kReceiptChars`).
const RECEIPT_CHARS: u32 = 32;

/// Test-print lifecycle (the Flutter `PrintState` enum, as the global's int).
const PRINT_IDLE: i32 = 0;
const PRINT_PRINTING: i32 = 1;
const PRINT_PRINTED: i32 = 2;
const PRINT_FAILED: i32 = 3;
const PRINT_NO_PRINTER: i32 = 4;

/// Split `"host"` / `"host:port"` → (host, port); default JetDirect 9100
/// (the natives' `parsePrinter`).
fn parse_printer(raw: &str) -> (String, u16) {
    let trimmed = raw.trim();
    match trimmed.rfind(':') {
        None => (trimmed.to_string(), JETDIRECT_PORT),
        Some(colon) => {
            let port = trimmed[colon + 1..].parse().unwrap_or(JETDIRECT_PORT);
            (trimmed[..colon].to_string(), port)
        }
    }
}

/// Reassemble `"host:port"` from the core's split printer config (the
/// natives' `printerAddress`). Empty when no printer is bound. The screen
/// seeds its printer field from this.
fn printer_address_of(config: &madar_core::device::DeviceConfigView) -> String {
    let host = config.printer_host.as_deref().unwrap_or("").trim();
    if host.is_empty() {
        return String::new();
    }
    match config.printer_port {
        Some(port) if port != JETDIRECT_PORT => format!("{host}:{port}"),
        _ => host.to_string(),
    }
}

/// `'7.0"'` — the Dart `'${inches.toStringAsFixed(1)}"'`.
fn threshold_label(inches: f32) -> String {
    format!("{inches:.1}\"")
}

// ── Localization: every `tr('…')` key the Dart source uses, resolved once
// per locale (call again from the locale-flip path). ─────────────────────────

pub fn apply_settings_strings(ui: &AppWindow, core: &MadarCore) {
    let t = |k: &str| SharedString::from(core.tr(k.into()));

    let s = ui.global::<SettingsState>();
    s.set_tr_title(t("settings.title"));
    s.set_tr_account(t("settings.account"));
    s.set_tr_appearance(t("settings.appearance"));
    s.set_tr_theme_light(t("settings.theme_light"));
    s.set_tr_theme_dark(t("settings.theme_dark"));
    s.set_tr_orientation(t("settings.orientation"));
    s.set_tr_flip_screen(t("settings.flip_screen"));
    s.set_tr_tablet_threshold(t("settings.tablet_threshold"));
    s.set_tr_language(t("settings.language"));
    s.set_tr_printer(t("settings.printer"));
    s.set_tr_device_code_hint(t("settings.device_code_hint"));
    s.set_tr_device_code_caption(t("settings.device_code_caption"));
    s.set_tr_printer_hint(t("settings.printer_hint"));
    s.set_tr_printer_epson(t("settings.printer_epson"));
    s.set_tr_printer_star(t("settings.printer_star"));
    s.set_tr_print(t("receipt.print"));
    s.set_tr_printing(t("receipt.printing"));
    s.set_tr_printed(t("receipt.printed"));
    s.set_tr_print_failed(t("receipt.print_failed"));
    s.set_tr_no_printer(t("receipt.no_printer"));
    s.set_tr_till(t("settings.till"));
    s.set_tr_till_default(t("settings.till_default"));
    s.set_tr_choose_station(t("setup.choose_station"));
    s.set_tr_lan(t("settings.lan"));
    s.set_tr_lan_hub_hint(t("settings.lan_hub_hint"));
    s.set_tr_lan_caption(t("settings.lan_caption"));
    s.set_tr_lan_active(t("settings.lan_active"));
    s.set_tr_lan_offline(t("settings.lan_offline"));
    s.set_tr_lan_peers(t("settings.lan_peers"));
    s.set_tr_device(t("settings.device"));
    s.set_tr_reconfigure(t("settings.reconfigure"));
    s.set_tr_diagnostics(t("settings.diagnostics"));
    s.set_tr_version(t("settings.version"));
    s.set_tr_server(t("settings.server"));
    s.set_tr_pending(t("settings.pending"));
    s.set_tr_realtime(t("settings.realtime"));
    s.set_tr_realtime_on(t("settings.realtime_on"));
    s.set_tr_realtime_off(t("settings.realtime_off"));
    s.set_tr_recent_warnings(t("settings.recent_warnings"));
    s.set_tr_clear(t("settings.clear"));
    s.set_tr_sign_out(t("settings.sign_out"));
    s.set_locale_is_en(core.locale().starts_with("en"));

    let y = ui.global::<SyncState>();
    y.set_tr_title(t("sync.title"));
    y.set_tr_retry(t("sync.retry"));
    y.set_tr_push(t("sync.push"));
    y.set_tr_pushing(t("sync.pushing"));
    y.set_tr_empty(t("sync.empty"));
    y.set_tr_attempts(t("sync.attempts"));
    y.set_tr_failed(t("sync.failed"));
    y.set_tr_sending(t("sync.sending"));
    y.set_tr_queued(t("sync.queued"));
}

// ── Mirrors ──────────────────────────────────────────────────────────────────

fn set_print_state(app: &Arc<App>, state: i32) {
    on_ui(app, move |ui, _| {
        ui.global::<SettingsState>().set_print_state(state)
    });
}

/// Re-read the config mirror after a device write (the Dart
/// `state.copyWith(config: _bridge.deviceConfig())`), plus the live LAN
/// relay row (`bridge.lanActive()` / `lanPeerCount()` are read per build in
/// Dart — here they refresh with every mirror pass).
fn refresh_config_mirror(app: &Arc<App>) {
    on_ui(app, |ui, app| {
        let config = app.core.device_config();
        let s = ui.global::<SettingsState>();
        s.set_till_id(config.till_id.unwrap_or_default().into());
        s.set_station_id(config.station_id.unwrap_or_default().into());
        s.set_brand_star(config.printer_brand.as_deref() == Some("star"));
        s.set_lan_active(app.core.lan_active());
        s.set_lan_peer_count(app.core.lan_peer_count() as i32);
    });
}

/// Seed the screen the way the Flutter screen's `initState` does (text
/// controllers from the config) and prime everything else (`load()`).
/// Call when routing to the settings screen.
pub fn open_settings(app: &Arc<App>) {
    on_ui(app, |ui, app| {
        let core = &app.core;
        let config = core.device_config();
        apply_settings_strings(&ui, core);
        let s = ui.global::<SettingsState>();
        // initState: controllers seeded once per mount.
        s.set_device_code(core.device_code().into());
        s.set_printer_address(printer_address_of(&config).into());
        s.set_lan_hub(config.lan_hub.clone().unwrap_or_default().into());
        s.set_brand_star(config.printer_brand.as_deref() == Some("star"));
        // Fresh mount starts clean (no stale error banner or print status).
        s.set_error(SharedString::new());
        s.set_print_state(PRINT_IDLE);
        // Orientation: desktop has no rotation lock — the flip row hides
        // (canFlip=false, the phone behavior); the threshold row still
        // renders with the OrientationController default (7") mirrored.
        s.set_can_flip(false);
        s.set_landscape_right(true);
        s.set_tablet_threshold(7.0);
        s.set_tablet_threshold_label(threshold_label(7.0).into());
    });
    settings_load(app);
}

/// Prime the screen: shift (sign-out/reconfigure guards + account card),
/// the till or station list, pending count, and the diagnostics feed.
/// Sets the state whole, so a fresh mount starts clean. Bridge failures are
/// swallowed (the Dart `_quiet`) — settings must render offline with
/// whatever's cached.
fn settings_load(app: &Arc<App>) {
    let app = app.clone();
    rt().spawn(async move {
        let core = app.core.clone();
        let config = core.device_config();
        let shift = core.current_shift().ok().flatten();
        let is_kitchen = core
            .current_session()
            .map(|s| s.role == "kitchen")
            .unwrap_or(false);
        let tills = if is_kitchen {
            Vec::new()
        } else {
            core.list_tills().await.unwrap_or_default()
        };
        let stations = if is_kitchen {
            core.kds_list_stations().await.unwrap_or_default()
        } else {
            Vec::new()
        };
        let pending = core.pending_outbox_count().unwrap_or(0);
        let diagnostics = core.recent_logs();

        let teller = shift.as_ref().map(|s| s.teller_name.clone()).unwrap_or_default();
        let initial = teller
            .chars()
            .next()
            .map(|c| c.to_uppercase().to_string())
            .unwrap_or_else(|| "?".to_string());
        let has_open_shift = shift.as_ref().map(|s| s.is_open).unwrap_or(false);
        let role = core
            .current_session()
            .map(|s| s.role)
            .unwrap_or_default();

        on_ui(&app, move |ui, app| {
            let s = ui.global::<SettingsState>();
            s.set_teller_name(teller.into());
            s.set_avatar_initial(initial.into());
            s.set_has_open_shift(has_open_shift);
            s.set_branch_name(config.branch_name.clone().unwrap_or_default().into());
            // Role chip: `role.replaceAll('_', ' ').toUpperCase()`.
            s.set_role_label(role.replace('_', " ").to_uppercase().into());
            s.set_is_kitchen(is_kitchen);
            s.set_till_id(config.till_id.clone().unwrap_or_default().into());
            s.set_station_id(config.station_id.clone().unwrap_or_default().into());
            s.set_tills(ModelRc::new(VecModel::from(
                tills
                    .iter()
                    .map(|t| SettingsTillData { id: t.id.clone().into(), name: t.name.clone().into() })
                    .collect::<Vec<_>>(),
            )));
            s.set_stations(ModelRc::new(VecModel::from(
                stations
                    .iter()
                    .map(|t| SettingsStationData { id: t.id.clone().into(), name: t.name.clone().into() })
                    .collect::<Vec<_>>(),
            )));
            s.set_pending(pending as i32);
            // Diagnostics feed — the screen shows `.take(15)`.
            s.set_diagnostics(ModelRc::new(VecModel::from(
                diagnostics
                    .iter()
                    .take(15)
                    .map(|d| SettingsDiagData {
                        message: d.message.clone().into(),
                        at: d.at.clone().into(),
                        level: d.level.clone().into(),
                    })
                    .collect::<Vec<_>>(),
            )));
            s.set_version(madar_core::core_version().into());
            s.set_server(app.core.base_url().into());
            s.set_realtime_on(app.core.is_realtime_subscribed());
            s.set_lan_active(app.core.lan_active());
            s.set_lan_peer_count(app.core.lan_peer_count() as i32);
            // Fresh state — no stale error banner or print status.
            s.set_error(SharedString::new());
            s.set_print_state(PRINT_IDLE);
        });
    });
}

/// Persist the printer (split "host:port" + brand wire name) and re-read
/// the config mirror (the Dart `persistPrinter`).
fn persist_printer(app: &Arc<App>, address: String, star: bool) {
    let (host, port) = parse_printer(&address);
    let wire = if star { "star" } else { "epson" };
    let _ = app.core.set_device_printer(
        if host.is_empty() { None } else { Some(host) },
        Some(port),
        Some(wire.to_string()),
    );
    refresh_config_mirror(app);
}

/// A zero-total single-line receipt for the test page (printed content, not
/// UI chrome — the natives print receipts only, so no i18n key exists for
/// it).
fn test_receipt(teller_name: Option<String>) -> ReceiptView {
    ReceiptView {
        local_order_id: "test-print".into(),
        order_number: None,
        order_ref: None,
        is_voided: false,
        lines: vec![ReceiptLineView {
            name: "TEST".into(),
            qty: 1,
            size_label: None,
            line_total_minor: 0,
            is_bundle: false,
            addons: Vec::new(),
            optionals: Vec::new(),
            components: Vec::new(),
        }],
        payment_label: "—".into(),
        subtotal_minor: 0,
        discount_minor: 0,
        tax_minor: 0,
        delivery_fee_minor: 0,
        total_minor: 0,
        tip_minor: 0,
        amount_tendered_minor: 0,
        change_minor: 0,
        is_cash: false,
        customer_name: None,
        teller_name,
        is_delivery: false,
        delivery_channel: None,
        customer_phone: None,
        delivery_address: None,
        delivery_zone: None,
        delivery_ref: None,
        payment_hint: None,
        delivery_notes: None,
        queued_offline: false,
        created_at: chrono::Utc::now().to_rfc3339(),
    }
}

/// Render a tiny TEST receipt in the core and stream it to the configured
/// printer — proves host/port/brand end-to-end (the Dart `testPrint`).
fn test_print(app: &Arc<App>) {
    let config = app.core.device_config();
    let host = config
        .printer_host
        .as_deref()
        .unwrap_or("")
        .trim()
        .to_string();
    if host.is_empty() {
        set_print_state(app, PRINT_NO_PRINTER);
        return;
    }
    set_print_state(app, PRINT_PRINTING);
    let app = app.clone();
    rt().spawn(async move {
        let session = app.core.current_session();
        let brand = if config.printer_brand.as_deref() == Some("star") {
            PrinterBrand::Star
        } else {
            PrinterBrand::Epson
        };
        let bytes = app.core.render_receipt(
            test_receipt(session.as_ref().map(|s| s.display_name.clone())),
            config.branch_name.clone().unwrap_or_default(),
            session
                .as_ref()
                .map(|s| s.currency_code.clone())
                .unwrap_or_default(),
            RECEIPT_CHARS,
            brand,
        );
        let port = config.printer_port.unwrap_or(JETDIRECT_PORT);
        match app.core.send_to_printer(host, port, bytes).await {
            Ok(()) => set_print_state(&app, PRINT_PRINTED),
            Err(e) => {
                // Failure detail rides the diagnostics feed; the status line
                // shows the localized "print failed" like the Dart port.
                let _ = human_message(&app.core, &e);
                set_print_state(&app, PRINT_FAILED);
            }
        }
    });
}

// ── Sync center ──────────────────────────────────────────────────────────────

/// Seed + load the sync screen. Call when routing to it.
pub fn open_sync(app: &Arc<App>) {
    on_ui(app, |ui, app| apply_settings_strings(&ui, &app.core));
    sync_load(app);
}

/// Re-read the outbox rows (the Dart `SyncNotifier.load`).
fn sync_load(app: &Arc<App>) {
    let app = app.clone();
    rt().spawn(async move {
        let outbox = app.core.list_outbox().unwrap_or_default();
        let loc_op = |op: &str| -> String {
            // Localized op-type label; unknown ops show their raw wire name.
            match op {
                "open_shift" => app.core.tr("sync.op_open_shift".into()),
                "close_shift" => app.core.tr("sync.op_close_shift".into()),
                "create_order" => app.core.tr("sync.op_create_order".into()),
                _ => op.to_string(),
            }
        };
        let has_failed = outbox.iter().any(|i| i.status == "dead");
        let rows: Vec<SyncOutboxData> = outbox
            .iter()
            .map(|i| SyncOutboxData {
                id: i.id.clone().into(),
                op: i.op_type.clone().into(),
                op_label: loc_op(&i.op_type).into(),
                status: i.status.clone().into(),
                error: i.last_error.clone().unwrap_or_default().into(),
                attempts: i.attempts as i32,
            })
            .collect();
        on_ui(&app, move |ui, _| {
            let y = ui.global::<SyncState>();
            y.set_outbox(ModelRc::new(VecModel::from(rows)));
            y.set_has_failed(has_failed);
        });
    });
}

// ── Intents — wire once at boot. ─────────────────────────────────────────────

pub fn wire_settings(app_window: &AppWindow, app: &Arc<App>) {
    let st = app_window.global::<SettingsState>();

    // Appearance — drives the theme global (the Flutter darkModeProvider;
    // desktop has no prefs vault yet, so the choice is session-scoped).
    {
        let a = app.clone();
        st.on_set_dark(move |dark| {
            if let Some(ui) = a.ui.upgrade() {
                ui.global::<T>().set_dark(dark);
            }
        });
    }

    // Language — live en/ar switch; strings + RTL re-resolve in place.
    {
        let a = app.clone();
        st.on_set_locale(move |locale| {
            a.core.set_locale(locale.to_string());
            on_ui(&a, |ui, app| {
                crate::apply_strings(&ui, &app.core); // shared app strings
                apply_settings_strings(&ui, &app.core);
            });
        });
    }

    // Orientation flip — mirror-only on desktop (no rotation lock to drive).
    {
        let a = app.clone();
        st.on_flip_orientation(move || {
            if let Some(ui) = a.ui.upgrade() {
                let s = ui.global::<SettingsState>();
                s.set_landscape_right(!s.get_landscape_right());
            }
        });
    }
    {
        let a = app.clone();
        st.on_set_tablet_threshold(move |inches| {
            if let Some(ui) = a.ui.upgrade() {
                let s = ui.global::<SettingsState>();
                s.set_tablet_threshold(inches);
                s.set_tablet_threshold_label(threshold_label(inches).into());
            }
        });
    }

    // Persist this till's device code per keystroke (the core sanitizes;
    // blank is ignored and keeps the current code).
    {
        let a = app.clone();
        st.on_set_device_code(move |code| a.core.set_device_code(code.to_string()));
    }

    // Printer host per keystroke (brand unchanged).
    {
        let a = app.clone();
        st.on_printer_changed(move |address| {
            let star = a
                .ui
                .upgrade()
                .map(|ui| ui.global::<SettingsState>().get_brand_star())
                .unwrap_or(false);
            persist_printer(&a, address.to_string(), star);
        });
    }

    // Brand chip — flips the chip and persists with the live host text.
    {
        let a = app.clone();
        st.on_pick_brand(move |wire, address| {
            let star = wire.as_str() == "star";
            if let Some(ui) = a.ui.upgrade() {
                ui.global::<SettingsState>().set_brand_star(star);
            }
            persist_printer(&a, address.to_string(), star);
        });
    }

    {
        let a = app.clone();
        st.on_test_print(move || test_print(&a));
    }

    // Bind this device's till (drawer); "" = the branch default.
    {
        let a = app.clone();
        st.on_bind_till(move |id| {
            let till = Some(id.to_string()).filter(|s| !s.is_empty());
            let _ = a.core.set_device_till(till);
            refresh_config_mirror(&a);
        });
    }

    // Bind this device's kitchen station (KDS devices). The station rides
    // the route, so the shell re-reads (the Dart `shell.refresh()`).
    {
        let a = app.clone();
        st.on_bind_station(move |id| {
            let _ = a.core.set_device_station(Some(id.to_string()));
            refresh_config_mirror(&a);
            crate::route_refresh(&a);
        });
    }

    // Persist a manual LAN hub address; empty clears it. The core registers
    // it live if the relay is already running.
    {
        let a = app.clone();
        st.on_set_lan_hub(move |value| {
            let trimmed = value.trim().to_string();
            let _ = a
                .core
                .set_device_lan_hub(Some(trimmed).filter(|s| !s.is_empty()));
            refresh_config_mirror(&a);
        });
    }

    // Re-provisioning is only allowed with a closed drawer (the natives'
    // guard). Pops first, then refreshes the shell — the route flips to
    // DeviceSetup on the shell subtree, not under this overlay.
    {
        let a = app.clone();
        st.on_reconfigure(move || {
            if let Some(ui) = a.ui.upgrade() {
                let s = ui.global::<SettingsState>();
                if s.get_has_open_shift() {
                    s.set_error(a.core.tr("settings.reconfigure_shift_open".into()).into());
                    return;
                }
                let _ = a.core.start_reconfigure();
                s.invoke_back();
                crate::route_refresh(&a);
            }
        });
    }

    // Sign-out (→ login) requires a closed drawer first. Tears down the
    // realtime subscription + LAN relay, then the session (outbox kept).
    {
        let a = app.clone();
        st.on_sign_out(move || {
            if let Some(ui) = a.ui.upgrade() {
                let s = ui.global::<SettingsState>();
                if s.get_has_open_shift() {
                    s.set_error(a.core.tr("settings.sign_out_shift_open".into()).into());
                    return;
                }
                a.core.unsubscribe_realtime();
                a.core.lan_stop();
                let _ = a.core.logout(false);
                s.invoke_back();
                crate::route_refresh(&a);
            }
        });
    }

    // Clear the recent-warnings feed.
    {
        let a = app.clone();
        st.on_clear_diagnostics(move || {
            a.core.clear_logs();
            if let Some(ui) = a.ui.upgrade() {
                ui.global::<SettingsState>()
                    .set_diagnostics(ModelRc::new(VecModel::from(Vec::<SettingsDiagData>::new())));
            }
        });
    }

    // ── Sync center intents ──────────────────────────────────────────────────
    let sy = app_window.global::<SyncState>();

    // Requeue every FAILED (dead) command and try to send now.
    {
        let a = app.clone();
        sy.on_retry(move || {
            let a = a.clone();
            rt().spawn(async move {
                let _ = a.core.retry_outbox().await;
                sync_load(&a);
            });
        });
    }

    // Manual PUSH of the durable outbox — force-drains every QUEUED (not
    // just failed) command. Pings first so a queue parked offline re-probes
    // connectivity + the auth-park, then drains. Concurrent taps ignored.
    {
        let a = app.clone();
        sy.on_sync_now(move || {
            if let Some(ui) = a.ui.upgrade() {
                let y = ui.global::<SyncState>();
                if y.get_pushing() {
                    return;
                }
                y.set_pushing(true);
            }
            let a = a.clone();
            rt().spawn(async move {
                let _ = a.core.refresh_connectivity().await;
                let _ = a.core.sync_now().await;
                on_ui(&a, |ui, _| ui.global::<SyncState>().set_pushing(false));
                sync_load(&a);
            });
        });
    }

    // Discard a single DEAD command (the teller gives up on it).
    {
        let a = app.clone();
        sy.on_discard(move |id| {
            let _ = a.core.discard_outbox_item(id.to_string());
            sync_load(&a);
        });
    }
}
