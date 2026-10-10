//! The business rules the dashboard shows, from madar-shared. Binding only:
//! each function hands its arguments to the crate that owns the rule and
//! returns its answer, so the Flutter dashboard computes none of them itself
//! (one copy, the one the POS core and the backend run).
//!
//! Dates cross as `YYYY-MM-DD`, instants as epoch milliseconds. madar-catalog's
//! views cross as their own JSON (the shape the backend serves), and its
//! answers come back as JSON: `{"Ok": …}` or `{"Err": …}`.

use chrono::{DateTime, NaiveDate, Utc};
use flutter_rust_bridge::frb;
use serde::{Serialize, de::DeserializeOwned};

fn ymd(s: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(s, "%Y-%m-%d").ok()
}

fn zone(name: &str) -> Option<chrono_tz::Tz> {
    name.parse().ok()
}

/// A snake_case enum from its word (`"dispatched"`), as its serde reads it.
fn from_word<T: DeserializeOwned>(word: &str) -> Option<T> {
    serde_json::from_value(serde_json::Value::String(word.to_string())).ok()
}

/// A snake_case enum's word, as its serde writes it.
fn word<T: Serialize>(value: &T) -> String {
    match serde_json::to_value(value) {
        Ok(serde_json::Value::String(s)) => s,
        _ => String::new(),
    }
}

fn json<T: Serialize>(value: &T) -> String {
    serde_json::to_string(value).unwrap_or_default()
}

fn parse_err(e: serde_json::Error) -> String {
    json(&serde_json::json!({ "Err": { "error": "bad_input", "detail": e.to_string() } }))
}

// ── Time (madar-time) ─────────────────────────────────────────────────

/// The branch-local date of an instant, `YYYY-MM-DD`; `None` for an unknown
/// zone or instant.
#[frb(sync)]
pub fn business_date(tz_name: String, at_ms: i64) -> Option<String> {
    let at = DateTime::<Utc>::from_timestamp_millis(at_ms)?;
    Some(madar_time::business_date_of(zone(&tz_name)?, at).to_string())
}

/// A branch-local calendar day as an instant range: start inclusive, end
/// exclusive (the next local midnight), DST days included.
pub struct DayBounds {
    pub start_ms: i64,
    pub end_ms: i64,
}

#[frb(sync)]
pub fn day_bounds(tz_name: String, date: String) -> Option<DayBounds> {
    let (start, end) = madar_time::day_bounds(zone(&tz_name)?, ymd(&date)?);
    Some(DayBounds {
        start_ms: start.timestamp_millis(),
        end_ms: end.timestamp_millis(),
    })
}

/// The first day of `date`'s week (weeks start on Saturday), `YYYY-MM-DD`.
#[frb(sync)]
pub fn week_start(date: String) -> Option<String> {
    Some(madar_time::week_start(ymd(&date)?).to_string())
}

// ── Pay period (madar-dawam) ──────────────────────────────────────────

/// The pay period holding a day, both ends inclusive.
pub struct PayPeriod {
    pub from: String,
    pub to: String,
}

#[frb(sync)]
pub fn pay_period(day: String, start_day: i64) -> Option<PayPeriod> {
    let (from, to) = madar_dawam::pay::period_window(ymd(&day)?, start_day);
    Some(PayPeriod {
        from: from.to_string(),
        to: to.to_string(),
    })
}

// ── Units (madar-units) ───────────────────────────────────────────────

/// A unit's base unit and how many of the base one of it is.
pub struct UnitSpec {
    pub base: String,
    pub factor: f64,
}

#[frb(sync)]
pub fn unit_spec(unit: String) -> Option<UnitSpec> {
    madar_units::unit_spec(&unit).map(|(base, factor)| UnitSpec {
        base: base.to_string(),
        factor,
    })
}

/// Every unit measured against `base`.
#[frb(sync)]
pub fn units_of(base: String) -> Vec<String> {
    madar_units::units_of(&base)
}

