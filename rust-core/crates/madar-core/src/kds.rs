//! Kitchen Display System — client side (PLAN §"Kitchen Display System").
//!
//! A KDS device subscribes to the `kitchen` topic on the unified bus (one SSE,
//! `realtime.rs`) and shows the branch's outstanding kitchen tickets — fed by BOTH
//! waiter rounds AND teller counter orders (the source-agnostic substrate). Each
//! station bumps its own lines; a ticket is "ready" when every line is bumped. The
//! seed/refresh list is `GET /kitchen/orders` (cached so the board survives a
//! reconnect); bump/unbump are online-direct writes.
//!
//! This module holds the FFI view DTOs + pure mappers + the feed sort. The exported
//! `MadarCore` methods (list_stations / feed / bump / unbump) live in `lib.rs`.
//!
//! Bump/unbump are OUTBOX-BACKED (Phase E §2): each tap writes a durable replay op
//! first, then drains to `POST /sync/replay` (online-direct when connected), so a
//! network blip never loses a bump. A read-time overlay of the still-pending bumps
//! ([`overlay_pending_bumps`]) reflects the cook's latest tap on the board instantly,
//! even offline, before the op syncs.

use madar_api::models;
use serde::{Deserialize, Serialize};

// ── Outbox command (durable bump intent) ──────────────────────────────────────

/// The payload of a queued bump/unbump op. The direction lives in the outbox
/// `op_type` (`bump_kitchen` / `unbump_kitchen`); the kitchen line `item_id` is the
/// natural idempotency key (re-bumping a bumped line is a server-side no-op).
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct BumpCommand {
    pub item_id: String,
}

// ── FFI view DTOs ─────────────────────────────────────────────────────────────

/// A kitchen station (Grill, Bar…) for the KDS station picker + chit printing.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct KdsStationView {
    pub id: String,
    pub name: String,
    pub is_default: bool,
    pub is_active: bool,
    /// Wire name of the station's printer brand (e.g. "star", "epson"), if set.
    pub printer_brand: Option<String>,
    pub printer_ip: Option<String>,
    pub printer_port: Option<i32>,
}

/// One outstanding kitchen ticket (a fired waiter round or a teller order).
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct KdsTicketView {
    pub id: String,
    pub kitchen_ref: Option<String>,
    pub table_label: Option<String>,
    pub round_number: i32,
    /// `order` (teller) | `open_ticket` (waiter).
    pub source_type: String,
    /// firing | ready | voided.
    pub status: String,
    pub created_at: String,
    pub items: Vec<KdsLineView>,
}

/// One kitchen line (NO prices — the kitchen copy is slim by design).
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct KdsLineView {
    pub id: String,
    pub name: String,
    pub qty: i32,
    pub size_label: Option<String>,
    pub modifiers: Vec<String>,
    pub notes: Option<String>,
    pub station_id: Option<String>,
    pub station_name: Option<String>,
    pub bumped: bool,
    /// The combo this line is one item of (C12): the station makes only its
    /// part, tagged with the combo so the pass can bring the rest together.
    pub combo: Option<KdsComboTag>,
}

/// A kitchen line's combo (`KitchenLine.combo`, contract §3.3).
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct KdsComboTag {
    /// The combo's header line id: every item of one combo shares it.
    pub line_id: String,
    pub name: String,
}

/// The combo tag a slim `KitchenLine` JSON carries, if any.
fn combo_tag(line: Option<&serde_json::Value>) -> Option<KdsComboTag> {
    let c = line?.get("combo").filter(|c| c.is_object())?;
    Some(KdsComboTag {
        line_id: c.get("line_id")?.as_str()?.to_string(),
        name: c.get("name").and_then(|n| n.as_str()).unwrap_or_default().to_string(),
    })
}

// ── Mappers ───────────────────────────────────────────────────────────────────

fn flat<T: Clone>(o: &Option<Option<T>>) -> Option<T> {
    o.as_ref().and_then(|x| x.clone())
}

