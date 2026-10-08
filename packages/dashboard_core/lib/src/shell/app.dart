/// The app widget both modes run (and the test harness pumps): the router,
/// the Madar theme the person chose, the language and its direction, and the
/// i18n and kit scopes every page reads its words from.
library;

import 'package:dashboard_core/src/format/tz.dart';
import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:dashboard_core/src/kit/kit_l10n.dart';
import 'package:dashboard_core/src/session/session.dart';
import 'package:dashboard_core/src/shell/router.dart';
import 'package:dashboard_core/src/shell/shell_prefs.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DashApp extends ConsumerWidget {
  const DashApp({
    this.localizationsDelegates = const [],
    this.reducedMotion,
    super.key,
  });

  /// Material/Cupertino/Widgets localizations (the app passes the global
  /// ones; tests pass the kit's test delegates).
  final List<LocalizationsDelegate<dynamic>> localizationsDelegates;

  /// Forces reduced motion on or off (tests); null follows the platform.
  final bool? reducedMotion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ensureTimeZones();
    final router = ref.watch(dashRouterProvider);
    final lang = ref.watch(localeProvider);
    final pref = ref.watch(themePrefProvider);
    final t = ref.watch(tProvider);
    return MaterialApp.router(
      onGenerateTitle: (_) => t('app.name', defaultValue: 'Madar'),
      debugShowCheckedModeBanner: false,
      theme: MadarTheme.light(),
      darkTheme: MadarTheme.dark(),
      themeMode: pref.mode,
      locale: Locale(lang),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: localizationsDelegates,
      routerConfig: router,
      builder: (context, child) {
        Widget app = Directionality(
          textDirection: t.textDirection,
          child: DashI18nScope(
            child: DashKitScope(
              child: _SessionGate(child: child ?? const SizedBox.shrink()),
            ),
          ),
        );
        final motion = reducedMotion;
        if (motion != null) {
          app = MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: motion),
            child: app,
          );
        }
        return app;
      },
    );
  }
}

/// Paper, and nothing else, while the kept session is being restored (so a
/// signed-in person never sees the sign-in page flash first).
class _SessionGate extends ConsumerWidget {
  const _SessionGate({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    if (s.isLoading && !s.hasValue && !s.hasError) {
      return ColoredBox(color: context.madarColors.bg);
    }
    return child;
  }
}
