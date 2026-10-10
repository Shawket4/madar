import 'dart:async';

import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tap that would not reach the widget it names fails the test instead of
/// printing a warning: a missed tap means the test never did what it says.
/// The mock's refusals read as real mode words them.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  WidgetController.hitTestWarningShouldBeFatal = true;
  DashHarness.wordRefusals = true;
  await testMain();
}
