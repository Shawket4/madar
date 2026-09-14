//! The floor-side boards read from the changefeed's rows (OFFLINE_B_DESIGN
//! Phases 3–4): open bills, the kitchen feed, the delivery queue and today's
//! arrivals. Each area has its own read-path flag (`tickets`, `kitchen`,
//! `delivery`, `bookings`).
//!
//! In `new` mode no read here touches the network: the rows are kept fresh by
//! the scheduler (realtime nudges, the fallback poll), and every overlay of
//! work this device has queued is applied on top, exactly as before. Until the
//! branch's first complete snapshot has landed there are no rows to read, so a
//! read falls back to the legacy path for that one bootstrap window.

use serde_json::{json, Value};

use crate::error::CoreError;
use crate::readpath::{self, ReadPathMode};
use crate::{bookings, delivery, kds, sync_pull, tickets, MadarCore};

/// Open bills from the synced rows, oldest first.
pub(crate) fn open_ticket_rows(store: &crate::store::Store, branch: &str) -> Vec<madar_api::models::OpenTicketView> {
    let mut bills: Vec<madar_api::models::OpenTicketView> = sync_pull::rows_of_type(store, branch, "open_ticket")
        .into_iter()
        .filter_map(|v| serde_json::from_value(v).ok())
        .filter(|t: &madar_api::models::OpenTicketView| t.status == "open")
        .collect();
    bills.sort_by_key(|t| t.opened_at);
    bills
}

/// A delivery row as the generated model: the feed leaves out `org_id` and
/// `updated_at` (never read by the queue), which the model requires.
fn delivery_model(v: &Value) -> Option<madar_api::models::DeliveryOrder> {
    let mut v = v.clone();
    if v.get("org_id").map(Value::is_null).unwrap_or(true) {
        v["org_id"] = json!(uuid::Uuid::nil());
    }
    if v.get("updated_at").map(Value::is_null).unwrap_or(true) {
        v["updated_at"] = v.get("created_at").cloned().unwrap_or(Value::Null);
    }
    serde_json::from_value(v).ok()
}

impl MadarCore {
    fn feed_mode(&self, area: &str) -> Option<(ReadPathMode, String)> {
        let branch = self.session_branch_id().ok()?;
        let mode = readpath::mode(&self.store, area);
        // Before the first complete snapshot there are no rows to read.
        if mode != ReadPathMode::Legacy && !self.pull_feed_complete(&branch) {
            return Some((ReadPathMode::Legacy, branch));
        }
        Some((mode, branch))
    }

    /// The open bills a read works from: the synced rows once the branch has a
    /// complete snapshot (and the flag is not `legacy`), else the legacy cache.
    pub(crate) fn bill_source(&self) -> Vec<madar_api::models::OpenTicketView> {
        match self.feed_mode("tickets") {
            Some((ReadPathMode::Legacy, _)) | None => {
                crate::cached_views(&self.store, crate::K_OPEN_TICKETS_CACHE)
            }
            Some((_, branch)) => open_ticket_rows(&self.store, &branch),
        }
    }