pub(crate) fn station_view(s: &models::KitchenStation) -> KdsStationView {
    let printer_brand = flat(&s.printer_brand)
        .and_then(|b| serde_json::to_value(b).ok())
        .and_then(|v| v.as_str().map(|x| x.to_string()));
    KdsStationView {
        id: s.id.to_string(),
        name: s.name.clone(),
        is_default: s.is_default,
        is_active: s.is_active,
        printer_brand,
        printer_ip: flat(&s.printer_ip),
        printer_port: flat(&s.printer_port),
    }
}

pub(crate) fn ticket_view(t: &models::KitchenTicketView) -> KdsTicketView {
    KdsTicketView {
        id: t.id.to_string(),
        kitchen_ref: flat(&t.kitchen_ref),
        table_label: flat(&t.table_label),
        round_number: t.round_number,
        source_type: t.source_type.clone(),
        status: t.status.clone(),
        created_at: t.created_at.to_rfc3339(),
        items: t.items.iter().map(line_view).collect(),
    }
}

fn line_view(it: &models::KitchenTicketItemView) -> KdsLineView {
    // The slim `line` JSON is the `KitchenLine` shape (name/qty/size/modifiers/notes).
    let line = it.line.as_ref();
    let s = |k: &str| {
        line.and_then(|l| l.get(k))
            .and_then(|v| v.as_str())
            .map(|x| x.to_string())
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
    KdsLineView {
        id: it.id.to_string(),
        name: s("name").unwrap_or_else(|| "Item".to_string()),
        qty: it.qty,
        size_label: s("size_label"),
        modifiers,
        notes: s("notes"),
        station_id: flat(&it.station_id).map(|u| u.to_string()),
        station_name: flat(&it.station_name),
        bumped: it.bumped,
        combo: combo_tag(line),
    }
}

// ── Chit printer routing ──────────────────────────────────────────────────────

/// Where a kitchen chit for one item goes: its station's printer, or — when the
/// item has no station with a printer — the device's own till printer.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChitPrinterTarget {
    /// The station the item routes to, when that station has a printer.
    pub station_id: Option<String>,
    pub station_name: Option<String>,
    /// The station printer's LAN address. `None` = print on the till printer.
    pub host: Option<String>,
    pub port: Option<u16>,
    /// The station printer's brand wire name (`epson` / `star`), if set.
    pub brand: Option<String>,
}

impl ChitPrinterTarget {
    /// The device's own till printer.
    pub fn till() -> Self {
        ChitPrinterTarget { station_id: None, station_name: None, host: None, port: None, brand: None }
    }
    pub fn is_till(&self) -> bool {
        self.host.is_none()
    }
}

/// JetDirect default when a station printer has an address but no port.
pub const DEFAULT_PRINTER_PORT: u16 = 9100;

/// The branch's station routes (`kitchen_routes` on the settings row).
pub(crate) const F_ROUTES: (&str, &str) = ("kitchen_routes", "cache:kitchen_routes");

/// Resolve the printer for ONE item's chit, the way a fired round routes it:
/// the item's own route, else its category's route, else the branch's default
/// station. The station must be active and have a printer; otherwise the chit
/// falls back to the till printer. Pure — the caller supplies synced data.
pub fn resolve_chit_printer(
    item_id: &str,
    category_id: Option<&str>,
    routes: &models::StationRoutes,
    stations: &[KdsStationView],
) -> ChitPrinterTarget {
    let routed = routes
        .items
        .iter()
        .find(|r| r.menu_item_id.to_string() == item_id)
        .map(|r| r.station_id.to_string())
        .or_else(|| {
            category_id.and_then(|c| {
                routes
                    .categories
                    .iter()
                    .find(|r| r.category_id.to_string() == c)
                    .map(|r| r.station_id.to_string())
            })
        });
    let station = match routed {
        Some(id) => stations.iter().find(|s| s.id == id),
        None => stations.iter().find(|s| s.is_default),
    };
    match station {
        Some(s) if s.is_active => match s.printer_ip.as_deref().map(str::trim).filter(|h| !h.is_empty()) {
            Some(host) => ChitPrinterTarget {
                station_id: Some(s.id.clone()),
                station_name: Some(s.name.clone()),
                host: Some(host.to_string()),
                port: Some(
                    s.printer_port
                        .and_then(|p| u16::try_from(p).ok())
                        .filter(|p| *p != 0)
                        .unwrap_or(DEFAULT_PRINTER_PORT),
                ),
                brand: s.printer_brand.clone(),
            },
            None => ChitPrinterTarget::till(),
        },
        _ => ChitPrinterTarget::till(),
    }
}

