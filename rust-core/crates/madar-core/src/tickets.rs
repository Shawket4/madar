//! Waiter open tickets — client side (PLAN §"waiter fire-now-pay-later").
//!
//! A waiter prices a dine-in cart with the SAME client-authoritative engine the
//! POS checkout uses (`checkout::lines_to_wire_items`) and FIRES it as an unpaid
//! open ticket; items are added in later ROUNDS; a cashier SETTLES it into a paid
//! order. Every write is offline-first: it rides the durable outbox →
//! `POST /sync/replay` (the backend ticket replay ops), deduped on a client-minted
//! key, so a fire/round/settle survives a dropped network exactly like a sale.
//!
//! This module holds the durable command shapes + the FFI view DTOs + pure
//! mappers. The exported `MadarCore` methods (fire/add_round/list/get/void/settle)
//! live in `lib.rs` alongside the other outbox entry points.

use madar_api::models;
use serde::{Deserialize, Serialize};

// ── Durable outbox commands (persisted as the op payload) ─────────────────────

/// Fire a new ticket (round 1). `ticket_id` is the client-minted ticket
/// idempotency key (also the outbox row id) — exactly-once across LAN + cloud.
#[derive(Serialize, Deserialize)]
pub(crate) struct FireTicketCommand {
    pub ticket_id: String,
    pub request: models::CreateOpenTicketRequest,
}

/// Add a round to an existing ticket. `round_id` is the per-round idempotency key.
#[derive(Serialize, Deserialize)]
pub(crate) struct AddRoundCommand {
    pub ticket_id: String,
    pub round_id: String,
    pub request: models::AddRoundRequest,
}

/// Settle a ticket into a paid order in the cashier's shift.
#[derive(Serialize, Deserialize)]
pub(crate) struct SettleTicketCommand {
    pub ticket_id: String,
    pub request: models::SettleOpenTicketRequest,
}

/// Void a ticket (and pull its kitchen tickets off the KDS).
#[derive(Serialize, Deserialize)]
pub(crate) struct VoidTicketCommand {
    pub ticket_id: String,
    pub request: models::VoidOpenTicketRequest,
}

/// Take ONE line off a bill — "they sent the calamari back". The same request
/// shape as voiding the whole bill, because it is the same act at a smaller
/// scale and a report should be able to count both with one vocabulary.
#[derive(Serialize, Deserialize)]
pub(crate) struct VoidTicketLineCommand {
    pub ticket_id: String,
    pub item_id: String,
    pub request: models::VoidOpenTicketRequest,
}

// ── FFI view DTOs ─────────────────────────────────────────────────────────────

/// The slim "sent to kitchen" confirmation after a fire/round — deliberately NOT
/// a money-laden receipt (a fired ticket has no payment yet). `queued_offline` is
/// true when the fire is still in the outbox (no network) — the UI shows "queued".
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct TicketFiredView {
    /// The client ticket id (idempotency key) — stable across the offline→online
    /// transition, so the UI can track the ticket before the server view arrives.
    pub ticket_id: String,
    /// The server-minted human ref (`T-…`), once known (None while queued offline).
    pub ticket_ref: Option<String>,
    pub queued_offline: bool,
}

/// An open ticket for the waiter list / detail screens.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct TicketView {
    pub id: String,
    pub ticket_ref: Option<String>,
    pub table_id: Option<String>,
    /// open | ready | settled | voided | queued (the last = still in the outbox).
    pub status: String,
    pub customer_name: Option<String>,
    /// The WAITER who opened this ticket (`open_tickets.opened_by` → user name),
    /// so the teller can see who took the table. `null` if the name is unknown.
    pub waiter_name: Option<String>,
    pub guest_count: Option<i32>,
    /// The lines as charged, before discount. The FIRST LINE of the bill, not
    /// the bill — see [`TicketBillView`].
    pub subtotal_minor: i64,
    /// What the drawer must collect, as the SERVER prices it.
    ///
    /// The till used to carry the subtotal alone and charge that, while the
    /// settle booked subtotal + service charge + tax. Every branch sits at rate
    /// 0 today so nothing was lost, but a new organisation defaults to 14%
    /// exclusive — at which point the drawer would have collected exactly the
    /// tax less than the books recorded, on every dine-in bill.
    ///
    /// `None` only for a ticket the server has not seen yet (a queued fire).
    /// A caller with no bill must say so rather than showing the subtotal as
    /// though it were a total.
    pub bill: Option<TicketBillView>,
    pub order_id: Option<String>,
    pub opened_at: String,
    pub queued_offline: bool,
    pub lines: Vec<TicketLineView>,
}