    /// Apply this device's queued ticket work over a list of bills.
    fn overlay_bills(&self, server: &[madar_api::models::OpenTicketView]) -> Result<Vec<tickets::TicketView>, CoreError> {
        let pending = self.store.pending()?;
        let mut line_voids = tickets::pending_line_voids(&self.store)?;
        // A peer's queued line voids take the plate off here too.
        for env in pending
            .iter()
            .filter(|i| i.op_type == "lan_mirror")
            .filter_map(|i| serde_json::from_str::<Value>(&i.payload).ok())
            .filter(|e| e.get("op").and_then(Value::as_str) == Some("void_ticket_line"))
        {
            if let Some(item) = env.get("item_id").and_then(Value::as_str) {
                line_voids.insert(item.to_string());
            }
        }
        let sc_taxable = self.service_charge_taxable();
        let mut out: Vec<tickets::TicketView> = server
            .iter()
            .filter(|v| v.status != "settled" && v.status != "voided")
            .map(|v| tickets::to_view_with(v, false, &line_voids, sc_taxable))
            .collect();
        // A LAN peer's ticket work this device mirrors for durability (`lan_mirror`
        // rows carry the peer's replay envelope): a bill a waiter fired on another
        // tablet shows here while the cloud is out of reach, and a peer's settle or
        // void clears it, exactly like this device's own queued work.
        let mirrored: Vec<Value> = pending
            .iter()
            .filter(|i| i.op_type == "lan_mirror")
            .filter_map(|i| serde_json::from_str::<Value>(&i.payload).ok())
            .collect();
        let cleared: std::collections::HashSet<String> = pending
            .iter()
            .filter(|i| matches!(i.op_type.as_str(), "settle_open_ticket" | "void_ticket" | "void_open_ticket"))
            .filter_map(|i| {
                serde_json::from_str::<Value>(&i.payload)
                    .ok()
                    .and_then(|v| v.get("ticket_id").and_then(|t| t.as_str()).map(String::from))
            })
            .chain(
                mirrored
                    .iter()
                    .filter(|e| matches!(e.get("op").and_then(Value::as_str), Some("settle_open_ticket" | "void_open_ticket")))
                    .filter_map(|e| e.get("ticket_id").and_then(Value::as_str).map(String::from)),
            )
            .collect();
        // Bills settled or voided on this device and still queued are gone here.
        out.retain(|t| !cleared.contains(&t.id));
        let waiter = self.current_session().map(|s| s.display_name).filter(|s| !s.is_empty());
        for item in pending.iter().filter(|i| i.op_type == "open_ticket") {
            if let Ok(cmd) = serde_json::from_str::<tickets::FireTicketCommand>(&item.payload) {
                if cleared.contains(&cmd.ticket_id) || out.iter().any(|t| t.id == cmd.ticket_id) {
                    continue;
                }
                out.push(crate::queued_ticket_view(&cmd, &item.event_at, waiter.clone()));
            }
        }
        for (item, env) in pending
            .iter()
            .filter(|i| i.op_type == "lan_mirror")
            .filter_map(|i| serde_json::from_str::<Value>(&i.payload).ok().map(|e| (i, e)))
            .filter(|(_, e)| e.get("op").and_then(Value::as_str) == Some("fire_open_ticket"))
        {
            let Ok(request) = serde_json::from_value::<madar_api::models::CreateOpenTicketRequest>(env["request"].clone()) else {
                continue;
            };
            let Some(ticket_id) = request.idempotency_key.flatten().map(|u| u.to_string()) else { continue };
            if cleared.contains(&ticket_id) || out.iter().any(|t| t.id == ticket_id) {
                continue;
            }
            let cmd = tickets::FireTicketCommand { ticket_id, request };
            out.push(crate::queued_ticket_view(&cmd, &item.event_at, None));
        }
        self.overlay_rounds(server, &pending, &mut out);
        Ok(out)
    }