// ── Routing mode ──────────────────────────────────────────────────────────────

/// kv key for the branch's last-known kitchen routing mode.
pub(crate) const K_ROUTING_MODE: &str = "cache:kitchen_routing_mode";

/// Does the TILL show kitchen work in this mode?
///
/// `till` and `both` are the two modes where a fired round is expected to be
/// seen and bumped at the counter. In `kds` the kitchen owns the board, and a
/// till that bumps is bumping behind the cook's back — the line goes dark on a
/// screen someone is still working from. In `off` nothing is routed anywhere,
/// so there is no work to show.
///
/// `None` is "we have never asked the server" — a device bound but not yet
/// synced. It answers `false`, deliberately: hiding a segment costs a tap,
/// showing it in `kds` mode costs the kitchen a ticket.
pub fn till_shows_kitchen(mode: Option<&str>) -> bool {
    matches!(mode, Some("till") | Some("both"))
}

/// Is anything routed to a kitchen at all?
///
/// `off` means the shop does not fire rounds anywhere — no chit, no board, no
/// readiness. A screen that draws "ready" states in `off` mode is describing a
/// workflow the shop does not run.
pub fn kitchen_is_routed(mode: Option<&str>) -> bool {
    !matches!(mode, Some("off"))
}

// ── Offline fire projection (Phase E) ─────────────────────────────────────────
//
// When a waiter fires while offline, the KDS must still show the ticket NOW. The
// fire publishes a projection of itself over the LAN; the KDS overlays it on the
// (stale) cached feed until the real server ticket arrives on reconnect. The ids are
// DERIVED from the round's client idempotency key by the SAME rule the backend uses
// (`kitchen::derive_*`), so the projection dedups against the server feed by id and a
// bump on a derived line id reconciles once the fire syncs.

/// The kitchen-ticket id a fire WILL create, from the round's client idempotency key
/// (madar-shared `madar_sync::kitchen`, the server's rule). Pinned here by
/// `kitchen_id_derivation_matches_backend`.
pub(crate) fn derive_kitchen_ticket_id(round_idem: &str) -> Option<String> {
    let seed = uuid::Uuid::parse_str(round_idem).ok()?;
    Some(madar_sync::kitchen::derive_kitchen_ticket_id(seed).to_string())
}

/// The kitchen-line id for the line at `index` within its derived kitchen ticket.
pub(crate) fn derive_kitchen_item_id(kitchen_ticket_id: &str, index: usize) -> String {
    let kt = uuid::Uuid::parse_str(kitchen_ticket_id).unwrap_or(uuid::Uuid::nil());
    madar_sync::kitchen::derive_kitchen_item_id(kt, index).to_string()
}

/// Build the KDS projection of a just-fired round from the cart lines, with the
/// SAME ids the server will mint (so reconnect dedups it). `None` if the round id
/// isn't a UUID (a non-client fire — no projection to predict).
pub(crate) fn build_fire_projection(
    round_idem: &str,
    lines: &[crate::cart::CartLineView],
    table_label: Option<String>,
    round_number: i32,
    created_at: String,
) -> Option<KdsTicketView> {
    let kt = derive_kitchen_ticket_id(round_idem)?;
    // A combo is never fired itself: each of its items goes to the kitchen,
    // tagged with it (C12), in the order the server numbers kitchen lines.
    let dishes: Vec<KdsLineView> = lines
        .iter()
        .flat_map(|l| -> Vec<KdsLineView> {
            if l.kind == crate::menu::KIND_COMBO {
                let tag = KdsComboTag { line_id: l.key.clone(), name: l.name.clone() };
                return l
                    .parts
                    .iter()
                    .map(|p| {
                        let mut modifiers: Vec<String> = p.addons.iter().map(|a| a.name.clone()).collect();
                        modifiers.extend(p.optionals.iter().map(|o| o.name.clone()));
                        KdsLineView {
                            id: String::new(),
                            name: p.item_name.clone(),
                            qty: (p.qty.max(1) * l.qty.max(1)) as i32,
                            size_label: p.size_label.clone(),
                            modifiers,
                            notes: p.notes.clone(),
                            station_id: None,
                            station_name: None,
                            bumped: false,
                            combo: Some(tag.clone()),
                        }
                    })
                    .collect();
            }
            let mut modifiers: Vec<String> = l.addons.iter().map(|a| a.name.clone()).collect();
            modifiers.extend(l.optionals.iter().map(|o| o.name.clone()));
            vec![KdsLineView {
                id: String::new(),
                name: l.name.clone(),
                qty: l.qty as i32,
                size_label: l.size_label.clone(),
                modifiers,
                notes: l.notes.clone(),
                station_id: None, // routing is server config; unknown offline
                station_name: None,
                bumped: false,
                combo: None,
            }]
        })
        .collect();
    let items = dishes
        .into_iter()
        .enumerate()
        .map(|(i, mut d)| {
            d.id = derive_kitchen_item_id(&kt, i);
            d
        })
        .collect();
    Some(KdsTicketView {
        id: kt,
        kitchen_ref: None,
        table_label,
        round_number,
        source_type: "open_ticket".into(),
        status: "firing".into(),
        created_at,
        items,
    })
}

