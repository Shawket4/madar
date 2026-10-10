/// Loads the host build of the bridge for `flutter test`, so the rules run in
/// Rust there too, never in a Dart stand-in.
library;

import 'dart:io';

import 'src/core.dart';

/// Call once per test file (from `flutter_test_config.dart`). Fails loudly when
/// the library isn't built, so no test passes without the rules it checks.
Future<void> loadRulesForTest() async {
  final library = _hostLibrary();
  if (library == null) {
    throw StateError(
      'libmadar_frb_dashboard is not built. Build it with\n'
      '  cargo build -p madar_frb_dashboard --release --manifest-path rust-core/Cargo.toml\n'
      'or point MADAR_DASHBOARD_DYLIB at a build.',
    );
  }
  await MadarCore.initForTest(dylibPath: library.path);
}

File? _hostLibrary() {
  final explicit = Platform.environment['MADAR_DASHBOARD_DYLIB'];
  if (explicit != null && explicit.isNotEmpty) return File(explicit);
  final name = Platform.isWindows
      ? 'madar_frb_dashboard.dll'
      : Platform.isMacOS
      ? 'libmadar_frb_dashboard.dylib'
      : 'libmadar_frb_dashboard.so';
  // The workspace root is the first directory up with `rust-core/`.
  for (var dir = Directory.current.absolute; ; dir = dir.parent) {
    final candidate = File('${dir.path}/rust-core/target/release/$name');
    if (candidate.existsSync()) return candidate;
    if (dir.parent.path == dir.path) return null;
  }
}
