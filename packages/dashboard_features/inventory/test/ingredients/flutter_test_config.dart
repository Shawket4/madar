import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// A tap that would not reach the widget it names fails the test instead of
/// printing a warning and passing.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  WidgetController.hitTestWarningShouldBeFatal = true;
  await testMain();
}
