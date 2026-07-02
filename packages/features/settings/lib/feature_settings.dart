/// Madar POS — settings, sync center, diagnostics.
///
/// Pixel-and-behavior ports of the Kotlin natives' SettingsScreen.kt and
/// SyncScreen.kt over the shared Rust core: `SettingsScreen` (device/till/
/// station binding, printer + test print, LAN relay, locale + theme via
/// host callbacks, diagnostics, sign-out) and `SyncScreen` (the durable-
/// outbox inspector with retry / sync-now / discard).
library;

export 'src/settings_screen.dart' show SettingsScreen;
export 'src/sync_screen.dart' show SyncScreen;
