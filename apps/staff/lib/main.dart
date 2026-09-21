import 'package:design_system/design_system.dart';
import 'package:feature_dawam_auth/feature_dawam_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:madar_staff/boot.dart';
import 'package:madar_staff/shell.dart';
import 'package:staff_core/staff_core.dart';

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
    final signedIn = ref.watch(dawamProvider.select((d) => d.me != null));
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
        return MadarKeyboardDoneBar(
          child: Stack(children: [child!, const _Toast()]),
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
            onDismiss: (_) => ref.read(toastProvider.notifier).dismiss(),
          ),
        ),
      ),
    );
  }
}
