import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// A tap that would not reach the widget it names fails the test instead of
/// printing a warning: a missed tap means the test never did what it says.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  WidgetController.hitTestWarningShouldBeFatal = true;
  await testMain();
}