/// The bill as the server prices it: what is owed, and how it was arrived at.
///
/// Projected rather than computed. The server is the only party that knows the
/// branch's effective tax policy at the moment of settle — the org's rate with
/// the branch's per-field override on top — and a till that recomputed it would
/// be a second opinion about money. `crate::tax` exists for the cart preview,
/// where there is no server bill to ask for.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
// No `Eq`: the rates are f64, and a rate is a number to render, not a key to
// compare. PartialEq is enough for the tests that pin these figures.
#[derive(Clone, Debug, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct TicketBillView {
    /// Lines as charged, before discount. Gross when tax-inclusive.
    pub subtotal_minor: i64,
    /// The WAITER's discount, resolved. A cashier who clears it at settle sees
    /// a different total than this one, which is the point of showing it.
    pub discount_minor: i64,
    pub service_charge_minor: i64,
    /// Inside the total when `tax_inclusive`, on top of it otherwise.
    pub tax_minor: i64,
    /// What the drawer must collect.
    pub total_minor: i64,
    /// The rates these figures were computed under, for the printed bill.
    pub tax_rate: f64,
    pub service_charge_rate: f64,
    pub tax_inclusive: bool,
}

/// One bill line (display projection of the frozen `StoredTicketLine`).
// PartialEq/Eq + serde so it can be embedded in `DeliveryOrderView` (which derives
// them) — tickets and delivery share this one line shape so both render identically.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct TicketLineView {
    /// `open_ticket_items.id` — what a reward names to cover this line.
    ///
    /// A POSITION would not do: the server flattens the ticket's rounds in its
    /// own order at settle time, and a till that guessed an index would take the
    /// wrong item off the bill. Empty for a line that has not synced yet, which
    /// is also a line that cannot be redeemed against.
    pub id: String,
    /// Which menu item this is, for matching against the reward catalogue.
    pub menu_item_id: Option<String>,
    pub name: String,
    pub qty: i32,
    pub size_label: Option<String>,
    pub modifiers: Vec<String>,
    pub line_total_minor: i64,
    pub voided: bool,
    /// Which visit to the table this line arrived on, and when.
    ///
    /// A bill is read as a sequence — the drinks at seven, the food at half
    /// past — and a flat list of items says nothing about how the evening went.
    /// RFC3339; the host formats it, because the core never guesses a timezone.
    pub round_number: i32,
    pub round_fired_at: String,
}

// ── Request builders ──────────────────────────────────────────────────────────

/// Assemble the fire (round-1) request from priced cart items. Pricing is
/// client-authoritative (`items` already carry their charged `unit_price`); the
/// backend records them verbatim and settles them into a byte-identical order.
#[allow(clippy::too_many_arguments)]
pub(crate) fn build_fire_request(
    branch_id: uuid::Uuid,
    items: Vec<models::OrderItemInput>,
    ticket_id: uuid::Uuid,
    round_id: uuid::Uuid,
    table_id: Option<uuid::Uuid>,
    customer_name: Option<String>,
    notes: Option<String>,
    guest_count: Option<i32>,
    booking_id: Option<uuid::Uuid>,
) -> models::CreateOpenTicketRequest {
    let mut r = models::CreateOpenTicketRequest::new(branch_id, items);
    r.idempotency_key = Some(Some(ticket_id));
    r.round_idempotency_key = Some(Some(round_id));
    r.table_id = table_id.map(Some);
    // The party arrived under a booking: the server links the ticket and seats it.
    r.booking_id = booking_id.map(Some);
    r.customer_name = customer_name.filter(|s| !s.trim().is_empty()).map(Some);
    r.notes = notes.filter(|s| !s.trim().is_empty()).map(Some);
    r.guest_count = guest_count.map(Some);
    r
}

