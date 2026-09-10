//! Server-backed held orders, the floor-layout mirror, and the transfer
//! waitlist — the POS side of the backend's `held_orders` feature.
//!
//! Three kv mirrors, all refreshed best-effort on catalog sync and after every
//! outbox drain, all readable fully OFFLINE:
//!
//! - `floor:sections` / `floor:tables` — the dashboard-authored branch layout
//!   (geometry only; an EMPTY mirror is the feature gate: no layout → the host
//!   renders no canvas, no table pickers, nothing changes).
//! - `held:mirror` — the branch's held orders (this till's AND every other
//!   till's), merged from `GET /held-orders` pulls. Local mutations update the
//!   mirror OPTIMISTICALLY and enqueue an outbox op; the server arbitrates on
//!   drain and the next pull reconciles (server wins, except entries with a
//!   still-pending local op).
//! - `transfers:mirror` — the "wants to move inside" queue, same model.
//!
//! Offline semantics mirror the backend contract: a PARK never fails on a
//! table race (the table is dropped, flagged), interactive assignment fails
//! loudly against the local mirror, and cross-till conflicts the mirror can't
//! see are surfaced by the drain (dead-letter → sync-center) or silently
//! reconciled by the next pull, depending on the op (see the drain arms in
//! `lib.rs`).

use serde::{Deserialize, Serialize};

use crate::cart;
use crate::error::{CoreError, CoreResult};
use crate::store::Store;

pub(crate) const K_HELD_MIRROR: &str = "held:mirror"; // Vec<HeldWire>
pub(crate) const K_FLOOR_SECTIONS: &str = "floor:sections"; // Vec<SectionWire>
pub(crate) const K_FLOOR_TABLES: &str = "floor:tables"; // Vec<TableWire>
pub(crate) const K_TRANSFERS: &str = "transfers:mirror"; // Vec<TransferWire>
pub(crate) const K_TRANSFERS_CURSOR: &str = "transfers:cursor";

// ── Wire shapes (lenient: unknown fields ignored, absent ones default) ───────

#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct HeldWire {
    pub id: String,
    pub branch_id: String,
    #[serde(default)]
    pub table_id: Option<String>,
    #[serde(default)]
    pub table_label: Option<String>,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub cart: serde_json::Value,
    pub status: String,
    #[serde(default)]
    pub device_id: Option<String>,
    #[serde(default)]
    pub claimed_by_device: Option<String>,
    #[serde(default)]
    pub revision: i64,
    #[serde(default)]
    pub created_at: String,
    #[serde(default)]
    pub updated_at: String,
}

impl HeldWire {
    pub(crate) fn is_live(&self) -> bool {
        self.status == "held" || self.status == "resumed"
    }
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct SectionWire {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub ordering: i32,
    #[serde(default)]
    pub canvas_w: i32,
    #[serde(default)]
    pub canvas_h: i32,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct TableWire {
    pub id: String,
    #[serde(default)]
    pub section_id: Option<String>,
    pub label: String,
    #[serde(default)]
    pub seats: i32,
    #[serde(default)]
    pub shape: String,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub pos_x: f64,
    #[serde(default)]
    pub pos_y: f64,
    #[serde(default)]
    pub width: f64,
    #[serde(default)]
    pub height: f64,
    #[serde(default)]
    pub rotation: f64,
    #[serde(default = "default_true")]
    pub is_active: bool,
    /// The next active booking claiming this table (server-derived; see the
    /// backend's `TableBookingHint`). `None` for a free evening.
    #[serde(default)]
    pub next_booking: Option<BookingHintWire>,
}

fn default_true() -> bool {
    true
}

/// The slice of a booking the floor needs: who, how many, when, and from when
/// the table reads as reserved.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub(crate) struct BookingHintWire {
    pub booking_id: String,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub guest_name: String,
    #[serde(default)]
    pub party_size: i32,
    #[serde(default)]
    pub starts_at: String,
    #[serde(default)]
    pub ends_at: String,
    #[serde(default)]
    pub held_from: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct TransferWire {
    pub id: String,
    pub branch_id: String,
    pub occupant_kind: String,
    pub occupant_id: String,
    #[serde(default)]
    pub occupant_label: Option<String>,
    #[serde(default)]
    pub from_table_id: Option<String>,
    #[serde(default)]
    pub target_section_id: Option<String>,
    #[serde(default)]
    pub target_table_id: Option<String>,
    #[serde(default)]
    pub note: Option<String>,
    pub status: String,
    #[serde(default)]
    pub created_at: String,
    #[serde(default)]
    pub updated_at: String,
}

// ── Outbox command payloads ──────────────────────────────────────────────────
// `request` is stored as the EXACT wire body the backend replay op expects, so
// the drain just wraps it in the `/sync/replay` envelope.

// `ParkCommand` and `HeldOpCommand` lived here. They are gone with the ops they
// carried: a parked draft is device-local and the backend has no held-order
// endpoints, so those five ops could only ever dead-letter.

#[derive(Serialize, Deserialize)]
pub(crate) struct SwapCommand {
    pub request: serde_json::Value,
}

#[derive(Serialize, Deserialize)]
pub(crate) struct CreateTransferCommand {
    pub transfer_id: String,
    pub request: serde_json::Value,
}

#[derive(Serialize, Deserialize)]
pub(crate) struct TransferOpCommand {
    pub transfer_id: String,
    pub request: serde_json::Value,
}

#[derive(Serialize, Deserialize)]
pub(crate) struct TableStateCommand {
    pub table_id: String,
    pub request: serde_json::Value,
}

// ── FFI views ────────────────────────────────────────────────────────────────

/// A floor area (level/zone) for the offline canvas.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FloorSectionInfo {
    pub id: String,
    pub name: String,
    pub ordering: i32,
    pub canvas_w: i32,
    pub canvas_h: i32,
}

/// A table on the offline canvas: geometry + last-known status + the held
/// order sitting on it (if any). Open-ticket occupancy is joined by the host
/// (the waiter screen already holds the ticket list).
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq)]
pub struct FloorTableStateView {
    pub id: String,
    pub section_id: Option<String>,
    pub label: String,
    pub seats: i32,
    /// `rect` | `circle`.
    pub shape: String,
    /// Last-known `free` | `held` | `seated` | `dirty`.
    pub status: String,
    pub pos_x: f64,
    pub pos_y: f64,
    pub width: f64,
    pub height: f64,
    pub rotation: f64,
    /// The live held order on this table, if any (from the mirror).
    pub held_order_id: Option<String>,
    pub held_order_name: Option<String>,
    /// RFC3339 stamp of when that order started — the host renders "how long
    /// this table has been sitting", the number floor staff actually scan for.
    pub held_since: Option<String>,
    /// True when that held order is being edited on ANOTHER till right now.
    pub held_locked_by_other: bool,
    /// The next booking claiming this table (today's service). The host reads
    /// the table as RESERVED once `booking_held_from` has passed and nobody
    /// sits there yet; a `seated` booking with no ticket yet reads as taken.
    pub booking_id: Option<String>,
    pub booking_guest: Option<String>,
    pub booking_party: Option<i32>,
    /// RFC3339 instants — rendered in the branch zone by the host.
    pub booking_starts_at: Option<String>,
    pub booking_held_from: Option<String>,
    /// `confirmed` | `seated`.
    pub booking_status: Option<String>,
}

