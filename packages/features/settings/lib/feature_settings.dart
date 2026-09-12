/// Madar POS — settings, sync, and the waiter's Me tab.
///
/// `SettingsScreen` (language, theme, printer / till / device / diagnostics
/// / legal as rows that open sheets, sign out — with Sync as a section),
/// `SyncScreen` (what the outbox pill opens: the full `SyncSection`),
/// `SyncSection` itself (waiting / stuck / blocked, the server's refusal
/// sentence under each dead row, Retry all / Discard / Recover), and
/// `MeScreen` (the waiter shell's Me tab). Each is backed by an exported
/// Notifier provider over the shared Rust core.
library;

export 'src/me_screen.dart' show MeBillsNotifier, MeScreen, meBillsProvider;
export 'src/settings_provider.dart'
    show SettingsNotifier, SettingsState, settingsProvider;
export 'src/settings_screen.dart'
    show LanguageSegment, SettingsScreen, ThemeSegment;
export 'src/settings_sheets.dart'
    show
        showDeviceSheet,
        showDiagnosticsSheet,
        showLegalSheet,
        showPrinterSheet,
        showStationSheet,
        showTillSheet;
export 'src/sync_provider.dart' show SyncNotifier, SyncState, syncProvider;
export 'src/sync_screen.dart' show SyncScreen;
export 'src/sync_section.dart'
    show SyncFigure, SyncSection, outboxOpLabel, waiterOutboxOps;
