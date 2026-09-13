//! Regenerates the `/sync/replay` envelopes an OLD POS core (v0.5.1 / v0.6.0)
//! puts on the wire, using THAT release's generated `madar-api` models and the
//! same field assignments its `madar-core` makes (checkout.rs `prepare`,
//! lib.rs `open_shift`/`close_shift`/`cash_movement`/`void_order`/
//! `refund_order`/`settle_open_ticket`/`delivery_finalize`, and the drain's
//! `send_outbox_item` envelope `json!` literals). Ids and clocks are fixed so the
//! output is byte-stable. Output: one pretty JSON file per case.
//!
//! Usage (via tool/old_client_api_check.sh --regen-envelopes):
//!   cargo run --features v060 --bin gen_envelopes -- <out_dir>

use madar_api::models;
use serde_json::{json, Value};
use std::path::PathBuf;

fn u(n: u32) -> uuid::Uuid {
    uuid::Uuid::parse_str(&format!("00000000-0000-4000-8000-{n:012}")).unwrap()
}
fn ts(s: &str) -> chrono::DateTime<chrono::FixedOffset> {
    chrono::DateTime::parse_from_rfc3339(s).unwrap()
}

const TELLER: u32 = 1;
const BRANCH: u32 = 2;
const SHIFT: u32 = 3;
const TILL: u32 = 4;
const MENU_ITEM: u32 = 10;
const ADDON: u32 = 11;
const OPTIONAL: u32 = 12;
const ORDER: u32 = 20;
const TICKET: u32 = 30;
const TICKET_LINE: u32 = 31;
const CUSTOMER: u32 = 40;
const DISCOUNT: u32 = 41;
const CLIENT_REF: u32 = 50;
#[allow(dead_code)]
const CORRECTS: u32 = 51;

// ── builders mirroring madar-core ────────────────────────────────────────────

fn open_shift_request(edit_reason: Option<String>, till: bool) -> models::OpenShiftRequest {
    // lib.rs open_shift: struct literal with ..Default::default()
    models::OpenShiftRequest {
        id: Some(Some(u(SHIFT))),
        opened_at: Some(Some(ts("2026-09-13T06:00:05.123456+00:00"))),
        opening_cash: 50_000,
        edit_reason: edit_reason.map(Some),
        till_id: if till { Some(Some(u(TILL))) } else { None },
        ..Default::default()
    }
}

fn close_shift_request(cash_note: Option<String>) -> models::CloseShiftRequest {
    let mut r = models::CloseShiftRequest::new(48_250);
    r.cash_note = Some(cash_note); // NOTE: None serializes as `"cash_note": null`
    r.closed_at = Some(Some(ts("2026-09-13T15:30:00.654321+00:00")));
    r
}

#[allow(unused_variables)]
fn cash_movement_request(amount: i32, note: &str, kind: Option<&str>, corrects: bool) -> models::CashMovementRequest {
    let mut r = models::CashMovementRequest::new(amount, note.to_string());
    r.client_ref = Some(Some(u(CLIENT_REF)));
    r.created_at = Some(Some(ts("2026-09-13T11:00:00.5+00:00")));
    #[cfg(feature = "v060")]
    {
        use models::CashMovementKind as K;
        r.kind = kind
            .map(|k| match k {
                "pay_in" => K::PayIn,
                "pay_out" => K::PayOut,
                "safe_drop" => K::SafeDrop,
                "correction" => K::Correction,
                _ => K::PayIn,
            })
            .map(Some);
        if corrects {
            r.corrects_id = Some(Some(u(CORRECTS)));
        }
    }
    r
}

fn items() -> Vec<models::OrderItemInput> {
    // checkout.rs lines_to_wire_items (non-bundle line)
    let mut addon = models::AddonInput::new(u(ADDON));
    addon.quantity = Some(1);
    addon.unit_price = Some(Some(1_000));
    let mut item = models::OrderItemInput::new(2);
    item.addons = Some(vec![addon]);
    item.optional_field_ids = Some(vec![u(OPTIONAL)]);
    item.menu_item_id = Some(Some(u(MENU_ITEM)));
    item.size_label = Some(Some("Large".into()));
    item.unit_price = Some(Some(6_500));
    let mut plain = models::OrderItemInput::new(1);
    plain.addons = Some(vec![]);
    plain.optional_field_ids = Some(vec![]);
    plain.menu_item_id = Some(Some(u(MENU_ITEM + 100)));
    plain.size_label = Some(None);
    plain.unit_price = Some(Some(4_000));
    vec![item, plain]
}

