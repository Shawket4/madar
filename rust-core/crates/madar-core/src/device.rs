//! Device configuration — the per-device binding, owned by the CORE (not the host).
//!
//! THE ONE RULE (see lib.rs): all real logic + state lives in Rust. So the device's
//! branch, till (drawer), kitchen station, printer, and the reconfigure flag are
//! persisted HERE, in the core's SQLite kv store — NOT in Swift `UserDefaults` /
//! Kotlin `SharedPreferences`. The hosts only call the getters/setters and render.
//!
//! `app_route`, `open_shift`, `refresh_shift`, `sign_in` and printing all read this
//! config instead of taking host-passed parameters. One JSON blob under one kv key
//! keeps it a simple singleton (there is exactly one device binding per install).

use serde::{Deserialize, Serialize};

use crate::error::CoreResult;
use crate::store::Store;

/// kv key holding the device-config JSON blob.
const KEY: &str = "device_config";

/// Default raster width (dots @ 203 dpi) for a Bluetooth printer — a 58 mm
/// portable (the P300 class), ~48 mm / 384 printable dots.
const BT_PAPER_DOTS: u32 = 384;
/// Default raster width for a LAN printer — a 72 mm desktop head (Epson/Star),
/// 576 dots. Matches `render::PRINT_WIDTH`, the historical hardcoded value.
const LAN_PAPER_DOTS: u32 = 576;

/// The persisted device binding. All-`Option` because a fresh install has none of
/// it; the device-setup flow fills branch (+ till for a POS, or station for a KDS).
#[derive(Serialize, Deserialize, Default, Clone, Debug)]
pub(crate) struct DeviceConfig {
    /// The branch this device is bound to (the org is derived from it at login).
    pub branch_id: Option<String>,
    /// Cached branch display name (so the login screen shows it offline).
    pub branch_name: Option<String>,
    /// The till (drawer) a POS device opens its shift on. `None` = the branch's
    /// default till. Irrelevant for a kitchen/waiter device (no shift).
    pub till_id: Option<String>,
    /// The kitchen station a KDS device displays. Required to route a kitchen-role
    /// session to the board; unused by POS/waiter devices.
    pub station_id: Option<String>,
    /// The device's own receipt/chit printer (host:port).
    pub printer_host: Option<String>,
    pub printer_port: Option<u16>,
    /// Printer command dialect — `"epson"` (ESC/POS) or `"star"` (Star Line Mode).
    /// The two are not byte-compatible; the host maps this to the render brand.
    pub printer_brand: Option<String>,
    /// Which transport carries the rendered receipt bytes — `"lan"` (raw-TCP
    /// JetDirect, the default when `None`) or `"bluetooth"` (Classic SPP to a
    /// paired device). Picks the active binding; the two coexist so switching
    /// back doesn't lose the other's address.
    #[serde(default)]
    pub printer_transport: Option<String>,
    /// The paired Bluetooth printer's MAC address (an Android bonded device).
    /// The CORE never opens the socket — the Flutter transport does — but the
    /// binding lives here beside the network printer for one source of truth.
    #[serde(default)]
    pub printer_bt_address: Option<String>,
    /// Cached Bluetooth printer display name (so Settings shows it offline).
    #[serde(default)]
    pub printer_bt_name: Option<String>,
    /// Raster width in dots for the rendered receipt bitmap. `None` = resolve from
    /// the active transport (Bluetooth → 384 / 58 mm, LAN → 576 / 72 mm); an
    /// explicit value (the Settings paper-size toggle) always wins. Lets a 58 mm
    /// portable and an 80 mm desktop head coexist with no re-render path.
    #[serde(default)]
    pub printer_paper_dots: Option<u32>,
    /// `true` while the manager is re-running device setup — forces `DeviceSetup`
    /// even though a branch is already bound.
    #[serde(default)]
    pub reconfiguring: bool,
    /// Manual LAN-relay hub address (`host` or `host:port`), the always-works
    /// discovery fallback when mDNS + the UDP beacon are both filtered. Empty/None =
    /// rely on auto-discovery. (Phase E.)
    #[serde(default)]
    pub lan_hub: Option<String>,
}

impl DeviceConfig {
    /// Whether the device is ready to use (bound to a branch and not mid-setup).
    pub fn configured(&self) -> bool {
        self.branch_id.is_some() && !self.reconfiguring
    }