/// `qty` of `from_unit` in `to_unit`; `None` across families or for an
/// unknown unit.
#[frb(sync)]
pub fn unit_convert(qty: f64, from_unit: String, to_unit: String) -> Option<f64> {
    madar_units::convert(qty, &from_unit, &to_unit).ok()
}

// ── Phone (madar-ids) ─────────────────────────────────────────────────

/// The canonical form of a phone number, or `None` when it isn't one.
#[frb(sync)]
pub fn phone_canonical(raw: String) -> Option<String> {
    madar_ids::phone::canonical(&raw)
}

// ── Money (madar-money) ───────────────────────────────────────────────

/// Net sales over orders, rounded half up; 0 with no orders.
#[frb(sync)]
pub fn average_ticket(net_sales: i64, order_count: i64) -> i64 {
    madar_money::metrics::average_ticket(net_sales, order_count)
}

// ── Stock transfers (madar-inventory) ─────────────────────────────────

/// Who takes an action on a transfer, the capability it needs and the status
/// it leads to.
pub struct TransferStep {
    /// `source` | `destination`
    pub side: String,
    /// The capability key, e.g. `inventory.transfers.create`.
    pub cap: String,
    pub next: String,
}

/// `None` when the action is not open in this status.
#[frb(sync)]
pub fn transfer_step(status: String, action: String) -> Option<TransferStep> {
    let step = madar_inventory::transfer::step(from_word(&status)?, from_word(&action)?)?;
    Some(TransferStep {
        side: word(&step.side),
        cap: step.cap.key().to_string(),
        next: word(&step.next),
    })
}

/// One received line, judged: an arrival (`exact` | `short` | `over`) with
/// `difference` = received − sent, or a refusal (`negative` |
/// `over_needs_note`).
pub struct ReceiveCheck {
    pub arrival: Option<String>,
    pub difference: f64,
    pub refused: Option<String>,
}

#[frb(sync)]
pub fn check_receive_line(sent: f64, got: f64, note: Option<String>) -> ReceiveCheck {
    match madar_inventory::transfer::check_receive_line(sent, got, note.as_deref()) {
        Ok(c) => ReceiveCheck {
            arrival: Some(word(&c.arrival)),
            difference: c.difference,
            refused: None,
        },
        Err(r) => ReceiveCheck {
            arrival: None,
            difference: 0.0,
            refused: Some(word(&r)),
        },
    }
}

/// How much a warehouse should send a branch.
pub struct Replenish {
    pub need: f64,
    pub available: f64,
    pub suggested: f64,
}

#[frb(sync)]
#[allow(clippy::too_many_arguments)] // one argument per input of the rule
pub fn replenish_suggest(
    on_hand: f64,
    par_min: f64,
    par_max: Option<f64>,
    in_transit: f64,
    open_inbound: f64,
    warehouse_on_hand: f64,
    warehouse_drafted_out: f64,
) -> Replenish {
    let s = madar_inventory::replenish::suggest(&madar_inventory::replenish::Input {
        on_hand,
        par_min,
        par_max,
        in_transit,
        open_inbound,
        warehouse_on_hand,
        warehouse_drafted_out,
    });
    Replenish {
        need: s.need,
        available: s.available,
        suggested: s.suggested,
    }
}

// ── Till close (madar-till) ───────────────────────────────────────────

/// One payment method's figures on the till being closed.
pub struct ReconcileTotal {
    pub method: String,
    pub payment_method_id: Option<String>,
    pub is_cash: bool,
    pub system_total: i64,
    pub order_count: i64,
}

/// What the person said about one method: `checked` or `disagreed`.
pub struct ReconcileInput {
    pub method: String,
    pub status: String,
    pub declared_amount: Option<i32>,
    pub note: Option<String>,
}

/// Why the server would refuse the close: its code
/// (`RECONCILIATION_AMOUNT_REQUIRED` | `RECONCILIATION_NOTE_REQUIRED`; `None`
/// for an unknown status) and the method it names.
pub struct ReconcileRefusal {
    pub code: Option<String>,
    pub method: String,
}

