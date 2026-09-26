/// Madar POS — Charge, the Done card, and the loyalty moments.
///
/// One drawer for every caller: `showCharge(context, ChargeTarget.cart())`,
/// `.bill(ticket)`, `.online(order)` presents the tender drawer (a centred
/// modal on a tablet, a full-height sheet on a phone), takes the money
/// through the one bridge call that caller has, and slides the `DoneCard`
/// down over the host (in Fast mode's panel, Done is a `DonePage` in place
/// of the menu instead). State lives in `checkoutProvider`; the session
/// starts itself.
///
/// Also exported: `ReceiptSheet` (a receipt preview with Print + Done) and
/// `ReceiptPaper`, for the history and till screens' reprints.
library;

export 'src/charge_sheet.dart'
    show
        ChargeSheet,
        DoneCardCallback,
        discountLabel,
        paymentGlyph,
        showCartDiscountPicker,
        showCharge;
export 'src/charge_strings.dart' show chargeTr;
export 'src/charge_target.dart'
    show
        BillChargeTarget,
        CartChargeTarget,
        ChargeOutcome,
        ChargeTarget,
        OnlineChargeTarget;
export 'src/checkout_provider.dart'
    show
        ChargeBlock,
        CheckoutNotifier,
        CheckoutState,
        CheckoutSummary,
        checkoutProvider;
export 'src/customer_card.dart'
    show CustomerCardSheet, LinkedCustomerRow, showCustomerCard;
export 'src/customer_sheet.dart' show CustomerSheet;
export 'src/discount_sheet.dart' show cartDiscountLabel, showCartDiscountSheet;
export 'src/done_card.dart'
    show DoneCard, DoneCardResult, DonePage, showDoneCard, showDonePage;
export 'src/kitchen_chit_sheet.dart'
    show
        CartChitPreviewNotifier,
        CartChitPreviewState,
        CartKitchenChitSheet,
        ChitPreviewNotifier,
        ChitPreviewState,
        KitchenChitPaper,
        KitchenChitSheet,
        cartChitPreviewProvider,
        chitPreviewProvider,
        sayChitPrint;
export 'src/loyalty_award_sheet.dart' show LoyaltyAwardSheet;
export 'src/loyalty_scan_sheet.dart' show LoyaltyScanSheet;
export 'src/manager_approval_sheet.dart' show askManagerWith;
export 'src/receipt_paper.dart' show ReceiptPaper;
export 'src/receipt_printing.dart'
    show
        PrintState,
        buildCartKitchenChit,
        buildCartLineChit,
        buildCartLineRecipeChit,
        kPrintTimeout,
        kReceiptChars,
        printCartKitchenChit,
        printCartLineChit,
        printReceiptView,
        printerBrandOf;
export 'src/receipt_sheet.dart'
    show
        PrintPreviewFrame,
        ReceiptPreviewNotifier,
        ReceiptPreviewState,
        ReceiptSheet,
        receiptPreviewProvider;