/// Assemble an add-round request (its own per-round idempotency key).
pub(crate) fn build_round_request(
    items: Vec<models::OrderItemInput>,
    round_id: uuid::Uuid,
) -> models::AddRoundRequest {
    let mut r = models::AddRoundRequest::new(items);
    r.idempotency_key = Some(Some(round_id));
    r
}

// ── Mappers (generated model → FFI view) ──────────────────────────────────────

/// Flatten a double-`Option` (the generated nullable shape) to a single `Option`.
fn flat<T: Clone>(o: &Option<Option<T>>) -> Option<T> {
    o.as_ref().and_then(|x| x.clone())
}

/// Project a server `OpenTicketView` to the FFI `TicketView`. `queued_offline` is
/// set by the caller (true for a still-outboxed fire that has no server view).
pub(crate) fn to_view(v: &models::OpenTicketView, queued_offline: bool) -> TicketView {
    to_view_with(v, queued_offline, &Default::default(), false)
}

/// Project a ticket, applying any line voids this device has queued but not
/// yet sent.
///
/// A waiter who takes the calamari off while the wifi is down must see the
/// calamari come off. The server has not heard yet, so its view still carries
/// the line and prices the bill with it — and the cashier who settles from
/// that figure would collect for a plate that was sent back.
///
/// `service_charge_taxable` is the one part of the policy the bill does not
/// carry, so it comes from the session. It is the same branch setting the
/// server read, and it only matters at all when a service charge exists.
pub(crate) fn to_view_with(
    v: &models::OpenTicketView,
    queued_offline: bool,
    voided_line_ids: &std::collections::HashSet<String>,
    service_charge_taxable: bool,
) -> TicketView {
    let mut lines: Vec<TicketLineView> = v.items.iter().map(line_view).collect();
    let mut removed: i64 = 0;
    for line in &mut lines {
        if !line.voided && voided_line_ids.contains(&line.id) {
            line.voided = true;
            removed += line.line_total_minor;
        }
    }
    let subtotal = (v.subtotal as i64 - removed).max(0);
    let bill = v.bill.as_deref().map(bill_view);
    let bill = match (&bill, removed) {
        // Nothing queued against this bill: the server's figures stand.
        (_, 0) | (None, _) => bill,
        (Some(b), _) => Some(reprice(b, subtotal, v, service_charge_taxable)),
    };
    TicketView {
        id: v.id.to_string(),
        ticket_ref: flat(&v.ticket_ref),
        table_id: flat(&v.table_id).map(|u| u.to_string()),
        status: v.status.clone(),
        customer_name: flat(&v.customer_name),
        waiter_name: flat(&v.opened_by_name).filter(|s| !s.is_empty()),
        guest_count: flat(&v.guest_count),
        subtotal_minor: subtotal,
        bill,
        order_id: flat(&v.order_id).map(|u| u.to_string()),
        opened_at: v.opened_at.to_rfc3339(),
        queued_offline,
        lines,
    }
}

/// Re-price a bill whose subtotal just dropped, through the SAME engine and
/// the same order of operations the server uses (`price_open_bill`): resolve
/// the discount against the NEW subtotal, then tax the remainder.
///
/// This is the one place the till computes a bill it was handed, and it is
/// safe for exactly one reason — `crate::tax` and the backend's engine are
/// held byte-identical by the shared conformance vectors. A percentage
/// discount shrinks with the bill and a fixed one does not, which is why the
/// discount is recomputed from its type rather than scaled.
fn reprice(
    b: &TicketBillView,
    subtotal: i64,
    v: &models::OpenTicketView,
    service_charge_taxable: bool,
) -> TicketBillView {
    use std::str::FromStr;
    let dec = |f: f64| rust_decimal::Decimal::from_str(&f.to_string()).unwrap_or_default();
    let policy = crate::tax::TaxPolicy {
        // The rates the SERVER froze onto this bill, not today's settings: a
        // rate changed mid-service must not restate a bill already priced.
        tax_rate: dec(b.tax_rate),
        tax_inclusive: b.tax_inclusive,
        service_charge_rate: dec(b.service_charge_rate),
        service_charge_taxable,
    };
    let discount = match (flat(&v.discount_type).as_deref(), flat(&v.discount_value)) {
        (Some("percentage"), Some(val)) => crate::tax::Discount::Percentage(dec(val)),
        (Some("fixed"), Some(val)) => crate::tax::Discount::Fixed(dec(val)),
        _ => crate::tax::Discount::None,
    };
    let discount = crate::tax::discount_amount(subtotal, discount);
    let out = crate::tax::compute(subtotal, discount, &policy);
    TicketBillView {
        subtotal_minor: out.subtotal,
        discount_minor: out.discount,
        service_charge_minor: out.service_charge,
        tax_minor: out.tax,
        total_minor: out.total,
        tax_rate: b.tax_rate,
        service_charge_rate: b.service_charge_rate,
        tax_inclusive: b.tax_inclusive,
    }
}

