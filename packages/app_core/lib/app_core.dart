/// The app's Riverpod spine: the core handle + the cross-cutting state
/// every feature watches (session/route, realtime ticks, connection,
/// alerts, reauth requests). Features depend on THIS — never on the app
/// package — and the app overrides `coreProvider` once boot completes.
library;

export 'src/orientation.dart';
export 'src/providers.dart';
export 'src/realtime_poll.dart';
