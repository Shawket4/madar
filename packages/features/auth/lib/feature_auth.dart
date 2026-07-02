/// Madar POS — device setup, PIN login, station picker.
///
/// Pixel-and-behavior ports of the Kotlin natives' LoginScreen.kt,
/// StationPickerScreen.kt, and BrandPanel.kt. Every screen takes
/// `{required MadarCore core, required void Function() onStateChanged}` and
/// calls `onStateChanged()` after any bridge call that can move
/// `app_route()`/session.
library;

export 'src/brand_panel.dart';
export 'src/device_setup_screen.dart';
export 'src/login_screen.dart';
export 'src/station_picker_screen.dart';
