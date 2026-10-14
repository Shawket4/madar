//! The organisation's plan at the till (FREEMIUM_SPEC_2026-10-11.md §5). Pure
//! delegation to madar-core's `plan`; owns the entitlements mirror.
use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;

pub use madar_core::plan::EntitlementsView;

/// What the plan switches on. `features` are the keys the plan HAS
/// (`inventory`, `loyalty`, `online`, `bookings`, `floor`, `kitchen`, `dawam`,
/// `branding`, `basira`); a limit of `None` is unlimited. Hide a screen
/// from this, never from the plan's name.
#[frb(mirror(EntitlementsView))]
pub struct _EntitlementsView {
    /// `free` | `paid`.
    pub plan: String,
    pub features: Vec<String>,
    /// May this till hold the realtime stream. Free tills poll instead.
    pub realtime: bool,
    pub max_branches: Option<u32>,
    pub max_pos_devices_per_branch: Option<u32>,
    pub max_kds_devices: Option<u32>,
    pub max_waiter_devices: Option<u32>,
    /// The plan switched THIS till off (a downgraded organisation keeps one
    /// till per branch selling): show the "This till isn't active" screen, not
    /// the sell screen.
    pub till_inactive: bool,
}

impl MadarBridge {
    /// The plan's features and limits, and whether this till is switched off.
    /// Unknown is Paid. Local; no network. Re-read on a `catalog`/`sync` change.
    #[frb(sync)]
    pub fn entitlements(&self) -> EntitlementsView {
        self.inner.entitlements()
    }

    /// A plan refusal's words in the till's language, from the `Forbidden`
    /// resource it travels under (`plan_feature:kitchen`, `plan_device_limit`…).
    /// `None` when it is not a plan refusal.
    #[frb(sync)]
    pub fn plan_refusal_words(&self, resource: String) -> Option<String> {
        self.inner.plan_refusal_words(&resource)
    }

    /// The same sentence for a `code` and optional `feature` a host holds.
    #[frb(sync)]
    pub fn plan_refusal_message(&self, code: String, feature: Option<String>) -> Option<String> {
        self.inner.plan_refusal_message(&code, feature.as_deref())
    }
}