/// Bill-line ids with a queued (un-sent) line void — the overlay's input.
pub(crate) fn pending_line_voids(
    store: &crate::store::Store,
) -> crate::error::CoreResult<std::collections::HashSet<String>> {
    let mut ids = std::collections::HashSet::new();
    for item in store.list_active_of_types(&["void_ticket_line"])? {
        if let Ok(cmd) = serde_json::from_str::<VoidTicketLineCommand>(&item.payload) {
            ids.insert(cmd.item_id);
        }
    }
    Ok(ids)
}

/// Project the server's priced bill. Every figure is taken, never derived — a
/// total this side recomputed from its parts would disagree with the books the
/// moment a rounding rule differed.
fn bill_view(b: &models::TicketBill) -> TicketBillView {
    TicketBillView {
        subtotal_minor: b.subtotal as i64,
        discount_minor: b.discount_amount as i64,
        service_charge_minor: b.service_charge_amount as i64,
        tax_minor: b.tax_amount as i64,
        total_minor: b.total as i64,
        tax_rate: b.tax_rate,
        service_charge_rate: b.service_charge_rate,
        tax_inclusive: b.tax_inclusive,
    }
}

/// Project one bill item, reading the display fields out of the frozen `line`
/// JSON (the `StoredTicketLine` projection: name / size_label / modifiers / qty).
fn line_view(it: &models::OpenTicketItemView) -> TicketLineView {
    let line = it.line.as_ref();
    let s = |k: &str| {
        line.and_then(|l| l.get(k))
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    };
    let modifiers = line
        .and_then(|l| l.get("modifiers"))
        .and_then(|v| v.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|m| m.as_str().map(|s| s.to_string()))
                .collect()
        })
        .unwrap_or_default();
    let qty = line
        .and_then(|l| l.get("qty"))
        .and_then(|v| v.as_i64())
        .unwrap_or(1) as i32;
    TicketLineView {
        id: it.id.to_string(),
        round_number: it.round_number,
        round_fired_at: it.round_fired_at.to_rfc3339(),
        menu_item_id: it.menu_item_id.flatten().map(|m| m.to_string()),
        name: s("name").unwrap_or_else(|| "Item".to_string()),
        qty,
        size_label: s("size_label"),
        modifiers,
        line_total_minor: it.line_total as i64,
        voided: it.voided,
    }
}

#[cfg(test)]
mod tests {
    /// A SEAT is a fire with no items — and the difference has to survive the
    /// request builder, because the server decides which act it is by looking
    /// at exactly that.
    #[test]
    fn a_seat_request_carries_a_table_and_no_items() {
        let branch = uuid::Uuid::new_v4();
        let table = uuid::Uuid::new_v4();
        let r = super::build_fire_request(
            branch,
            Vec::new(),
            uuid::Uuid::new_v4(),
            uuid::Uuid::new_v4(),
            Some(table),
            None,
            None,
            Some(2),
            None,
        );
        assert!(r.items.is_empty(), "seating orders nothing");
        assert_eq!(
            r.table_id.flatten(),
            Some(table),
            "the table IS the request — a seat without one is not anything"
        );
        assert_eq!(r.guest_count.flatten(), Some(2));
        // No round to dedup against, but the key rides along regardless so a
        // retry of the same seat cannot open two tabs.
        assert!(r.idempotency_key.flatten().is_some());
    }

