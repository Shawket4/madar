/// The dashboard's app frame: the router ([buildDashRouter]) with sign-in,
/// the legacy redirects and the page gates; the frame ([DashShell]: the ink
/// sidebar and header, the scope bar, the user menu, the phone's app bar,
/// bottom bar and drawer); the command palette; the ask-a-manager service;
/// the theme and sidebar preferences; and [DashApp], which both the app and
/// the test harness run.
library;

export 'src/shell/app.dart';
export 'src/shell/ask_manager.dart';
export 'src/shell/brand_mark.dart';
export 'src/shell/command_palette.dart';
export 'src/shell/footer.dart';
export 'src/shell/frame.dart';
export 'src/shell/header.dart';
export 'src/shell/pages.dart';
export 'src/shell/router.dart';
export 'src/shell/session_guard.dart';
export 'src/shell/shell_nav.dart';
export 'src/shell/shell_prefs.dart';
export 'src/shell/shell_strings.dart';
export 'src/shell/sidebar.dart';
export 'src/shell/sign_in.dart';
