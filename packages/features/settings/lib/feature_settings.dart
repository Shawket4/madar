/// Madar POS — settings, sync center, diagnostics.
///
/// Pixel-and-behavior ports of the Kotlin natives' SettingsScreen.kt and
/// SyncScreen.kt over the shared Rust core: `SettingsScreen` (device/till/
/// station binding, printer + test print, LAN relay, locale + theme via the
/// app-core providers, diagnostics, sign-out) and `SyncScreen` (the durable-
/// outbox inspector with retry / sync-now / discard), each backed by an
/// exported Notifier provider.
library;

export 'src/settings_provider.dart'
    show SettingsNotifier, SettingsState, settingsProvider;
export 'src/settings_screen.dart' show SettingsScreen;
export 'src/sync_provider.dart' show SyncNotifier, SyncState, syncProvider;
export 'src/sync_screen.dart' show SyncScreen;
