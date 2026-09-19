//! The staff drinks pool (owner design 2026-09-19): today's allowance, the
//! verdict on one drink, and recording it. Pure delegation to madar-core; owns
//! the view mirrors.
//!
//! Everything the sheet shows arrives already decided and already worded — the
//! refusal, the over-allowance warning, "3 left today". Dart sequences; it does
//! not count, compare dates or pick a string.
use flutter_rust_bridge::frb;

use crate::api::approvals::{ActDecisionView, ApprovalView};
use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

pub use madar_core::staff_drink::{
    StaffDrinkInput, StaffDrinkLineView, StaffDrinkPreviewView, StaffDrinkRecordedView,
    StaffPoolTodayView,
};
pub use madar_core::staff_pool::{StaffDrinkDecision, StaffDrinkRefusal, StaffPoolDay};

/// A branch's pool as it stands on one business day.
#[frb(mirror(StaffPoolDay))]
pub struct _StaffPoolDay {
    pub business_date: String,
    pub allowance: i32,
    pub used: i32,
    pub remaining: i32,
    pub over: i32,
}

/// Why a staff drink was refused. An overspend is never one of these.
#[frb(mirror(StaffDrinkRefusal))]
pub enum _StaffDrinkRefusal {
    PoolOff,
    NoEligibleItems,
    ItemNotEligible,
    NoteRequired,
}

/// The verdict on one drink, from the engine both sides share.
#[frb(mirror(StaffDrinkDecision))]
pub struct _StaffDrinkDecision {
    pub allowed: bool,
    pub refusal: Option<StaffDrinkRefusal>,
    pub overspent: bool,
    pub pool: StaffPoolDay,
}

/// What the person has picked: the cart line, and their words.
#[frb(mirror(StaffDrinkInput))]
pub struct _StaffDrinkInput {
    pub menu_item_id: String,
    pub size_label: Option<String>,
    pub quantity: i32,
    pub note: String,
    pub order_id: Option<String>,
}

/// The branch's pool as this device holds it today.
#[frb(mirror(StaffPoolTodayView))]
pub struct _StaffPoolTodayView {
    pub on: bool,
    pub pool: StaffPoolDay,
    pub eligible_item_ids: Vec<String>,
    pub pool_label: String,
    pub resets_label: String,
}

/// The verdict before committing, with everything the sheet needs worded.
#[frb(mirror(StaffDrinkPreviewView))]
pub struct _StaffDrinkPreviewView {
    pub offered: bool,
    pub access: ActDecisionView,
    pub decision: StaffDrinkDecision,
    pub reason: String,
    pub over_warning: String,
    pub pool_label: String,
}

/// What was written.
#[frb(mirror(StaffDrinkRecordedView))]
pub struct _StaffDrinkRecordedView {
    pub id: String,
    pub item_name: String,
    pub quantity: i32,
    pub overspent: bool,
    pub pool: StaffPoolDay,
    pub message: String,
}

/// One drink on today's list.
#[frb(mirror(StaffDrinkLineView))]
pub struct _StaffDrinkLineView {
    pub id: String,
    pub item_name: String,
    pub size_label: Option<String>,
    pub quantity: i32,
    pub note: String,
    pub overspent: bool,
    pub recorded_at: String,
    pub queued: bool,
}

impl MadarBridge {
    /// The action is offered at all (held, or ask-a-manager).
    #[frb(sync)]
    pub fn can_record_staff_drink(&self) -> bool {
        self.inner.can_record_staff_drink()
    }

    /// `allow` / `needs_approval` / `deny` for the signed-in person.
    #[frb(sync)]
    pub fn staff_drink_access(&self) -> ActDecisionView {
        self.inner.staff_drink_access()
    }

    /// The branch's pool for its business day. Local; no network.
    #[frb(sync)]
    pub fn staff_pool_today(&self) -> Result<StaffPoolTodayView, MadarError> {
        self.inner.staff_pool_today().map_err(MadarError::from)
    }

    /// The verdict on this drink before it is committed.
    #[frb(sync)]
    pub fn preview_staff_drink(
        &self,
        input: StaffDrinkInput,
    ) -> Result<StaffDrinkPreviewView, MadarError> {
        self.inner.preview_staff_drink(input).map_err(MadarError::from)
    }

    /// Today's drinks, oldest first.
    #[frb(sync)]
    pub fn staff_drinks_today(&self) -> Result<Vec<StaffDrinkLineView>, MadarError> {
        self.inner.staff_drinks_today().map_err(MadarError::from)
    }

    /// A manager unlocks this act with their PIN.
    pub fn approve_staff_drink(&self, approver_pin: String) -> Result<ApprovalView, MadarError> {
        self.inner.approve_staff_drink(approver_pin).map_err(MadarError::from)
    }

    /// Put the drink on the branch's pool (queued; works offline).
    pub async fn record_staff_drink(
        &self,
        input: StaffDrinkInput,
        approval: Option<ApprovalView>,
    ) -> Result<StaffDrinkRecordedView, MadarError> {
        self.inner.record_staff_drink(input, approval).await.map_err(MadarError::from)
    }
}
