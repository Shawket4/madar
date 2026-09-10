//! Mirrored madar-core records for the dashboard FRB surface. Each `_Type` is a
//! field-for-field copy that FRB codegen validates against the REAL (re-exported)
//! type — any drift in madar-core becomes a compile error here.
use flutter_rust_bridge::frb;

pub use madar_core::session::{BranchView, SessionSnapshot};
pub use madar_core::{ActiveScopeView, MadarConfig};

#[frb(mirror(MadarConfig))]
pub struct _MadarConfig {
    pub base_url: String,
    pub environment: String,
    pub db_path: String,
    pub locale: String,
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