    /// Blank names and notes are dropped rather than stored as whitespace.
    #[test]
    fn a_blank_customer_name_is_not_a_name() {
        let r = super::build_fire_request(
            uuid::Uuid::new_v4(),
            Vec::new(),
            uuid::Uuid::new_v4(),
            uuid::Uuid::new_v4(),
            Some(uuid::Uuid::new_v4()),
            Some("   ".into()),
            Some("\t".into()),
            None,
            None,
        );
        assert!(r.customer_name.flatten().is_none());
        assert!(r.notes.flatten().is_none());
    }

    use super::*;

    #[test]
    fn fire_request_carries_idempotency_and_optionals() {
        let tid = uuid::Uuid::new_v4();
        let rid = uuid::Uuid::new_v4();
        let bid = uuid::Uuid::new_v4();
        let r = build_fire_request(
            bid,
            vec![models::OrderItemInput::new(2)],
            tid,
            rid,
            None,
            Some("  ".into()), // whitespace-only customer → dropped
            Some("extra hot".into()),
            Some(4),
            Some(tid),
        );
        assert_eq!(r.branch_id, bid);
        assert_eq!(
            r.booking_id,
            Some(Some(tid)),
            "booking id rides on the fire"
        );
        assert_eq!(r.idempotency_key, Some(Some(tid)));
        assert_eq!(r.round_idempotency_key, Some(Some(rid)));
        assert_eq!(r.customer_name, None, "blank customer name dropped");
        assert_eq!(r.notes, Some(Some("extra hot".into())));
        assert_eq!(r.guest_count, Some(Some(4)));
        assert_eq!(r.items.len(), 1);
    }

    #[test]
    fn line_view_reads_frozen_json() {
        let it = models::OpenTicketItemView {
            id: uuid::Uuid::new_v4(),
            line: Some(serde_json::json!({
                "name": "Burger", "size_label": "Large", "qty": 3,
                "modifiers": ["No onion", "Extra cheese"]
            })),
            line_total: 4500,
            menu_item_id: None,
            round_number: 2,
            round_fired_at: "2026-09-10T19:17:00Z".parse().unwrap(),
            voided: false,
        };
        let lv = line_view(&it);
        assert_eq!(lv.round_number, 2, "which visit this arrived on");
        assert!(lv.round_fired_at.starts_with("2026-09-10T19:17:00"));
        assert_eq!(lv.name, "Burger");
        assert_eq!(lv.qty, 3);
        assert_eq!(lv.size_label.as_deref(), Some("Large"));
        assert_eq!(lv.modifiers, vec!["No onion", "Extra cheese"]);
        assert_eq!(lv.line_total_minor, 4500);
        assert!(!lv.voided);
    }

    /// THE DRAWER COLLECTS WHAT THE SETTLE BOOKS.
    ///
    /// `TicketView` carried only a subtotal, and the Charge sheet used it as
    /// the total — so a bill of 175 in lines, priced by the server at 175 + 21
    /// service charge + 27 tax, would have been charged at 175 and booked at
    /// 223. Nothing was ever short, because every branch sits at rate 0; a new
    /// organisation defaults to 14% exclusive, and from that moment every
    /// dine-in bill would have been out by exactly the tax.
    ///
    /// The figures are TAKEN, never derived. A total recomputed on this side
    /// from its parts would disagree with the books the moment a rounding rule
    /// differed, which is the failure the shared tax fixture exists to prevent.
    #[test]
    fn the_bill_is_the_servers_price_not_the_subtotal() {
        let bill = models::TicketBill {
            subtotal: 17500,
            discount_amount: 0,
            service_charge_amount: 2100,
            tax_amount: 2744,
            total: 22344,
            tax_rate: 0.14,
            service_charge_rate: 0.12,
            tax_inclusive: false,
        };
        let got = bill_view(&bill);

        assert_eq!(got.subtotal_minor, 17500, "the lines");
        assert_eq!(got.total_minor, 22344, "what the drawer collects");
        assert_ne!(
            got.total_minor, got.subtotal_minor,
            "a taxed bill's total is not its subtotal — the bug this pins"
        );
        assert_eq!(got.service_charge_minor, 2100);
        assert_eq!(got.tax_minor, 2744);
        assert!(!got.tax_inclusive);
    }

