import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:madar/app/app_state.dart';
import 'package:madar/app/shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The POS runs in a single landscape orientation, matching the native apps.
  unawaited(
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]),
  );
  final state = MadarAppState();
  unawaited(state.boot());
  runApp(MadarApp(state: state));
}

/// Root widget: themes from the design system, shell driven by the core.
class MadarApp extends StatelessWidget {
  const MadarApp({required this.state, super.key});

  final MadarAppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return MaterialApp(
          title: 'Madar POS',
          debugShowCheckedModeBanner: false,
          theme: MadarTheme.light(),
          darkTheme: MadarTheme.dark(),
          themeMode: state.themeMode,
          home: MadarShell(state: state),
        );
      },
    );
  }
}
