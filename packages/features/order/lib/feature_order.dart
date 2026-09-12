/// Madar POS — Sell, the Floor, and the Bill.
///
/// The three screens the redesign put at the centre of the till, over the
/// shared `orderProvider` (one cart / board truth for every surface):
///
///   * `SellScreen`  — the catalog with quick-add and the cart beside it
///                     (a column on an iPad, a bar on a phone); the counter
///                     screen and, entered from a table or a bill, the round
///                     builder.
///   * `FloorScreen` — the room, plan-first on an iPad and list-first on a
///                     phone; one tap, one sheet, contents by state.
///   * `BillScreen`  — one bill, full screen: rounds, lines, subtotal, add a
///                     round, move, void, and (teller) Charge.
///   * `BillsScreen` — the waiter's tab: every open bill, mine first.
///
/// Which side a feature falls on is the shell's to decide: `canCharge` on
/// the Floor, the Bills tab and the Bill says whether taking money is
/// offered, and the shell that mounts them passes it.
///
/// `DraftsScreen`, `OpenTicketsScreen`, `OrderScreen` and `TablesScreen`
/// are the ones these replace. They stay exported until the shell in
/// `apps/madar` has moved over; nothing new should reach for them.
library;

export 'src/bill_screen.dart' show BillScreen;
export 'src/bills_screen.dart' show BillsScreen;
export 'src/drafts_screen.dart' show DraftsScreen;
export 'src/floor_screen.dart' show FloorScreen, FloorView;
export 'src/open_tickets_screen.dart' show OpenTicketsScreen;
export 'src/order_providers.dart' show OrderNotifier, OrderState, orderProvider;
export 'src/order_screen.dart' show OrderScreen;
export 'src/sell_screen.dart' show SellScreen;
export 'src/table_clear_prompt.dart'
    show listenForTableClear, showTableClearPrompt;
export 'src/table_history_sheet.dart' show showTableHistory;
export 'src/tables_screen.dart'
    show TablePick, TableStatusWords, TablesScreen, showTablePickerSheet;