    /// An inclusive shop's tax is INSIDE the total, so the drawer collects the
    /// menu price and the tax is carved out for the books.
    #[test]
    fn an_inclusive_bill_collects_the_menu_price() {
        let bill = models::TicketBill {
            subtotal: 11400,
            discount_amount: 0,
            service_charge_amount: 0,
            tax_amount: 1400,
            total: 11400,
            tax_rate: 0.14,
            service_charge_rate: 0.0,
            tax_inclusive: true,
        };
        let got = bill_view(&bill);
        assert_eq!(got.total_minor, got.subtotal_minor, "tax is already inside");
        assert_eq!(got.tax_minor, 1400, "and still recorded");
        assert!(got.tax_inclusive);
    }

    /// A fixture bill: two lines at the given totals, priced by the "server"
    /// under `rate` exclusive with no service charge.
    fn priced_ticket(a: i32, b: i32, rate: f64) -> models::OpenTicketView {
        let subtotal = a + b;
        let tax = (f64::from(subtotal) * rate).round() as i32;
        models::OpenTicketView {
            id: uuid::Uuid::new_v4(),
            branch_id: uuid::Uuid::new_v4(),
            booking_id: None,
            table_id: None,
            ticket_ref: Some(Some("T-1".into())),
            status: "open".into(),
            bill: Some(Box::new(models::TicketBill {
                subtotal,
                discount_amount: 0,
                service_charge_amount: 0,
                service_charge_rate: 0.0,
                tax_amount: tax,
                tax_inclusive: false,
                tax_rate: rate,
                total: subtotal + tax,
            })),
            discount_id: None,
            discount_type: None,
            discount_value: None,
            ready: None,
            void_note: None,
            void_reason: None,
            voided_at: None,
            opened_by: uuid::Uuid::new_v4(),
            opened_by_name: Some(Some("Sara".into())),
            customer_name: None,
            notes: None,
            guest_count: Some(Some(2)),
            subtotal,
            order_id: None,
            opened_at: chrono::Utc::now().fixed_offset(),
            ready_at: None,
            settled_at: None,
            items: vec![
                models::OpenTicketItemView {
                    id: uuid::Uuid::from_u128(0xA),
                    line: Some(serde_json::json!({ "name": "Calamari", "qty": 1 })),
                    line_total: a,
                    menu_item_id: None,
                    round_fired_at: chrono::Utc::now().fixed_offset(),
                    round_number: 1,
                    voided: false,
                },
                models::OpenTicketItemView {
                    id: uuid::Uuid::from_u128(0xB),
                    line: Some(serde_json::json!({ "name": "Burger", "qty": 1 })),
                    line_total: b,
                    menu_item_id: None,
                    round_fired_at: chrono::Utc::now().fixed_offset(),
                    round_number: 1,
                    voided: false,
                },
            ],
        }
    }

    fn ids(of: &[u128]) -> std::collections::HashSet<String> {
        of.iter()
            .map(|n| uuid::Uuid::from_u128(*n).to_string())
            .collect()
    }

    #[test]
    fn a_queued_line_void_takes_the_line_off_the_bill_before_it_syncs() {
        // 50 + 30 at 14%: the server says 80 + 11.20.
        let v = priced_ticket(5000, 3000, 0.14);
        let whole = to_view(&v, false);
        assert_eq!(whole.subtotal_minor, 8000);
        assert_eq!(whole.bill.as_ref().unwrap().total_minor, 9120);

        // The calamari goes back, and the wifi is down.
        let tv = to_view_with(&v, false, &ids(&[0xA]), false);
        assert!(tv.lines[0].voided, "the waiter sees it come off");
        assert!(!tv.lines[1].voided);
        assert_eq!(tv.subtotal_minor, 3000);
        let bill = tv.bill.unwrap();
        assert_eq!(bill.subtotal_minor, 3000);
        assert_eq!(bill.tax_minor, 420, "taxed on what is left, not on 80");
        assert_eq!(
            bill.total_minor, 3420,
            "the cashier collects for one plate, not two"
        );
    }