    /// Rounds still on their way — this device's own queued rounds and a peer's
    /// mirrored ones — on the bill they belong to: their lines (named from the
    /// catalogue, as the server will), the bill re-priced through the same engine
    /// as a line void. A round the server already shows (it has a round fired at
    /// or after this one was queued) is not added twice.
    fn overlay_rounds(
        &self,
        server: &[madar_api::models::OpenTicketView],
        pending: &[crate::store::OutboxItem],
        out: &mut [tickets::TicketView],
    ) {
        let mut rounds: Vec<(String, String, madar_api::models::AddRoundRequest, String)> = Vec::new();
        for item in pending {
            let round = match item.op_type.as_str() {
                "ticket_add_round" => serde_json::from_str::<tickets::AddRoundCommand>(&item.payload)
                    .ok()
                    .map(|c| (c.ticket_id, c.round_id, c.request)),
                "lan_mirror" => serde_json::from_str::<Value>(&item.payload)
                    .ok()
                    .filter(|e| e.get("op").and_then(Value::as_str) == Some("add_ticket_round"))
                    .and_then(|e| {
                        let ticket = e.get("ticket_id")?.as_str()?.to_string();
                        let req: madar_api::models::AddRoundRequest = serde_json::from_value(e.get("request")?.clone()).ok()?;
                        let id = req.idempotency_key.flatten()?.to_string();
                        Some((ticket, id, req))
                    }),
                _ => None,
            };
            if let Some((ticket, id, req)) = round {
                if !rounds.iter().any(|r| r.1 == id) {
                    rounds.push((ticket, id, req, item.event_at.clone()));
                }
            }
        }
        if rounds.is_empty() {
            return;
        }
        let names: std::collections::HashMap<String, String> =
            self.list_menu_items().unwrap_or_default().into_iter().map(|m| (m.id, m.name)).collect();
        let instant = |t: &str| chrono::DateTime::parse_from_rfc3339(t).ok();
        for (ticket, _, req, at) in rounds {
            let Some(bill) = out.iter_mut().find(|t| t.id == ticket) else { continue };
            let queued_at = instant(&at);
            let server_has_it = bill
                .lines
                .iter()
                .any(|l| matches!((instant(&l.round_fired_at), queued_at), (Some(f), Some(q)) if f >= q));
            if server_has_it {
                continue;
            }
            let round_number = bill.lines.iter().map(|l| l.round_number).max().unwrap_or(0) + 1;
            let mut added = 0i64;
            for it in &req.items {
                let menu_item_id = it.menu_item_id.flatten().map(|u| u.to_string());
                let line_total = it.unit_price.flatten().unwrap_or(0) as i64 * it.quantity as i64;
                added += line_total;
                bill.lines.push(tickets::TicketLineView {
                    id: String::new(),
                    name: menu_item_id.as_ref().and_then(|m| names.get(m).cloned()).unwrap_or_else(|| "Item".into()),
                    menu_item_id,
                    qty: it.quantity,
                    size_label: it.size_label.clone().flatten(),
                    modifiers: Vec::new(),
                    line_total_minor: line_total,
                    voided: false,
                    round_number,
                    round_fired_at: at.clone(),
                });
            }
            bill.subtotal_minor += added;
            if let (Some(b), Some(v)) = (bill.bill.as_ref(), server.iter().find(|v| v.id.to_string() == ticket)) {
                let (dt, dv) = tickets::waiter_discount(v);
                bill.bill = Some(tickets::reprice_with(b, bill.subtotal_minor, dt.as_deref(), dv, false));
            }
            bill.queued_offline = true;
        }
    }

    /// The branch's open bills (newest first) with this device's queued fires,
    /// line voids, settles and voids applied.
    pub async fn list_open_tickets(&self) -> Result<Vec<tickets::TicketView>, CoreError> {
        let (mode, branch) = self.feed_mode("tickets").ok_or_else(|| CoreError::Unauthenticated {
            detail: "not signed in".into(),
        })?;
        if mode == ReadPathMode::Legacy {
            return self.legacy_list_open_tickets().await;
        }
        let new = self.overlay_bills(&open_ticket_rows(&self.store, &branch))?;
        let _ = self.store.kv_put(crate::K_OPEN_TICKETS_STALE, "");
        if mode == ReadPathMode::Shadow {
            let legacy = self.legacy_list_open_tickets().await?;
            self.report_divergence(
                "tickets",
                readpath::diff_keyed("open tickets", &readpath::tickets_keyed(&legacy), &readpath::tickets_keyed(&new)),
            );
            return Ok(legacy);
        }
        Ok(new)
    }

