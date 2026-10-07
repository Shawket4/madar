import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file in this package. A tap that would not reach
/// the widget it names fails the test instead of printing a warning and
/// passing — a missed tap means the test never did what it says.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  WidgetController.hitTestWarningShouldBeFatal = true;
  await testMain();
}