/// The whole branch layout + occupancy, offline. EMPTY sections+tables ⇒ the
/// branch has no floor configured ⇒ the host hides every table affordance.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq)]
pub struct FloorLayoutView {
    pub sections: Vec<FloorSectionInfo>,
    pub tables: Vec<FloorTableStateView>,
}

/// One entry of the transfer waitlist, display-ready (labels resolved).
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TransferQueueView {
    pub id: String,
    /// `held_order` | `open_ticket`.
    pub occupant_kind: String,
    pub occupant_id: String,
    pub occupant_label: Option<String>,
    pub from_table_id: Option<String>,
    pub from_table_label: Option<String>,
    pub target_section_id: Option<String>,
    pub target_section_name: Option<String>,
    pub target_table_id: Option<String>,
    pub target_table_label: Option<String>,
    pub note: Option<String>,
    /// `waiting` | `fulfilled` | `cancelled`.
    pub status: String,
    pub created_at: String,
}

// ── Mirror load/save ─────────────────────────────────────────────────────────

fn load_vec<T: serde::de::DeserializeOwned>(store: &Store, key: &str) -> CoreResult<Vec<T>> {
    match store.kv_get(key)? {
        Some(json) => Ok(serde_json::from_str(&json).unwrap_or_default()),
        None => Ok(Vec::new()),
    }
}

pub(crate) fn load_held(store: &Store) -> CoreResult<Vec<HeldWire>> {
    load_vec(store, K_HELD_MIRROR)
}
fn save_held(store: &Store, v: &[HeldWire]) -> CoreResult<()> {
    store.kv_put(K_HELD_MIRROR, &serde_json::to_string(v)?)
}
pub(crate) fn load_sections(store: &Store) -> CoreResult<Vec<SectionWire>> {
    load_vec(store, K_FLOOR_SECTIONS)
}
pub(crate) fn load_tables(store: &Store) -> CoreResult<Vec<TableWire>> {
    load_vec(store, K_FLOOR_TABLES)
}
pub(crate) fn load_transfers(store: &Store) -> CoreResult<Vec<TransferWire>> {
    load_vec(store, K_TRANSFERS)
}
fn save_transfers(store: &Store, v: &[TransferWire]) -> CoreResult<()> {
    store.kv_put(K_TRANSFERS, &serde_json::to_string(v)?)
}

fn table_label(store: &Store, table_id: Option<&str>) -> Option<String> {
    let id = table_id?;
    load_tables(store)
        .ok()?
        .into_iter()
        .find(|t| t.id == id)
        .map(|t| t.label)
}

/// The LIVE held order on `table_id`, excluding `exclude` (an order moving to
/// its own table must not see itself as the occupant).
pub(crate) fn held_on_table(
    store: &Store,
    table_id: &str,
    exclude: Option<&str>,
) -> CoreResult<Option<HeldWire>> {
    Ok(load_held(store)?.into_iter().find(|h| {
        h.table_id.as_deref() == Some(table_id) && h.is_live() && Some(h.id.as_str()) != exclude
    }))
}

fn get_mut<'a>(list: &'a mut [HeldWire], id: &str) -> Option<&'a mut HeldWire> {
    list.iter_mut().find(|h| h.id == id)
}

pub(crate) fn get(store: &Store, id: &str) -> CoreResult<Option<HeldWire>> {
    Ok(load_held(store)?.into_iter().find(|h| h.id == id))
}

// ── Local (optimistic) mutations ─────────────────────────────────────────────

