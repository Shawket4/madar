/// Madar POS — the shared checkout drawer, receipt confirmation and preview.
///
/// Pixel-and-behavior port of the Kotlin natives' TenderScreen.kt /
/// ReceiptPaper.kt over the shared Rust core: `TenderSheet` is THE checkout
/// drawer (present via `showMadarSheet(size: SheetSize.large)`, resolves
/// with the placed `ReceiptView`), `CheckoutDrawer` is the shared tender
/// collector the future settle/finalize flows reuse, `ReceiptPaper` renders
/// a receipt as white thermal paper, and `ReceiptSheet` wraps it with
/// Print + Done actions.
library;

export 'src/checkout_controller.dart'
    show CheckoutController, PrintState, kReceiptChars;
export 'src/checkout_drawer.dart'
    show CheckoutDrawer, CheckoutResult, CheckoutSummary;
export 'src/receipt_paper.dart' show ReceiptPaper;
export 'src/receipt_sheet.dart' show ReceiptSheet;
export 'src/tender_sheet.dart' show TenderSheet;
