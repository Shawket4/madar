//! Tills (TILLS_CONTRACT §4). A till is a PERSON's sales session on this device
//! (what "shift" used to be). Opening one is the first OUTBOX WRITE: an optimistic
//! local record + a queued, idempotent `open_till` command whose client-minted UUID
//! is the till PK (so replay never needs a remap). Several people can each hold an
//! open till on one device; `current` is the SIGNED-IN person's till here.

use madar_api::models;
use serde::{Deserialize, Serialize};

use crate::error::CoreResult;
use crate::store::Store;

/// LEGACY kv key (<= v0.6): the device's one current shift (`Shift` JSON). Read
/// once by [`migrate_legacy_current`] and then removed.
pub(crate) const LEGACY_CURRENT_SHIFT_KEY: &str = "current_shift";
/// kv key naming the person whose session is live (the `current` till's owner).
pub(crate) const ACTIVE_USER_KEY: &str = "till:active_user";
/// kv key holding the suggested opening cash for the NEXT till — the previous
/// till's declared closing (cash continuity).
pub(crate) const SUGGESTED_OPEN_CASH_KEY: &str = "shift:suggested_open_cash";

/// kv key: the till this device holds for `user_id` (contract §4.3).
pub(crate) fn device_till_key(user_id: &str) -> String {
    format!("{DEVICE_TILL_PREFIX}{user_id}")
}
pub(crate) const DEVICE_TILL_PREFIX: &str = "device_till:";

/// kv key holding the server's `CloseTillResponse` once a queued close acks.
pub(crate) fn close_result_key(till_id: &str) -> String {
    format!("till:close_result:{till_id}")
}

/// A server report as an older build cached it in kv: the current object form,
/// the one-element list an earlier build wrote, or the pre-rework
/// `ShiftReportResponse` (key `shift`, no rework fields). Read once, by the store
/// migration that retires those caches (`schema::step5_drop_legacy_read_caches`).
pub(crate) fn parse_cached_report(raw: &str) -> Option<models::TillReportResponse> {
    let v: serde_json::Value = serde_json::from_str(raw).ok()?;
    let mut v = match v {
        serde_json::Value::Array(mut a) if !a.is_empty() => a.swap_remove(0),
        other => other,
    };
    let obj = v.as_object_mut()?;
    if let Some(shift) = obj.remove("shift") {
        obj.entry("till").or_insert(shift);
    }
    if let Some(till) = obj.get_mut("till").and_then(|t| t.as_object_mut()) {
        till.entry("verification").or_insert_with(|| "legacy".into());
        till.entry("opened_while_another_open").or_insert(false.into());
        till.entry("disagreement_count").or_insert(0.into());
    }
    obj.entry("reconciliation").or_insert_with(|| serde_json::json!([]));
    obj.entry("order_number_range").or_insert_with(|| serde_json::json!({}));
    serde_json::from_value(v).ok()
}

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TillView {
    pub id: String,
    pub branch_id: String,
    pub teller_id: String,
    pub teller_name: String,
    pub opening_cash_minor: i64,
    pub opened_at: String,
    pub status: String,
    pub is_open: bool,
    pub device_id: Option<String>,
    pub device_code: Option<String>,
    /// `server` | `lan` | `unverified` | `legacy`.
    pub verification: String,
    pub opened_while_another_open: bool,
}

/// A till as this device stores it (kv `till:record:{id}`): the optimistic local
/// open, later refreshed from the server's `Till`. A LOCAL record, not a wire
/// type — its JSON is what older builds persisted (a legacy `Shift` body decodes
/// too), so every field defaults.
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct TillRecord {
    pub id: String,
    #[serde(default)]
    pub branch_id: String,
    #[serde(default)]
    pub branch_name: Option<String>,
    #[serde(default)]
    pub teller_id: String,
    #[serde(default)]
    pub teller_name: String,
    #[serde(default = "open_status")]
    pub status: String,
    #[serde(default)]
    pub opening_cash: i64,
    #[serde(default)]
    pub opening_cash_original: Option<i64>,
    #[serde(default)]
    pub opening_cash_was_edited: bool,
    #[serde(default)]
    pub opening_cash_edit_reason: Option<String>,
    #[serde(default)]
    pub closing_cash_declared: Option<i64>,
    #[serde(default)]
    pub closing_cash_system: Option<i64>,
    #[serde(default)]
    pub cash_discrepancy: Option<i64>,
    #[serde(default)]
    pub opened_at: String,
    #[serde(default)]
    pub closed_at: Option<String>,
    #[serde(default)]
    pub force_closed_at: Option<String>,
    #[serde(default)]
    pub timezone: Option<String>,
    #[serde(default)]
    pub device_id: Option<String>,
    #[serde(default)]
    pub device_code: Option<String>,
    #[serde(default)]
    pub device_label: Option<String>,
    #[serde(default)]
    pub verification: Option<String>,
    #[serde(default)]
    pub opened_while_another_open: bool,
    #[serde(default)]
    pub other_till_id: Option<String>,
    #[serde(default)]
    pub reconciliation_status: Option<String>,
    #[serde(default)]
    pub disagreement_count: i64,
    #[serde(default)]
    pub open_bills_at_close: Option<i64>,
    #[serde(default)]
    pub old_bills_at_close: Option<i64>,
}

fn open_status() -> String {
    "open".into()
}

impl TillRecord {
    /// The server's `Till` as the stored record.
    pub(crate) fn from_api(t: &models::Till) -> Self {
        Self {
            id: t.id.to_string(),
            branch_id: t.branch_id.to_string(),
            branch_name: t.branch_name.clone().flatten(),
            teller_id: t.teller_id.to_string(),
            teller_name: t.teller_name.clone(),
            status: t.status.to_string(),
            opening_cash: t.opening_cash as i64,
            opening_cash_original: t.opening_cash_original.flatten().map(i64::from),
            opening_cash_was_edited: t.opening_cash_was_edited,
            opening_cash_edit_reason: t.opening_cash_edit_reason.clone().flatten(),
            closing_cash_declared: t.closing_cash_declared.flatten().map(i64::from),
            closing_cash_system: t.closing_cash_system.flatten().map(i64::from),
            cash_discrepancy: t.cash_discrepancy.flatten().map(i64::from),
            opened_at: t.opened_at.to_rfc3339(),
            closed_at: t.closed_at.flatten().map(|d| d.to_rfc3339()),
            force_closed_at: t.force_closed_at.flatten().map(|d| d.to_rfc3339()),
            timezone: t.timezone.clone().flatten(),
            device_id: t.device_id.flatten().map(|u| u.to_string()),
            device_code: t.device_code.clone().flatten(),
            device_label: t.device_label.clone().flatten(),
            verification: Some(t.verification.to_string()),
            opened_while_another_open: t.opened_while_another_open,
            other_till_id: t.other_till_id.flatten().map(|u| u.to_string()),
            reconciliation_status: t.reconciliation_status.clone().flatten(),
            disagreement_count: t.disagreement_count,
            open_bills_at_close: t.open_bills_at_close.flatten().map(i64::from),
            old_bills_at_close: t.old_bills_at_close.flatten().map(i64::from),
        }
    }
}

/// Decode a queued request written before the tills rework: the generated
/// request types now name the till `till_id`, and a payload queued by an older
/// build still says `shift_id` inside `request` (create_order, settle, refund).
/// Old rows must replay (decision 12), so the name is carried over on read.
pub(crate) fn de_legacy_till_request<'de, D, T>(d: D) -> Result<T, D::Error>
where
    D: serde::Deserializer<'de>,
    T: serde::de::DeserializeOwned,
{
    let mut v = serde_json::Value::deserialize(d)?;
    if let Some(obj) = v.as_object_mut() {
        if let Some(legacy) = obj.remove("shift_id") {
            obj.entry("till_id").or_insert(legacy);
        }
    }
    serde_json::from_value(v).map_err(serde::de::Error::custom)
}

/// Outbox payload for `open_till` (legacy `open_shift` payloads decode too: the
/// device fields default and the old `request.till_id` is ignored).
#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct OpenTillCommand {
    pub branch_id: String,
    #[serde(default)]
    pub device_id: String,
    #[serde(default)]
    pub device_code: String,
    /// `server` | `lan` | `unverified`.
    #[serde(default)]
    pub verification: String,
    pub request: models::OpenTillRequest,
}

/// Outbox payload for `close_till` (legacy `close_shift` payloads decode via the alias).
#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct CloseTillCommand {
    #[serde(alias = "shift_id")]
    pub till_id: String,
    #[serde(default)]
    pub device_id: Option<String>,
    pub request: models::CloseTillRequest,
}

/// Outbox payload for an offline cash movement. Idempotent on `client_ref`.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct CashMovementCommand {
    #[serde(alias = "shift_id")]
    pub till_id: String,
    #[serde(default)]
    pub device_id: Option<String>,
    pub request: models::CashMovementRequest,
}

/// A cash-drawer movement (pay-in / pay-out). `amount_minor` is signed:
/// positive = cash in, negative = cash out.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct CashMovementView {
    pub id: String,
    /// `pay_in` | `pay_out` | `safe_drop` | `correction` — what the sign
    /// alone cannot say (a safe drop and a pay-out both take cash out).
    #[serde(default)]
    pub kind: String,
    pub amount_minor: i64,
    pub note: String,
    pub moved_by_name: String,
    pub created_at: String,
}

/// Merge synced server cash movements with the still-queued offline ones, dropping
/// a queued movement that has ALREADY synced (its `client_ref`, now the view `id`,
/// identifies a server row). Server first (chronological), then the queued tail.
pub fn merge_cash_for_view(
    server: Vec<CashMovementView>,
    queued: Vec<CashMovementView>,
) -> Vec<CashMovementView> {
    let seen: std::collections::HashSet<String> = server.iter().map(|m| m.id.clone()).collect();
    let mut out = server;
    out.extend(queued.into_iter().filter(|q| !seen.contains(&q.id)));
    out
}

/// A past till, projected for the history list.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct TillSummaryView {
    pub id: String,
    pub branch_name: Option<String>,
    /// Teller who owns the till (the Teller column in the past-tills table).
    pub teller_name: Option<String>,
    pub opened_at: String,
    pub closed_at: Option<String>,
    pub opening_cash_minor: i64,
    pub closing_declared_minor: Option<i64>,
    pub closing_system_minor: Option<i64>,
    pub discrepancy_minor: Option<i64>,
    pub status: String,
    pub is_open: bool,
    #[serde(default)]
    pub device_code: Option<String>,
    #[serde(default = "legacy_verification")]
    pub verification: String,
    #[serde(default)]
    pub opened_while_another_open: bool,
    #[serde(default)]
    pub reconciliation_status: Option<String>,
}

