//! Mirrored madar-core records for the dashboard FRB surface. Each `_Type` is a
//! field-for-field copy that FRB codegen validates against the REAL (re-exported)
//! type — any drift in madar-core becomes a compile error here.
use flutter_rust_bridge::frb;

pub use madar_core::plan::EntitlementsView;
pub use madar_core::session::{BranchView, SessionSnapshot};
pub use madar_core::{ActiveScopeView, MadarConfig};

#[frb(mirror(MadarConfig))]
pub struct _MadarConfig {
    pub base_url: String,
    pub environment: String,
    pub db_path: String,
    pub locale: String,
    pub app_version: Option<String>,
}

#[frb(mirror(SessionSnapshot))]
pub struct _SessionSnapshot {
    pub user_id: String,
    pub display_name: String,
    pub role: String,
    pub org_id: Option<String>,
    pub branch_id: Option<String>,
    pub currency_code: String,
    pub tax_rate: f64,
    pub tax_inclusive: bool,
    pub service_charge_rate: f64,
    pub service_charge_taxable: bool,
    pub require_table_for_orders: bool,
    pub online: bool,
    pub permissions_loaded: bool,
}

#[frb(mirror(BranchView))]
pub struct _BranchView {
    pub id: String,
    pub name: String,
    pub is_active: bool,
    pub org_logo_url: Option<String>,
}

#[frb(mirror(ActiveScopeView))]
pub struct _ActiveScopeView {
    pub org_id: Option<String>,
    pub branch_id: Option<String>,
}

/// What the organisation's plan switches on: hide a nav entry or lock a page
/// from `features`, never from the plan's name. `till_inactive` is a POS
/// notion (always false here).
#[frb(mirror(EntitlementsView))]
pub struct _EntitlementsView {
    /// `free` | `paid`.
    pub plan: String,
    pub features: Vec<String>,
    pub realtime: bool,
    pub max_branches: Option<u32>,
    pub max_pos_devices_per_branch: Option<u32>,
    pub max_kds_devices: Option<u32>,
    pub max_waiter_devices: Option<u32>,
    pub till_inactive: bool,
}
