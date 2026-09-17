/// Madar POS — Orders: this till's sales and every till's, the sale
/// beside the list, reprint, and the one correction the core knows.
///
/// `OrderHistoryScreen` is the one Orders screen: a This till / All
/// segment (the till's own ledger from the local mirror, or the server's
/// cross-till search when online), one search box, one chip row, and the
/// selected sale beside the list on a tablet or pushed over it on a phone
/// (`SaleScreen`, the same `SalePanel`). The old cross-till Search page
/// survives only as a name: `OrderSearchScreen` opens Orders on All.
///
/// A refund is not a void, and the screen says so: Void lives in the sale's
/// ⋯ sheet with what it does and why it may not apply; Refund is not drawn
/// because the core has no refund yet.
///
/// State lives in Riverpod (`historyProvider`). Screens are paramless —
/// they bridge via `ref.bridge`. New words this screen
/// needed are in `historyFallbackStrings`, ready to paste into the core.
library;

export 'src/approval_sheet.dart' show askCashSpotPin, askManager;
export 'src/history_provider.dart'
    show
        HistoryNotifier,
        HistoryState,
        OrdersFilter,
        OrdersScope,
        historyProvider,
        kHistoryPageSize;
export 'src/history_screen.dart' show OrderHistoryScreen, OrderSearchScreen;
export 'src/history_strings.dart' show historyTr;
export 'src/orders_table.dart'
    show OrdersTable, orderColumns, orderRail, orderStatus;
export 'src/sale_panel.dart' show SalePanel, SaleScreen;