/// A verification word (`server` | `lan` | `unverified` | `legacy`) as the wire enum;
/// an unknown word is `unverified` (never claims more than it knows).
pub(crate) fn verification_wire(word: &str) -> models::TillVerification {
    serde_json::from_value(serde_json::Value::String(word.to_string())).unwrap_or(models::TillVerification::Unverified)
}

fn legacy_verification() -> String {
    "legacy".into()
}

pub(crate) fn till_summary_view(s: &TillRecord) -> TillSummaryView {
    TillSummaryView {
        id: s.id.clone(),
        branch_name: s.branch_name.clone(),
        teller_name: Some(s.teller_name.clone()).filter(|x| !x.is_empty()),
        opened_at: s.opened_at.clone(),
        closed_at: s.closed_at.clone(),
        opening_cash_minor: s.opening_cash,
        closing_declared_minor: s.closing_cash_declared,
        closing_system_minor: s.closing_cash_system,
        discrepancy_minor: s.cash_discrepancy,
        status: s.status.clone(),
        is_open: s.status == "open",
        device_code: s.device_code.clone(),
        verification: s.verification.clone().unwrap_or_else(legacy_verification),
        opened_while_another_open: s.opened_while_another_open,
        reconciliation_status: s.reconciliation_status.clone(),
    }
}

/// One payment-method line in the shift report.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TillReportPaymentLine {
    pub method: String,
    pub is_cash: bool,
    pub order_count: i64,
    pub total_minor: i64,
}

/// The shift report shown on close (drives the system-cash + discrepancy) and in
/// a report preview. `expected_cash_minor` is the server's expected drawer cash
/// PLUS still-queued cash sales (offline: opening cash + queued cash).
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TillReportView {
    /// Teller who ran the shift, and the open/close/print timestamps (RFC3339) —
    /// the host stamps them to the branch timezone for display.
    pub teller_name: String,
    pub opened_at: String,
    /// `None` while the shift is still open.
    pub closed_at: Option<String>,
    pub printed_at: String,
    pub is_open: bool,
    pub expected_cash_minor: i64,
    pub opening_cash_minor: i64,
    /// Opening-cash mismatch: when the teller's opening count differed from the
    /// suggested (last close), `opening_cash_was_edited` is set, `*_original_minor`
    /// is the suggested amount, and `*_edit_reason` is the teller's note. The
    /// report shows the signed difference + reason. (Server path only; the offline
    /// fallback has no original to diff against.)
    pub opening_cash_was_edited: bool,
    pub opening_cash_original_minor: Option<i64>,
    pub opening_cash_edit_reason: Option<String>,
    /// Cash actually counted at close (the drawer count). `None` until closed —
    /// drives the reconciliation block + the over/short difference.
    pub closing_cash_declared_minor: Option<i64>,
    pub total_payments_minor: i64,
    pub net_payments_minor: i64,
    pub voided_amount_minor: i64,
    /// Refunds ISSUED FROM THIS DRAWER — money out, keyed on the refund's own
    /// shift, which need not be the shift that made the sale. `*_cash_minor`
    /// is the slice that left the drawer and the only part `expected_cash`
    /// subtracts; the rest went back the way it came.
    pub refunds_issued_minor: i64,
    pub refunds_issued_cash_minor: i64,
    pub refunds_issued_count: i64,
    /// Cash taken on this shift's sales that were later fully refunded. The
    /// payment lines leave those sales out — they are revenue, and the sale
    /// was undone — but the notes DID go into the drawer, so expected cash
    /// counts them. Without this line the report does not add up.
    pub cash_in_refunded_sales_minor: i64,
    /// Tax and service charge on this till's sales, net of what their refunds
    /// took back — a partial refund takes back its share (Z report).
    pub total_tax_minor: i64,
    pub total_service_charge_minor: i64,
    /// Table bills whose service charge was waived, and what it came to.
    pub service_charge_waived_count: i64,
    pub service_charge_waived_minor: i64,
    pub cash_movements_net_minor: i64,
    /// Pay-in / pay-out drawer totals (separate, not just the net) — Z-report depth.
    pub cash_in_minor: i64,
    pub cash_out_minor: i64,
    pub payment_lines: Vec<TillReportPaymentLine>,
    /// Each individual cash movement (newest-first), for the itemised drawer block.
    pub cash_movements: Vec<TillReportCashLine>,
    /// `false` = offline fallback (no server figures, just opening + queued).
    pub from_server: bool,
    /// The device the till was opened on (receipts / Z report).
    pub device_code: Option<String>,
    /// This till's device order-number range (`36B-1` … `36B-42`).
    pub order_number_first: Option<i64>,
    pub order_number_last: Option<i64>,
    /// Per-method close reconciliation (empty while open / pre-rework).
    pub reconciliation: Vec<ReconciliationLineView>,
    /// Old / all open bills at the branch when the till closed.
    pub old_bills_count: Option<i64>,
    pub open_bills_count: Option<i64>,
    /// Held orders left open at this close for the next till, and their total.
    pub held_orders_left_open: Option<i64>,
    pub held_orders_left_open_total_minor: Option<i64>,
    pub opened_while_another_open: bool,
    /// `server` | `lan` | `unverified` | `legacy`.
    pub verification: String,
    /// Who viewed / printed the cash spot report, oldest first (Z report).
    pub spot_views: Vec<crate::cash_spot::SpotViewLineView>,
}

/// One itemised cash-drawer movement on the report. `amount_minor` is signed
/// (positive = pay-in, negative = pay-out).
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TillReportCashLine {
    pub amount_minor: i64,
    pub note: String,
    pub moved_by_name: String,
    pub created_at: String,
}

/// Project the server report, adding still-queued cash sales to expected cash.
pub(crate) fn report_view(
    report: &models::TillReportResponse,
    queued_cash: i64,
    label: &dyn Fn(&str) -> String,
) -> TillReportView {
    let shift = &report.till;
    TillReportView {
        teller_name: shift.teller_name.clone(),
        opened_at: shift.opened_at.to_rfc3339(),
        closed_at: shift.closed_at.flatten().map(|d| d.to_rfc3339()),
        printed_at: report.printed_at.to_rfc3339(),
        is_open: shift.status == models::TillStatus::Open,
        opening_cash_was_edited: shift.opening_cash_was_edited,
        opening_cash_original_minor: shift.opening_cash_original.flatten().map(|v| v as i64),
        opening_cash_edit_reason: shift
            .opening_cash_edit_reason
            .clone()
            .flatten()
            .filter(|s| !s.is_empty()),
        closing_cash_declared_minor: shift.closing_cash_declared.flatten().map(|v| v as i64),
        expected_cash_minor: report.expected_cash + queued_cash,
        opening_cash_minor: shift.opening_cash as i64,
        total_payments_minor: report.total_payments,
        net_payments_minor: report.net_payments,
        voided_amount_minor: report.voided_amount,
        // `#[serde(default)]` on the wire: a server older than refunds simply
        // reports nothing given back, which is what it means.
        refunds_issued_minor: report.refunds_issued_amount.unwrap_or(0),
        refunds_issued_cash_minor: report.refunds_issued_cash.unwrap_or(0),
        refunds_issued_count: report.refunds_issued_count.unwrap_or(0),
        cash_in_refunded_sales_minor: report.cash_in_refunded_sales.unwrap_or(0),
        total_tax_minor: report.total_tax.unwrap_or(0),
        total_service_charge_minor: report.total_service_charge.unwrap_or(0),
        service_charge_waived_count: report.service_charge_waived_count.unwrap_or(0),
        service_charge_waived_minor: report.service_charge_waived_amount.unwrap_or(0),
        cash_movements_net_minor: report.cash_movements_net,
        cash_in_minor: report.cash_movements_in,
        cash_out_minor: report.cash_movements_out,
        payment_lines: report
            .payment_summary
            .iter()
            .map(|p| TillReportPaymentLine {
                method: p.payment_method.clone(),
                is_cash: p.is_cash,
                order_count: p.order_count,
                total_minor: p.total,
            })
            .collect(),
        cash_movements: report
            .cash_movements
            .iter()
            .map(|m| TillReportCashLine {
                amount_minor: m.amount as i64,
                note: m.note.clone(),
                moved_by_name: m.moved_by_name.clone(),
                created_at: m.created_at.to_rfc3339(),
            })
            .collect(),
        from_server: true,
        device_code: shift
            .device_code
            .clone()
            .flatten()
            .or_else(|| report.order_number_range.device_code.clone().flatten()),
        order_number_first: report.order_number_range.first.flatten().map(i64::from),
        order_number_last: report.order_number_range.last.flatten().map(i64::from),
        reconciliation: reconciliation_lines_from_api(&report.reconciliation, label),
        old_bills_count: report.old_bills_at_close.flatten().map(i64::from),
        open_bills_count: report.open_bills_at_close.flatten().map(i64::from),
        held_orders_left_open: report.held_orders_left_open.flatten().map(i64::from),
        held_orders_left_open_total_minor: report.held_orders_left_open_total.flatten().map(i64::from),
        opened_while_another_open: shift.opened_while_another_open,
        verification: shift.verification.to_string(),
        spot_views: report
            .spot_views
            .iter()
            .flatten()
            .map(|v| crate::cash_spot::SpotViewLineView {
                id: v.id.to_string(),
                viewed_by_name: v.viewed_by_name.clone(),
                approved_by_name: v.approved_by_name.clone().flatten(),
                viewed_at: v.viewed_at.to_rfc3339(),
                printed: v.printed,
                queued: false,
            })
            .collect(),
    }
}