    /// Effective raster width in dots. Honors an explicit `printer_paper_dots`;
    /// otherwise defaults by transport — a Bluetooth printer is assumed to be a
    /// 58 mm portable (384 dots), LAN a 72 mm desktop head (576 dots).
    pub fn paper_dots(&self) -> u32 {
        self.printer_paper_dots.unwrap_or(match self.printer_transport.as_deref() {
            Some("bluetooth") => BT_PAPER_DOTS,
            _ => LAN_PAPER_DOTS,
        })
    }

    /// Whether the active printer has an auto-cutter. Desktop (LAN) heads do;
    /// Bluetooth portables (the P300 class) don't — so the raster feeds extra
    /// paper instead of emitting a `GS V` cut the head would choke on or ignore.
    pub fn printer_has_cutter(&self) -> bool {
        self.printer_transport.as_deref() != Some("bluetooth")
    }
}

/// Load the device config (an empty default when nothing's been set yet).
pub(crate) fn load(store: &Store) -> DeviceConfig {
    store
        .kv_get(KEY)
        .ok()
        .flatten()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

/// Persist the device config.
pub(crate) fn save(store: &Store, cfg: &DeviceConfig) -> CoreResult<()> {
    let json = serde_json::to_string(cfg).map_err(|e| crate::error::CoreError::Internal {
        detail: format!("device cfg: {e}"),
    })?;
    store.kv_put(KEY, &json)
}

/// Read-modify-write helper so each setter is a one-liner.
pub(crate) fn update(store: &Store, f: impl FnOnce(&mut DeviceConfig)) -> CoreResult<DeviceConfig> {
    let mut cfg = load(store);
    f(&mut cfg);
    save(store, &cfg)?;
    Ok(cfg)
}

/// The FFI view the host reads to render device-setup / Settings (and to know which
/// screen chrome to show). `configured` is the derived "ready to use" bit.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct DeviceConfigView {
    pub branch_id: Option<String>,
    pub branch_name: Option<String>,
    pub till_id: Option<String>,
    pub station_id: Option<String>,
    pub printer_host: Option<String>,
    pub printer_port: Option<u16>,
    pub printer_brand: Option<String>,
    pub printer_transport: Option<String>,
    pub printer_bt_address: Option<String>,
    pub printer_bt_name: Option<String>,
    pub printer_paper_dots: Option<u32>,
    pub reconfiguring: bool,
    pub lan_hub: Option<String>,
    pub configured: bool,
}

impl From<DeviceConfig> for DeviceConfigView {
    fn from(c: DeviceConfig) -> Self {
        let configured = c.configured();
        DeviceConfigView {
            branch_id: c.branch_id,
            branch_name: c.branch_name,
            till_id: c.till_id,
            station_id: c.station_id,
            printer_host: c.printer_host,
            printer_port: c.printer_port,
            printer_brand: c.printer_brand,
            printer_transport: c.printer_transport,
            printer_bt_address: c.printer_bt_address,
            printer_bt_name: c.printer_bt_name,
            printer_paper_dots: c.printer_paper_dots,
            reconfiguring: c.reconfiguring,
            lan_hub: c.lan_hub,
            configured,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::Store;

    fn store() -> Store {
        Store::open("").unwrap() // in-memory
    }

    #[test]
    fn defaults_to_unconfigured() {
        let s = store();
        let cfg = load(&s);
        assert!(cfg.branch_id.is_none());
        assert!(!cfg.configured());
    }

    #[test]
    fn round_trips_and_reconfigure_gates_configured() {
        let s = store();
        update(&s, |c| {
            c.branch_id = Some("b1".into());
            c.branch_name = Some("Main".into());
            c.station_id = Some("grill".into());
        })
        .unwrap();
        let cfg = load(&s);
        assert_eq!(cfg.branch_id.as_deref(), Some("b1"));
        assert_eq!(cfg.station_id.as_deref(), Some("grill"));
        assert!(
            cfg.configured(),
            "branch set, not reconfiguring → configured"
        );

        update(&s, |c| c.reconfiguring = true).unwrap();
        assert!(!load(&s).configured(), "mid-reconfigure → not configured");

        update(&s, |c| c.reconfiguring = false).unwrap();
        assert!(load(&s).configured());
    }
}
