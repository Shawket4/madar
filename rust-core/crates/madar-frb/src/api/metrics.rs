//! The till's Metrics screen (`reports.pos_metrics`). Delegation to madar-core
//! `metrics` only; owns the view mirrors.
use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

pub use madar_core::metrics::{
    MetricsHourView, MetricsItemView, MetricsPresetView, MetricsTenderView, PosMetricsView,
};
pub use madar_core::timefmt::DatePickerChromeView;

/// What a date-range picker draws itself with.
#[frb(mirror(DatePickerChromeView))]
pub struct _DatePickerChromeView {
    /// Today in the BRANCH timezone, `YYYY-MM-DD` — the future-date guard.
    pub today: String,
    /// 0 = Sunday … 6 = Saturday. The owner's rule is Saturday.
    pub week_start: i32,
    /// Seven column headings, already rotated so index 0 is `week_start`.
    pub weekdays: Vec<String>,
    /// Twelve month names in full, January first.
    pub months: Vec<String>,
    /// Twelve month names as a date shows them (`Sep`).
    pub months_short: Vec<String>,
}

/// A date preset chip.
#[frb(mirror(MetricsPresetView))]
pub struct _MetricsPresetView {
    pub key: String,
    pub label: String,
}

/// One payment method's takings.
#[frb(mirror(MetricsTenderView))]
pub struct _MetricsTenderView {
    pub method: String,
    pub label: String,
    pub amount_minor: i64,
    pub order_count: i64,
    /// 0..=1, the bar's length.
    pub share: f64,
}

/// One top item.
#[frb(mirror(MetricsItemView))]
pub struct _MetricsItemView {
    pub name: String,
    pub quantity: i64,
    pub revenue_minor: i64,
    /// 0..=1, the bar's length.
    pub share: f64,
}

/// One local hour.
#[frb(mirror(MetricsHourView))]
pub struct _MetricsHourView {
    pub hour: i32,
    pub label: String,
    pub order_count: i64,
    pub net_sales_minor: i64,
    /// 0..=1, the bar's height.
    pub share: f64,
}

/// Everything the Metrics screen shows.
#[frb(mirror(PosMetricsView))]
pub struct _PosMetricsView {
    pub preset: String,
    pub from_date: String,
    pub to_date: String,
    pub range_label: String,
    /// `server` · `device`.
    pub source: String,
    /// Shown as is when the figures come from this device.
    pub offline_note: Option<String>,
    pub items_note: Option<String>,
    pub currency_code: String,
    pub net_sales_minor: i64,
    pub gross_sales_minor: i64,
    pub refunded_amount_minor: i64,
    pub order_count: i64,
    pub average_ticket_minor: i64,
    pub tenders: Vec<MetricsTenderView>,
    pub voided_count: i64,
    pub voided_amount_minor: i64,
    pub refunded_orders_count: i64,
    pub refunds_issued_count: i64,
    pub refunds_issued_amount_minor: i64,
    pub top_items: Vec<MetricsItemView>,
    pub hourly: Vec<MetricsHourView>,
}

impl MadarBridge {
    /// The date presets, in order, labelled.
    #[frb(sync)]
    pub fn pos_metrics_presets(&self) -> Vec<MetricsPresetView> {
        self.inner.pos_metrics_presets()
    }

    /// The chrome a date-range picker draws itself with: today in the branch
    /// zone, the week start, and the month / weekday words in the till's
    /// language. One cheap local read; always succeeds offline.
    #[frb(sync)]
    pub fn date_picker_chrome(&self) -> DatePickerChromeView {
        self.inner.date_picker_chrome()
    }

    /// The Metrics screen for a preset (`custom` takes two `YYYY-MM-DD` days).
    /// NETWORK-CAPABLE: one server call when online, the device's rows otherwise.
    /// Call it when a person opens the screen or picks a window, never on a tick.
    pub async fn pos_metrics(
        &self,
        preset: String,
        custom_from: Option<String>,
        custom_to: Option<String>,
    ) -> Result<PosMetricsView, MadarError> {
        self.inner
            .pos_metrics(preset, custom_from, custom_to)
            .await
            .map_err(MadarError::from)
    }
}