/// The KDS projection of a fire or round from its replay envelope (catch-up of an
/// op rung while no relay ran): the SAME derived ids as the live projection, line
/// names from the catalogue.
pub(crate) fn projection_from_envelope(
    envelope: &serde_json::Value,
    names: &std::collections::HashMap<String, String>,
    created_at: &str,
) -> Option<KdsTicketView> {
    let req = envelope.get("request")?;
    let round_idem = req
        .get("round_idempotency_key")
        .or_else(|| req.get("idempotency_key"))
        .and_then(|v| v.as_str())?;
    let kt = derive_kitchen_ticket_id(round_idem)?;
    let name_of = |id: &str| names.get(id).cloned().unwrap_or_else(|| "Item".into());
    let items = req
        .get("items")
        .and_then(|v| v.as_array())
        .map(|a| {
            a.iter()
                .enumerate()
                .flat_map(|(li, it)| -> Vec<KdsLineView> {
                    let menu = it.get("menu_item_id").and_then(|m| m.as_str()).unwrap_or("");
                    let qty = it.get("quantity").and_then(|q| q.as_i64()).unwrap_or(1);
                    // A combo line: its picks are the dishes (C12).
                    if let Some(picks) = it.pointer("/combo/picks").and_then(|p| p.as_array()) {
                        let tag = KdsComboTag { line_id: format!("{round_idem}:{li}"), name: name_of(menu) };
                        return picks
                            .iter()
                            .map(|p| KdsLineView {
                                id: String::new(),
                                name: name_of(p.get("menu_item_id").and_then(|m| m.as_str()).unwrap_or("")),
                                qty: (p.get("quantity").and_then(|q| q.as_i64()).unwrap_or(1).max(1) * qty.max(1)) as i32,
                                size_label: p.get("size_label").and_then(|x| x.as_str()).map(str::to_string),
                                modifiers: Vec::new(),
                                notes: p.get("notes").and_then(|x| x.as_str()).map(str::to_string),
                                station_id: None,
                                station_name: None,
                                bumped: false,
                                combo: Some(tag.clone()),
                            })
                            .collect();
                    }
                    vec![KdsLineView {
                        id: String::new(),
                        name: name_of(menu),
                        qty: qty as i32,
                        size_label: it.get("size_label").and_then(|x| x.as_str()).map(str::to_string),
                        modifiers: Vec::new(),
                        notes: it.get("notes").and_then(|x| x.as_str()).map(str::to_string),
                        station_id: None,
                        station_name: None,
                        bumped: false,
                        combo: None,
                    }]
                })
                .enumerate()
                .map(|(i, mut d)| {
                    d.id = derive_kitchen_item_id(&kt, i);
                    d
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    if items.is_empty() {
        return None;
    }
    let is_round = envelope.get("op").and_then(|o| o.as_str()) == Some("add_ticket_round");
    Some(KdsTicketView {
        id: kt,
        kitchen_ref: None,
        table_label: None,
        round_number: if is_round { 0 } else { 1 },
        source_type: "open_ticket".into(),
        status: "firing".into(),
        created_at: created_at.to_string(),
        items,
    })
}

/// Overlay LAN-received (un-synced) kitchen tickets onto the server feed: include a
/// projected ticket only when the server feed doesn't already have it (dedup by id —
/// the derived id == the eventual server id), and never a voided one. The host then
/// sees an offline fire instantly; on reconnect the server row replaces it cleanly.
pub(crate) fn overlay_lan_tickets(feed: &mut Vec<KdsTicketView>, lan: Vec<KdsTicketView>) {
    let have: std::collections::HashSet<String> = feed.iter().map(|t| t.id.clone()).collect();
    for t in lan {
        if !have.contains(&t.id) && t.status != "voided" {
            feed.push(t);
        }
    }
}

/// Mark a line bumped/un-bumped across a set of (LAN-overlay) tickets — so a bump
/// relayed over the LAN greys the line on a peer's board too, not just the bumper's.
pub(crate) fn apply_lan_bump(tickets: &mut [KdsTicketView], item_id: &str, bumped: bool) {
    for t in tickets.iter_mut() {
        for l in t.items.iter_mut() {
            if l.id == item_id {
                l.bumped = bumped;
            }
        }
        if t.status != "voided" {
            t.status = if !t.items.is_empty() && t.items.iter().all(|l| l.bumped) {
                "ready".into()
            } else {
                "firing".into()
            };
        }
    }
}

/// Overlay still-pending (un-synced) bumps onto a freshly-built feed so the board
/// reflects the cook's latest tap instantly — even offline, before the bump drains.
/// `bumps` is `(line_id, bumped)` in FIFO (enqueue) order, so a later tap on the
/// same line wins. A ticket whose lines are now all bumped is shown `ready` (unless
/// voided), keeping the optimistic state consistent with `sort_feed`'s grouping.
/// Pure + unit-tested.
pub(crate) fn overlay_pending_bumps(tickets: &mut [KdsTicketView], bumps: &[(String, bool)]) {
    if bumps.is_empty() {
        return;
    }
    for t in tickets.iter_mut() {
        let mut touched = false;
        for line in t.items.iter_mut() {
            // Last matching intent wins (FIFO order → fold left).
            for (id, bumped) in bumps.iter() {
                if *id == line.id {
                    line.bumped = *bumped;
                    touched = true;
                }
            }
        }
        // Re-derive display readiness from the overlaid lines (never resurrect a
        // voided ticket; never mark an empty ticket ready).
        if touched && t.status != "voided" {
            t.status = if !t.items.is_empty() && t.items.iter().all(|l| l.bumped) {
                "ready".to_string()
            } else {
                "firing".to_string()
            };
        }
    }
}

/// Order the feed for the board: OLDEST first (rush-to-top — the longest-waiting
/// ticket leads), still-firing ahead of already-ready at the same instant. Pure +
/// unit-tested; the host renders the result verbatim.
pub(crate) fn sort_feed(tickets: &mut [KdsTicketView]) {
    tickets.sort_by(|a, b| {
        // Ready tickets sink below still-firing ones; within a group, oldest first.
        let rank = |s: &str| if s == "ready" { 1 } else { 0 };
        rank(&a.status)
            .cmp(&rank(&b.status))
            .then(a.created_at.cmp(&b.created_at))
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tk(id: &str, status: &str, created_at: &str) -> KdsTicketView {
        KdsTicketView {
            id: id.into(),
            kitchen_ref: None,
            table_label: None,
            round_number: 1,
            source_type: "open_ticket".into(),
            status: status.into(),
            created_at: created_at.into(),
            items: vec![],
        }
    }

    #[test]
    fn sort_puts_oldest_firing_first_ready_last() {
        let mut v = vec![
            tk("new", "firing", "2026-06-25T10:05:00Z"),
            tk("ready_old", "ready", "2026-06-25T10:00:00Z"),
            tk("old", "firing", "2026-06-25T10:01:00Z"),
        ];
        sort_feed(&mut v);
        let order: Vec<&str> = v.iter().map(|t| t.id.as_str()).collect();
        // firing oldest → firing newer → ready (even though ready is chronologically oldest).
        assert_eq!(order, ["old", "new", "ready_old"]);
    }

    fn line(id: &str, bumped: bool) -> KdsLineView {
        KdsLineView {
            id: id.into(),
            name: "Item".into(),
            qty: 1,
            size_label: None,
            modifiers: vec![],
            notes: None,
            station_id: None,
            station_name: None,
            bumped,
            combo: None,
        }
    }

    #[test]
    fn overlay_applies_latest_pending_bump_and_rederives_ready() {
        let mut t = tk("t1", "firing", "2026-06-25T10:00:00Z");
        t.items = vec![line("a", false), line("b", false)];
        let mut feed = vec![t];

        // Bump both lines → ticket should flip to ready.
        overlay_pending_bumps(&mut feed, &[("a".into(), true), ("b".into(), true)]);
        assert!(feed[0].items.iter().all(|l| l.bumped));
        assert_eq!(feed[0].status, "ready", "all lines bumped → ready");

        // A later un-bump of one line wins over the earlier bump → back to firing.
        overlay_pending_bumps(&mut feed, &[("a".into(), true), ("a".into(), false)]);
        assert!(!feed[0].items.iter().find(|l| l.id == "a").unwrap().bumped);
        assert_eq!(feed[0].status, "firing", "a re-opened → not ready");
    }

    #[test]
    fn kitchen_id_derivation_matches_backend() {
        // CROSS-REPO CONTRACT: these MUST equal the backend's pinned values
        // (`kitchen::id_tests::kitchen_id_derivation_is_pinned`). Same namespace + v5.
        let nil = "00000000-0000-0000-0000-000000000000";
        let kt = derive_kitchen_ticket_id(nil).unwrap();
        assert_eq!(kt, "e9b2a598-f8ea-5510-8382-927f5e218fff");
        assert_eq!(
            derive_kitchen_item_id(&kt, 0),
            "0b40ac60-7d15-5bef-858f-849b09850f69"
        );
        assert_eq!(
            derive_kitchen_item_id(&kt, 1),
            "50cef3f1-fced-57d3-bb6c-daa1c917a8b6"
        );
    }

    #[test]
    fn lan_overlay_adds_unsynced_and_dedups_synced() {
        let mut feed = vec![tk("server-1", "firing", "2026-06-25T10:00:00Z")];
        let lan = vec![
            tk("server-1", "firing", "2026-06-25T10:00:00Z"), // already in feed → dropped
            tk("lan-2", "firing", "2026-06-25T10:01:00Z"),    // not synced → added
            tk("lan-void", "voided", "2026-06-25T10:02:00Z"), // voided → never shown
        ];
        overlay_lan_tickets(&mut feed, lan);
        let ids: Vec<&str> = feed.iter().map(|t| t.id.as_str()).collect();
        assert_eq!(ids, ["server-1", "lan-2"]);
    }

    #[test]
    fn overlay_never_resurrects_a_voided_ticket() {
        let mut t = tk("t1", "voided", "2026-06-25T10:00:00Z");
        t.items = vec![line("a", false)];
        let mut feed = vec![t];
        overlay_pending_bumps(&mut feed, &[("a".into(), true)]);
        assert_eq!(feed[0].status, "voided", "voided stays voided");
    }

    #[test]
    fn line_view_reads_slim_kitchen_json() {
        let it = models::KitchenTicketItemView {
            bumped: false,
            id: uuid::Uuid::new_v4(),
            line: Some(serde_json::json!({
                "name": "Steak", "size_label": null, "qty": 2,
                "modifiers": ["Medium rare"], "notes": "no salt"
            })),
            qty: 2,
            station_id: None,
            station_name: Some(Some("Grill".into())),
        };
        let lv = line_view(&it);
        assert_eq!(lv.name, "Steak");
        assert_eq!(lv.qty, 2);
        assert_eq!(lv.modifiers, vec!["Medium rare"]);
        assert_eq!(lv.notes.as_deref(), Some("no salt"));
        assert_eq!(lv.station_name.as_deref(), Some("Grill"));
        assert!(!lv.bumped);
    }

    #[test]
    fn only_till_modes_let_the_counter_bump() {
        assert!(till_shows_kitchen(Some("till")));
        assert!(till_shows_kitchen(Some("both")));
        assert!(
            !till_shows_kitchen(Some("kds")),
            "the kitchen owns the board"
        );
        assert!(!till_shows_kitchen(Some("off")));
        assert!(!till_shows_kitchen(None), "never asked → do not guess");
    }

    #[test]
    fn off_is_the_only_mode_with_no_kitchen() {
        assert!(!kitchen_is_routed(Some("off")));
        for m in ["kds", "till", "both"] {
            assert!(kitchen_is_routed(Some(m)));
        }
        assert!(
            kitchen_is_routed(None),
            "unknown is not off — a shop that routes must not lose its readiness"
        );
    }

    // ── chit printer routing ────────────────────────────────────────────────

    const ITEM: &str = "11111111-1111-1111-1111-111111111111";
    const CAT: &str = "22222222-2222-2222-2222-222222222222";
    const GRILL: &str = "33333333-3333-3333-3333-333333333333";
    const BAR: &str = "44444444-4444-4444-4444-444444444444";

    fn st(id: &str, name: &str, default: bool, ip: Option<&str>) -> KdsStationView {
        KdsStationView {
            id: id.into(),
            name: name.into(),
            is_default: default,
            is_active: true,
            printer_brand: Some("star".into()),
            printer_ip: ip.map(Into::into),
            printer_port: None,
        }
    }

    fn uid(s: &str) -> uuid::Uuid {
        uuid::Uuid::parse_str(s).unwrap()
    }

    fn no_routes() -> models::StationRoutes {
        models::StationRoutes { categories: vec![], items: vec![] }
    }

    #[test]
    fn a_chit_goes_to_its_stations_printer() {
        let routes = models::StationRoutes {
            categories: vec![],
            items: vec![models::ItemRoute::new(uid(ITEM), uid(GRILL))],
        };
        let stations = [st(BAR, "Bar", true, Some("10.0.0.9")), st(GRILL, "Grill", false, Some("10.0.0.5"))];
        let t = resolve_chit_printer(ITEM, Some(CAT), &routes, &stations);
        assert!(!t.is_till());
        assert_eq!(t.station_name.as_deref(), Some("Grill"));
        assert_eq!(t.host.as_deref(), Some("10.0.0.5"));
        assert_eq!(t.port, Some(DEFAULT_PRINTER_PORT));
        assert_eq!(t.brand.as_deref(), Some("star"));

        // A category route answers for an item with no route of its own.
        let routes = models::StationRoutes {
            categories: vec![models::CategoryRoute::new(uid(CAT), uid(BAR))],
            items: vec![],
        };
        let t = resolve_chit_printer(ITEM, Some(CAT), &routes, &stations);
        assert_eq!(t.station_name.as_deref(), Some("Bar"));
    }

    #[test]
    fn no_station_printer_falls_back_to_the_till() {
        // No stations at all.
        assert_eq!(resolve_chit_printer(ITEM, None, &no_routes(), &[]), ChitPrinterTarget::till());
        // Routed to a station that has no printer.
        let routes = models::StationRoutes {
            categories: vec![],
            items: vec![models::ItemRoute::new(uid(ITEM), uid(GRILL))],
        };
        let stations = [st(GRILL, "Grill", false, None)];
        assert!(resolve_chit_printer(ITEM, None, &routes, &stations).is_till());
        // Routed to an inactive station.
        let mut off = st(GRILL, "Grill", false, Some("10.0.0.5"));
        off.is_active = false;
        assert!(resolve_chit_printer(ITEM, None, &routes, &[off]).is_till());
        // Unrouted, and no default station.
        let stations = [st(GRILL, "Grill", false, Some("10.0.0.5"))];
        assert!(resolve_chit_printer(ITEM, Some(CAT), &no_routes(), &stations).is_till());
        // Unrouted items follow the default station, like a fired round.
        let stations = [st(BAR, "Bar", true, Some("10.0.0.9"))];
        assert_eq!(resolve_chit_printer(ITEM, None, &no_routes(), &stations).host.as_deref(), Some("10.0.0.9"));
    }
}