/// Offline close against a CACHED server report: the real figures the server
/// last knew for this shift, plus the work this device has not drained yet.
///
/// This is the offline path whenever the shift has ever been reported on while
/// online. `queued` holds only movements still in the outbox — the server's copy
/// already carries every drained one, so the two lists are disjoint and appending
/// cannot double count. `from_server` stays FALSE: the figures are real but they
/// are a snapshot, and the teller is entitled to see that the device is offline.
pub(crate) fn cached_report_view(
    report: &models::TillReportResponse,
    queued_cash: i64,
    queued: Vec<TillReportCashLine>,
    label: &dyn Fn(&str) -> String,
) -> TillReportView {
    let mut view = report_view(report, queued_cash, label);
    view.from_server = false;
    if queued.is_empty() {
        return view;
    }
    view.cash_movements.extend(queued);
    // Recompute the drawer split over the union rather than trusting the
    // server's totals, which predate the queued movements.
    view.cash_in_minor = view
        .cash_movements
        .iter()
        .filter(|m| m.amount_minor > 0)
        .map(|m| m.amount_minor)
        .sum();
    view.cash_out_minor = view
        .cash_movements
        .iter()
        .filter(|m| m.amount_minor < 0)
        .map(|m| -m.amount_minor)
        .sum();
    view.cash_movements_net_minor = view.cash_in_minor - view.cash_out_minor;
    view
}

pub(crate) fn view_from(t: &TillRecord) -> TillView {
    TillView {
        id: t.id.clone(),
        branch_id: t.branch_id.clone(),
        teller_id: t.teller_id.clone(),
        teller_name: t.teller_name.clone(),
        opening_cash_minor: t.opening_cash,
        opened_at: t.opened_at.clone(),
        status: t.status.clone(),
        is_open: t.status == "open",
        device_id: t.device_id.clone(),
        device_code: t.device_code.clone(),
        verification: t
            .verification
            .clone()
            .unwrap_or_else(|| "legacy".to_string()),
        opened_while_another_open: t.opened_while_another_open,
    }
}

/// Cache the suggested opening cash (previous declared closing) for the next
/// till. A non-positive value clears it (no carryover to suggest).
pub(crate) fn cache_suggested_opening_cash(store: &Store, minor: i64) -> CoreResult<()> {
    store.kv_put(SUGGESTED_OPEN_CASH_KEY, &minor.max(0).to_string())
}

/// The suggested opening cash for the next till (0 when none is known).
pub(crate) fn suggested_opening_cash(store: &Store) -> CoreResult<i64> {
    Ok(store
        .kv_get(SUGGESTED_OPEN_CASH_KEY)?
        .and_then(|s| s.parse::<i64>().ok())
        .unwrap_or(0))
}

// ── person-scoped till state ────────────────────────────────────────────────

/// Record whose session is live, so `current` resolves THEIR till. `None` on
/// sign-out (the records themselves stay: an open till is device state).
pub(crate) fn set_active_user(store: &Store, user_id: Option<&str>) -> CoreResult<()> {
    migrate_legacy_current(store)?;
    match user_id.filter(|u| !u.is_empty()) {
        Some(u) => store.kv_put(ACTIVE_USER_KEY, u),
        None => store.kv_delete(ACTIVE_USER_KEY),
    }
}

pub(crate) fn active_user(store: &Store) -> Option<String> {
    store
        .kv_get(ACTIVE_USER_KEY)
        .ok()
        .flatten()
        .filter(|s| !s.is_empty())
}

/// One-shot: the pre-rework device-global `current_shift` becomes a till record
/// held for its teller on this device. Loses nothing; idempotent.
pub(crate) fn migrate_legacy_current(store: &Store) -> CoreResult<()> {
    let Some(raw) = store.kv_get(LEGACY_CURRENT_SHIFT_KEY)? else {
        return Ok(());
    };
    if raw != "null" {
        if let Ok(t) = serde_json::from_str::<TillRecord>(&raw) {
            if !t.id.is_empty() {
                if record(store, &t.id).is_none() {
                    save(store, &t)?;
                } else if !t.teller_id.is_empty() {
                    // The ledger backfill already holds the till (from its queued
                    // open): it only needs to be its teller's till on this device.
                    store.kv_put(&device_till_key(&t.teller_id), &t.id)?;
                }
            }
        }
    }
    store.kv_delete(LEGACY_CURRENT_SHIFT_KEY)
}

/// A till record by id (any person, any status) — the till's ledger row
/// (offline plan B; the pre-B `till:rec:<id>` kv rows are moved there once).
pub(crate) fn record(store: &Store, till_id: &str) -> Option<TillRecord> {
    store
        .with_conn(|c| crate::ledger::stored(c, crate::ledger::T_TILL, till_id))
        .ok()
        .flatten()
        .and_then(|row| serde_json::from_value(row.raw).ok())
}

/// The signed-in person's till on this device (open or locally closed).
pub(crate) fn current_record(store: &Store) -> CoreResult<Option<TillRecord>> {
    migrate_legacy_current(store)?;
    let Some(user) = active_user(store) else {
        return Ok(None);
    };
    let Some(till_id) = store.kv_get(&device_till_key(&user))? else {
        return Ok(None);
    };
    Ok(record(store, &till_id))
}

pub(crate) fn current(store: &Store) -> CoreResult<Option<TillView>> {
    Ok(current_record(store)?.as_ref().map(view_from))
}

/// Persist a till record the SERVER holds (a resumed or adopted till) and point
/// its teller's device slot at it. A row a live op still holds keeps the
/// device's state; the server's version is remembered for it.
pub(crate) fn save(store: &Store, till: &TillRecord) -> CoreResult<()> {
    update_record(store, till)?;
    if !till.teller_id.is_empty() {
        store.kv_put(&device_till_key(&till.teller_id), &till.id)?;
    }
    Ok(())
}

/// Update a stored record without moving any device slot (a late ack of a till
/// that is no longer anyone's current one, a force-close).
pub(crate) fn update_record(store: &Store, till: &TillRecord) -> CoreResult<()> {
    let v = serde_json::to_value(till)?;
    store.with_tx_touch(|tx, touched| {
        use crate::ledger::{self as l, T_TILL};
        if l::is_protected(tx, T_TILL, &till.id)? && l::stored(tx, T_TILL, &till.id)?.is_some() {
            l::shadow(tx, T_TILL, &till.id, &v, 0)?;
        } else {
            l::write_row(tx, T_TILL, &till.id, &v, l::Origin::Fetch, None)?;
            l::local::reapply_pending(tx, T_TILL, &till.id)?;
        }
        touched.push(crate::changes::TILLS);
        Ok(())
    })
}

/// Drop the signed-in person's device slot (server says none / force-closed).
pub(crate) fn clear(store: &Store) -> CoreResult<()> {
    if let Some(user) = active_user(store) {
        store.kv_delete(&device_till_key(&user))?;
    }
    Ok(())
}

/// Drop whichever person's slot points at `till_id` (a dead open, a force-close).
pub(crate) fn clear_till(store: &Store, till_id: &str) -> CoreResult<()> {
    for (k, v) in store.kv_list_prefix(DEVICE_TILL_PREFIX)? {
        if v == till_id {
            store.kv_delete(&k)?;
        }
    }
    Ok(())
}

/// Every OPEN till this device holds, one per person — the LAN advert.
pub(crate) fn open_on_device(store: &Store) -> Vec<TillRecord> {
    let mut out: Vec<TillRecord> = store
        .kv_list_prefix(DEVICE_TILL_PREFIX)
        .unwrap_or_default()
        .into_iter()
        .filter_map(|(_, id)| record(store, &id))
        .filter(|t| t.status == "open")
        .collect();
    out.sort_by(|a, b| a.opened_at.cmp(&b.opened_at));
    out
}

// ── the device lock (owner decision 2026-09-19) ────────────────────────────

/// Is this device walled to the open-till screen, and why?
///
/// ONE answer the shell reads — no screen decides this for itself. Computed
/// entirely from local state (session, capabilities, the local till record and
/// the synced till rows), so it is the same answer with or without a network.
///
/// `reason` is a stable key, never a sentence: `""` when unlocked, else
/// `"no_till"`, `"not_permitted"` or `"open_elsewhere"`. `title`/`body` are
/// the localized words for the locked screen — a reason and what to do next,
/// never a dead end.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct TillLockView {
    pub locked: bool,
    pub reason: String,
    pub title: String,
    pub body: String,
    /// This person may still open a till here (the form is worth showing).
    pub can_open: bool,
    /// This device holds a drawer at all — false for waiters and the kitchen,
    /// who are never locked.
    pub holds_drawer: bool,
    /// Set when the refusal is a till open somewhere else.
    pub elsewhere: Option<TillElsewhereView>,
}

// ── open: verification (contract §4.5) ─────────────────────────────────────

/// Where the person's till is open, when it is not this device.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TillElsewhereView {
    pub till_id: String,
    pub device_code: Option<String>,
    pub device_label: Option<String>,
    pub opened_at: String,
    /// `server` | `lan`.
    pub source: String,
}

/// What `open_till` did.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OpenTillOutcome {
    pub till: Option<TillView>,
    /// `server` | `lan` | `unverified` (empty when blocked).
    pub verification: String,
    pub open_elsewhere: Option<TillElsewhereView>,
}