    /// One bill (the detail screen): the synced row, with this device's queued
    /// line voids applied; the server only for a bill not held here.
    pub async fn get_ticket(&self, ticket_id: String) -> Result<tickets::TicketView, CoreError> {
        if let Some((mode, branch)) = self.feed_mode("tickets") {
            if mode != ReadPathMode::Legacy {
                if let Some(v) = sync_pull::rows_of_type(&self.store, &branch, "open_ticket")
                    .into_iter()
                    .filter_map(|v| serde_json::from_value::<madar_api::models::OpenTicketView>(v).ok())
                    .find(|v| v.id.to_string() == ticket_id)
                {
                    return Ok(tickets::to_view_with(
                        &v,
                        false,
                        &tickets::pending_line_voids(&self.store)?,
                        self.service_charge_taxable(),
                    ));
                }
            }
        }
        self.legacy_get_ticket(ticket_id).await
    }

    /// The kitchen board: open kitchen tickets (for a station: those with work
    /// still on it), with LAN-relayed fires and queued bumps overlaid.
    pub async fn kds_list(&self, station_id: Option<String>) -> Result<Vec<kds::KdsTicketView>, CoreError> {
        let (mode, branch) = self.feed_mode("kitchen").ok_or_else(|| CoreError::Unauthenticated {
            detail: "not signed in".into(),
        })?;
        if mode == ReadPathMode::Legacy {
            return self.legacy_kds_list(station_id).await;
        }
        let station = station_id.as_deref().and_then(|s| uuid::Uuid::parse_str(s).ok());
        let mut rows: Vec<madar_api::models::KitchenTicketView> = sync_pull::rows_of_type(&self.store, &branch, "kitchen_ticket")
            .into_iter()
            .filter(|v| v.get("closed_at").map(Value::is_null).unwrap_or(true))
            .filter_map(|v| serde_json::from_value::<madar_api::models::KitchenTicketView>(v).ok())
            .filter(|t| t.status != "voided")
            .filter(|t| {
                station.is_none_or(|st| {
                    t.items.iter().any(|it| !it.bumped && it.station_id.flatten() == Some(st))
                })
            })
            .collect();
        rows.sort_by_key(|t| t.created_at);
        let mut out: Vec<kds::KdsTicketView> = rows.iter().map(kds::ticket_view).collect();
        let mut lan = crate::lan_kds_read(&self.store);
        let synced: std::collections::HashSet<String> = out.iter().map(|t| t.id.clone()).collect();
        let before = lan.len();
        lan.retain(|t| !synced.contains(&t.id));
        if lan.len() != before {
            crate::lan_kds_write(&self.store, &lan);
        }
        kds::overlay_lan_tickets(&mut out, lan);
        kds::overlay_pending_bumps(&mut out, &self.pending_bumps());
        kds::sort_feed(&mut out);
        if mode == ReadPathMode::Shadow {
            let legacy = self.legacy_kds_list(station_id).await?;
            let key = |v: &[kds::KdsTicketView]| {
                v.iter()
                    .map(|t| (t.id.clone(), (t.status.clone(), t.items.len() as i64)))
                    .collect::<std::collections::BTreeMap<_, _>>()
            };
            self.report_divergence("kitchen", readpath::diff_keyed("kds", &key(&legacy), &key(&out)));
            return Ok(legacy);
        }
        Ok(out)
    }

    /// The branch's base prep minutes: the synced branch settings, else the
    /// last settings read.
    pub(crate) fn prep_minutes(&self) -> i64 {
        self.session_branch_id()
            .ok()
            .and_then(|b| {
                sync_pull::rows_of_type(&self.store, &b, "branch_settings")
                    .into_iter()
                    .find(|v| v.get("id").and_then(Value::as_str) == Some(b.as_str()))
            })
            .and_then(|v| v.get("delivery_prep_minutes").and_then(Value::as_i64))
            .unwrap_or_else(|| self.cached_prep_minutes())
    }

