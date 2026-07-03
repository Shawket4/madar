//! Mirrored madar-core records/enums. Each `_Type` below is a field-for-field
//! copy that FRB codegen validates against the REAL (re-exported) type — any
//! drift in madar-core becomes a compile error here, never silent corruption.
//! Only plain records and unit enums are mirrorable; struct-variant enums are
//! re-declared in `routes.rs` / `error.rs`.
use flutter_rust_bridge::frb;

pub use madar_core::session::{LoginMode, LoginRequest, SessionSnapshot};
pub use madar_core::shift::ShiftView;
pub use madar_core::MadarConfig;

#[frb(mirror(MadarConfig))]
pub struct _MadarConfig {
    pub base_url: String,
    pub environment: String,
    pub db_path: String,
    pub locale: String,
}

#[frb(mirror(LoginMode))]
pub enum _LoginMode {
    Pin,
    Email,
}

#[frb(mirror(LoginRequest))]
pub struct _LoginRequest {
    pub mode: LoginMode,
    pub name: Option<String>,
    pub pin: Option<String>,
    pub branch_id: Option<String>,
    pub email: Option<String>,
    pub password: Option<String>,
    pub org_id: Option<String>,
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
    pub online: bool,
    pub permissions_loaded: bool,
}

#[frb(mirror(ShiftView))]
pub struct _ShiftView {
    pub id: String,
    pub branch_id: String,
    pub teller_id: String,
    pub teller_name: String,
    pub opening_cash_minor: i64,
    pub opened_at: String,
    pub status: String,
    pub is_open: bool,
}
