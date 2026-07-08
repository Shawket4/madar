//! Device binding + LAN relay bindings — the per-device config (branch / till /
//! station / printer / managed code), reconfigure/clear flows, the Phase E LAN
//! relay controls, and the device-setup branch picker. Pure delegation to
//! madar-core; owns the `DeviceConfigView` and `BranchView` mirrors.
use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

pub use madar_core::device::DeviceConfigView;
pub use madar_core::session::BranchView;

/// The FFI view the host reads to render device-setup / Settings (and to know which
/// screen chrome to show). `configured` is the derived "ready to use" bit.
#[frb(mirror(DeviceConfigView))]
pub struct _DeviceConfigView {
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

/// A selectable branch (device-setup picker).
#[frb(mirror(BranchView))]
pub struct _BranchView {
    pub id: String,
    pub name: String,
    pub is_active: bool,
    pub org_logo_url: Option<String>,
}

impl MadarBridge {
    // ── device binding (branch / till / station / printer) ────────────────

    /// The device's current binding (for device-setup / Settings + screen chrome).
    #[frb(sync)]
    pub fn device_config(&self) -> DeviceConfigView {
        self.inner.device_config()
    }

    /// Bind the device to a branch (device setup). Clears the reconfigure flag.
    pub fn set_device_branch(
        &self,
        branch_id: String,
        branch_name: Option<String>,
    ) -> Result<(), MadarError> {
        self.inner
            .set_device_branch(branch_id, branch_name)
            .map_err(MadarError::from)
    }

    /// Bind the device's till (POS drawer). `None` = use the branch default till.
    pub fn set_device_till(&self, till_id: Option<String>) -> Result<(), MadarError> {
        self.inner
            .set_device_till(till_id)
            .map_err(MadarError::from)
    }

    /// Bind the device's kitchen station (a KDS device). `None` clears it.
    pub fn set_device_station(&self, station_id: Option<String>) -> Result<(), MadarError> {
        self.inner
            .set_device_station(station_id)
            .map_err(MadarError::from)
    }

    /// Set the device's receipt/chit printer (host:port + brand `"epson"`/`"star"`).
    /// `None` host clears it.
    pub fn set_device_printer(
        &self,
        host: Option<String>,
        port: Option<u16>,
        brand: Option<String>,
    ) -> Result<(), MadarError> {
        self.inner
            .set_device_printer(host, port, brand)
            .map_err(MadarError::from)
    }

    /// Pick the printer transport — `"bluetooth"` (Classic SPP) or `"lan"`
    /// (raw-TCP, the default). Only the active transport's binding is used at
    /// print time; the other is retained so switching back is lossless.
    pub fn set_device_printer_transport(&self, kind: String) -> Result<(), MadarError> {
        self.inner
            .set_device_printer_transport(kind)
            .map_err(MadarError::from)
    }

    /// Bind the paired Bluetooth printer (MAC `address` + cached display `name`).
    /// `None` address clears it. The core stores the binding; the Flutter
    /// transport opens the socket.
    pub fn set_device_printer_bt(
        &self,
        address: Option<String>,
        name: Option<String>,
    ) -> Result<(), MadarError> {
        self.inner
            .set_device_printer_bt(address, name)
            .map_err(MadarError::from)
    }

    /// Pin the receipt raster width in dots (Settings paper-size toggle): 384 for
    /// a 58 mm roll, 576 for 80 mm. `None` clears it → the width falls back to the
    /// transport default (Bluetooth → 384, LAN → 576).
    pub fn set_device_printer_paper(&self, dots: Option<u32>) -> Result<(), MadarError> {
        self.inner
            .set_device_printer_paper(dots)
            .map_err(MadarError::from)
    }

    /// This device's managed code — the `<DEVICE>` segment of every order_ref.
    /// Auto-assigned (stable random) on first use; the manager renames it in
    /// Settings (e.g. `T1`/`W2`/`K1`) so a branch's devices are distinct.
    #[frb(sync)]
    pub fn device_code(&self) -> String {
        self.inner.device_code()
    }

    /// Set this device's managed code (Settings). Sanitized to short A-Z0-9; an
    /// empty/blank value is ignored (keeps the current code).
    #[frb(sync)]
    pub fn set_device_code(&self, code: String) {
        self.inner.set_device_code(code);
    }

    /// Re-enter device setup (keeps the binding but forces the setup screen until
    /// `set_device_branch` confirms a — possibly new — branch).
    pub fn start_reconfigure(&self) -> Result<(), MadarError> {
        self.inner.start_reconfigure().map_err(MadarError::from)
    }

    /// Wipe the device binding entirely (factory reset of the device config).
    pub fn clear_device(&self) -> Result<(), MadarError> {
        self.inner.clear_device().map_err(MadarError::from)
    }

    // ── LAN relay control (Phase E) ────────────────────────────────────────

    /// Persist a manual LAN hub-IP (`host` or `host:port`) in the device config and,
    /// if the relay is running, register it immediately. `None`/empty clears it.
    pub fn set_device_lan_hub(&self, hub: Option<String>) -> Result<(), MadarError> {
        self.inner.set_device_lan_hub(hub).map_err(MadarError::from)
    }

    /// Start the LAN relay for the signed-in branch (idempotent). Needs a session +
    /// the cached bundle's LAN secret; binds the embedded server, begins discovery
    /// (mDNS + UDP beacon), advertises this till's open shift, and wires any manual
    /// hub. Safe to call after every login — a no-op if already running.
    pub async fn lan_start(&self) -> Result<(), MadarError> {
        self.inner.lan_start().await.map_err(MadarError::from)
    }

    /// Stop + tear down the LAN relay (idempotent). Call on logout / branch switch.
    pub fn lan_stop(&self) {
        self.inner.lan_stop();
    }

    /// Whether the LAN relay is currently running.
    #[frb(sync)]
    pub fn lan_active(&self) -> bool {
        self.inner.lan_active()
    }

    /// Live discovered peers + manual hubs (a "LAN: N devices" diagnostics chip).
    #[frb(sync)]
    pub fn lan_peer_count(&self) -> u32 {
        self.inner.lan_peer_count()
    }

    /// The LAN shift-open gate: is a till at this branch advertising a FRESH open
    /// shift right now? The freshest "is the branch operating" signal (it beats the
    /// backend, which may not yet know a till opened/closed). `false` if not running.
    #[frb(sync)]
    pub fn lan_branch_has_open_till(&self) -> bool {
        self.inner.lan_branch_has_open_till()
    }

    // ── branches (device-setup picker) ─────────────────────────────────────

    /// List the org's active branches — for the device-setup picker. Requires a
    /// live (manager) session; online-only.
    pub async fn list_branches(&self) -> Result<Vec<BranchView>, MadarError> {
        self.inner.list_branches().await.map_err(MadarError::from)
    }
}