/// A LAN peer's advert of an open till (`lan::BeaconTill` + its device).
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct LanTillSighting {
    pub till_id: String,
    pub device_id: String,
    pub device_code: Option<String>,
    pub opened_at: String,
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) enum OpenDecision {
    /// The person's till is open on another device — no enqueue.
    Blocked(TillElsewhereView),
    /// The server already holds the person's open till on THIS device.
    Resume(Box<TillRecord>),
    /// Open a new till with this verification.
    Allow(&'static str),
}

/// Decide an open from what can actually VERIFY it. Device-local memory is
/// deliberately not an input: the only checks are the live server and live LAN
/// peers; when neither answers, the open is allowed and marked unverified.
///
/// `server` = the `/tills/branches/{b}/current` prefill when the call succeeded.
/// `lan_sighting` = a live peer advertising this person's open till on ANOTHER
/// device. `lan_teller_peer_live` = at least one live teller peer at the branch.
pub(crate) fn decide_open(
    server: Option<&models::TillPreFill>,
    this_device_id: &str,
    lan_sighting: Option<&LanTillSighting>,
    lan_teller_peer_live: bool,
) -> OpenDecision {
    if let Some(pf) = server {
        if let Some(b) = pf
            .open_elsewhere
            .iter()
            .find(|b| !same_device(&b.device_id, this_device_id))
        {
            return OpenDecision::Blocked(TillElsewhereView {
                till_id: b.id.to_string(),
                device_code: b.device_code.clone().flatten(),
                device_label: b.device_label.clone().flatten(),
                opened_at: b.opened_at.to_rfc3339(),
                source: "server".into(),
            });
        }
        if let Some(t) = open_till_of(pf) {
            let t = TillRecord::from_api(t);
            if t.device_id.as_deref() == Some(this_device_id) {
                return OpenDecision::Resume(Box::new(t));
            }
            // An open till the server did not list as elsewhere but that names a
            // different device is still elsewhere.
            if t.device_id.is_some() {
                return OpenDecision::Blocked(TillElsewhereView {
                    till_id: t.id.clone(),
                    device_code: t.device_code.clone(),
                    device_label: t.device_label.clone(),
                    opened_at: t.opened_at.clone(),
                    source: "server".into(),
                });
            }
            // A legacy till (opened by an old client, no device): it is the
            // person's drawer and no other device claims it — resume it here.
            return OpenDecision::Resume(Box::new(t));
        }
        return OpenDecision::Allow("server");
    }
    if let Some(s) = lan_sighting.filter(|s| s.device_id != this_device_id) {
        return OpenDecision::Blocked(TillElsewhereView {
            till_id: s.till_id.clone(),
            device_code: s.device_code.clone(),
            device_label: None,
            opened_at: s.opened_at.clone(),
            source: "lan".into(),
        });
    }
    if lan_teller_peer_live {
        OpenDecision::Allow("lan")
    } else {
        OpenDecision::Allow("unverified")
    }
}

/// Does a server device id name this device? (ids compare as UUIDs, so case
/// never makes this device look like another one).
fn same_device(device_id: &Option<Option<uuid::Uuid>>, this_device_id: &str) -> bool {
    match (device_id.flatten(), uuid::Uuid::parse_str(this_device_id)) {
        (Some(d), Ok(me)) => d == me,
        _ => false,
    }
}

/// The prefill's open till, when it is actually open.
fn open_till_of(pf: &models::TillPreFill) -> Option<&models::Till> {
    pf.open_till
        .as_ref()
        .and_then(|o| o.as_deref())
        .filter(|t| t.status == models::TillStatus::Open)
}

/// kv key: what sign-in said about the person's open till (`/auth/login`'s
/// `open_till`), with when it was said.
fn login_open_till_key(user_id: &str) -> String {
    format!("till:login_open:{user_id}")
}

/// How long sign-in's answer stands in for a failed `/tills/.../current`.
pub(crate) const LOGIN_OPEN_TILL_TTL_SECS: i64 = 300;

#[derive(Serialize, Deserialize)]
struct LoginOpenTill {
    at: chrono::DateTime<chrono::Utc>,
    till: Option<models::TillBrief>,
}

/// Remember sign-in's server check (decision 4a: the live check at sign-in).
pub(crate) fn remember_login_open_till(
    store: &Store,
    user_id: &str,
    till: Option<models::TillBrief>,
    now: chrono::DateTime<chrono::Utc>,
) {
    if let Ok(raw) = serde_json::to_string(&LoginOpenTill { at: now, till }) {
        let _ = store.kv_put(&login_open_till_key(user_id), &raw);
    }
}

/// Sign-in's answer as a prefill, while it is fresh: the person's till open on
/// another device is `open_elsewhere`; open on THIS device it resumes the local
/// record (sign-in does not carry the opening cash, so only a till this device
/// already holds can resume); no open till is a clean, server-verified prefill.
pub(crate) fn login_prefill(
    store: &Store,
    user_id: &str,
    this_device_id: &str,
    now: chrono::DateTime<chrono::Utc>,
) -> Option<models::TillPreFill> {
    let raw = store.kv_get(&login_open_till_key(user_id)).ok()??;
    let said: LoginOpenTill = serde_json::from_str(&raw).ok()?;
    if (now - said.at).num_seconds() > LOGIN_OPEN_TILL_TTL_SECS {
        return None;
    }
    let mut pf = models::TillPreFill::default();
    let Some(brief) = said.till.filter(|b| b.status == models::TillStatus::Open) else {
        return Some(pf);
    };
    pf.has_open_till = true;
    if !same_device(&brief.device_id, this_device_id) && brief.device_id.flatten().is_some() {
        pf.open_elsewhere = vec![brief];
        return Some(pf);
    }
    let local = record(store, &brief.id.to_string())?;
    let mut till = models::Till::new(
        brief.branch_id,
        0,
        brief.id,
        brief.opened_at,
        brief.opened_while_another_open,
        local.opening_cash as i32,
        local.opening_cash_was_edited,
        models::TillStatus::Open,
        brief.teller_id,
        brief.teller_name.clone(),
        brief.verification,
    );
    till.device_id = brief.device_id;
    till.device_code = brief.device_code.clone();
    till.device_label = brief.device_label.clone();
    pf.open_till = Some(Some(Box::new(till)));
    Some(pf)
}

/// What to do with the local till after the server's prefill comes back.
#[derive(Debug)]
pub(crate) enum TillReconcile {
    /// The server holds the person's open till on this device — adopt it.
    Adopt(Box<TillRecord>),
    /// Keep the local state (our open/close has not reached the server yet).
    KeepLocal,
    /// The server authoritatively has no open till here (e.g. force-closed).
    Clear,
}

/// Every till row this device holds for `branch` (the changefeed's `till` rows
/// and this device's own), any status.
pub(crate) fn branch_records(store: &Store, branch: &str) -> Vec<TillRecord> {
    store
        .with_conn(|c| {
            let mut st = c.prepare("SELECT raw FROM ledger_tills WHERE branch_id=?1 OR branch_id=''")?;
            let rows: Vec<String> = st.query_map([branch], |r| r.get(0))?.collect::<Result<Vec<_>, _>>()?;
            Ok(rows.iter().filter_map(|raw| serde_json::from_str::<TillRecord>(raw).ok()).collect())
        })
        .unwrap_or_default()
}

/// A row's opening instant, for ordering (unparseable sorts first).
fn opened_instant(t: &TillRecord) -> Option<chrono::DateTime<chrono::FixedOffset>> {
    chrono::DateTime::parse_from_rfc3339(&t.opened_at).ok()
}

/// Does a till row name THIS device (or no device: a legacy till)?
fn row_is_here(t: &TillRecord, this_device_id: &str) -> bool {
    match t.device_id.as_deref().filter(|d| !d.is_empty()) {
        None => true,
        Some(d) => match (uuid::Uuid::parse_str(d), uuid::Uuid::parse_str(this_device_id)) {
            (Ok(a), Ok(b)) => a == b,
            _ => d == this_device_id,
        },
    }
}

/// The person's till open on ANOTHER device, from the rows. PURE.
pub(crate) fn elsewhere_from_rows(rows: &[TillRecord], user_id: &str, this_device_id: &str) -> Option<TillElsewhereView> {
    rows.iter()
        .filter(|t| t.teller_id == user_id && t.status == "open" && !row_is_here(t, this_device_id))
        .max_by_key(|t| opened_instant(t))
        .map(|t| TillElsewhereView {
            till_id: t.id.clone(),
            device_code: t.device_code.clone(),
            device_label: t.device_label.clone(),
            opened_at: t.opened_at.clone(),
            source: "server".into(),
        })
}

/// Reconcile the signed-in person's local till with the synced till rows. PURE.
/// The rows are the server's view as of the last pull plus this device's own
/// writes:
/// - "no open till here" is authoritative only once our own `open_till` has
///   reached the server (`open_pending` keeps the optimistic till);
/// - "still open" is stale while our `close_till` is queued (`close_pending`);
/// - a till open on ANOTHER device is never adopted here.
pub(crate) fn reconcile_rows(
    rows: &[TillRecord],
    user_id: &str,
    this_device_id: &str,
    local: Option<&TillView>,
    open_pending: bool,
    close_pending: bool,
) -> TillReconcile {
    let here = rows
        .iter()
        .filter(|t| t.teller_id == user_id && t.status == "open" && row_is_here(t, this_device_id))
        .max_by_key(|t| opened_instant(t));
    if let Some(t) = here {
        if close_pending && local.map(|l| l.id == t.id).unwrap_or(false) {
            return TillReconcile::KeepLocal;
        }
        if open_pending && local.map(|l| l.is_open && l.id != t.id).unwrap_or(false) {
            return TillReconcile::KeepLocal;
        }
        return TillReconcile::Adopt(Box::new(t.clone()));
    }
    if open_pending || close_pending {
        TillReconcile::KeepLocal
    } else {
        TillReconcile::Clear
    }
}

/// The DRAWER's most recent declared close (the server's
/// `last_close_declared`), from the rows. PURE.
///
/// Mirrors the backend exactly: a drawer is a physical box, identified by
/// DEVICE where one is known and by the branch otherwise — never by the
/// person, because cash stays in the drawer when a shift changes. `rows` is
/// already this branch's; the caller must not pass another branch's.
pub(crate) fn last_close_declared_rows(rows: &[TillRecord], device_id: Option<&str>) -> Option<i64> {
    let closed = || {
        rows.iter()
            .filter(|t| matches!(t.status.as_str(), "closed" | "force_closed"))
            .filter(|t| t.closing_cash_declared.is_some())
    };
    // This device's own last close wins; otherwise the drawer this branch ran.
    device_id
        .and_then(|dev| {
            closed()
                .filter(|t| t.device_id.as_deref() == Some(dev))
                .max_by_key(|t| opened_instant(t))
        })
        .or_else(|| closed().max_by_key(|t| opened_instant(t)))
        .and_then(|t| t.closing_cash_declared)
}

// ── close: reconciliation + warnings (contract §4.8) ───────────────────────

/// Open bills left at the branch, shown after a till opens. `None` when zero.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OpenBillsNoticeView {
    pub open_bills_count: i64,
    pub open_bills_amount_minor: i64,
    pub oldest_opened_at: Option<String>,
    pub old_bills_count: i64,
    pub old_bill_hours: i64,
    pub seated_tables_count: i64,
    pub since: Option<String>,
}

/// A bill as the local mirror knows it: when it opened and what it holds.
#[derive(Clone, Debug)]
pub(crate) struct LocalBill {
    pub opened_at: String,
    pub amount_minor: i64,
}

