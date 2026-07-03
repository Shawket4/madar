//! Kitchen Display System bindings — station picker, ticket feed, bump/unbump.
//! Pure delegation into `madar-core`; the KDS view mirrors live here.
use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

pub use madar_core::kds::{KdsLineView, KdsStationView, KdsTicketView};

/// A kitchen station (Grill, Bar…) for the KDS station picker + chit printing.
#[frb(mirror(KdsStationView))]
pub struct _KdsStationView {
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
#[frb(mirror(KdsTicketView))]
pub struct _KdsTicketView {
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
#[frb(mirror(KdsLineView))]
pub struct _KdsLineView {
    pub id: String,
    pub name: String,
    pub qty: i32,
    pub size_label: Option<String>,
    pub modifiers: Vec<String>,
    pub notes: Option<String>,
    pub station_id: Option<String>,
    pub station_name: Option<String>,
    pub bumped: bool,
}

impl MadarBridge {
    /// The branch's kitchen stations (the KDS device-setup / chit-routing picker).
    pub async fn kds_list_stations(&self) -> Result<Vec<KdsStationView>, MadarError> {
        self.inner
            .kds_list_stations()
            .await
            .map_err(MadarError::from)
    }

    /// The KDS feed: outstanding kitchen tickets for the branch (optionally
    /// filtered to a `station_id`), oldest-first, ready tickets last.
    pub async fn kds_list(
        &self,
        station_id: Option<String>,
    ) -> Result<Vec<KdsTicketView>, MadarError> {
        self.inner
            .kds_list(station_id)
            .await
            .map_err(MadarError::from)
    }

    /// Bump a kitchen line (mark it done at its station). Outbox-first.
    pub async fn kds_bump(&self, item_id: String) -> Result<(), MadarError> {
        self.inner.kds_bump(item_id).await.map_err(MadarError::from)
    }

    /// Un-bump a kitchen line (undo a mistaken bump). Same outbox-first path.
    pub async fn kds_unbump(&self, item_id: String) -> Result<(), MadarError> {
        self.inner
            .kds_unbump(item_id)
            .await
            .map_err(MadarError::from)
    }
}