struct Sale {
    method: &'static str,
    cash: bool,
    tip: Option<(i32, &'static str)>,
    splits: Vec<(i32, &'static str)>,
    loyalty: bool,
    discount: bool,
}

fn create_order_request(s: &Sale) -> models::CreateOrderRequest {
    // checkout.rs prepare()
    let subtotal = 19_000;
    let discount = if s.discount { 1_900 } else { 0 };
    let tax = 0;
    let total = subtotal - discount + tax;
    let mut r = models::CreateOrderRequest::new(u(BRANCH), items(), s.method.to_string(), u(SHIFT));
    r.idempotency_key = Some(Some(u(ORDER)));
    r.subtotal = Some(Some(subtotal));
    r.tax_amount = Some(Some(tax));
    r.total_amount = Some(Some(total));
    r.created_at = Some(Some(ts("2026-09-13T09:15:42.123+03:00")));
    if s.cash {
        r.amount_tendered = Some(Some(20_000));
        r.change_given = Some(Some(20_000 - total - s.tip.map(|t| t.0).unwrap_or(0)));
    }
    if let Some((tip, m)) = s.tip {
        r.tip_amount = Some(Some(tip));
        r.tip_payment_method = Some(Some(m.to_string()));
    }
    r.loyalty_customer_id = if s.loyalty { Some(Some(u(CUSTOMER))) } else { None };
    if s.loyalty {
        r.loyalty_redemptions = Some(vec![models::LoyaltyRedemptionInput {
            item_index: Some(Some(1)),
            ticket_line_id: None,
            units: Some(Some(1)),
        }]);
    }
    r.customer_name = if s.loyalty { Some(Some("Mona".into())) } else { None };
    r.notes = None;
    if !s.splits.is_empty() {
        r.payment_splits = Some(Some(
            s.splits
                .iter()
                .map(|(a, m)| models::PaymentSplitInput { amount: *a, method: m.to_string(), reference: None })
                .collect(),
        ));
    }
    if s.discount {
        r.discount_id = Some(Some(u(DISCOUNT)));
        r.discount_type = Some(Some("percentage".into()));
        r.discount_value = Some(Some(10.0));
        r.discount_amount = Some(Some(discount));
    }
    r.order_ref = Some(Some("CAI1-260913-36B-0012".into()));
    r
}

#[allow(unused_variables)]
fn settle_request(method: &str, cash: bool, tip: Option<(i32, &str)>, splits: Vec<(i32, &str)>, loyalty: bool) -> models::SettleOpenTicketRequest {
    // lib.rs settle_open_ticket
    let mut r = models::SettleOpenTicketRequest::new(method.to_string(), u(SHIFT));
    r.amount_tendered = if cash { Some(Some(30_000)) } else { None };
    r.tip_amount = tip.map(|t| Some(t.0));
    r.tip_payment_method = tip.map(|t| Some(t.1.to_string()));
    r.discount_id = None;
    r.discount_type = None;
    r.discount_value = None;
    r.loyalty_customer_id = if loyalty { Some(Some(u(CUSTOMER))) } else { None };
    #[cfg(feature = "v060")]
    if !splits.is_empty() {
        r.payment_splits = Some(Some(
            splits
                .iter()
                .map(|(a, m)| models::PaymentSplitInput { amount: *a, method: m.to_string(), reference: None })
                .collect(),
        ));
    }
    if loyalty {
        r.loyalty_redemptions = Some(vec![models::LoyaltyRedemptionInput {
            item_index: None,
            ticket_line_id: Some(Some(u(TICKET_LINE))),
            units: Some(Some(1)),
        }]);
    }
    r
}

fn void_request() -> models::VoidOrderRequest {
    #[cfg(feature = "v060")]
    let mut r = models::VoidOrderRequest::new(models::VoidReason::WrongOrder.to_string());
    #[cfg(feature = "v051")]
    let mut r = models::VoidOrderRequest::new("wrong_order".to_string());
    r.note = Some(None);
    r.restore_inventory = Some(Some(true));
    r.voided_at = Some(Some(ts("2026-09-13T10:05:00.25+00:00")));
    r
}

// ── envelopes (lib.rs send_outbox_item) ──────────────────────────────────────

fn teller() -> String {
    u(TELLER).to_string()
}

fn cases() -> Vec<(&'static str, Value)> {
    let t = teller();
    let shift = u(SHIFT).to_string();
    let branch = u(BRANCH).to_string();
    let mut out: Vec<(&'static str, Value)> = vec![
        ("open_shift", json!({ "op": "open_shift", "teller_id": t, "branch_id": branch, "request": open_shift_request(None, true) })),
        ("open_shift_edited_no_till", json!({ "op": "open_shift", "teller_id": t, "branch_id": branch, "request": open_shift_request(Some("counted again".into()), false) })),
        ("close_shift", json!({ "op": "close_shift", "teller_id": t, "shift_id": shift, "request": close_shift_request(None) })),
        ("close_shift_with_note", json!({ "op": "close_shift", "teller_id": t, "shift_id": shift, "request": close_shift_request(Some("50 short".into())) })),
    ];
    #[cfg(feature = "v051")]
    {
        out.push(("cash_movement_in", json!({ "op": "cash_movement", "teller_id": t, "shift_id": shift, "request": cash_movement_request(5_000, "float top-up", None, false) })));
        out.push(("cash_movement_out", json!({ "op": "cash_movement", "teller_id": t, "shift_id": shift, "request": cash_movement_request(-2_000, "milk", None, false) })));
    }
    #[cfg(feature = "v060")]
    {
        out.push(("cash_movement_pay_in", json!({ "op": "cash_movement", "teller_id": t, "shift_id": shift, "request": cash_movement_request(5_000, "float top-up", Some("pay_in"), false) })));
        out.push(("cash_movement_pay_out", json!({ "op": "cash_movement", "teller_id": t, "shift_id": shift, "request": cash_movement_request(-2_000, "milk", Some("pay_out"), false) })));
        out.push(("cash_movement_safe_drop", json!({ "op": "cash_movement", "teller_id": t, "shift_id": shift, "request": cash_movement_request(-30_000, "to safe", Some("safe_drop"), false) })));
        out.push(("cash_movement_correction", json!({ "op": "cash_movement", "teller_id": t, "shift_id": shift, "request": cash_movement_request(2_000, "undo milk", Some("correction"), true) })));
        out.push(("cash_movement_no_kind", json!({ "op": "cash_movement", "teller_id": t, "shift_id": shift, "request": cash_movement_request(1_000, "legacy", None, false) })));
    }
    let sales = [
        ("create_order_cash", Sale { method: "Cash", cash: true, tip: None, splits: vec![], loyalty: false, discount: false }),
        ("create_order_card", Sale { method: "Card", cash: false, tip: None, splits: vec![], loyalty: false, discount: true }),
        ("create_order_split", Sale { method: "Cash", cash: true, tip: None, splits: vec![(10_000, "Cash"), (9_000, "Card")], loyalty: false, discount: false }),
        ("create_order_tip", Sale { method: "Card", cash: false, tip: Some((1_500, "Cash")), splits: vec![], loyalty: false, discount: false }),
        ("create_order_loyalty", Sale { method: "Cash", cash: true, tip: None, splits: vec![], loyalty: true, discount: false }),
    ];
    for (name, s) in sales {
        out.push((name, json!({ "op": "create_order", "teller_id": t, "request": create_order_request(&s) })));
    }
    let ticket = u(TICKET).to_string();
    out.push(("settle_open_ticket_cash", json!({ "op": "settle_open_ticket", "teller_id": t, "ticket_id": ticket, "request": settle_request("Cash", true, None, vec![], false) })));
    out.push(("settle_open_ticket_tip_loyalty", json!({ "op": "settle_open_ticket", "teller_id": t, "ticket_id": ticket, "request": settle_request("Card", false, Some((2_000, "Card")), vec![], true) })));
    #[cfg(feature = "v060")]
    out.push(("settle_open_ticket_split", json!({ "op": "settle_open_ticket", "teller_id": t, "ticket_id": ticket, "request": settle_request("Cash", true, None, vec![(15_000, "Cash"), (10_000, "Card")], false) })));
    out.push(("void_order", json!({ "op": "void_order", "teller_id": t, "order_id": u(ORDER).to_string(), "request": void_request() })));
    #[cfg(feature = "v060")]
    {
        // lib.rs refund_order
        let mut r = models::CreateRefundRequest::new(4_000, "Cash".into(), u(ORDER), models::RefundReason::QualityIssue);
        r.note = Some(None);
        r.issued_at = Some(Some(ts("2026-09-13T12:00:00.75+00:00")));
        r.client_ref = Some(Some(u(CLIENT_REF + 1)));
        r.shift_id = Some(Some(u(SHIFT)));
        out.push(("refund_order", json!({ "op": "refund_order", "teller_id": t, "request": r })));
    }
    out
}

fn main() {
    let dir = PathBuf::from(std::env::args().nth(1).expect("usage: gen_envelopes <out_dir>"));
    std::fs::create_dir_all(&dir).unwrap();
    for (name, v) in cases() {
        std::fs::write(dir.join(format!("{name}.json")), serde_json::to_string_pretty(&v).unwrap() + "\n").unwrap();
    }
    // Delivery finalize is NOT an outbox op: it is a live
    // POST /delivery-orders/{id}/finalize body (lib.rs delivery_finalize).
    let fin = models::FinalizeInput::new("Cash".into(), u(SHIFT));
    std::fs::write(dir.join("delivery_finalize.body.json"), serde_json::to_string_pretty(&fin).unwrap() + "\n").unwrap();
    eprintln!("wrote envelopes to {}", dir.display());
}