/// The notice computed from local mirrors (offline). Old = opened more than
/// `old_bill_hours` before `now`.
pub(crate) fn local_open_bills_notice(
    bills: &[LocalBill],
    seated_tables: i64,
    old_bill_hours: i64,
    since: Option<String>,
    now: chrono::DateTime<chrono::Utc>,
) -> Option<OpenBillsNoticeView> {
    if bills.is_empty() {
        return None;
    }
    let cutoff = now - chrono::Duration::hours(old_bill_hours.max(1));
    let parse = |s: &str| {
        chrono::DateTime::parse_from_rfc3339(s)
            .ok()
            .map(|d| d.with_timezone(&chrono::Utc))
    };
    let oldest = bills
        .iter()
        .filter_map(|b| parse(&b.opened_at).map(|d| (d, b.opened_at.clone())))
        .min_by_key(|(d, _)| *d)
        .map(|(_, s)| s);
    Some(OpenBillsNoticeView {
        open_bills_count: bills.len() as i64,
        open_bills_amount_minor: bills.iter().map(|b| b.amount_minor).sum(),
        oldest_opened_at: oldest,
        old_bills_count: bills
            .iter()
            .filter(|b| parse(&b.opened_at).map(|d| d < cutoff).unwrap_or(false))
            .count() as i64,
        old_bill_hours: old_bill_hours.max(1),
        seated_tables_count: seated_tables,
        since,
    })
}

/// One method line the teller checks at close.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ReconciliationInput {
    pub method: String,
    /// `checked` | `disagreed` | `counted` (a blind count: the core compares
    /// the declared amount with the system total itself).
    pub status: String,
    pub declared_amount_minor: Option<i64>,
    pub note: Option<String>,
}

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CloseTillMethodView {
    pub method: String,
    pub label: String,
    pub is_cash: bool,
    pub system_total_minor: i64,
    pub order_count: i64,
}

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LastTillWarningView {
    pub open_bills_count: i64,
    pub open_bills_amount_minor: i64,
    pub seated_tables_count: i64,
}

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CloseTillPreviewView {
    pub till: TillView,
    pub expected_cash_minor: i64,
    pub methods: Vec<CloseTillMethodView>,
    pub last_till_warning: Option<LastTillWarningView>,
    pub from_server: bool,
    /// The person counts blind: expected figures are zeroed (cash spot design).
    pub figures_hidden: bool,
}

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ReconciliationLineView {
    pub method: String,
    pub label: String,
    pub is_cash: bool,
    pub system_total_minor: i64,
    /// `checked` | `disagreed` | `unreviewed`.
    pub status: String,
    pub declared_amount_minor: Option<i64>,
    pub note: Option<String>,
    pub changed_after_close: bool,
}

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CloseTillOutcomeView {
    /// `true` while the close is still in the outbox.
    pub queued: bool,
    pub reconciliation: Vec<ReconciliationLineView>,
    pub last_till_warning: Option<LastTillWarningView>,
}

/// A till open at the branch: from the server list, a LAN advert, or both.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BranchOpenTillView {
    pub till_id: String,
    pub teller_id: String,
    pub teller_name: String,
    pub device_code: Option<String>,
    pub device_label: Option<String>,
    pub opened_at: String,
    pub is_this_device: bool,
    /// `server` | `lan` | `both`.
    pub source: String,
}

/// Validate + convert the close inputs (non-blocking rules, contract §2.2 T9):
/// a non-cash `disagreed` line needs an amount and a note; the cash line's
/// status is derived from the count, so it is never sent as input.
pub(crate) fn reconciliation_wire(
    inputs: &[ReconciliationInput],
) -> Result<Vec<models::ReconciliationInput>, crate::error::CoreError> {
    let mut out = Vec::new();
    for i in inputs {
        let status = i.status.trim().to_ascii_lowercase();
        if status != "checked" && status != "disagreed" {
            return Err(crate::error::CoreError::Validation {
                field: "reconciliation.status".into(),
                detail: format!("unknown status {}", i.status),
            });
        }
        let note = i
            .note
            .as_deref()
            .map(str::trim)
            .filter(|n| !n.is_empty())
            .map(str::to_string);
        if status == "disagreed" {
            if i.declared_amount_minor.is_none() {
                return Err(crate::error::CoreError::Validation {
                    field: "reconciliation.declared_amount".into(),
                    detail: "RECONCILIATION_AMOUNT_REQUIRED".into(),
                });
            }
            if note.is_none() {
                return Err(crate::error::CoreError::Validation {
                    field: "reconciliation.note".into(),
                    detail: "RECONCILIATION_NOTE_REQUIRED".into(),
                });
            }
        }
        let mut line = models::ReconciliationInput::new(i.method.clone(), status.clone());
        if status == "disagreed" {
            line.declared_amount = i
                .declared_amount_minor
                .and_then(|v| i32::try_from(v).ok())
                .map(Some);
        }
        line.note = note.map(Some);
        out.push(line);
    }
    Ok(out)
}

/// The lines as recorded at close, offline: what the teller said per method,
/// methods left out as `unreviewed`, the cash line from the count.
pub(crate) fn local_reconciliation_lines(
    methods: &[CloseTillMethodView],
    inputs: &[models::ReconciliationInput],
    closing_cash_minor: i64,
    cash_note: Option<&str>,
) -> Vec<ReconciliationLineView> {
    methods
        .iter()
        .map(|m| {
            if m.is_cash {
                let matches = closing_cash_minor == m.system_total_minor;
                return ReconciliationLineView {
                    method: m.method.clone(),
                    label: m.label.clone(),
                    is_cash: true,
                    system_total_minor: m.system_total_minor,
                    status: if matches { "checked" } else { "disagreed" }.into(),
                    declared_amount_minor: Some(closing_cash_minor),
                    note: cash_note.map(str::to_string),
                    changed_after_close: false,
                };
            }
            match inputs.iter().find(|i| i.method == m.method) {
                Some(i) => ReconciliationLineView {
                    method: m.method.clone(),
                    label: m.label.clone(),
                    is_cash: false,
                    system_total_minor: m.system_total_minor,
                    status: i.status.clone(),
                    declared_amount_minor: i.declared_amount.flatten().map(i64::from),
                    note: i.note.clone().flatten(),
                    changed_after_close: false,
                },
                None => ReconciliationLineView {
                    method: m.method.clone(),
                    label: m.label.clone(),
                    is_cash: false,
                    system_total_minor: m.system_total_minor,
                    status: "unreviewed".into(),
                    declared_amount_minor: None,
                    note: None,
                    changed_after_close: false,
                },
            }
        })
        .collect()
}

pub(crate) fn reconciliation_lines_from_api(
    lines: &[models::TillReconciliationLine],
    label: &dyn Fn(&str) -> String,
) -> Vec<ReconciliationLineView> {
    lines
        .iter()
        .map(|l| ReconciliationLineView {
            method: l.method.clone(),
            label: label(&l.method),
            is_cash: l.is_cash,
            system_total_minor: i64::from(l.system_total),
            status: l.status.clone(),
            declared_amount_minor: l.declared_amount.flatten().map(i64::from),
            note: l.note.clone().flatten(),
            changed_after_close: l.changed_after_close,
        })
        .collect()
}

/// The last-till warning (never blocks): only when no other open till remains
/// and something is still open or seated.
pub(crate) fn last_till_warning(
    other_open_tills: usize,
    open_bills_count: i64,
    open_bills_amount_minor: i64,
    seated_tables_count: i64,
) -> Option<LastTillWarningView> {
    (other_open_tills == 0 && (open_bills_count > 0 || seated_tables_count > 0)).then(|| {
        LastTillWarningView {
            open_bills_count,
            open_bills_amount_minor,
            seated_tables_count,
        }
    })
}

// ── payment method availability (decision 10) ──────────────────────────────