/// Park (create or re-park) locally. Mirrors the server contract: a requested
/// table that's occupied per the LOCAL mirror is dropped, never fatal.
/// Returns `(entry, table_conflict)`.
#[allow(clippy::too_many_arguments)]
pub(crate) fn park_local(
    store: &Store,
    id: &str,
    branch_id: &str,
    name: &str,
    payload: serde_json::Value,
    table_id: Option<String>,
    device: &str,
    now: &str,
) -> CoreResult<(HeldWire, bool)> {
    let mut list = load_held(store)?;

    // Resolve the requested table against the local mirror.
    let mut conflict = false;
    let resolved = match table_id {
        Some(t) => {
            let known = load_tables(store)?.iter().any(|x| x.id == t);
            if !known || held_on_table(store, &t, Some(id))?.is_some() {
                conflict = true;
                None
            } else {
                Some(t)
            }
        }
        None => None,
    };
    let label = table_label(store, resolved.as_deref());

    let entry = match get_mut(&mut list, id) {
        Some(e) => {
            if !e.is_live() {
                return Err(CoreError::Validation {
                    field: "draft".into(),
                    detail: format!("held order is already {}", e.status),
                });
            }
            if e.status == "resumed"
                && e.claimed_by_device.is_some()
                && e.claimed_by_device.as_deref() != Some(device)
            {
                return Err(CoreError::Validation {
                    field: "draft".into(),
                    detail: "held order is being edited on another till".into(),
                });
            }
            e.name = name.to_string();
            e.cart = payload;
            e.table_id = resolved;
            e.table_label = label;
            e.status = "held".into();
            e.claimed_by_device = None;
            e.device_id = Some(device.to_string());
            e.revision += 1;
            e.updated_at = now.to_string();
            e.clone()
        }
        None => {
            let e = HeldWire {
                id: id.to_string(),
                branch_id: branch_id.to_string(),
                table_id: resolved,
                table_label: label,
                name: name.to_string(),
                cart: payload,
                status: "held".into(),
                device_id: Some(device.to_string()),
                claimed_by_device: None,
                revision: 1,
                created_at: now.to_string(),
                updated_at: now.to_string(),
            };
            list.push(e.clone());
            e
        }
    };
    // Mirror the server's choreography: the table the order landed on reads
    // as taken right away.
    if let Some(t) = entry.table_id.as_deref() {
        set_table_state_local(store, t, Some("seated"), None, false)?;
    }
    save_held(store, &list)?;
    Ok((entry, conflict))
}

/// Claim + load for resume. Errors when the order is terminal or claimed by
/// another till (per the last-known mirror — the queued claim op is the final
/// arbiter). Returns the cart payload to restore.
pub(crate) fn claim_local(
    store: &Store,
    id: &str,
    device: &str,
    now: &str,
) -> CoreResult<serde_json::Value> {
    let mut list = load_held(store)?;
    let e = get_mut(&mut list, id).ok_or_else(|| CoreError::Validation {
        field: "draft".into(),
        detail: "held order not found".into(),
    })?;
    if !e.is_live() {
        return Err(CoreError::Validation {
            field: "draft".into(),
            detail: format!("held order is already {}", e.status),
        });
    }
    if e.status == "resumed" && e.claimed_by_device.as_deref() != Some(device) {
        return Err(CoreError::Validation {
            field: "draft".into(),
            detail: "held order is being edited on another till".into(),
        });
    }
    e.status = "resumed".into();
    e.claimed_by_device = Some(device.to_string());
    e.revision += 1;
    e.updated_at = now.to_string();
    let payload = e.cart.clone();
    save_held(store, &list)?;
    Ok(payload)
}

/// Give a resume claim back without re-parking (cart unchanged server-side).
pub(crate) fn release_local(store: &Store, id: &str, device: &str, now: &str) -> CoreResult<()> {
    let mut list = load_held(store)?;
    if let Some(e) = get_mut(&mut list, id) {
        if e.status == "resumed" && e.claimed_by_device.as_deref() == Some(device) {
            e.status = "held".into();
            e.claimed_by_device = None;
            e.revision += 1;
            e.updated_at = now.to_string();
            save_held(store, &list)?;
        }
    }
    Ok(())
}

/// Tombstone locally (`discarded` / `completed`), hand the table on, and
/// cancel the party's waiting transfer, mirroring the server walk.
pub(crate) fn terminate_local(
    store: &Store,
    id: &str,
    target: &str,
    device: Option<&str>,
    now: &str,
) -> CoreResult<()> {
    let mut list = load_held(store)?;
    let Some(e) = get_mut(&mut list, id) else {
        return Ok(()); // unknown locally — the queued op still settles it server-side
    };
    if !e.is_live() {
        if e.status == target {
            return Ok(()); // idempotent
        }
        return Err(CoreError::Validation {
            field: "draft".into(),
            detail: format!("held order is already {}", e.status),
        });
    }
    if target == "discarded"
        && e.status == "resumed"
        && e.claimed_by_device.is_some()
        && e.claimed_by_device.as_deref() != device
    {
        return Err(CoreError::Validation {
            field: "draft".into(),
            detail: "held order is being edited on another till".into(),
        });
    }
    let freed = e.table_id.clone();
    e.status = target.to_string();
    e.table_id = None;
    e.table_label = None;
    e.claimed_by_device = None;
    e.revision += 1;
    e.updated_at = now.to_string();
    save_held(store, &list)?;
    // Checked out → the party left their plates behind: the table needs a BUS
    // before anyone else sits, so it lands `dirty` and waits for a human to
    // clear it (the POS prompts right after the sale; the tables screen keeps
    // a one-tap clear). Discarded → nobody ever sat, so it goes straight back
    // to the room. Same walk as the server, so the canvas is right offline too.
    if let Some(t) = freed {
        let next = if target == "completed" {
            "dirty"
        } else {
            "free"
        };
        set_table_state_local(store, &t, Some(next), None, false)?;
    }
    cancel_occupant_transfers_local(store, "held_order", id, now)?;
    Ok(())
}

