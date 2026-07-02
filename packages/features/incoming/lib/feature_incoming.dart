/// Madar POS — the unified "Orders" surface: the live delivery queue and
/// the open-tickets settle board in one two-tab screen, plus the shared
/// order-details sheets.
///
/// Pixel-and-behavior port of the Kotlin natives' IncomingScreen.kt /
/// DeliveryScreen.kt / WaiterScreen.kt (TicketsSettleBody) over the shared
/// Rust core: `IncomingScreen` is the teller entry (segmented tabs with
/// live count badges, SSE-tick refreshed); `DeliveryBody` works the branch
/// delivery queue (accepting overrides, lifecycle advance, +5 min prep,
/// cancel-with-restock, reject, finalize through the ONE shared
/// CheckoutDrawer); `TicketsSettleBody` settles waiter-fired tickets
/// through the SAME drawer.
library;

export 'src/delivery_body.dart' show DeliveryBody;
export 'src/details_sheets.dart' show DeliveryDetailsSheet, TicketDetailsSheet;
export 'src/incoming_controller.dart' show IncomingController;
export 'src/incoming_screen.dart' show IncomingScreen;
export 'src/tickets_settle_body.dart' show TicketsSettleBody;
