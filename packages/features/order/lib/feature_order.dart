/// Madar POS — the flagship Order screen: branch catalog (categories, search,
/// adaptive item grid, combos), the live cart with held-orders strip and
/// waiter round-targets, item customization + bundle configuration sheets;
/// plus the cashier "Open tickets" settle surface and the held-orders
/// (drafts) manager.
///
/// Pixel-and-behavior port of the Kotlin natives' OrderScreen.kt /
/// ItemDetailSheet.kt / BundleDetailSheet.kt / WaiterScreen.kt /
/// DraftsScreen.kt over the shared Rust core, driven by the shared
/// `orderProvider` (one cart/board truth across all three surfaces).
library;

export 'src/drafts_screen.dart' show DraftsScreen;
export 'src/open_tickets_screen.dart' show OpenTicketsScreen;
export 'src/order_providers.dart' show OrderNotifier, OrderState, orderProvider;
export 'src/order_screen.dart' show OrderScreen;
