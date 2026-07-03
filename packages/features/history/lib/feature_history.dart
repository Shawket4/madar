/// Madar POS — order history, cross-shift search, receipt reprint.
///
/// Pixel-and-behavior port of the Kotlin natives' OrderHistoryScreen.kt /
/// OrderSearchScreen.kt (+ the order-details surface of
/// OrderDetailsSheet.kt) over the shared Rust core: `OrderHistoryScreen`
/// is the current shift's order list (sortable table ≥680, expandable
/// cards below) with void + reprint (via feature_checkout's ReceiptSheet),
/// `OrderSearchScreen` looks up orders ACROSS shifts (filters, paging,
/// CSV export), and `OrderDetailsSheet` shows one order's full line
/// breakdown (present via `showMadarSheet(size: SheetSize.hug)`).
///
/// State lives in Riverpod: `historyProvider` (shift list + memoized
/// filtered rows / chip counts) and `searchProvider` (cross-shift query,
/// sequence-guarded pagination). Screens are paramless — they bridge via
/// `ref.watch(bridgeProvider)`.
library;

export 'src/history_provider.dart'
    show
        HistoryNotifier,
        HistorySortCol,
        HistoryState,
        HistorySyncFilter,
        HistoryTypeFilter,
        historyProvider,
        kHistoryPageSize;
export 'src/history_screen.dart' show OrderHistoryScreen;
export 'src/order_details_sheet.dart' show OrderDetailsSheet;
export 'src/search_provider.dart'
    show OrderSearchNotifier, OrderSearchState, searchProvider;
export 'src/search_screen.dart' show OrderSearchScreen;