    #[test]
    fn a_percentage_discount_shrinks_with_the_bill_and_a_fixed_one_does_not() {
        let mut v = priced_ticket(5000, 3000, 0.0);
        v.discount_type = Some(Some("percentage".into()));
        v.discount_value = Some(Some(0.10));
        let bill = to_view_with(&v, false, &ids(&[0xA]), false).bill.unwrap();
        assert_eq!(bill.discount_minor, 300, "10% of the remaining 30");
        assert_eq!(bill.total_minor, 2700);

        v.discount_type = Some(Some("fixed".into()));
        v.discount_value = Some(Some(500.0));
        let bill = to_view_with(&v, false, &ids(&[0xA]), false).bill.unwrap();
        assert_eq!(bill.discount_minor, 500, "five off is five off");
        assert_eq!(bill.total_minor, 2500);
    }

    #[test]
    fn voiding_every_line_leaves_a_bill_of_nothing_not_a_negative_one() {
        let v = priced_ticket(5000, 3000, 0.14);
        let tv = to_view_with(&v, false, &ids(&[0xA, 0xB]), false);
        assert_eq!(tv.subtotal_minor, 0);
        let bill = tv.bill.unwrap();
        assert_eq!(
            (bill.subtotal_minor, bill.tax_minor, bill.total_minor),
            (0, 0, 0)
        );
    }

    #[test]
    fn a_line_the_server_already_voided_is_not_subtracted_twice() {
        let mut v = priced_ticket(5000, 3000, 0.0);
        // The void reached the server: the line comes back already voided AND
        // the subtotal already excludes it.
        v.items[0].voided = true;
        v.subtotal = 3000;
        v.bill = Some(Box::new(models::TicketBill {
            subtotal: 3000,
            discount_amount: 0,
            service_charge_amount: 0,
            service_charge_rate: 0.0,
            tax_amount: 0,
            tax_inclusive: false,
            tax_rate: 0.0,
            total: 3000,
        }));
        // …while the op is still in this device's outbox, mid-drain.
        let tv = to_view_with(&v, false, &ids(&[0xA]), false);
        assert_eq!(
            tv.subtotal_minor, 3000,
            "the overlay skips a line the server has already taken off"
        );
        assert_eq!(tv.bill.unwrap().total_minor, 3000);
    }

    #[test]
    fn to_view_flattens_double_options() {
        let v = models::OpenTicketView {
            id: uuid::Uuid::new_v4(),
            branch_id: uuid::Uuid::new_v4(),
            booking_id: None,
            table_id: None,
            ticket_ref: Some(Some("T-BR-260625-0001".into())),
            status: "open".into(),
            // The server prices the bill; this fixture exercises the flattening
            // of the double-Options around it, so `None` is the case under test.
            bill: None,
            discount_id: None,
            discount_type: None,
            discount_value: None,
            ready: None,
            void_note: None,
            void_reason: None,
            voided_at: None,
            opened_by: uuid::Uuid::new_v4(),
            opened_by_name: Some(Some("Sara".into())),
            customer_name: None,
            notes: None,
            guest_count: Some(Some(2)),
            subtotal: 2000,
            order_id: None,
            opened_at: chrono::Utc::now().fixed_offset(),
            ready_at: None,
            settled_at: None,
            items: vec![],
        };
        let tv = to_view(&v, false);
        assert_eq!(tv.ticket_ref.as_deref(), Some("T-BR-260625-0001"));
        assert_eq!(tv.guest_count, Some(2));
        assert_eq!(tv.subtotal_minor, 2000);
        assert_eq!(tv.status, "open");
        assert!(!tv.queued_offline);
        assert_eq!(
            tv.waiter_name.as_deref(),
            Some("Sara"),
            "the ticket's opener is exposed as the waiter"
        );
    }
}