/// Effective methods = active org methods ∩ branch list ∩ user list ∩ device list,
/// where an absent list means "no restriction". Order of `all` is preserved.
pub(crate) fn effective_method_ids(
    all_active: &[String],
    branch: Option<&[String]>,
    user: Option<&[String]>,
    device: Option<&[String]>,
) -> Vec<String> {
    all_active
        .iter()
        .filter(|id| {
            [branch, user, device]
                .iter()
                .all(|list| list.map(|l| l.iter().any(|x| x == *id)).unwrap_or(true))
        })
        .cloned()
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const DEV: &str = "dddddddd-0000-0000-0000-000000000001";
    const OTHER_DEV: &str = "dddddddd-0000-0000-0000-000000000002";

    /// A server `Till` open on `device` (ids are stable v5 UUIDs of the labels).
    fn api(id: &str, teller: &str, status: &str, device: &str) -> Box<models::Till> {
        Box::new(models::Till {
            id: uid(id),
            branch_id: uid("B1"),
            teller_id: uid(teller),
            teller_name: format!("name-{teller}"),
            status: serde_json::from_value(serde_json::Value::String(status.into())).unwrap(),
            opening_cash: 500,
            opened_at: chrono::DateTime::parse_from_rfc3339("2026-09-13T09:00:00Z").unwrap(),
            device_id: Some(Some(uuid::Uuid::parse_str(device).unwrap())),
            verification: models::TillVerification::Server,
            ..Default::default()
        })
    }

    fn uid(label: &str) -> uuid::Uuid {
        uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_OID, label.as_bytes())
    }

    fn rec(id: &str, teller: &str, status: &str) -> TillRecord {
        TillRecord {
            id: id.into(),
            branch_id: "B1".into(),
            teller_id: teller.into(),
            teller_name: format!("name-{teller}"),
            status: status.into(),
            opening_cash: 500,
            opened_at: "2026-09-13T09:00:00Z".into(),
            device_id: Some(DEV.into()),
            verification: Some("server".into()),
            ..Default::default()
        }
    }

    #[test]
    fn open_till_server_blocks_elsewhere() {
        let pf = models::TillPreFill {
            open_elsewhere: vec![models::TillBrief {
                id: uid("T9"),
                device_id: Some(Some(uuid::Uuid::parse_str(OTHER_DEV).unwrap())),
                device_code: Some(Some("36B".into())),
                opened_at: chrono::DateTime::parse_from_rfc3339("2026-09-13T08:00:00Z").unwrap(),
                status: models::TillStatus::Open,
                ..Default::default()
            }],
            ..Default::default()
        };
        match decide_open(Some(&pf), DEV, None, true) {
            OpenDecision::Blocked(e) => {
                assert_eq!(e.till_id, uid("T9").to_string());
                assert_eq!(e.source, "server");
                assert_eq!(e.device_code.as_deref(), Some("36B"));
            }
            other => panic!("expected blocked, got {other:?}"),
        }
        // A clean prefill allows, verified by the server (LAN is not consulted).
        let clean = models::TillPreFill::default();
        assert_eq!(
            decide_open(Some(&clean), DEV, None, false),
            OpenDecision::Allow("server")
        );
        // The person's open till ON THIS device resumes instead of opening twice.
        let here = models::TillPreFill {
            open_till: Some(Some(api("T1", "U1", "open", DEV))),
            ..Default::default()
        };
        assert!(matches!(
            decide_open(Some(&here), DEV, None, false),
            OpenDecision::Resume(t) if t.id == uid("T1").to_string()
        ));
    }

    #[test]
    fn open_till_lan_blocks_elsewhere() {
        let sighting = LanTillSighting {
            till_id: "T7".into(),
            device_id: OTHER_DEV.into(),
            device_code: Some("K2".into()),
            opened_at: "2026-09-13T07:00:00Z".into(),
        };
        match decide_open(None, DEV, Some(&sighting), true) {
            OpenDecision::Blocked(e) => {
                assert_eq!(e.source, "lan");
                assert_eq!(e.till_id, "T7");
            }
            other => panic!("expected blocked, got {other:?}"),
        }
        // A live teller peer with no sighting verifies the open over the LAN.
        assert_eq!(decide_open(None, DEV, None, true), OpenDecision::Allow("lan"));
        // A peer advertising OUR device is not "elsewhere".
        let own = LanTillSighting {
            device_id: DEV.into(),
            ..sighting
        };
        assert_eq!(
            decide_open(None, DEV, Some(&own), true),
            OpenDecision::Allow("lan")
        );
    }

    #[test]
    fn open_till_offline_unverified_allowed() {
        assert_eq!(
            decide_open(None, DEV, None, false),
            OpenDecision::Allow("unverified")
        );
    }

    #[test]
    fn open_till_ignores_device_local_memory() {
        // The device REMEMBERS the person holding an open till recorded against
        // another device (a cached list, an old record). Fully offline with no
        // peers, that memory is not a check: the decision has no input for it and
        // the open is allowed, unverified.
        let store = Store::open("").unwrap();
        let mut remembered = rec("OLD", "U1", "open");
        remembered.device_id = Some(OTHER_DEV.into());
        save(&store, &remembered).unwrap();
        set_active_user(&store, Some("U1")).unwrap();
        assert_eq!(
            decide_open(None, DEV, None, false),
            OpenDecision::Allow("unverified")
        );
    }

    #[test]
    fn two_tills_one_device_are_person_scoped() {
        let store = Store::open("").unwrap();
        save(&store, &rec("TA", "UA", "open")).unwrap();
        save(&store, &rec("TB", "UB", "open")).unwrap();
        set_active_user(&store, Some("UA")).unwrap();
        assert_eq!(current(&store).unwrap().unwrap().id, "TA");
        set_active_user(&store, Some("UB")).unwrap();
        assert_eq!(current(&store).unwrap().unwrap().id, "TB");
        // Closing B's till (the close verb's own commit) leaves A's open and advertised.
        let closing = current(&store).unwrap().unwrap().id;
        store
            .with_tx(|tx| {
                crate::ledger::local::commit_close_till(
                    tx,
                    &crate::store::NewOutboxOp {
                        id: "TB:close".into(),
                        op_type: "close_till".into(),
                        idempotency_key: "TB:close".into(),
                        payload: "{}".into(),
                        event_at: "2026-09-14T10:00:00Z".into(),
                        till_id: Some("TB".into()),
                        entity_type: Some(crate::ledger::T_TILL.into()),
                        entity_id: Some(closing.clone()),
                        ..Default::default()
                    },
                    "2026-09-14T10:00:00Z",
                    0,
                )
            })
            .unwrap();
        assert!(!current(&store).unwrap().unwrap().is_open);
        let open: Vec<String> = open_on_device(&store).into_iter().map(|t| t.id).collect();
        assert_eq!(open, vec!["TA".to_string()]);
        // Signed out: nobody's till is current, both records stay.
        set_active_user(&store, None).unwrap();
        assert!(current(&store).unwrap().is_none());
        assert!(record(&store, "TA").is_some() && record(&store, "TB").is_some());
        // A person with no till on this device has none current.
        set_active_user(&store, Some("UC")).unwrap();
        assert!(current(&store).unwrap().is_none());
    }

    #[test]
    fn legacy_current_shift_becomes_the_tellers_till() {
        let store = Store::open("").unwrap();
        let json = r#"{"branch_id":"00000000-0000-0000-0000-0000000000b1",
          "id":"00000000-0000-0000-0000-0000000000a1","opened_at":"2026-06-20T09:00:00Z",
          "opening_cash":50000,"opening_cash_was_edited":false,"status":"open",
          "teller_id":"00000000-0000-0000-0000-0000000000c1","teller_name":"Sara","till_id":"ee"}"#;
        store.kv_put(LEGACY_CURRENT_SHIFT_KEY, json).unwrap();
        set_active_user(&store, Some("00000000-0000-0000-0000-0000000000c1")).unwrap();
        let v = current(&store).unwrap().unwrap();
        assert_eq!(v.teller_name, "Sara");
        assert_eq!(v.opening_cash_minor, 50000);
        assert!(v.is_open);
        assert_eq!(v.verification, "legacy");
        assert!(store.kv_get(LEGACY_CURRENT_SHIFT_KEY).unwrap().is_none());
        // A literal "null" legacy value migrates to nothing.
        store.kv_put(LEGACY_CURRENT_SHIFT_KEY, "null").unwrap();
        migrate_legacy_current(&store).unwrap();
        assert!(store.kv_get(LEGACY_CURRENT_SHIFT_KEY).unwrap().is_none());
    }

    #[test]
    fn reconcile_adopts_only_a_till_on_this_device() {
        let u = "U1";
        let local = view_from(&rec("T1", u, "open"));
        let here = vec![rec("T1", u, "open")];
        assert!(matches!(reconcile_rows(&here, u, DEV, Some(&local), false, false), TillReconcile::Adopt(_)));
        // Open on another device: never adopted here.
        let mut there = rec("T2", u, "open");
        there.device_id = Some(OTHER_DEV.into());
        assert!(matches!(reconcile_rows(&[there], u, DEV, None, false, false), TillReconcile::Clear));
        // Our close is queued: the rows' "still open" is stale.
        assert!(matches!(reconcile_rows(&here, u, DEV, Some(&local), false, true), TillReconcile::KeepLocal));
        // No open till in the rows but our open is queued: keep the optimistic till.
        let closed = vec![rec("T1", u, "closed")];
        assert!(matches!(reconcile_rows(&closed, u, DEV, Some(&local), true, false), TillReconcile::KeepLocal));
        assert!(matches!(reconcile_rows(&closed, u, DEV, Some(&local), false, false), TillReconcile::Clear));
        // Someone else's open till is not mine; a legacy till (no device) is.
        assert!(matches!(reconcile_rows(&[rec("T3", "U2", "open")], u, DEV, None, false, false), TillReconcile::Clear));
        let mut legacy = rec("T4", u, "open");
        legacy.device_id = None;
        assert!(matches!(reconcile_rows(&[legacy], u, DEV, None, false, false), TillReconcile::Adopt(_)));
    }

    #[test]
    fn the_rows_say_where_a_persons_till_is_open_and_what_they_last_declared() {
        let u = "U1";
        let mut there = rec("T2", u, "open");
        there.device_id = Some(OTHER_DEV.to_uppercase());
        there.device_code = Some("D-2".into());
        let rows = vec![rec("T1", u, "open"), there, rec("T3", "U2", "open")];
        let e = elsewhere_from_rows(&rows, u, DEV).expect("open on the other device");
        assert_eq!((e.till_id.as_str(), e.device_code.as_deref(), e.source.as_str()), ("T2", Some("D-2"), "server"));
        assert!(elsewhere_from_rows(&rows[..1], u, DEV).is_none(), "this device's own till is not elsewhere");
        assert!(elsewhere_from_rows(&rows, u, &OTHER_DEV.to_uppercase()).is_some(), "ids compare as UUIDs");

        let mut old = rec("T5", u, "closed");
        old.opened_at = "2026-09-11T09:00:00Z".into();
        old.closing_cash_declared = Some(700);
        let mut newer = rec("T6", u, "force_closed");
        newer.opened_at = "2026-09-12T09:00:00+02:00".into();
        newer.closing_cash_declared = Some(900);
        let mut undeclared = rec("T7", u, "closed");
        undeclared.opened_at = "2026-09-12T12:00:00Z".into();
        // ANOTHER person's close still counts: the money is in the drawer,
        // not in the person. This is the whole point of the change.
        let mut other = rec("T8", "U2", "closed");
        other.opened_at = "2026-09-13T09:00:00Z".into();
        other.closing_cash_declared = Some(5);
        other.device_id = Some(OTHER_DEV.into());
        let rows = [old.clone(), newer.clone(), undeclared, other.clone()];
        assert_eq!(last_close_declared_rows(&rows, None), Some(5), "newest close wins, whoever closed it");
        // This device's own last close wins over a newer one on another device.
        let mut mine = rec("T9", u, "closed");
        mine.opened_at = "2026-09-12T20:00:00Z".into();
        mine.closing_cash_declared = Some(450);
        mine.device_id = Some(DEV.into());
        assert_eq!(last_close_declared_rows(&[other, mine], Some(DEV)), Some(450));
        // A device with no history of its own falls back to the branch's.
        assert_eq!(last_close_declared_rows(&[newer], Some(OTHER_DEV)), Some(900));
        assert_eq!(last_close_declared_rows(&[old], Some(DEV)), Some(700));
        assert_eq!(last_close_declared_rows(&[], Some(DEV)), None);
    }

    #[test]
    fn available_methods_intersection_offline() {
        let all: Vec<String> = ["cash", "cib-counter", "cib-2", "wallet"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        let branch = vec!["cash".to_string(), "cib-counter".into(), "cib-2".into()];
        let user = vec!["cash".to_string(), "cib-counter".into(), "wallet".into()];
        let device = vec!["cib-counter".to_string(), "cash".into()];
        assert_eq!(
            effective_method_ids(&all, Some(&branch), Some(&user), Some(&device)),
            vec!["cash".to_string(), "cib-counter".into()]
        );
        // No rows anywhere = no restriction.
        assert_eq!(effective_method_ids(&all, None, None, None), all);
        // Only the device narrows.
        assert_eq!(
            effective_method_ids(&all, None, None, Some(&device)),
            vec!["cash".to_string(), "cib-counter".into()]
        );
    }

    #[test]
    fn reconciliation_requires_amount_and_note_on_disagree_and_rolls_unreviewed() {
        let bad = [ReconciliationInput {
            method: "Card".into(),
            status: "disagreed".into(),
            declared_amount_minor: Some(100),
            note: Some("  ".into()),
        }];
        assert!(reconciliation_wire(&bad).is_err());
        let ok = [ReconciliationInput {
            method: "Card".into(),
            status: "checked".into(),
            declared_amount_minor: Some(999),
            note: None,
        }];
        let wire = reconciliation_wire(&ok).unwrap();
        assert_eq!(wire[0].declared_amount, None, "checked carries no amount");
        let methods = vec![
            CloseTillMethodView {
                method: "Cash".into(),
                label: "Cash".into(),
                is_cash: true,
                system_total_minor: 1000,
                order_count: 3,
            },
            CloseTillMethodView {
                method: "Card".into(),
                label: "Card".into(),
                is_cash: false,
                system_total_minor: 500,
                order_count: 1,
            },
            CloseTillMethodView {
                method: "Wallet".into(),
                label: "Wallet".into(),
                is_cash: false,
                system_total_minor: 200,
                order_count: 1,
            },
        ];
        let lines = local_reconciliation_lines(&methods, &wire, 900, Some("short"));
        assert_eq!(lines[0].status, "disagreed");
        assert_eq!(lines[0].declared_amount_minor, Some(900));
        assert_eq!(lines[1].status, "checked");
        assert_eq!(lines[2].status, "unreviewed");
    }

    #[test]
    fn last_till_warning_only_when_last_and_something_open() {
        assert!(last_till_warning(1, 3, 100, 2).is_none());
        assert!(last_till_warning(0, 0, 0, 0).is_none());
        let w = last_till_warning(0, 2, 4500, 0).unwrap();
        assert_eq!(w.open_bills_amount_minor, 4500);
    }

    #[test]
    fn open_bills_notice_counts_old_bills() {
        let now = chrono::DateTime::parse_from_rfc3339("2026-09-13T12:00:00Z")
            .unwrap()
            .with_timezone(&chrono::Utc);
        let bills = vec![
            LocalBill {
                opened_at: "2026-09-13T11:00:00Z".into(),
                amount_minor: 100,
            },
            LocalBill {
                opened_at: "2026-09-13T07:00:00Z".into(),
                amount_minor: 250,
            },
        ];
        let n = local_open_bills_notice(&bills, 1, 3, None, now).unwrap();
        assert_eq!(n.open_bills_count, 2);
        assert_eq!(n.old_bills_count, 1);
        assert_eq!(n.open_bills_amount_minor, 350);
        assert_eq!(n.oldest_opened_at.as_deref(), Some("2026-09-13T07:00:00Z"));
        assert!(local_open_bills_notice(&[], 0, 3, None, now).is_none());
    }

    #[test]
    fn sign_in_answer_stands_in_for_a_failed_current_call() {
        let store = Store::open("").unwrap();
        let now = chrono::Utc::now();
        let brief = |device: &str| models::TillBrief {
            id: uid("T5"),
            branch_id: uid("B1"),
            teller_id: uid("U1"),
            teller_name: "Sara".into(),
            status: models::TillStatus::Open,
            opened_at: chrono::DateTime::parse_from_rfc3339("2026-09-13T08:00:00Z").unwrap(),
            device_id: Some(Some(uuid::Uuid::parse_str(device).unwrap())),
            device_code: Some(Some("36B".into())),
            verification: models::TillVerification::Server,
            ..Default::default()
        };
        // Nothing said at sign-in: no stand-in.
        assert!(login_prefill(&store, "U1", DEV, now).is_none());
        // Open on another device: blocks, as the server would.
        remember_login_open_till(&store, "U1", Some(brief(OTHER_DEV)), now);
        let pf = login_prefill(&store, "U1", DEV, now).unwrap();
        assert!(matches!(decide_open(Some(&pf), DEV, None, false), OpenDecision::Blocked(e) if e.source == "server"));
        // Stale after the window: LAN / unverified decide again.
        let later = now + chrono::Duration::seconds(LOGIN_OPEN_TILL_TTL_SECS + 1);
        assert!(login_prefill(&store, "U1", DEV, later).is_none());
        // No open till at sign-in: a clean, server-verified open.
        remember_login_open_till(&store, "U1", None, now);
        let pf = login_prefill(&store, "U1", DEV, now).unwrap();
        assert_eq!(decide_open(Some(&pf), DEV, None, true), OpenDecision::Allow("server"));
        // Open on THIS device: resumes the record the device holds, cash kept.
        let mut local = rec("T5", "U1", "open");
        local.id = uid("T5").to_string();
        local.opening_cash = 7_500;
        save(&store, &local).unwrap();
        remember_login_open_till(&store, "U1", Some(brief(DEV)), now);
        let pf = login_prefill(&store, "U1", DEV, now).unwrap();
        match decide_open(Some(&pf), DEV, None, false) {
            OpenDecision::Resume(t) => {
                assert_eq!(t.id, uid("T5").to_string());
                assert_eq!(t.opening_cash, 7_500);
            }
            other => panic!("expected resume, got {other:?}"),
        }
    }

    #[test]
    fn queued_requests_with_shift_id_decode_as_till_id() {
        let till = "00000000-0000-0000-0000-00000000c0de";
        let settle = format!(r#"{{"ticket_id":"k1","request":{{"payment_method":"Cash","shift_id":"{till}"}}}}"#);
        let cmd: crate::tickets::SettleTicketCommand = serde_json::from_str(&settle).unwrap();
        assert_eq!(cmd.request.till_id.to_string(), till);
        let refund = format!(
            r#"{{"request":{{"amount":100,"method":"Cash","order_id":"{till}","reason":"other","shift_id":"{till}"}}}}"#
        );
        let cmd: crate::orders::RefundOrderCommand = serde_json::from_str(&refund).unwrap();
        assert_eq!(cmd.request.till_id.flatten().unwrap().to_string(), till);
        // A payload that already says `till_id` wins over a stray legacy name.
        let both = format!(
            r#"{{"ticket_id":"k1","request":{{"payment_method":"Cash","till_id":"{till}","shift_id":"00000000-0000-0000-0000-000000000001"}}}}"#
        );
        let cmd: crate::tickets::SettleTicketCommand = serde_json::from_str(&both).unwrap();
        assert_eq!(cmd.request.till_id.to_string(), till);
    }

    #[test]
    fn a_cached_report_parses_the_pre_rework_shift_report() {
        let legacy = r#"[{"shift":{"id":"00000000-0000-0000-0000-0000000000a1","branch_id":"00000000-0000-0000-0000-0000000000b1",
            "teller_id":"00000000-0000-0000-0000-0000000000c1","teller_name":"Sara","status":"open","opening_cash":500,
            "opened_at":"2026-09-01T09:00:00Z","opening_cash_was_edited":false},
            "cash_movements":[],"cash_movements_in":0,"cash_movements_net":0,"cash_movements_out":0,"cash_tips":0,
            "expected_cash":900,"net_payments":0,"non_cash_tips":0,"payment_summary":[],"printed_at":"2026-09-01T18:00:00Z",
            "total_payments":0,"total_tips":0,"voided_amount":0,"cash_adjustments":0,"safe_drops":0}]"#;
        let r = parse_cached_report(legacy).expect("legacy report read");
        assert_eq!(r.expected_cash, 900);
        assert_eq!(r.till.verification, models::TillVerification::Legacy);
        // The object form a later build wrote parses too.
        let object = serde_json::to_string(&r).unwrap();
        assert_eq!(parse_cached_report(&object).unwrap().expected_cash, 900);
    }

    #[test]
    fn legacy_outbox_payloads_decode_into_till_commands() {
        let open = r#"{"branch_id":"B1","request":{"id":"00000000-0000-0000-0000-0000000000a1",
            "opening_cash":500,"till_id":"00000000-0000-0000-0000-0000000000ee","opened_at":"2026-06-20T09:00:00+00:00"}}"#;
        let cmd: OpenTillCommand = serde_json::from_str(open).unwrap();
        assert_eq!(cmd.request.opening_cash, 500);
        assert!(cmd.device_id.is_empty() && cmd.verification.is_empty());
        let close = r#"{"shift_id":"S1","request":{"closing_cash_declared":480,"cash_note":null}}"#;
        let c: CloseTillCommand = serde_json::from_str(close).unwrap();
        assert_eq!(c.till_id, "S1");
        assert!(c.request.reconciliation.is_none(), "filled with [] when sent");
        let cash = r#"{"shift_id":"S1","request":{"amount":100,"note":"float"}}"#;
        let m: CashMovementCommand = serde_json::from_str(cash).unwrap();
        assert_eq!(m.till_id, "S1");
        // Re-serialized, the new name is written.
        assert!(serde_json::to_string(&m).unwrap().contains("\"till_id\""));
    }

    #[test]
    fn suggested_opening_cash_roundtrips_and_clamps() {
        let store = Store::open("").unwrap();
        assert_eq!(suggested_opening_cash(&store).unwrap(), 0); // none known yet
        cache_suggested_opening_cash(&store, 48000).unwrap();
        assert_eq!(suggested_opening_cash(&store).unwrap(), 48000);
        cache_suggested_opening_cash(&store, -5).unwrap(); // non-positive clears
        assert_eq!(suggested_opening_cash(&store).unwrap(), 0);
    }

    #[test]
    fn report_view_adds_queued_cash_to_server_expected() {
        let mut report = models::TillReportResponse::default();
        report.expected_cash = 60000;
        report.till = Box::new(models::Till {
            opening_cash: 50000,
            ..Default::default()
        });
        report.total_payments = 15000;
        report.payment_summary = vec![models::PaymentSummaryRow::new(
            true,
            3,
            "Cash".into(),
            12000,
        )];
        let v = report_view(&report, 2280, &|m| m.to_string());
        assert_eq!(v.expected_cash_minor, 62280); // 60000 + 2280 queued
        assert_eq!(v.opening_cash_minor, 50000);
        assert_eq!(v.total_payments_minor, 15000);
        assert_eq!(v.payment_lines.len(), 1);
        assert_eq!(v.payment_lines[0].total_minor, 12000);
        assert!(v.from_server);
    }

    // ── cached_report_view: the offline close of a shift that already sold ────

    /// The regression this exists for: a teller signs into a shift that ALREADY
    /// has sales (opened on another device, or their own already-drained ones),
    /// then loses the network and closes. The outbox holds none of those sales,
    /// so rebuilding from local state alone expects only the opening float and
    /// the drawer reads a huge phantom "over".
    #[test]
    fn cached_report_view_keeps_the_server_figures_a_drained_shift_already_had() {
        let mut report = models::TillReportResponse::default();
        report.expected_cash = 60000; // opening 50000 + 10000 already taken
        report.till = Box::new(models::Till {
            opening_cash: 50000,
            ..Default::default()
        });
        report.total_payments = 10000;
        report.payment_summary = vec![models::PaymentSummaryRow::new(
            true,
            4,
            "Cash".into(),
            10000,
        )];

        // Nothing of this is in the outbox — it all drained before we went offline.
        let v = cached_report_view(&report, 0, vec![], &|m| m.to_string());

        // The old offline path returned opening cash (50000) and no payments.
        assert_eq!(v.expected_cash_minor, 60000);
        assert_eq!(v.total_payments_minor, 10000);
        assert_eq!(v.payment_lines.len(), 1);
        // Real figures, but a snapshot — the teller still sees "offline".
        assert!(!v.from_server);
    }

    #[test]
    fn cached_report_view_adds_queued_work_on_top_without_double_counting() {
        let mut report = models::TillReportResponse::default();
        report.expected_cash = 60000;
        report.till = Box::new(models::Till {
            opening_cash: 50000,
            ..Default::default()
        });
        // The server already knows about this drained pay-in.
        report.cash_movements = vec![models::CashMovementSummaryRow {
            amount: 2000,
            note: "float top-up".into(),
            moved_by_name: "Mona".into(),
            ..Default::default()
        }];
        report.cash_movements_in = 2000;
        report.cash_movements_net = 2000;

        // …and these two are still sitting in our outbox, undrained.
        let queued = vec![
            TillReportCashLine {
                amount_minor: 1500,
                note: "pay-in".into(),
                moved_by_name: "Ali".into(),
                created_at: "2026-09-06T10:00:00Z".into(),
            },
            TillReportCashLine {
                amount_minor: -500,
                note: "pay-out".into(),
                moved_by_name: "Ali".into(),
                created_at: "2026-09-06T11:00:00Z".into(),
            },
        ];
        let v = cached_report_view(&report, 3000, queued, &|m| m.to_string());

        assert_eq!(v.expected_cash_minor, 63000); // 60000 + 3000 queued cash sales
                                                  // The drained movement is listed once, alongside the two queued ones.
        assert_eq!(v.cash_movements.len(), 3);
        assert_eq!(v.cash_in_minor, 3500); // 2000 drained + 1500 queued
        assert_eq!(v.cash_out_minor, 500);
        assert_eq!(v.cash_movements_net_minor, 3000);
        assert!(!v.from_server);
    }


    // ── report_view: full field projection + movements + ordering ─────────────

    #[test]
    fn report_view_projects_every_field_and_preserves_movement_order() {
        let mut report = models::TillReportResponse::default();
        report.expected_cash = 30000;
        report.till = Box::new(models::Till {
            opening_cash: 20000,
            ..Default::default()
        });
        report.total_payments = 9000;
        report.net_payments = 8500; // distinct from total (a void)
        report.voided_amount = 500;
        report.cash_movements_net = 1200;
        report.cash_movements_in = 3000;
        report.cash_movements_out = 1800;
        report.payment_summary = vec![
            models::PaymentSummaryRow::new(true, 2, "Cash".into(), 5000),
            models::PaymentSummaryRow::new(false, 1, "Card".into(), 4000),
        ];
        report.cash_movements = vec![
            models::CashMovementSummaryRow {
                amount: 3000,
                note: "float".into(),
                moved_by_name: "Mona".into(),
                ..Default::default()
            },
            models::CashMovementSummaryRow {
                amount: -1800,
                note: "".into(),
                moved_by_name: "Ali".into(),
                ..Default::default()
            },
        ];
        let v = report_view(&report, 0, &|m| m.to_string());
        // Every server figure mapped through verbatim (queued = 0 here).
        assert_eq!(v.expected_cash_minor, 30000);
        assert_eq!(v.net_payments_minor, 8500);
        assert_eq!(v.voided_amount_minor, 500);
        assert_eq!(v.cash_movements_net_minor, 1200);
        assert_eq!(v.cash_in_minor, 3000);
        assert_eq!(v.cash_out_minor, 1800);
        // Payment lines keep order and per-row fields.
        assert_eq!(v.payment_lines.len(), 2);
        assert_eq!(v.payment_lines[0].method, "Cash");
        assert!(v.payment_lines[0].is_cash);
        assert_eq!(v.payment_lines[0].order_count, 2);
        assert_eq!(v.payment_lines[1].method, "Card");
        assert!(!v.payment_lines[1].is_cash);
        // Movement order preserved; note + signed amount mapped.
        assert_eq!(v.cash_movements.len(), 2);
        assert_eq!(v.cash_movements[0].amount_minor, 3000);
        assert_eq!(v.cash_movements[0].note, "float");
        assert_eq!(v.cash_movements[0].moved_by_name, "Mona");
        assert_eq!(v.cash_movements[1].amount_minor, -1800);
        assert_eq!(v.cash_movements[1].moved_by_name, "Ali");
    }

    #[test]
    fn report_view_default_response_is_all_zero_and_empty() {
        // A defaulted server response (no sales, no movements) projects cleanly.
        let report = models::TillReportResponse::default();
        let v = report_view(&report, 0, &|m| m.to_string());
        assert_eq!(v.expected_cash_minor, 0);
        assert_eq!(v.opening_cash_minor, 0);
        assert_eq!(v.total_payments_minor, 0);
        assert_eq!(v.net_payments_minor, 0);
        assert_eq!(v.voided_amount_minor, 0);
        assert_eq!(v.cash_in_minor, 0);
        assert_eq!(v.cash_out_minor, 0);
        assert!(v.payment_lines.is_empty());
        assert!(v.cash_movements.is_empty());
        assert!(v.from_server);
    }

    #[test]
    fn report_view_negative_queued_cash_lowers_expected() {
        // queued_cash is just added — a negative (net cash refund queued) lowers it.
        let mut report = models::TillReportResponse::default();
        report.expected_cash = 60000;
        let v = report_view(&report, -1500, &|m| m.to_string());
        assert_eq!(v.expected_cash_minor, 58500);
    }

    // ── offline_report_view: cash split / net / empties / boundaries ──────────

    // ── cash_movement_view ────────────────────────────────────────────────────

    #[test]
    fn merge_cash_for_view_dedups_synced_movement() {
        let view = |id: &str, amt: i64| CashMovementView {
            id: id.into(),
            kind: "pay_in".into(),
            amount_minor: amt,
            note: String::new(),
            moved_by_name: String::new(),
            created_at: String::new(),
        };
        // 'ref-1' synced (server row id == client_ref) AND still queued → must dedup.
        let server = vec![view("ref-1", 100)];
        let queued = vec![view("ref-1", 100), view("ref-2", 50)]; // ref-2 is offline-only
        let merged = merge_cash_for_view(server, queued);
        assert_eq!(
            merged.len(),
            2,
            "a synced movement must not double the drawer"
        );
        assert_eq!(merged.iter().filter(|m| m.id == "ref-1").count(), 1);
        // Drawer net is correct (150), not double-counted (would be 250).
        assert_eq!(merged.iter().map(|m| m.amount_minor).sum::<i64>(), 150);
    }

    // ── till_summary_view: Option<Option<T>> flatten ────────────────────────

    // ── view_from / current / save / clear / close ───────────────────────────

    // ── suggested opening cash: clamp boundary ───────────────────────────────

    #[test]
    fn cache_suggested_opening_cash_clamps_negative_to_zero_exactly() {
        let store = Store::open("").unwrap();
        cache_suggested_opening_cash(&store, 0).unwrap(); // boundary: 0 stays 0
        assert_eq!(suggested_opening_cash(&store).unwrap(), 0);
        cache_suggested_opening_cash(&store, -1).unwrap(); // just below clamps
        assert_eq!(suggested_opening_cash(&store).unwrap(), 0);
        cache_suggested_opening_cash(&store, 1).unwrap(); // just above kept
        assert_eq!(suggested_opening_cash(&store).unwrap(), 1);
    }

    #[test]
    fn suggested_opening_cash_defaults_to_zero_on_garbage() {
        let store = Store::open("").unwrap();
        store
            .kv_put(SUGGESTED_OPEN_CASH_KEY, "not-a-number")
            .unwrap();
        // Unparseable cached value falls back to 0, not an error.
        assert_eq!(suggested_opening_cash(&store).unwrap(), 0);
    }

    // ── reconcile: remaining matrix corners ──────────────────────────────────

}

