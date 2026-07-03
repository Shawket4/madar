/// Madar POS — the kitchen display board: outstanding tickets in an adaptive
/// grid, age-escalating header strips, tap-to-bump/recall lines, and the
/// per-line station labels of the expo board, backed by the exported
/// per-station `kdsProvider` family.
///
/// Pixel-and-behavior port of the Kotlin native's KitchenDisplayScreen.kt
/// over the shared Rust core.
library;

export 'src/kds_provider.dart' show KdsNotifier, KdsState, kdsProvider;
export 'src/kitchen_display_screen.dart' show KitchenDisplayScreen;
