import 'dart:ui' show PlatformDispatcher;

import 'package:dashboard_core/shell.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'boot/mock.dart';
import 'boot/real.dart';

/// `--dart-define=MADAR_MOCK=1` runs the whole app on the mock backend.
const String _mockFlag = String.fromEnvironment('MADAR_MOCK');
bool get mockMode => _mockFlag == '1' || _mockFlag == 'true';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Boot BEFORE runApp so the container (and the restored session) is in
    // place when the router first decides where to go.
    final container = mockMode ? await bootMock() : await bootReal();
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const DashApp(
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
  } on Object catch (e) {
    runApp(_BootErrorApp(message: '$e'));
  }
}

/// Shown only if boot itself fails (the store, the native library) — rare,
/// and local. The tables may not have loaded, so its one word is bilingual on
/// the device's language.
class _BootErrorApp extends StatelessWidget {
  const _BootErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: MadarTheme.light(),
      darkTheme: MadarTheme.dark(),
      home: MadarPageScaffold(
        body: ErrorState(
          message: message,
          retryLabel: _arabic ? 'إعادة المحاولة' : 'Retry',
          onRetry: main,
        ),
      ),
    );
  }
}

bool get _arabic => PlatformDispatcher.instance.locale.languageCode == 'ar';