/// Turn `counted` inputs (a blind count) into `checked` when the amount equals
/// the system total, else `disagreed` with that amount and `note` when none
/// was given. Other inputs pass through.
pub(crate) fn resolve_blind_counts(
    inputs: Vec<ReconciliationInput>,
    methods: &[CloseTillMethodView],
    note: &str,
) -> Vec<ReconciliationInput> {
    inputs
        .into_iter()
        .map(|mut i| {
            if i.status != "counted" {
                return i;
            }
            let system = methods.iter().find(|m| m.method == i.method).map(|m| m.system_total_minor);
            match (i.declared_amount_minor, system) {
                (Some(d), Some(s)) if d == s => {
                    i.status = "checked".into();
                    i.declared_amount_minor = None;
                }
                (None, _) => {
                    i.status = "checked".into();
                }
                _ => {
                    i.status = "disagreed".into();
                    if i.note.as_deref().map(str::trim).unwrap_or("").is_empty() {
                        i.note = Some(note.to_string());
                    }
                }
            }
            i
        })
        .collect()
}

#[cfg(test)]
mod blind_count_tests {
    use super::*;

    #[test]
    fn a_blind_count_is_checked_when_it_agrees_and_disagreed_with_a_note_when_not() {
        let methods = vec![CloseTillMethodView {
            method: "card".into(),
            label: "Card".into(),
            is_cash: false,
            system_total_minor: 5000,
            order_count: 2,
        }];
        let input = |amount| ReconciliationInput {
            method: "card".into(),
            status: "counted".into(),
            declared_amount_minor: Some(amount),
            note: None,
        };
        let out = resolve_blind_counts(vec![input(5000), input(4000)], &methods, "blind count");
        assert_eq!(out[0].status, "checked");
        assert_eq!(out[1].status, "disagreed");
        assert_eq!(out[1].declared_amount_minor, Some(4000));
        assert_eq!(out[1].note.as_deref(), Some("blind count"));
    }
}
