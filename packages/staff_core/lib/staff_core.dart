/// Dawam's spine — the staff app's `app_core`: the core handle
/// (`dawamProvider`), the language, theme and toast state every feature
/// watches, the core's words (`tr`), and the Dawam pieces two features
/// share. Features depend on THIS, never on the app.
library;

export 'src/data.dart';
export 'src/format.dart';
export 'src/providers.dart';
export 'src/push.dart';
export 'src/widgets.dart';
