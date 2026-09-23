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
use crate::api::cart::{CartLineView, CartStaffSummary};
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
    /// The cart line asked about, when it is ALREADY marked (so it does not
    /// count its own units against the pool).
    pub line_key: Option<String>,
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
    pub comp_minor: Option<i64>,
    pub extras_minor: Option<i64>,
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

    /// MARK a counter-cart line as a staff drink (note REQUIRED). Nothing is
    /// spent: the pool entry is written when the order is charged. Returns the
    /// cart's lines — the marked line has a new key.
    pub fn mark_staff_drink(
        &self,
        table_id: Option<String>,
        line_key: String,
        note: String,
        approval: Option<ApprovalView>,
    ) -> Result<Vec<CartLineView>, MadarError> {
        self.inner.mark_staff_drink(table_id, line_key, note, approval).map_err(MadarError::from)
    }

    /// Change a marked line's note (still required).
    pub fn edit_staff_drink_note(
        &self,
        table_id: Option<String>,
        line_key: String,
        note: String,
    ) -> Result<Vec<CartLineView>, MadarError> {
        self.inner.edit_staff_drink_note(table_id, line_key, note).map_err(MadarError::from)
    }

    /// Take the mark off: the line rings at its normal price again.
    pub fn unmark_staff_drink(
        &self,
        table_id: Option<String>,
        line_key: String,
    ) -> Result<Vec<CartLineView>, MadarError> {
        self.inner.unmark_staff_drink(table_id, line_key).map_err(MadarError::from)
    }

    /// The cart's staff drinks as the Charge sheet states them. Local.
    #[frb(sync)]
    pub fn cart_staff_summary(&self, table_id: Option<String>) -> Option<CartStaffSummary> {
        self.inner.cart_staff_summary(table_id)
    }

    /// Why marks left their lines since the last ask, each already a sentence
    /// in the till's language. Re-checks the cart first. Local; no network.
    #[frb(sync)]
    pub fn take_staff_drink_notices(&self, table_id: Option<String>) -> Vec<String> {
        self.inner.take_staff_drink_notices(table_id)
    }

    /// The cart is becoming a table's bill (aimed at a table or a ticket): its
    /// staff-drink marks go. Returns the reasons, already worded.
    #[frb(sync)]
    pub fn drop_staff_marks_for_bill(&self, table_id: Option<String>) -> Vec<String> {
        self.inner.drop_staff_marks_for_bill(table_id)
    }

    /// The sentence for a sale answered by a server that does not support free
    /// staff drinks yet; `None` otherwise.
    #[frb(sync)]
    pub fn staff_old_server_notice(&self, order_id: String) -> Option<String> {
        self.inner.staff_old_server_notice(order_id)
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
