import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:madar/spike_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Madar POS',
      debugShowCheckedModeBanner: false,
      theme: MadarTheme.light(),
      darkTheme: MadarTheme.dark(),
      // M1/M2: the hello-core spike is the home screen (with the design
      // gallery behind its app-bar action); M3 replaces this with the
      // router-driven shell.
      home: const SpikeScreen(),
    );
  }
}
