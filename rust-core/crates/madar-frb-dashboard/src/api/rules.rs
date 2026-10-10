//! The business rules the dashboard shows, from madar-shared. Binding only:
//! each function hands its arguments to the crate that owns the rule and
//! returns its answer, so the Flutter dashboard computes none of them itself
//! (one copy, the one the POS core and the backend run).
//!
//! Dates cross as `YYYY-MM-DD`, instants as epoch milliseconds, and the
//! Decimal figures madar-dawam takes (working days, a rung's value) as f64,
//! read as the decimal they print as (`26.5` is 26.5). madar-catalog's
//! views cross as their own JSON (the shape the backend serves), and its
//! answers come back as JSON: `{"Ok": …}` or `{"Err": …}`.

use chrono::{DateTime, NaiveDate, Utc};
use flutter_rust_bridge::frb;
use rust_decimal::Decimal;
use rust_decimal::prelude::ToPrimitive;
use serde::{Serialize, de::DeserializeOwned};

fn ymd(s: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(s, "%Y-%m-%d").ok()
}

fn zone(name: &str) -> Option<chrono_tz::Tz> {
    name.parse().ok()
}

/// `x` as the decimal it prints as; `None` for NaN or an infinity.
fn dec(x: f64) -> Option<Decimal> {
    if !x.is_finite() {
        return None;
    }
    x.to_string().parse().ok()
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

/// An instant on a zone's wall clock: its date (`YYYY-MM-DD`), hour (0–23)
/// and minute.
pub struct LocalParts {
    pub date: String,
    pub hour: u32,
    pub minute: u32,
}

/// `None` for an unknown zone or instant.
#[frb(sync)]
pub fn local_parts(tz_name: String, at_ms: i64) -> Option<LocalParts> {
    let at = DateTime::<Utc>::from_timestamp_millis(at_ms)?;
    let p = madar_time::local_parts(zone(&tz_name)?, at);
    Some(LocalParts {
        date: p.date.to_string(),
        hour: p.hour,
        minute: p.minute,
    })
}

/// `date` at `hour`:`minute` on the zone's wall clock, in epoch ms (past its
/// range an hour or minute rolls over; a repeated time is the earliest, a
/// skipped one moves forward by the gap); `None` for an unknown zone or date.
#[frb(sync)]
pub fn local_instant(tz_name: String, date: String, hour: u32, minute: u32) -> Option<i64> {
    Some(madar_time::local_instant(zone(&tz_name)?, ymd(&date)?, hour, minute).timestamp_millis())
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

// ── Salary and the late ladder (madar-dawam) ──────────────────────────

/// A salary as a month, a day and an hour, in piastres.
pub struct SalaryRates {
    pub monthly: i64,
    pub daily: i64,
    pub hourly: i64,
}

/// The three rates from the one typed (`monthly` | `daily` | `hourly`, in
/// piastres), over `working_days` a month of `day_minutes` each; `None` for
/// another word or working days that are not a number.
#[frb(sync)]
pub fn salary_rates(typed: String, value: i64, working_days: f64, day_minutes: i64) -> Option<SalaryRates> {
    use madar_dawam::salary::Typed;
    let typed = match typed.as_str() {
        "monthly" => Typed::Monthly(value),
        "daily" => Typed::Daily(value),
        "hourly" => Typed::Hourly(value),
        _ => return None,
    };
    let r = madar_dawam::salary::rates(typed, dec(working_days)?, day_minutes);
    Some(SalaryRates {
        monthly: r.monthly,
        daily: r.daily,
        hourly: r.hourly,
    })
}

/// A joiner's first pay: from the hire date to the end of the pay period
/// holding it (both `YYYY-MM-DD`), the days employed in it, the period's days
/// and the pay, in piastres.
pub struct FirstPay {
    pub from: String,
    pub to: String,
    pub days: i64,
    pub period_days: i64,
    pub piastres: i64,
}

#[frb(sync)]
pub fn first_pay(monthly: i64, hire_date: String, start_day: i64) -> Option<FirstPay> {
    let p = madar_dawam::salary::first_pay(monthly, ymd(&hire_date)?, start_day);
    Some(FirstPay {
        from: p.from.to_string(),
        to: p.to.to_string(),
        days: p.days,
        period_days: p.period_days,
        piastres: p.piastres,
    })
}

/// A salary from a day on (`YYYY-MM-DD`), in piastres.
pub struct SalaryFrom {
    pub from: String,
    pub salary: i64,
}

/// Base pay for a window (both ends `YYYY-MM-DD`, inclusive), pro rata by
/// calendar days at each day's salary (the newest `history` row at or before
/// the day, else `fallback_salary`), paid from `paid_from` to `paid_to`;
/// `None` for a date that does not exist.
#[frb(sync)]
pub fn prorated_base(
    history: Vec<SalaryFrom>,
    fallback_salary: i64,
    window_start: String,
    window_end: String,
    paid_from: String,
    paid_to: String,
) -> Option<i64> {
    let history = history
        .iter()
        .map(|h| Some((ymd(&h.from)?, h.salary)))
        .collect::<Option<Vec<_>>>()?;
    Some(madar_dawam::salary::prorated_base(
        &history,
        fallback_salary,
        ymd(&window_start)?,
        ymd(&window_end)?,
        ymd(&paid_from)?,
        ymd(&paid_to)?,
    ))
}

/// `percent` % of a salary, in piastres (a bonus line, the advance cap);
/// `None` for a percent that is not a number.
#[frb(sync)]
pub fn percent_of_salary(salary: i64, percent: f64) -> Option<i64> {
    Some(madar_dawam::pay::percent_of_salary(salary, dec(percent)?))
}

/// One rung of the late ladder: both ends inclusive, `to_minutes` `None` the
/// open top rung.
pub struct LadderRung {
    pub from_minutes: i32,
    pub to_minutes: Option<i32>,
}

/// The index of the FIRST rung `late_minutes` falls on; `None` on time or
/// past a ladder that stops.
#[frb(sync)]
pub fn select_late_tier(rungs: Vec<LadderRung>, late_minutes: i64) -> Option<u32> {
    use madar_dawam::ladder::{LateDeductionKind, LateTier, select_late_tier};
    // The kind and value do not enter the choice.
    let tiers: Vec<LateTier> = rungs
        .iter()
        .map(|r| LateTier {
            from_minutes: r.from_minutes,
            to_minutes: r.to_minutes,
            kind: LateDeductionKind::Piastres,
            value: Decimal::ZERO,
        })
        .collect();
    let hit = select_late_tier(&tiers, late_minutes)?;
    let i = tiers.iter().position(|t| std::ptr::eq(t, hit))?;
    u32::try_from(i).ok()
}

/// What a rung of `kind` (`minutes` | `piastres` | `day_fraction`) and
/// `value` docks at a monthly `salary` over `working_days` of `day_minutes`,
/// in piastres; `None` for another kind or a figure that is not a number.
#[frb(sync)]
pub fn late_deduction_piastres(
    kind: String,
    value: f64,
    salary: i64,
    working_days: f64,
    day_minutes: i64,
) -> Option<i64> {
    use madar_dawam::ladder::{LateTier, late_deduction_piastres};
    use madar_dawam::salary::PayRates;
    let tier = LateTier {
        from_minutes: 0,
        to_minutes: None,
        kind: from_word(&kind)?,
        value: dec(value)?,
    };
    let rates = PayRates::from_base(salary, dec(working_days)?, day_minutes);
    Some(late_deduction_piastres(&tier, &rates))
}

/// What `days_absent` absent days at `deduction_days` docked each cost at a
/// monthly `salary` over `working_days`, in piastres; `None` for a figure
/// that is not a number.
#[frb(sync)]
pub fn absence_deduction_piastres(
    salary: i64,
    working_days: f64,
    days_absent: f64,
    deduction_days: f64,
) -> Option<i64> {
    use madar_dawam::salary::PayRates;
    // A day's pay does not read the day's minutes.
    let rates = PayRates::from_base(salary, dec(working_days)?, 0);
    Some(madar_dawam::ladder::absence_deduction_piastres(
        &rates,
        dec(days_absent)?,
        dec(deduction_days)?,
    ))
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

/// What a recipe line stores for `qty` typed in `unit`: in the ingredient's
/// `base_unit` (through its density), grossed up by its yield, 3 dp; `None`
/// when the units don't convert.
#[frb(sync)]
pub fn recipe_base_qty(
    qty: f64,
    unit: String,
    base_unit: String,
    density: Option<f64>,
    yield_pct: Option<f64>,
) -> Option<f64> {
    madar_units::recipe_base_qty(qty, &unit, &base_unit, density, yield_pct).ok()
}

/// The usable amount of a stored recipe quantity (the amount typed, in the
/// base unit), 3 dp.
#[frb(sync)]
pub fn usable_qty(stored: f64, yield_pct: Option<f64>) -> f64 {
    madar_units::usable_qty(stored, yield_pct)
}

/// A recipe quantity copied to another size × `factor`, 3 dp (half away from
/// zero).
#[frb(sync)]
pub fn scale_qty(qty: f64, factor: f64) -> f64 {
    madar_units::scale_qty(qty, factor)
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

// ── Recipe cost (madar-money `cost`) ──────────────────────────────────

/// A line's cost in whole piastres: `qty × cost_per_unit`, exact, half away
/// from zero.
#[frb(sync)]
pub fn line_cost(qty: f64, cost_per_unit: f64) -> i64 {
    madar_money::cost::line_cost(qty, cost_per_unit)
}

/// One recipe line: its quantity and its cost per unit (`None`: unknown; 0
/// is known, free).
pub struct CostLine {
    pub qty: f64,
    pub cost_per_unit: Option<f64>,
}

/// A recipe's cost: the known lines summed exactly and rounded once;
/// `complete` is false when a line's cost is unknown.
pub struct RecipeCost {
    pub piastres: i64,
    pub complete: bool,
}

#[frb(sync)]
pub fn recipe_cost(lines: Vec<CostLine>) -> RecipeCost {
    let lines: Vec<madar_money::cost::CostLine> = lines
        .into_iter()
        .map(|l| madar_money::cost::CostLine {
            qty: l.qty,
            cost_per_unit: l.cost_per_unit,
        })
        .collect();
    let c = madar_money::cost::recipe_cost(&lines);
    RecipeCost {
        piastres: c.piastres,
        complete: c.complete,
    }
}

/// `(price − cost) / price`; `None` unless the price is above 0.
#[frb(sync)]
pub fn margin(price: i64, cost: i64) -> Option<f64> {
    madar_money::cost::margin(price, cost)
}

/// The food-cost band (`good` | `fair` | `poor`); `None` unless the price is
/// above 0.
#[frb(sync)]
pub fn food_cost_band(cost: i64, price: i64) -> Option<String> {
    madar_money::cost::food_cost_band(cost, price).map(|b| word(&b))
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

/// A transfer quantity in whole thousandths, as the server compares them
/// (`madar_inventory::milli`; a purchase's column grain is
/// [`quantity_milli`]).
#[frb(sync)]
pub fn milli(q: f64) -> i64 {
    madar_inventory::milli(q)
}

// ── Purchases and counts (madar-inventory) ────────────────────────────

/// The order dialog's estimate of a line, in whole piastres: cost per stock
/// unit × `qty` typed in `purchase_unit`, exact, rounded once; `None` with no
/// cost, a quantity not above 0, or units that don't convert.
#[frb(sync)]
pub fn estimate_line_total(
    cost_per_stock_unit: Option<f64>,
    qty: f64,
    purchase_unit: String,
    stock_unit: String,
) -> Option<i64> {
    madar_inventory::purchase::estimate_line_total(cost_per_stock_unit, qty, &purchase_unit, &stock_unit)
}

/// The unit cost a line total implies (piastres per unit, 8 dp); `None` for a
/// negative total or a quantity that is 0 at 3 dp.
#[frb(sync)]
pub fn unit_cost_from_total(line: i64, qty: f64) -> Option<f64> {
    madar_inventory::purchase::unit_cost_from_total(line, qty)
}

/// A purchase line's costs as the server stores them: the line total, the
/// unit cost (whole piastres) and the exact unit cost (8 dp); or `refused`,
/// the server's words for a 400.
pub struct LineCosts {
    pub line_cost: i64,
    pub unit_cost: i64,
    pub unit_cost_exact: f64,
    pub refused: Option<String>,
}

#[frb(sync)]
pub fn line_costs(quantity_ordered: f64, line_cost: Option<i64>, unit_cost: Option<i64>) -> LineCosts {
    match madar_inventory::purchase::line_costs(quantity_ordered, line_cost, unit_cost) {
        Ok((line, exact)) => LineCosts {
            line_cost: line,
            unit_cost: madar_money::cost::round_piastres(exact),
            unit_cost_exact: exact.to_f64().unwrap_or(0.0),
            refused: None,
        },
        Err(e) => LineCosts {
            line_cost: 0,
            unit_cost: 0,
            unit_cost_exact: 0.0,
            refused: Some(e.to_string()),
        },
    }
}

/// What one delivery costs, in whole piastres (half away from zero): the
/// invoice total if given, else a unit cost × the quantity, else the ordered
/// total pro rata; `None` when the server would refuse the costs.
#[frb(sync)]
pub fn delivery_cost(
    quantity_received: f64,
    line_cost: Option<i64>,
    unit_cost: Option<i64>,
    ordered_line_cost: i64,
    quantity_ordered: f64,
) -> Option<i64> {
    use madar_inventory::purchase::{delivery_cost, quantity_dec};
    let cost = delivery_cost(
        quantity_received,
        line_cost,
        unit_cost,
        ordered_line_cost,
        quantity_dec(quantity_ordered),
    )
    .ok()?;
    Some(madar_money::cost::round_piastres(cost))
}

/// A purchase quantity in whole thousandths, as the column stores it (half
/// away from zero).
#[frb(sync)]
pub fn quantity_milli(q: f64) -> i64 {
    madar_inventory::purchase::milli(q)
}

/// Whether a counted row needs a variance reason: it differs from the book by
/// at least `pct` percent, or stock appears from zero (exact, in thousandths).
#[frb(sync)]
pub fn is_variance_flagged(book: f64, counted: f64, pct: f64) -> bool {
    madar_inventory::count::is_variance_flagged(book, counted, pct)
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
