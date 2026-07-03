/// Madar POS — the shared checkout drawer, receipt confirmation and preview.
///
/// Pixel-and-behavior port of the Kotlin natives' TenderScreen.kt /
/// ReceiptPaper.kt over the shared Rust core: `TenderSheet` is THE checkout
/// drawer (present via `showMadarSheet(size: SheetSize.large)`, resolves
/// with the placed `ReceiptView`), `CheckoutDrawer` is the shared tender
/// collector the settle/finalize flows reuse (state in `checkoutProvider` —
/// the presenting sheet calls `startCart()` / `startSettle(summary)` in its
/// `initState`), `ReceiptPaper` renders a receipt as white thermal paper,
/// and `ReceiptSheet` wraps it with Print + Done actions.
library;

export 'src/checkout_drawer.dart' show CheckoutDrawer;
export 'src/checkout_provider.dart'
    show
        CheckoutNotifier,
        CheckoutResult,
        CheckoutState,
        CheckoutSummary,
        PrintState,
        checkoutProvider,
        kReceiptChars,
        printerBrandOf;
export 'src/receipt_paper.dart' show ReceiptPaper;
export 'src/receipt_sheet.dart'
    show
        ReceiptPreviewNotifier,
        ReceiptPreviewState,
        ReceiptSheet,
        receiptPreviewProvider;
export 'src/tender_sheet.dart' show TenderSheet;