/// `None` when the live close would be accepted.
#[frb(sync)]
pub fn reconcile_refusal(
    totals: Vec<ReconcileTotal>,
    closing_cash_declared: i32,
    closing_cash_system: i32,
    cash_note: Option<String>,
    inputs: Vec<ReconcileInput>,
) -> Option<ReconcileRefusal> {
    use madar_till::reconcile::{Input, MethodTotal, PlanError, plan_lines};
    let totals: Vec<MethodTotal<String>> = totals
        .into_iter()
        .map(|t| MethodTotal {
            method: t.method,
            payment_method_id: t.payment_method_id,
            is_cash: t.is_cash,
            system_total: t.system_total,
            order_count: t.order_count,
        })
        .collect();
    let inputs: Vec<Input<'_>> = inputs
        .iter()
        .map(|i| Input {
            method: &i.method,
            status: &i.status,
            declared_amount: i.declared_amount,
            note: i.note.as_deref(),
        })
        .collect();
    let err = plan_lines(
        &totals,
        closing_cash_declared,
        closing_cash_system,
        cash_note.as_deref(),
        &inputs,
        false,
    )
    .err()?;
    let method = match &err {
        PlanError::AmountRequired { method }
        | PlanError::NoteRequired { method }
        | PlanError::InvalidStatus { method, .. } => method.clone(),
    };
    Some(ReconcileRefusal {
        code: err.code().map(str::to_string),
        method,
    })
}

// ── Catalogue prices (madar-catalog) ──────────────────────────────────

/// One unit of an item at a size (`None`: the sizeless line); `None` when the
/// item has no active priced size.
#[frb(sync)]
pub fn unit_price(item_json: String, size_label: Option<String>) -> Option<i64> {
    let item: madar_catalog::ItemView = serde_json::from_str(&item_json).ok()?;
    madar_catalog::unit_price(&item, size_label.as_deref()).ok()
}

/// A line's options and optional fields, priced: `{"Ok": PricedOptions}` or
/// `{"Err": PriceError}`.
#[frb(sync)]
pub fn price_options(view_json: String, selection_json: String) -> String {
    let view: madar_catalog::CatalogView = match serde_json::from_str(&view_json) {
        Ok(v) => v,
        Err(e) => return parse_err(e),
    };
    let selection: madar_catalog::Selection = match serde_json::from_str(&selection_json) {
        Ok(s) => s,
        Err(e) => return parse_err(e),
    };
    json(&madar_catalog::price_options(&view, &selection))
}

/// The ids of the combo's slots that take the item (madar-catalog's
/// `combo::choice_for`: its own item choice, else its category's), in order;
/// none for a combo that does not parse.
#[frb(sync)]
pub fn combo_slots_for(combo_json: String, menu_item_id: String, category_id: Option<String>) -> Vec<String> {
    let Ok(combo) = serde_json::from_str::<madar_catalog::combo::ComboView>(&combo_json) else {
        return Vec::new();
    };
    combo
        .slots
        .into_iter()
        .filter(|s| madar_catalog::combo::choice_for(s, &menu_item_id, category_id.as_deref()).is_some())
        .map(|s| s.id)
        .collect()
}

/// A combo's quote for `n` of it: `{"Ok": ComboQuote}` or `{"Err":
/// ComboRefusal}`.
#[frb(sync)]
pub fn combo_quote(combo_json: String, picks_json: String, n: i64) -> String {
    let combo: madar_catalog::combo::ComboView = match serde_json::from_str(&combo_json) {
        Ok(c) => c,
        Err(e) => return parse_err(e),
    };
    let picks: Vec<madar_catalog::combo::PickIn> = match serde_json::from_str(&picks_json) {
        Ok(p) => p,
        Err(e) => return parse_err(e),
    };
    json(&madar_catalog::combo::quote(&combo, &picks, n))
}