/// Interactive table assignment (edit sheet / canvas): loud error on a table
/// occupied per the local mirror; `None` releases the table.
pub(crate) fn assign_table_local(
    store: &Store,
    id: &str,
    table_id: Option<String>,
    now: &str,
) -> CoreResult<HeldWire> {
    if let Some(t) = table_id.as_deref() {
        if !load_tables(store)?.iter().any(|x| x.id == t) {
            return Err(CoreError::Validation {
                field: "table_id".into(),
                detail: "table is not in this branch".into(),
            });
        }
        if let Some(occ) = held_on_table(store, t, Some(id))? {
            return Err(CoreError::Validation {
                field: "table_id".into(),
                detail: format!(
                    "table is taken by {}",
                    if occ.name.is_empty() {
                        "another order".into()
                    } else {
                        occ.name
                    }
                ),
            });
        }
        // A SEATED PARTY is an occupant this function could not see.
        //
        // Not every table order is a held one — a party can be seated straight
        // onto a table and rung up from there, which is an open ticket and
        // leaves no held row at all. Checking only held orders therefore missed
        // the commoner case entirely, and would have parked somebody's cart on
        // a table with people already eating at it.
        //
        // The mirrored status is the shared answer: `seated` is written by a
        // ticket landing, by a booking being seated, and by another hold — the
        // three ways a table becomes taken.
        let seated = load_tables(store)?
            .iter()
            .any(|x| x.id == t && x.status == "seated");
        if seated {
            return Err(CoreError::Validation {
                field: "table_id".into(),
                detail: "table is taken".into(),
            });
        }
    }
    let label = table_label(store, table_id.as_deref());
    let mut list = load_held(store)?;
    let e = get_mut(&mut list, id).ok_or_else(|| CoreError::Validation {
        field: "draft".into(),
        detail: "held order not found".into(),
    })?;
    if !e.is_live() {
        return Err(CoreError::Validation {
            field: "draft".into(),
            detail: format!("held order is already {}", e.status),
        });
    }
    let previous = e.table_id.clone();
    e.table_id = table_id;
    e.table_label = label;
    e.revision += 1;
    e.updated_at = now.to_string();
    let out = e.clone();
    save_held(store, &list)?;
    if let Some(old) = previous.filter(|p| Some(p) != out.table_id.as_ref()) {
        set_table_state_local(store, &old, Some("free"), None, false)?;
    }
    if let Some(t) = out.table_id.as_deref() {
        set_table_state_local(store, t, Some("seated"), None, false)?;
        autofulfill_local(store, "held_order", id, t, now)?;
    }
    Ok(out)
}

/// Optimistic local half of a table swap: exchange the HELD occupants of the
/// two tables (open tickets aren't mirrored — the server moves those; the next
/// pull reconciles). Never errors: the queued op is the arbiter.
pub(crate) fn swap_local(store: &Store, table_a: &str, table_b: &str, now: &str) -> CoreResult<()> {
    let mut list = load_held(store)?;
    let label_a = table_label(store, Some(table_a));
    let label_b = table_label(store, Some(table_b));
    for h in list.iter_mut() {
        if !h.is_live() {
            continue;
        }
        if h.table_id.as_deref() == Some(table_a) {
            h.table_id = Some(table_b.to_string());
            h.table_label = label_b.clone();
            h.revision += 1;
            h.updated_at = now.to_string();
        } else if h.table_id.as_deref() == Some(table_b) {
            h.table_id = Some(table_a.to_string());
            h.table_label = label_a.clone();
            h.revision += 1;
            h.updated_at = now.to_string();
        }
    }
    save_held(store, &list)?;
    Ok(())
}

// ── Transfer waitlist (local) ────────────────────────────────────────────────

pub(crate) fn create_transfer_local(store: &Store, wire: TransferWire) -> CoreResult<()> {
    let mut list = load_transfers(store)?;
    if list.iter().any(|t| t.id == wire.id) {
        return Ok(()); // dedup on the client-minted id
    }
    if list.iter().any(|t| {
        t.status == "waiting"
            && t.occupant_kind == wire.occupant_kind
            && t.occupant_id == wire.occupant_id
    }) {
        return Err(CoreError::Validation {
            field: "transfer".into(),
            detail: "this party already has a waiting transfer".into(),
        });
    }
    list.push(wire);
    save_transfers(store, &list)
}

pub(crate) fn cancel_transfer_local(store: &Store, id: &str, now: &str) -> CoreResult<()> {
    let mut list = load_transfers(store)?;
    if let Some(t) = list
        .iter_mut()
        .find(|t| t.id == id && t.status == "waiting")
    {
        t.status = "cancelled".into();
        t.updated_at = now.to_string();
        save_transfers(store, &list)?;
    }
    Ok(())
}

fn cancel_occupant_transfers_local(
    store: &Store,
    kind: &str,
    occupant_id: &str,
    now: &str,
) -> CoreResult<()> {
    let mut list = load_transfers(store)?;
    let mut changed = false;
    for t in list.iter_mut() {
        if t.status == "waiting" && t.occupant_kind == kind && t.occupant_id == occupant_id {
            t.status = "cancelled".into();
            t.updated_at = now.to_string();
            changed = true;
        }
    }
    if changed {
        save_transfers(store, &list)?;
    }
    Ok(())
}

/// Resolve the waiting wish when its party lands on a matching table.
fn autofulfill_local(
    store: &Store,
    kind: &str,
    occupant_id: &str,
    landed_table: &str,
    now: &str,
) -> CoreResult<()> {
    let section_of_table = load_tables(store)?
        .into_iter()
        .find(|t| t.id == landed_table)
        .and_then(|t| t.section_id);
    let mut list = load_transfers(store)?;
    let mut changed = false;
    for t in list.iter_mut() {
        if t.status == "waiting"
            && t.occupant_kind == kind
            && t.occupant_id == occupant_id
            && (t.target_table_id.as_deref() == Some(landed_table)
                || (t.target_table_id.is_none()
                    && t.target_section_id.is_some()
                    && t.target_section_id == section_of_table))
        {
            t.status = "fulfilled".into();
            t.updated_at = now.to_string();
            changed = true;
        }
    }
    if changed {
        save_transfers(store, &list)?;
    }
    Ok(())
}

