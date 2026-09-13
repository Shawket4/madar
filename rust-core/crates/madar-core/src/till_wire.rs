//! Hand-written, lenient copies of the tills-rework wire shapes (TILLS_CONTRACT
//! §2.1, §2.2, §4.2). They exist until `madar-api` is regenerated from the
//! backend's new `openapi.json`; every field the server may omit is defaulted so
//! an older or newer backend never fails a decode. Swap to the generated models
//! once they carry these names.

use chrono::{DateTime, FixedOffset};
use serde::{Deserialize, Serialize};

/// `OpenTillRequest` (§2.2 T2). `id` is client-minted: the till PK.
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct OpenTillRequestWire {
    pub id: uuid::Uuid,
    pub opening_cash: i32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opening_cash_edited: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub edit_reason: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opened_at: Option<DateTime<FixedOffset>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub device_id: Option<uuid::Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub verification: Option<String>,
}

/// `ReconciliationInput` (§2.2 T9).
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq, Eq)]
pub struct ReconciliationInputWire {
    pub method: String,
    /// `checked` | `disagreed`.
    pub status: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub declared_amount: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
}

/// `CloseTillRequest` (§2.2 T9).
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct CloseTillRequestWire {
    pub closing_cash_declared: i32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cash_note: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub closed_at: Option<DateTime<FixedOffset>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub device_id: Option<uuid::Uuid>,
    #[serde(default)]
    pub reconciliation: Vec<ReconciliationInputWire>,
}

/// `Till` (§2.1). Also decodes a legacy `Shift` body (the fields overlap).
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct TillWire {
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

/// `TillBrief` (§2.1).
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct TillBriefWire {
    pub id: String,
    #[serde(default)]
    pub branch_id: String,
    #[serde(default)]
    pub teller_id: String,
    #[serde(default)]
    pub teller_name: String,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub opened_at: String,
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
}

/// `OpenBillsNotice` (§2.1).
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq, Eq)]
pub struct OpenBillsNoticeWire {
    #[serde(default)]
    pub open_bills_count: i64,
    #[serde(default)]
    pub open_bills_amount: i64,
    #[serde(default)]
    pub oldest_opened_at: Option<String>,
    #[serde(default)]
    pub old_bills_count: i64,
    #[serde(default = "three")]
    pub old_bill_hours: i64,
    #[serde(default)]
    pub seated_tables_count: i64,
    #[serde(default)]
    pub since: Option<String>,
}

fn three() -> i64 {
    3
}

/// `TillPreFill` (§2.2 T1).
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct TillPreFillWire {
    #[serde(default)]
    pub has_open_till: bool,
    #[serde(default)]
    pub open_till: Option<TillWire>,
    #[serde(default)]
    pub open_elsewhere: Vec<TillBriefWire>,
    #[serde(default)]
    pub suggested_opening_cash: i64,
    #[serde(default)]
    pub last_close_declared: Option<i64>,
    #[serde(default)]
    pub open_bills_notice: Option<OpenBillsNoticeWire>,
}

/// `LastTillWarning` (§2.1).
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq, Eq)]
pub struct LastTillWarningWire {
    #[serde(default)]
    pub is_last_open_till: bool,
    #[serde(default)]
    pub open_bills_count: i64,
    #[serde(default)]
    pub open_bills_amount: i64,
    #[serde(default)]
    pub seated_tables_count: i64,
}

/// One method row of `CloseTillPreview` (§2.2 T8).
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq, Eq)]
pub struct CloseTillMethodWire {
    pub method: String,
    #[serde(default)]
    pub payment_method_id: Option<String>,
    #[serde(default)]
    pub is_cash: bool,
    #[serde(default)]
    pub system_total: i64,
    #[serde(default)]
    pub order_count: i64,
}

/// `CloseTillPreview` (§2.2 T8).
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct CloseTillPreviewWire {
    pub till: TillWire,
    #[serde(default)]
    pub expected_cash: i64,
    #[serde(default)]
    pub methods: Vec<CloseTillMethodWire>,
    #[serde(default)]
    pub last_till_warning: Option<LastTillWarningWire>,
}

/// `TillReconciliationLine` (§2.1).
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq, Eq)]
pub struct TillReconciliationLineWire {
    pub method: String,
    #[serde(default)]
    pub payment_method_id: Option<String>,
    #[serde(default)]
    pub is_cash: bool,
    #[serde(default)]
    pub system_total: i64,
    #[serde(default)]
    pub current_system_total: i64,
    #[serde(default)]
    pub order_count: i64,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub declared_amount: Option<i64>,
    #[serde(default)]
    pub note: Option<String>,
    #[serde(default)]
    pub changed_after_close: bool,
}

