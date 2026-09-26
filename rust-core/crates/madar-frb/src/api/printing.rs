//! Printing domain: receipt / shift-report rendering to ESC/POS bytes, the
//! cash-drawer kick, and raw byte delivery to network thermal printers. Pure
//! delegation over `MadarCore` — see bridge.rs for the pattern.
use flutter_rust_bridge::frb;

use madar_core::checkout::ReceiptView;
pub use madar_core::kds::ChitPrinterTarget;
pub use madar_core::receipt::{CartKitchenChit, CartLineChit, ChitLineView, KitchenChit, KitchenSlip, KitchenSlipItem};
use madar_core::till::TillReportView;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;
use crate::api::orders::OrderSummaryView;

pub use madar_core::receipt::PrinterBrand;

/// Which thermal-printer command dialect to emit. Epson (ESC/POS) and Star
/// (Star Line Mode) are NOT byte-compatible — different alignment, character
/// size, cut and drawer-kick commands. The host picks this in Settings.
#[frb(mirror(PrinterBrand))]
pub enum _PrinterBrand {
    Epson,
    Star,
}

impl MadarBridge {
    /// The line at the foot of a customer receipt: the org's own footer from
    /// the dashboard, or the localized "Thank you!" when none is set. Local.
    #[frb(sync)]
    pub fn receipt_footer(&self) -> String {
        self.inner.receipt_footer()
    }

    /// Render a placed order's receipt to printer bytes ready to stream to a
    /// thermal printer (rasterized 1-bit bitmap wrapped in the brand's raster
    /// protocol). Pair with `send_to_printer`.
    pub fn render_receipt(
        &self,
        receipt: ReceiptView,
        store_name: String,
        currency: String,
        width: u32,
        brand: PrinterBrand,
    ) -> Vec<u8> {
        self.inner
            .render_receipt(receipt, store_name, currency, width, brand)
    }

    /// Render ONE item as a compact kitchen chit — no money, no logo, no
    /// totals. Pair with `send_to_printer`.
    pub fn render_kitchen_chit(
        &self,
        chit: KitchenChit,
        width: u32,
        brand: PrinterBrand,
    ) -> Vec<u8> {
        self.inner.render_kitchen_chit(chit, width, brand)
    }

    /// A cart line as the round's single-dish chits (the fire print): one
    /// per dish, a combo's items each tagged with it (C12).
    #[frb(sync)]
    pub fn kitchen_chits_for_line(
        &self,
        line: crate::api::cart::CartLineView,
        table_label: Option<String>,
        ticket_ref: Option<String>,
    ) -> Vec<KitchenChit> {
        self.inner.kitchen_chits_for_line(line, table_label, ticket_ref)
    }

    /// ONE cart line as a kitchen chit, sent early from the cart (the per-line
    /// print button). Renders the chit with the kitchen chit renderer and
    /// routes it like a fired round: the item's station printer, else the
    /// till printer (`target.host == null`). Returns the bytes for that
    /// printer, the same document as preview lines for the preview sheet, and
    /// the target. Local only; marks nothing sent.
    pub fn cart_line_chit(
        &self,
        table_id: Option<String>,
        line_key: String,
        table_label: Option<String>,
        ticket_ref: Option<String>,
        width: u32,
        till_brand: PrinterBrand,
    ) -> Result<CartLineChit, MadarError> {
        self.inner
            .cart_line_chit(table_id, line_key, table_label, ticket_ref, width, till_brand)
            .map_err(MadarError::from)
    }

    /// ONE cart line's RECIPE CARD: the line's kitchen chit (same routing and
    /// printer), with each dish's ingredients for one and its steps under
    /// it. Local only; marks nothing sent.
    pub fn cart_line_recipe_chit(
        &self,
        table_id: Option<String>,
        line_key: String,
        table_label: Option<String>,
        ticket_ref: Option<String>,
        width: u32,
        till_brand: PrinterBrand,
    ) -> Result<CartLineChit, MadarError> {
        self.inner
            .cart_line_recipe_chit(table_id, line_key, table_label, ticket_ref, width, till_brand)
            .map_err(MadarError::from)
    }

    /// The WHOLE cart as one kitchen print (the cart-level print button):
    /// every line's chit, one after another, each carrying its own kitchen
    /// note, plus the cart-level kitchen note. Always to the till printer —
    /// a whole-cart copy is a manual/backup pass, not per-station routing.
    /// Local only; marks nothing sent; checkout/fire printing is unchanged.
    pub fn cart_kitchen_chit(
        &self,
        table_id: Option<String>,
        table_label: Option<String>,
        ticket_ref: Option<String>,
        width: u32,
        till_brand: PrinterBrand,
    ) -> Result<CartKitchenChit, MadarError> {
        self.inner
            .cart_kitchen_chit(table_id, table_label, ticket_ref, width, till_brand)
            .map_err(MadarError::from)
    }

    /// Render the shift report (Z-report) to printer bytes — rasterized like
    /// `render_receipt`. Pass the shift's `orders` to append the per-order
    /// breakdown (the expanded print); an empty list prints the summary only.
    /// Pair with `send_to_printer`.
    pub fn render_till_report(
        &self,
        report: TillReportView,
        store_name: String,
        currency: String,
        width: u32,
        brand: PrinterBrand,
        orders: Vec<OrderSummaryView>,
    ) -> Vec<u8> {
        self.inner
            .render_till_report(report, store_name, currency, width, brand, orders)
    }

