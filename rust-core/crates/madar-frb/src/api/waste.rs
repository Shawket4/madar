//! Waste from the teller app (phase 6). Pure delegation to madar-core; owns
//! the waste view mirrors.
use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

pub use madar_core::approvals::{ActDecisionView, ApprovalView};
pub use madar_core::waste::{
    WasteIngredientView, WasteInput, WasteItemView, WasteLineView, WastePreviewView,
    WasteReasonView, WasteRecordedView,
};

#[frb(mirror(WasteReasonView))]
pub struct _WasteReasonView {
    pub key: String,
    pub label: String,
}

/// An ingredient the person may waste.
#[frb(mirror(WasteIngredientView))]
pub struct _WasteIngredientView {
    pub id: String,
    pub name: String,
    pub unit: String,
    pub units: Vec<String>,
}

/// A menu item with a recipe.
#[frb(mirror(WasteItemView))]
pub struct _WasteItemView {
    pub id: String,
    pub name: String,
    pub sizes: Vec<String>,
}

/// What the person has picked so far.
#[frb(mirror(WasteInput))]
pub struct _WasteInput {
    pub subject_kind: String,
    pub subject_id: String,
    pub size_label: Option<String>,
    pub quantity: f64,
    pub unit: String,
    pub reason: String,
    pub note: Option<String>,
}

#[frb(mirror(WasteLineView))]
pub struct _WasteLineView {
    pub name: String,
    pub quantity: f64,
    pub unit: String,
}

/// The waste's lines, value and whether the person may record it.
#[frb(mirror(WastePreviewView))]
pub struct _WastePreviewView {
    pub lines: Vec<WasteLineView>,
    pub value_minor: Option<i64>,
    pub value_partial: bool,
    pub decision: ActDecisionView,
}

#[frb(mirror(WasteRecordedView))]
pub struct _WasteRecordedView {
    pub id: String,
    pub subject_name: String,
    pub quantity: f64,
    pub unit: String,
    pub value_minor: Option<i64>,
}

impl MadarBridge {
    /// Whether the waste screen is offered (held, or ask-a-manager).
    #[frb(sync)]
    pub fn can_record_waste(&self) -> bool {
        self.inner.can_record_waste()
    }

    #[frb(sync)]
    pub fn waste_reasons(&self) -> Vec<WasteReasonView> {
        self.inner.waste_reasons()
    }

    /// Catalog ingredients matching a name. Offline.
    #[frb(sync)]
    pub fn waste_ingredients(&self, query: String) -> Result<Vec<WasteIngredientView>, MadarError> {
        self.inner.waste_ingredients(query).map_err(MadarError::from)
    }

    /// Menu items with a recipe matching a name. Offline.
    #[frb(sync)]
    pub fn waste_items(&self, query: String) -> Result<Vec<WasteItemView>, MadarError> {
        self.inner.waste_items(query).map_err(MadarError::from)
    }

    /// Lines, value and decision for what is picked. Offline.
    #[frb(sync)]
    pub fn preview_waste(&self, input: WasteInput) -> Result<WastePreviewView, MadarError> {
        self.inner.preview_waste(input).map_err(MadarError::from)
    }

    /// A manager approves this waste with their PIN.
    pub fn approve_waste(
        &self,
        approver_pin: String,
        input: WasteInput,
    ) -> Result<ApprovalView, MadarError> {
        self.inner.approve_waste(approver_pin, input).map_err(MadarError::from)
    }

    /// Record the waste (queued; works offline).
    pub fn record_waste(
        &self,
        input: WasteInput,
        approval: Option<ApprovalView>,
    ) -> Result<WasteRecordedView, MadarError> {
        self.inner.record_waste(input, approval).map_err(MadarError::from)
    }
}
