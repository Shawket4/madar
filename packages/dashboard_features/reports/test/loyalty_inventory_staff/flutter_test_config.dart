import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge_dashboard/testing.dart';

/// A tap that would not reach the widget it names fails the test instead of
/// printing a warning and passing.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // The rules run in Rust in tests too (madar-frb-dashboard's rules).
  await loadRulesForTest();
  WidgetController.hitTestWarningShouldBeFatal = true;
  await testMain();
}