/// Fulfill locally: move the held occupant (tickets are server-moved) and
/// resolve the wish. Loud error if the chosen table doesn't satisfy the wish
/// or is locally occupied — mirrors the server's interactive semantics.
pub(crate) fn fulfill_transfer_local(
    store: &Store,
    id: &str,
    table_id: &str,
    now: &str,
) -> CoreResult<()> {
    let list = load_transfers(store)?;
    let Some(t) = list.iter().find(|t| t.id == id) else {
        return Err(CoreError::Validation {
            field: "transfer".into(),
            detail: "transfer not found".into(),
        });
    };
    if t.status == "fulfilled" {
        return Ok(()); // idempotent
    }
    if t.status != "waiting" {
        return Err(CoreError::Validation {
            field: "transfer".into(),
            detail: format!("transfer is already {}", t.status),
        });
    }
    if let Some(want) = t.target_table_id.as_deref() {
        if want != table_id {
            return Err(CoreError::Validation {
                field: "table_id".into(),
                detail: "the party asked for a different table".into(),
            });
        }
    }
    if t.target_table_id.is_none() {
        if let Some(section) = t.target_section_id.as_deref() {
            let in_section = load_tables(store)?
                .iter()
                .any(|x| x.id == table_id && x.section_id.as_deref() == Some(section));
            if !in_section {
                return Err(CoreError::Validation {
                    field: "table_id".into(),
                    detail: "table is not in the section the party asked for".into(),
                });
            }
        }
    }
    let (kind, occupant) = (t.occupant_kind.clone(), t.occupant_id.clone());
    if kind == "held_order" {
        // Loud occupancy check + move through the assign path (auto-fulfils).
        assign_table_local(store, &occupant, Some(table_id.to_string()), now)?;
    }
    // Stamp the wish fulfilled regardless of kind (ticket moves are server-side).
    let mut list = load_transfers(store)?;
    if let Some(t) = list
        .iter_mut()
        .find(|t| t.id == id && t.status == "waiting")
    {
        t.status = "fulfilled".into();
        t.updated_at = now.to_string();
        save_transfers(store, &list)?;
    }
    Ok(())
}

/// Operational table-state edit (status walk / zone move) applied to the
/// floor mirror. Unknown table = no-op (the queued op still lands server-side
/// once the layout syncs). LWW by design — matches the backend core.
pub(crate) fn set_table_state_local(
    store: &Store,
    table_id: &str,
    status: Option<&str>,
    section_id: Option<&str>,
    clear_section: bool,
) -> CoreResult<()> {
    let mut tables = load_tables(store)?;
    let Some(t) = tables.iter_mut().find(|t| t.id == table_id) else {
        return Ok(());
    };
    if let Some(s) = status {
        t.status = s.to_string();
    }
    if clear_section {
        t.section_id = None;
    }
    if let Some(sec) = section_id {
        t.section_id = Some(sec.to_string());
    }
    store.kv_put(K_FLOOR_TABLES, &serde_json::to_string(&tables)?)
}

// ── Views ────────────────────────────────────────────────────────────────────

/// The strip/list of parked orders: every live held order in the branch,
/// EXCEPT the one this till itself is editing (that IS the live cart). Orders
/// resumed on other tills render locked. Newest first (legacy order — the
/// host strip re-sorts oldest→newest by `created_at`).
pub(crate) fn drafts(store: &Store, my_device: &str) -> CoreResult<Vec<cart::DraftView>> {
    let mut live: Vec<HeldWire> = load_held(store)?
        .into_iter()
        .filter(|h| h.is_live())
        .filter(|h| !(h.status == "resumed" && h.claimed_by_device.as_deref() == Some(my_device)))
        .collect();
    live.sort_by(|a, b| b.created_at.cmp(&a.created_at));
    Ok(live
        .into_iter()
        .map(|h| {
            let (item_count, total_minor) = cart::payload_counts(&h.cart);
            cart::DraftView {
                id: h.id,
                name: h.name,
                item_count,
                total_minor,
                created_at: h.created_at,
                table_id: h.table_id,
                table_label: h.table_label,
                locked_by_other: h.status == "resumed",
            }
        })
        .collect())
}

/// The offline canvas: sections (by `ordering`) + active tables with held-order
/// occupancy joined from the mirror. Empty when the branch has no layout.
pub(crate) fn layout(store: &Store, my_device: &str) -> CoreResult<FloorLayoutView> {
    let mut sections = load_sections(store)?;
    sections.sort_by_key(|s| (s.ordering, s.name.clone()));
    let held = load_held(store)?;
    let tables = load_tables(store)?
        .into_iter()
        .filter(|t| t.is_active)
        .map(|t| {
            let occ = held
                .iter()
                .find(|h| h.is_live() && h.table_id.as_deref() == Some(t.id.as_str()));
            FloorTableStateView {
                id: t.id,
                section_id: t.section_id,
                label: t.label,
                seats: t.seats,
                shape: t.shape,
                status: t.status,
                pos_x: t.pos_x,
                pos_y: t.pos_y,
                width: t.width,
                height: t.height,
                rotation: t.rotation,
                held_order_id: occ.map(|h| h.id.clone()),
                held_order_name: occ.map(|h| h.name.clone()),
                held_since: occ.map(|h| h.created_at.clone()),
                held_locked_by_other: occ
                    .map(|h| {
                        h.status == "resumed" && h.claimed_by_device.as_deref() != Some(my_device)
                    })
                    .unwrap_or(false),
                booking_id: t.next_booking.as_ref().map(|b| b.booking_id.clone()),
                booking_guest: t.next_booking.as_ref().map(|b| b.guest_name.clone()),
                booking_party: t.next_booking.as_ref().map(|b| b.party_size),
                booking_starts_at: t.next_booking.as_ref().map(|b| b.starts_at.clone()),
                booking_held_from: t.next_booking.as_ref().map(|b| b.held_from.clone()),
                booking_status: t.next_booking.as_ref().map(|b| b.status.clone()),
            }
        })
        .collect();
    Ok(FloorLayoutView {
        sections: sections
            .into_iter()
            .map(|s| FloorSectionInfo {
                id: s.id,
                name: s.name,
                ordering: s.ordering,
                canvas_w: s.canvas_w,
                canvas_h: s.canvas_h,
            })
            .collect(),
        tables,
    })
}