    /// The delivery queue (newest first), filtered by a comma-separated status list.
    pub async fn list_delivery_orders(&self, status: Option<String>) -> Result<Vec<delivery::DeliveryOrderView>, CoreError> {
        let (mode, branch) = self.feed_mode("delivery").ok_or_else(|| CoreError::Unauthenticated {
            detail: "not signed in".into(),
        })?;
        if mode == ReadPathMode::Legacy {
            return self.legacy_list_delivery_orders(status).await;
        }
        let wanted: Option<Vec<String>> = status
            .as_deref()
            .map(|s| s.split(',').map(|x| x.trim().to_string()).filter(|x| !x.is_empty()).collect());
        let loc = self.current_locale();
        let prep = self.prep_minutes();
        let mut rows: Vec<madar_api::models::DeliveryOrder> = sync_pull::rows_of_type(&self.store, &branch, "delivery")
            .iter()
            .filter_map(delivery_model)
            .filter(|o| wanted.as_ref().is_none_or(|w| w.iter().any(|s| s == &o.status)))
            .collect();
        rows.sort_by_key(|o| std::cmp::Reverse(o.created_at));
        let new: Vec<delivery::DeliveryOrderView> = rows
            .iter()
            .map(|o| self.localize_payment_hint(delivery::order_view(o, &loc, prep)))
            .collect();
        if mode == ReadPathMode::Shadow {
            let legacy = self.legacy_list_delivery_orders(status).await?;
            let key = |v: &[delivery::DeliveryOrderView]| {
                v.iter().map(|d| (d.id.clone(), d.status.clone())).collect::<std::collections::BTreeMap<_, _>>()
            };
            // The legacy list is capped at 200 and reaches further back.
            let l = key(&legacy);
            let n: std::collections::BTreeMap<_, _> = key(&new).into_iter().filter(|(k, _)| l.contains_key(k)).collect();
            self.report_divergence("delivery", readpath::diff_keyed("delivery", &l, &n));
            return Ok(legacy);
        }
        Ok(new)
    }

    /// Today's active bookings (earliest first), with this device's queued seat /
    /// no-show answers applied.
    pub fn list_arrivals(&self) -> Result<Vec<bookings::BookingView>, CoreError> {
        let Some((mode, branch)) = self.feed_mode("bookings") else {
            return self.legacy_list_arrivals();
        };
        if mode == ReadPathMode::Legacy {
            return self.legacy_list_arrivals();
        }
        let tz = crate::timefmt::branch_tz(&self.store);
        let today = chrono::Utc::now().with_timezone(&tz).date_naive();
        let (from, to) = crate::timefmt::local_day_bounds(tz, today);
        let mut list: Vec<bookings::BookingView> = sync_pull::rows_of_type(&self.store, &branch, "booking")
            .into_iter()
            .filter_map(|v| serde_json::from_value::<madar_api::models::BookingView>(v).ok())
            .filter(|b| b.starts_at < to && b.ends_at > from)
            .map(bookings::BookingView::from)
            .collect();
        for item in self.store.pending()? {
            let (id, status) = match item.op_type.as_str() {
                "seat_booking" => match serde_json::from_str::<bookings::SeatBookingCommand>(&item.payload) {
                    Ok(c) => (c.booking_id, "seated"),
                    Err(_) => continue,
                },
                "no_show_booking" => match serde_json::from_str::<bookings::NoShowBookingCommand>(&item.payload) {
                    Ok(c) => (c.booking_id, "no_show"),
                    Err(_) => continue,
                },
                _ => continue,
            };
            if let Some(b) = list.iter_mut().find(|b| b.id == id) {
                b.status = status.to_string();
            }
        }
        list.retain(|b| matches!(b.status.as_str(), "confirmed" | "seated"));
        list.sort_by(|a, b| a.starts_at.cmp(&b.starts_at));
        if mode == ReadPathMode::Shadow {
            let legacy = self.legacy_list_arrivals()?;
            let key = |v: &[bookings::BookingView]| {
                v.iter().map(|b| (b.id.clone(), b.status.clone())).collect::<std::collections::BTreeMap<_, _>>()
            };
            self.report_divergence("bookings", readpath::diff_keyed("arrivals", &key(&legacy), &key(&list)));
            return Ok(legacy);
        }
        Ok(list)
    }
}