    /// Cash-drawer kick bytes for the chosen printer dialect — send via
    /// `send_to_printer` right after a CASH sale's receipt so the till pops.
    pub fn cash_drawer_kick(&self, brand: PrinterBrand) -> Vec<u8> {
        self.inner.cash_drawer_kick(brand)
    }

    /// Re-render a synced order as a receipt for reprint — same ESC/POS path as
    /// a fresh receipt. Offline-durable for any order seen online (cached).
    pub async fn render_order_receipt(
        &self,
        order_id: String,
        store_name: String,
        currency: String,
        width: u32,
        brand: PrinterBrand,
    ) -> Result<Vec<u8>, MadarError> {
        self.inner
            .render_order_receipt(order_id, store_name, currency, width, brand)
            .await
            .map_err(MadarError::from)
    }

    /// Print pre-rendered ESC/POS bytes to the DEVICE's configured printer
    /// (from the core device config). Errors if no printer is bound.
    pub async fn print_to_device(&self, bytes: Vec<u8>) -> Result<(), MadarError> {
        self.inner
            .print_to_device(bytes)
            .await
            .map_err(MadarError::from)
    }

    /// Best-effort raw-TCP send of pre-rendered ESC/POS bytes to a network
    /// (JetDirect / port 9100) thermal printer.
    pub async fn send_to_printer(
        &self,
        host: String,
        port: u16,
        bytes: Vec<u8>,
    ) -> Result<(), MadarError> {
        self.inner
            .send_to_printer(host, port, bytes)
            .await
            .map_err(MadarError::from)
    }
}

/// One item, for the people cooking it.
///
/// Mirrors `madar_core::receipt::KitchenChit` so the host can build one. A
/// chit is a DIFFERENT document from a receipt, not a shorter one: no money,
/// no logo, no totals — the item, the count, what was changed about it, and
/// the table it belongs to.
#[frb(mirror(KitchenChit))]
pub struct _KitchenChit {
    pub item: String,
    pub qty: i64,
    pub size_label: Option<String>,
    pub modifiers: Vec<String>,
    pub note: Option<String>,
    pub table_label: Option<String>,
    pub ticket_ref: Option<String>,
    pub at: String,
    pub teller: Option<String>,
    /// The combo this dish belongs to, already worded ("In Lunch deal").
    pub combo: Option<String>,
}

/// Mirrors `madar_core::receipt::ChitLineView` — one printed chit line for the
/// preview sheet.
#[frb(mirror(ChitLineView))]
pub struct _ChitLineView {
    pub text: String,
    pub centered: bool,
    pub bold: bool,
    pub large: bool,
}

/// Mirrors `madar_core::kds::ChitPrinterTarget` — where a chit prints.
/// `host == null` means the device's till printer.
#[frb(mirror(ChitPrinterTarget))]
pub struct _ChitPrinterTarget {
    pub station_id: Option<String>,
    pub station_name: Option<String>,
    pub host: Option<String>,
    pub port: Option<u16>,
    pub brand: Option<String>,
}

/// Mirrors `madar_core::receipt::CartLineChit` — a cart line's chit, ready to
/// print and to preview.
#[frb(mirror(CartLineChit))]
pub struct _CartLineChit {
    pub chit: KitchenSlip,
    pub preview: Vec<ChitLineView>,
    pub bytes: Vec<u8>,
    pub target: ChitPrinterTarget,
}

/// Mirrors `madar_core::receipt::CartKitchenChit` — the whole cart printed as
/// ONE continuous kitchen slip.
#[frb(mirror(CartKitchenChit))]
pub struct _CartKitchenChit {
    pub slip: KitchenSlip,
    pub cart_note: Option<String>,
    pub bytes: Vec<u8>,
    pub preview: Vec<ChitLineView>,
}

/// Mirrors `madar_core::receipt::KitchenSlipItem` — one item's line on a
/// kitchen slip: no header, no top note (those print once for the slip).
#[frb(mirror(KitchenSlipItem))]
pub struct _KitchenSlipItem {
    pub item: String,
    pub qty: i64,
    pub size_label: Option<String>,
    pub modifiers: Vec<String>,
    pub note: Option<String>,
    /// The combo this dish belongs to, already worded ("In Lunch deal").
    pub combo: Option<String>,
    /// A recipe card's ingredients for one, already worded; else empty.
    pub recipe: Vec<String>,
    /// A recipe card's steps in order, already worded; else empty.
    pub steps: Vec<String>,
}

/// Mirrors `madar_core::receipt::KitchenSlip` — a kitchen slip: one header,
/// the notes that apply to the whole slip printed once at the top, then one
/// or more items each with only its own note.
#[frb(mirror(KitchenSlip))]
pub struct _KitchenSlip {
    pub table_label: Option<String>,
    pub ticket_ref: Option<String>,
    pub at: String,
    pub teller: Option<String>,
    pub top_notes: Vec<String>,
    pub items: Vec<KitchenSlipItem>,
}
