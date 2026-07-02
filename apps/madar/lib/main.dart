import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The POS runs in a single landscape orientation, matching the native apps.
  unawaited(
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]),
  );
  runApp(const MadarApp());
}

/// Placeholder shell proving the scaffold builds and brands correctly.
/// Replaced by the real app shell (routing, core wiring) in M3.
class MadarApp extends StatelessWidget {
  const MadarApp({super.key});

  // Ink/teal brand roles — the full token set lands in design_system (M2).
  static const _paper = Color(0xFFEFF3F4);
  static const _ink = Color(0xFF14181E);
  static const _tealDeep = Color(0xFF0D6273);
  static const _tealLight = Color(0xFF2E94A6);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Madar POS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _tealDeep),
        scaffoldBackgroundColor: _paper,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _tealLight,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: _ink,
      ),
      home: Builder(
        builder: (context) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return Scaffold(
            body: Center(
              child: Image.asset(
                dark
                    ? 'assets/brand/lockup_latin_reversed.png'
                    : 'assets/brand/lockup_latin.png',
                width: 220,
              ),
            ),
          );
        },
      ),
    );
  }
}
