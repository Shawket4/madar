import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/boot.dart';
import 'app/providers.dart';
import 'app/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Boot the core BEFORE runApp, then install it (+ strings) as ROOT-scope
    // overrides so every provider — including the root-mounted router/session —
    // resolves them. (A nested-scope override would be invisible to those.)
    final boot = await bootStaff();
    runApp(
      ProviderScope(
        overrides: [
          coreProvider.overrideWithValue(boot.core),
          stringsProvider.overrideWithValue(boot.strings),
        ],
        child: const _App(),
      ),
    );
  } on Object catch (e) {
    runApp(_BootErrorApp(message: '$e'));
  }
}

class _App extends ConsumerWidget {
  const _App();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);
    final t = ref.watch(tProvider);
    return MaterialApp.router(
      title: t('app.title'),
      debugShowCheckedModeBanner: false,
      theme: MadarTheme.light(),
      darkTheme: MadarTheme.dark(),
      themeMode: ThemeMode.system,
      locale: Locale(locale),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}

/// Shown only if boot itself fails (store open / FFI load) — rare, and local.
class _BootErrorApp extends StatelessWidget {
  const _BootErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: MadarTheme.light(),
      home: Scaffold(body: Center(child: Text(message))),
    );
  }
}
