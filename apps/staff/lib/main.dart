import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_dawam_auth/feature_dawam_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:madar_staff/boot.dart';
import 'package:madar_staff/shell.dart';
import 'package:staff_core/staff_core.dart';

// The Android location service starts `dawamTrackingMain` by name in an
// engine of its own (DawamTrackingService.kt). The library must be part of
// the app's program for that to resolve: nothing else imports it, so without
// this export it is left out of the build and no ping is ever sent (E2E S3).
export 'package:madar_staff/background.dart' show dawamTrackingMain;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The calendar's day and month tables for Arabic and English.
  await initializeDateFormatting();
  try {
    final overrides = await boot();
    runApp(ProviderScope(overrides: overrides, child: const DawamApp()));
  } on Object catch (e) {
    // The core could not start (a stale binding, a store it cannot open).
    // Say so, as the POS does, rather than leave a blank screen.
    runApp(_BootFailure('$e'));
  }
}

class _BootFailure extends StatelessWidget {
  const _BootFailure(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: MadarTheme.light(),
    darkTheme: MadarTheme.dark(),
    home: MadarPageScaffold(
      body: ErrorState(
        message: message,
        retryLabel: 'Retry · أعد المحاولة',
        onRetry: main,
      ),
    ),
  );
}

/// The app: Madar's themes, the chosen language and direction, and either
/// sign-in or the shell. The shared toast rides above every route.
class DawamApp extends ConsumerWidget {
  const DawamApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeProvider);
    final theme = ref.watch(themeChoiceProvider);
    // The tabs open only once this phone accepted the location notice on
    // the server (AT-5); a signed-in person who has not sees the notice.
    final signedIn = ref.watch(
      dawamProvider.select((d) => d.me != null && d.privacyAccepted),
    );
    return MaterialApp(
      title: tr('staff.dawam_by_madar'),
      debugShowCheckedModeBanner: false,
      theme: MadarTheme.light(),
      darkTheme: MadarTheme.dark(),
      themeMode: theme.mode,
      locale: Locale(lang),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        use24h = MediaQuery.alwaysUse24HourFormatOf(context);
        MadarKeyboardDone.label = tr('common.done');
        // Above the Navigator there is no Material: without one, the toast
        // and the keyboard's Done bar took MaterialApp's fallback text style
        // (the yellow double underline) — E2E money CB2.
        return Material(
          type: MaterialType.transparency,
          child: MadarKeyboardDoneBar(
            child: _Failures(child: Stack(children: [child!, const _Toast()])),
          ),
        );
      },
      // Keyed by language: every string re-reads the core on a switch.
      home: KeyedSubtree(
        key: ValueKey('$lang$signedIn'),
        child: signedIn ? const StaffShell() : const SignInScreen(),
      ),
    );
  }
}

class _Toast extends ConsumerWidget {
  const _Toast();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toast = ref.watch(toastProvider);
    if (toast == null) return const SizedBox.shrink();
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 96),
          child: ToastHost(
            toast,
            onAction: ref.read(toastProvider.notifier).act,
            onDismiss: (_) => ref.read(toastProvider.notifier).dismiss(),
          ),
        ),
      ),
    );
  }
}

/// A live write the server refused, after its screen moved on: the toast
/// says why in the server's words.
class _Failures extends ConsumerStatefulWidget {
  const _Failures({required this.child});

  final Widget child;

  @override
  ConsumerState<_Failures> createState() => _FailuresState();
}

class _FailuresState extends ConsumerState<_Failures> {
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref
        .read(dawamProvider)
        .failures
        .stream
        .listen(
          (m) =>
              ref.read(toastProvider.notifier).show(m, tone: ChipTone.danger),
        );
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
