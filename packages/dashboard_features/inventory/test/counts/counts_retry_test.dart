// A Retry while the read is still out keeps the failure up with its Retry
// spinning: never an empty state or a skeleton in between (INV-CNT-017,
// -033, -053).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Fails [route] until the Retry in [scope] is pressed, holds that Retry's
/// read, and checks [words] stay up (its Retry spinning) until it lands.
Future<void> _retryHeld(
  DashHarness h,
  MockServer server,
  String route,
  Finder scope,
  String words,
) async {
  Finder within(Finder f) => find.descendant(of: scope, matching: f);
  expect(within(find.text(words)), findsOneWidget);
  server.clearFailures();
  final gate = server.hold('GET', route);
  final retry = within(find.text('Retry'));
  await h.tester.ensureVisible(retry);
  await h.tester.pump();
  await h.tester.tap(retry);
  await h.tester.pump();
  expect(within(find.text(words)), findsOneWidget);
  expect(
    h.tester
        .widget<DashErrorState>(within(find.byType(DashErrorState)))
        .retrying,
    isTrue,
  );
  gate.release();
  await h.settle();
  expect(within(find.text(words)), findsNothing);
}

void main() {
  testWidgets('INV-CNT-017 Retry while the list is out: the failure stays '
      'up', (tester) async {
    final s = countsServer();
    s.server.fail('GET', listRoute, MockResponse.error(500, 'Down'));
    final h = await pumpCounts(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    await _retryHeld(h, s.server, listRoute, table, "Couldn't load this");
    expect(inTable(find.text('Karim Adel')), findsWidgets);
  });

  testWidgets('INV-CNT-033 Retry while the open count is out: the failure '
      'stays up, its Retry spinning', (tester) async {
    final s = countsServer();
    s.server.fail('GET', getRoute, MockResponse.error(500, 'Down'));
    final h = await pumpCounts(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.newCairo,
    );
    await _retryHeld(
      h,
      s.server,
      getRoute,
      editor,
      "Couldn't load the open count",
    );
    expect(inEditor(byKey('count-table')), findsOneWidget);
    await waitAutosave(h);
  });

  testWidgets('INV-CNT-053 Retry while the report is out: the failure stays '
      'up, its Retry spinning', (tester) async {
    final s = countsServer();
    // Every try fails (the press's own warm read included) until Retry.
    s.server.fail(
      'GET',
      reportRoute,
      MockResponse.error(500, 'Down'),
      times: null,
    );
    final h = await pumpCounts(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    await h.tap(inTable(byKey('counts-report-$zamalekFull')));
    await _retryHeld(
      h,
      s.server,
      reportRoute,
      report,
      "Couldn't load the variance report",
    );
    expect(inReport(byKey('variance-table')), findsOneWidget);
  });
}