/// The waiting queue, FIFO, labels resolved for display.
pub(crate) fn transfer_queue(store: &Store) -> CoreResult<Vec<TransferQueueView>> {
    let sections = load_sections(store)?;
    let held = load_held(store)?;
    let mut waiting: Vec<TransferWire> = load_transfers(store)?
        .into_iter()
        .filter(|t| t.status == "waiting")
        .collect();
    waiting.sort_by(|a, b| a.created_at.cmp(&b.created_at));
    Ok(waiting
        .into_iter()
        .map(|t| {
            let occupant_label = t.occupant_label.clone().or_else(|| {
                held.iter()
                    .find(|h| h.id == t.occupant_id)
                    .map(|h| h.name.clone())
                    .filter(|n| !n.is_empty())
            });
            TransferQueueView {
                from_table_label: table_label(store, t.from_table_id.as_deref()),
                target_section_name: t
                    .target_section_id
                    .as_deref()
                    .and_then(|sid| sections.iter().find(|s| s.id == sid))
                    .map(|s| s.name.clone()),
                target_table_label: table_label(store, t.target_table_id.as_deref()),
                id: t.id,
                occupant_kind: t.occupant_kind,
                occupant_id: t.occupant_id,
                occupant_label,
                from_table_id: t.from_table_id,
                target_section_id: t.target_section_id,
                target_table_id: t.target_table_id,
                note: t.note,
                status: t.status,
                created_at: t.created_at,
            }
        })
        .collect())
}

// ── Server merge (pull) ──────────────────────────────────────────────────────

/// Commit a `/floor/sections` + `/floor/tables` pull. Raw JSON is validated by
/// parsing; a body that doesn't parse is rejected (keep the old mirror).
pub(crate) fn save_floor(store: &Store, sections_json: &str, tables_json: &str) -> CoreResult<()> {
    let sections: Vec<SectionWire> =
        serde_json::from_str(sections_json).map_err(CoreError::from)?;
    let tables: Vec<TableWire> = serde_json::from_str(tables_json).map_err(CoreError::from)?;
    store.kv_put(K_FLOOR_SECTIONS, &serde_json::to_string(&sections)?)?;
    store.kv_put(K_FLOOR_TABLES, &serde_json::to_string(&tables)?)?;
    Ok(())
}

/// Flip the status of the booking claiming any table in the mirror (seated /
/// no-show / cancelled) so the canvas reacts before the next pull. A terminal
/// status drops the hint — the table is simply free again.
pub(crate) fn set_booking_status_local(
    store: &Store,
    booking_id: &str,
    status: &str,
) -> CoreResult<()> {
    let mut tables = load_tables(store)?;
    for t in tables.iter_mut() {
        if t.next_booking
            .as_ref()
            .is_some_and(|b| b.booking_id == booking_id)
        {
            if matches!(status, "confirmed" | "seated") {
                if let Some(b) = t.next_booking.as_mut() {
                    b.status = status.to_string();
                }
            } else {
                t.next_booking = None;
            }
        }
    }
    store.kv_put(K_FLOOR_TABLES, &serde_json::to_string(&tables)?)?;
    Ok(())
}

/// Merge a `GET /floor/transfers` pull. A `full` pull (no cursor) rebuilds the
/// mirror from the server list; a cursored one upserts by id and drops anything
/// no longer `waiting`. Ids in `protect` — those with a queued-but-unacked local
/// op — keep their local optimistic state either way, so a transfer this device
/// created but has not drained yet survives a full pull the server knows nothing
/// about.
pub(crate) fn merge_transfers(
    store: &Store,
    body: &str,
    full: bool,
    protect: &[String],
) -> CoreResult<()> {
    #[derive(Deserialize)]
    struct Pull {
        server_time: String,
        transfers: Vec<TransferWire>,
    }
    let pull: Pull = serde_json::from_str(body).map_err(CoreError::from)?;
    let local = load_transfers(store)?;
    let mut next: Vec<TransferWire> = if full {
        local
            .iter()
            .filter(|t| protect.contains(&t.id))
            .cloned()
            .collect()
    } else {
        local.clone()
    };
    for server in pull.transfers {
        if protect.contains(&server.id) {
            continue;
        }
        next.retain(|t| t.id != server.id);
        if server.status == "waiting" {
            next.push(server);
        }
    }
    save_transfers(store, &next)?;
    store.kv_put(K_TRANSFERS_CURSOR, &pull.server_time)?;
    Ok(())
}

// ── Legacy migration ─────────────────────────────────────────────────────────

