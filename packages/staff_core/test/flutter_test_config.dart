import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';

/// Runs before every test file in this package. A tap that would not reach
/// the widget it names fails the test instead of printing a warning and
/// passing — a missed tap means the test never did what it says.
///
/// The location tracker's own diagnostics ("dawam: ping (…)", "dawam: a …
/// reading … is not sent") are the behaviour these tests drive; they stay off
/// the test output so a clean run prints only results.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  WidgetController.hitTestWarningShouldBeFatal = true;
  dawamLog = (message, {wrapWidth}) {};
  await testMain();
}