/// `CloseTillResponse` (§2.2 T9).
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct CloseTillResponseWire {
    pub till: TillWire,
    #[serde(default)]
    pub reconciliation: Vec<TillReconciliationLineWire>,
    #[serde(default)]
    pub last_till_warning: Option<LastTillWarningWire>,
}

/// The tills-rework additions a `TillReportResponse` (§2.2 T7) carries on top of
/// the legacy report body (which is decoded with the generated
/// `ShiftReportResponse` after renaming the `till` key back to `shift`).
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct TillReportExtrasWire {
    #[serde(default)]
    pub till: Option<TillWire>,
    #[serde(default)]
    pub reconciliation: Vec<TillReconciliationLineWire>,
    #[serde(default)]
    pub old_bills_at_close: Option<i64>,
    #[serde(default)]
    pub open_bills_at_close: Option<i64>,
    #[serde(default)]
    pub order_number_range: Option<OrderNumberRangeWire>,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq, Eq)]
pub struct OrderNumberRangeWire {
    #[serde(default)]
    pub device_code: Option<String>,
    #[serde(default)]
    pub first: Option<i64>,
    #[serde(default)]
    pub last: Option<i64>,
}

/// Decode a `TillReportResponse` body: the generated legacy report (key `till`
/// accepted as `shift`) plus the rework extras.
pub fn decode_till_report(
    body: &str,
) -> Result<(madar_api::models::ShiftReportResponse, TillReportExtrasWire), serde_json::Error> {
    let mut v: serde_json::Value = serde_json::from_str(body)?;
    let extras: TillReportExtrasWire = serde_json::from_value(v.clone())?;
    if let Some(obj) = v.as_object_mut() {
        if !obj.contains_key("shift") {
            if let Some(t) = obj.get("till").cloned() {
                obj.insert("shift".into(), t);
            }
        }
    }
    let report = serde_json::from_value(v)?;
    Ok((report, extras))
}

/// A `Till` body as the generated legacy `Shift` (the pieces of core still typed
/// on it: reports, history). Unknown fields are ignored by the generated struct.
pub fn till_as_shift(till: &TillWire) -> Option<madar_api::models::Shift> {
    serde_json::to_value(till)
        .ok()
        .and_then(|v| serde_json::from_value(v).ok())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn till_wire_decodes_a_legacy_shift_body() {
        let body = r#"{"id":"00000000-0000-0000-0000-0000000000a1","branch_id":"b","teller_id":"t",
            "teller_name":"Sara","status":"open","opening_cash":500,"opened_at":"2026-09-01T09:00:00Z",
            "opening_cash_was_edited":false,"till_id":null,"till_name":null}"#;
        let t: TillWire = serde_json::from_str(body).unwrap();
        assert_eq!(t.teller_name, "Sara");
        assert_eq!(t.verification, None);
        assert!(!t.opened_while_another_open);
    }

    #[test]
    fn close_request_serializes_reconciliation_and_skips_absent_fields() {
        let r = CloseTillRequestWire {
            closing_cash_declared: 100,
            reconciliation: vec![ReconciliationInputWire {
                method: "Card".into(),
                status: "checked".into(),
                ..Default::default()
            }],
            ..Default::default()
        };
        let v = serde_json::to_value(&r).unwrap();
        assert_eq!(v["reconciliation"][0]["method"], "Card");
        assert!(v.get("cash_note").is_none());
        assert!(v["reconciliation"][0].get("note").is_none());
    }

    #[test]
    fn till_report_decodes_with_till_key() {
        let body = r#"{"till":{"id":"00000000-0000-0000-0000-0000000000a1","branch_id":"00000000-0000-0000-0000-0000000000b1",
            "teller_id":"00000000-0000-0000-0000-0000000000c1","teller_name":"Sara","status":"closed","opening_cash":500,
            "opened_at":"2026-09-01T09:00:00Z","opening_cash_was_edited":false,"device_code":"36B"},
            "cash_movements":[],"cash_movements_in":0,"cash_movements_net":0,"cash_movements_out":0,"cash_tips":0,
            "expected_cash":900,"net_payments":0,"non_cash_tips":0,"payment_summary":[],"printed_at":"2026-09-01T18:00:00Z",
            "total_payments":0,"total_tips":0,"voided_amount":0,"cash_adjustments":0,"safe_drops":0,
            "reconciliation":[{"method":"Card","is_cash":false,"system_total":300,"current_system_total":300,"status":"checked"}],
            "old_bills_at_close":2,"order_number_range":{"device_code":"36B","first":1,"last":9}}"#;
        let (report, extras) = decode_till_report(body).unwrap();
        assert_eq!(report.expected_cash, 900);
        assert_eq!(report.shift.teller_name, "Sara");
        assert_eq!(extras.reconciliation.len(), 1);
        assert_eq!(extras.old_bills_at_close, Some(2));
        assert_eq!(extras.till.unwrap().device_code.as_deref(), Some("36B"));
    }
}
