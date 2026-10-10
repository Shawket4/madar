import 'dart:async';

import 'package:rust_bridge_dashboard/testing.dart';

/// The rules run in Rust in tests too (madar-frb-dashboard's rules).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadRulesForTest();
  await testMain();
}
