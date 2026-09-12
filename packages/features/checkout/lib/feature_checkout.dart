/// Madar POS — Charge, the Done card, and the loyalty moments.
///
/// One drawer for every caller: `showCharge(context, ChargeTarget.cart())`,
/// `.bill(ticket)`, `.online(order)` presents the tender drawer (a centred
/// modal on a tablet, a full-height sheet on a phone), takes the money
/// through the one bridge call that caller has, and slides the `DoneCard`
/// down over the host. State lives in `checkoutProvider`; the session
/// starts itself.
///
/// Still exported for the screens that have not migrated: `TenderSheet` and
/// `CheckoutDrawer` (the previous checkout / settle / finalize drawer),
/// `ReceiptSheet` (a receipt preview with Print + Done), `ReceiptPaper`.
library;

export 'src/charge_sheet.dart'
    show ChargeSheet, DoneCardCallback, discountLabel, paymentGlyph, showCharge;
export 'src/charge_strings.dart' show chargeTr;
export 'src/charge_target.dart'
    show
        BillChargeTarget,
        CartChargeTarget,
        ChargeOutcome,
        ChargeTarget,
        OnlineChargeTarget;
export 'src/checkout_drawer.dart' show CheckoutDrawer;
export 'src/checkout_provider.dart'
    show
        ChargeBlock,
        CheckoutNotifier,
        CheckoutResult,
        CheckoutState,
        CheckoutSummary,
        RedeemableLine,
        checkoutProvider;
export 'src/done_card.dart' show DoneCard, DoneCardResult, showDoneCard;
export 'src/loyalty_award_sheet.dart' show LoyaltyAwardSheet;
export 'src/loyalty_scan_sheet.dart' show LoyaltyScanSheet;
export 'src/receipt_paper.dart' show ReceiptPaper;
export 'src/receipt_printing.dart'
    show PrintState, kReceiptChars, printReceiptView, printerBrandOf;
export 'src/receipt_sheet.dart'
    show
        ReceiptPreviewNotifier,
        ReceiptPreviewState,
        ReceiptSheet,
        receiptPreviewProvider;
export 'src/tender_sheet.dart' show TenderSheet;