/// Lift pre-existing device-local drafts into the held mirror (once). Returns
/// the lifted entries so the caller enqueues a park op per draft.
pub(crate) fn migrate_legacy(
    store: &Store,
    branch_id: &str,
    device: &str,
) -> CoreResult<Vec<HeldWire>> {
    let legacy = cart::take_legacy_drafts(store)?;
    if legacy.is_empty() {
        return Ok(Vec::new());
    }
    let mut list = load_held(store)?;
    let mut lifted = Vec::new();
    for (id, name, created_at, payload) in legacy {
        if list.iter().any(|h| h.id == id) {
            continue;
        }
        let e = HeldWire {
            id,
            branch_id: branch_id.to_string(),
            table_id: None,
            table_label: None,
            name,
            cart: payload,
            status: "held".into(),
            device_id: Some(device.to_string()),
            claimed_by_device: None,
            revision: 1,
            created_at: created_at.clone(),
            updated_at: created_at,
        };
        list.push(e.clone());
        lifted.push(e);
    }
    save_held(store, &list)?;
    Ok(lifted)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store() -> Store {
        Store::open("").unwrap()
    }

    fn seed_floor(s: &Store) {
        s.kv_put(
            K_FLOOR_SECTIONS,
            r#"[{"id":"sec-in","name":"Inside","ordering":0,"canvas_w":1000,"canvas_h":700},
                {"id":"sec-out","name":"Outside","ordering":1,"canvas_w":800,"canvas_h":600}]"#,
        )
        .unwrap();
        s.kv_put(
            K_FLOOR_TABLES,
            r#"[{"id":"t1","section_id":"sec-in","label":"T1","seats":4,"shape":"rect","status":"free","pos_x":0,"pos_y":0,"width":80,"height":80,"rotation":0,"is_active":true},
                {"id":"t2","section_id":"sec-out","label":"T2","seats":2,"shape":"circle","status":"free","pos_x":10,"pos_y":10,"width":60,"height":60,"rotation":0,"is_active":true}]"#,
        )
        .unwrap();
    }

    fn payload(qty: i64) -> serde_json::Value {
        serde_json::json!({ "lines": [{
            "item_id": "a", "name": "Latte", "unit_price_minor": 5000, "qty": qty
        }], "discount_id": null })
    }

    /// A table order does NOT have to be a held one, and the two must not be
    /// able to sit on the same table.
    ///
    /// A party can be seated straight onto a table and rung up from there —
    /// that is an open ticket and leaves no held row at all, which is the
    /// commoner case. `held_on_table` only ever saw held orders, so it was
    /// blind to exactly that, and would have parked somebody's cart on a table
    /// with people already eating at it.
    #[test]
    fn a_hold_cannot_be_parked_on_a_table_a_party_is_already_seated_at() {
        let s = store();
        seed_floor(&s);

        // A seated party with no held order behind it — a ticket landing, or a
        // booking seated, both write exactly this and nothing else.
        set_table_state_local(&s, "t1", Some("seated"), None, false).unwrap();

        // A hold parked with no table, then offered that one.
        park_local(&s, "h1", "b", "Sara", payload(1), None, "dev-a", "now").unwrap();
        let err = assign_table_local(&s, "h1", Some("t1".into()), "now")
            .expect_err("a seated table is taken, held row or not");
        assert!(
            format!("{err}").contains("taken"),
            "the refusal says the table is taken: {err}"
        );

        // The free one is still fine, so this refuses the right thing only.
        let e = assign_table_local(&s, "h1", Some("t2".into()), "now").unwrap();
        assert_eq!(e.table_id.as_deref(), Some("t2"));
    }

    /// Clearing a hold's table is never refused — it frees, it does not claim.
    #[test]
    fn a_hold_can_always_be_taken_off_its_table() {
        let s = store();
        seed_floor(&s);
        park_local(
            &s,
            "h1",
            "b",
            "Sara",
            payload(1),
            Some("t1".into()),
            "dev-a",
            "now",
        )
        .unwrap();
        // Parking marked t1 seated; unassigning must not trip the new guard.
        let e = assign_table_local(&s, "h1", None, "now").unwrap();
        assert!(e.table_id.is_none());
    }

    #[test]
    fn park_assign_and_conflict_drop() {
        let s = store();
        seed_floor(&s);
        let (e, conflict) = park_local(
            &s,
            "h1",
            "b",
            "Sara",
            payload(2),
            Some("t1".into()),
            "dev-a",
            "now",
        )
        .unwrap();
        assert!(!conflict);
        assert_eq!(e.table_label.as_deref(), Some("T1"));

        // Second order wanting the same table parks WITHOUT it.
        let (e2, conflict) = park_local(
            &s,
            "h2",
            "b",
            "Ali",
            payload(1),
            Some("t1".into()),
            "dev-a",
            "now",
        )
        .unwrap();
        assert!(conflict);
        assert!(e2.table_id.is_none());

        // Unknown table id (stale layout) also drops.
        let (_, conflict) = park_local(
            &s,
            "h3",
            "b",
            "X",
            payload(1),
            Some("zz".into()),
            "dev-a",
            "now",
        )
        .unwrap();
        assert!(conflict);

        // Interactive assign is loud on occupied…
        assert!(assign_table_local(&s, "h2", Some("t1".into()), "now").is_err());
        // …and works on a free table.
        let e2 = assign_table_local(&s, "h2", Some("t2".into()), "now").unwrap();
        assert_eq!(e2.table_label.as_deref(), Some("T2"));
    }

    #[test]
    fn claim_release_and_lock_semantics() {
        let s = store();
        seed_floor(&s);
        park_local(&s, "h1", "b", "Sara", payload(2), None, "dev-a", "t0").unwrap();

        let p = claim_local(&s, "h1", "dev-b", "t1").unwrap();
        assert_eq!(p, payload(2));
        // Another device may not claim or discard while locked.
        assert!(claim_local(&s, "h1", "dev-a", "t2").is_err());
        assert!(terminate_local(&s, "h1", "discarded", Some("dev-a"), "t2").is_err());
        // The strip on dev-a shows it locked; on dev-b it's hidden (live cart).
        let a = drafts(&s, "dev-a").unwrap();
        assert_eq!(a.len(), 1);
        assert!(a[0].locked_by_other);
        assert!(drafts(&s, "dev-b").unwrap().is_empty());

        release_local(&s, "h1", "dev-b", "t3").unwrap();
        assert_eq!(drafts(&s, "dev-a").unwrap().len(), 1);
        assert!(!drafts(&s, "dev-a").unwrap()[0].locked_by_other);
    }

    #[test]
    fn terminate_buses_table_and_cancels_wish() {
        let s = store();
        seed_floor(&s);
        park_local(
            &s,
            "h1",
            "b",
            "Sara",
            payload(2),
            Some("t2".into()),
            "dev-a",
            "t0",
        )
        .unwrap();
        create_transfer_local(
            &s,
            TransferWire {
                id: "w1".into(),
                branch_id: "b".into(),
                occupant_kind: "held_order".into(),
                occupant_id: "h1".into(),
                occupant_label: None,
                from_table_id: Some("t2".into()),
                target_section_id: Some("sec-in".into()),
                target_table_id: None,
                note: None,
                status: "waiting".into(),
                created_at: "t0".into(),
                updated_at: "t0".into(),
            },
        )
        .unwrap();
        terminate_local(&s, "h1", "completed", None, "t1").unwrap();
        assert!(drafts(&s, "dev-a").unwrap().is_empty());
        assert!(held_on_table(&s, "t2", None).unwrap().is_none());
        // Checkout leaves the table needing a bus — NOT available. A human
        // clears it (POS prompt or the tables screen).
        let status_of = |id: &str| {
            load_tables(&s)
                .unwrap()
                .into_iter()
                .find(|t| t.id == id)
                .unwrap()
                .status
        };
        assert_eq!(status_of("t2"), "dirty");
        assert!(
            transfer_queue(&s).unwrap().is_empty(),
            "wish auto-cancelled"
        );
        // Clearing it by hand is what hands it back to the room.
        set_table_state_local(&s, "t2", Some("free"), None, false).unwrap();
        assert_eq!(status_of("t2"), "free");
        // Idempotent; the opposite terminal is an error.
        terminate_local(&s, "h1", "completed", None, "t2").unwrap();
        assert!(terminate_local(&s, "h1", "discarded", None, "t2").is_err());
    }

    #[test]
    fn discard_hands_table_straight_back() {
        let s = store();
        seed_floor(&s);
        park_local(
            &s,
            "h1",
            "b",
            "Sara",
            payload(2),
            Some("t2".into()),
            "dev-a",
            "t0",
        )
        .unwrap();
        // Nobody ever sat: a discarded cart owes the room nothing to bus.
        terminate_local(&s, "h1", "discarded", None, "t1").unwrap();
        let t2 = load_tables(&s)
            .unwrap()
            .into_iter()
            .find(|t| t.id == "t2")
            .unwrap();
        assert_eq!(t2.status, "free");
    }

    #[test]
    fn assign_into_wished_section_autofulfills() {
        let s = store();
        seed_floor(&s);
        park_local(
            &s,
            "h1",
            "b",
            "Sara",
            payload(1),
            Some("t2".into()),
            "dev-a",
            "t0",
        )
        .unwrap();
        create_transfer_local(
            &s,
            TransferWire {
                id: "w1".into(),
                branch_id: "b".into(),
                occupant_kind: "held_order".into(),
                occupant_id: "h1".into(),
                occupant_label: Some("Sara".into()),
                from_table_id: Some("t2".into()),
                target_section_id: Some("sec-in".into()),
                target_table_id: None,
                note: None,
                status: "waiting".into(),
                created_at: "t0".into(),
                updated_at: "t0".into(),
            },
        )
        .unwrap();
        // A second waiting wish for the same party is rejected.
        assert!(create_transfer_local(
            &s,
            TransferWire {
                id: "w2".into(),
                branch_id: "b".into(),
                occupant_kind: "held_order".into(),
                occupant_id: "h1".into(),
                occupant_label: None,
                from_table_id: None,
                target_section_id: Some("sec-in".into()),
                target_table_id: None,
                note: None,
                status: "waiting".into(),
                created_at: "t1".into(),
                updated_at: "t1".into(),
            },
        )
        .is_err());
        // Fulfil validates the section…
        assert!(fulfill_transfer_local(&s, "w1", "t2", "t2").is_err());
        // …and moves + resolves on a matching table.
        fulfill_transfer_local(&s, "w1", "t1", "t2").unwrap();
        assert!(transfer_queue(&s).unwrap().is_empty());
        assert_eq!(
            get(&s, "h1").unwrap().unwrap().table_label.as_deref(),
            Some("T1")
        );
        // Replay is idempotent.
        fulfill_transfer_local(&s, "w1", "t1", "t3").unwrap();
    }

    #[test]
    fn swap_exchanges_local_held_occupants() {
        let s = store();
        seed_floor(&s);
        park_local(&s, "h1", "b", "A", payload(1), Some("t1".into()), "d", "t0").unwrap();
        park_local(&s, "h2", "b", "B", payload(1), Some("t2".into()), "d", "t0").unwrap();
        swap_local(&s, "t1", "t2", "t1").unwrap();
        assert_eq!(
            get(&s, "h1").unwrap().unwrap().table_id.as_deref(),
            Some("t2")
        );
        assert_eq!(
            get(&s, "h2").unwrap().unwrap().table_id.as_deref(),
            Some("t1")
        );
        // One-sided swap = move.
        terminate_local(&s, "h2", "discarded", None, "t2").unwrap();
        swap_local(&s, "t2", "t1", "t3").unwrap();
        assert_eq!(
            get(&s, "h1").unwrap().unwrap().table_id.as_deref(),
            Some("t1")
        );
    }

    #[test]
    fn layout_joins_occupancy_and_gates_on_empty() {
        let s = store();
        // No layout → empty view (the host hides the whole feature).
        let v = layout(&s, "dev-a").unwrap();
        assert!(v.sections.is_empty() && v.tables.is_empty());

        seed_floor(&s);
        park_local(
            &s,
            "h1",
            "b",
            "Sara",
            payload(1),
            Some("t1".into()),
            "dev-b",
            "t0",
        )
        .unwrap();
        claim_local(&s, "h1", "dev-b", "t1").unwrap();
        let v = layout(&s, "dev-a").unwrap();
        assert_eq!(v.sections.len(), 2);
        assert_eq!(v.sections[0].name, "Inside", "sorted by ordering");
        let t1 = v.tables.iter().find(|t| t.id == "t1").unwrap();
        assert_eq!(t1.held_order_name.as_deref(), Some("Sara"));
        assert!(t1.held_locked_by_other, "resumed on another till");
    }

    #[test]
    fn migrate_legacy_lifts_once() {
        let s = store();
        // Seed a legacy draft through the old path.
        crate::cart::add(&s, "a", "Latte", 5000).unwrap();
        crate::cart::hold(&s, "old-1".into(), "Legacy".into(), "t0".into()).unwrap();

        let lifted = migrate_legacy(&s, "b", "dev-a").unwrap();
        assert_eq!(lifted.len(), 1);
        assert_eq!(lifted[0].name, "Legacy");
        let (count, total) = cart::payload_counts(&lifted[0].cart);
        assert_eq!((count, total), (1, 5000));
        // Second run is a no-op.
        assert!(migrate_legacy(&s, "b", "dev-a").unwrap().is_empty());
        assert_eq!(drafts(&s, "dev-a").unwrap().len(), 1);
    }
}
