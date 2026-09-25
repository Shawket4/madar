/// The app's Riverpod spine: the core handle + the cross-cutting state
/// every feature watches (session/route, realtime ticks, connection,
/// alerts, reauth requests). Features depend on THIS — never on the app
/// package — and the app overrides `coreProvider` once boot completes.
library;

// The theme enum lives with the themes; re-exported so features keep one import.
export 'package:design_system/design_system.dart' show ThemeChoice;

export 'src/app_toast.dart';
export 'src/generated/capabilities.dart';
export 'src/orientation.dart';
export 'src/printing/printer_service.dart';
export 'src/printing/printer_transport.dart';
export 'src/providers.dart';
export 'src/pull.dart';
export 'src/roles.dart';
export 'src/table_changes.dart';
export 'src/table_watcher.dart';
