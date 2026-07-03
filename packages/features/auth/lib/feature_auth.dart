/// Madar POS — device setup, PIN login, station picker, mid-shift re-auth.
///
/// Pixel-and-behavior ports of the Kotlin natives' LoginScreen.kt,
/// StationPickerScreen.kt, ReauthScreen.kt, and BrandPanel.kt, driven by
/// Riverpod: screens take no constructor params, read the bridge via
/// `bridgeProvider`, render from `authProvider`, and every state-changing
/// bridge call ends with `shellProvider.notifier.refresh()`.
library;

export 'src/brand_panel.dart';
export 'src/device_setup_screen.dart';
export 'src/login_screen.dart';
export 'src/providers.dart';
export 'src/reauth_sheet.dart';
export 'src/station_picker_screen.dart';
