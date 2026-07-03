//! Printing domain: receipt / shift-report rendering to ESC/POS bytes, the
//! cash-drawer kick, and raw byte delivery to network thermal printers. Pure
//! delegation over `MadarCore` — see bridge.rs for the pattern.
use flutter_rust_bridge::frb;

use madar_core::checkout::ReceiptView;
use madar_core::shift::ShiftReportView;

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

    /// Render the shift report (Z-report) to printer bytes — rasterized like
    /// `render_receipt`. Pass the shift's `orders` to append the per-order
    /// breakdown (the expanded print); an empty list prints the summary only.
    /// Pair with `send_to_printer`.
    pub fn render_shift_report(
        &self,
        report: ShiftReportView,
        store_name: String,
        currency: String,
        width: u32,
        brand: PrinterBrand,
        orders: Vec<OrderSummaryView>,
    ) -> Vec<u8> {
        self.inner
            .render_shift_report(report, store_name, currency, width, brand, orders)
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
