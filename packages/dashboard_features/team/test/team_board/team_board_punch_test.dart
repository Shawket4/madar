// The punch dialog (TEAM-TEM-029/030, TEAM-ALL-017): a manager punches
// someone whose phone died, always with a reason.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'team_board_support.dart';

Finder _reasonField(DashHarness h) => inSurface(
  find.byWidgetPredicate(
    (w) => w is DashTextField && w.label == h.t('staff.reason'),
  ),
);

Future<void> _type(DashHarness h, String text) => h.enterText(
  find.descendant(of: _reasonField(h), matching: find.byType(EditableText)),
  text,
);

Future<void> _openTarek(DashHarness h) =>
    h.tap(inRow('Tarek Saber', boardButton(h.t('dawam.punchIn'))));

void main() {
  testWidgets('TEAM-TEM-029 the dialog: title, hint, reason with chips; Punch '
      'in waits for a reason', (tester) async {
    final h = await pumpTeam(tester);
    await _openTarek(h);
    expect(
      surfaceText(h.t('dawam.punchInFor', args: {'name': 'Tarek Saber'})),
      findsOneWidget,
    );
    expect(surfaceText(h.t('dawam.punchHint')), findsOneWidget);
    expect(surfaceText(h.t('dawam.punchReasonNeeded')), findsOneWidget);
    final submit = surfaceButton(h.t('dawam.punchIn'));
    expect(enabled(tester, submit), isFalse);
    await h.tap(surfaceButton(h.t('dawam.reasonNoSignal')));
    expect(
      tester.widget<DashTextField>(_reasonField(h)).value,
      h.t('dawam.reasonNoSignal'),
    );
    expect(surfaceText(h.t('dawam.punchReasonNeeded')), findsNothing);
    expect(enabled(tester, submit), isTrue);
    await _type(h, '   ');
    expect(enabled(tester, submit), isFalse);
    expect(h.server.callsTo(punchT), isEmpty);
  });

  testWidgets('TEAM-TEM-029 punching someone out says "out"', (tester) async {
    final h = await pumpTeam(tester);
    await h.tap(inRow('Adham Reda', boardButton(h.t('dawam.punchOut'))));
    expect(
      surfaceText(h.t('dawam.punchOutFor', args: {'name': 'Adham Reda'})),
      findsOneWidget,
    );
    await h.tap(surfaceButton(h.t('dawam.reasonPhoneDied')));
    await h.tap(surfaceButton(h.t('dawam.punchOut')));
    await h.expectToast(h.t('dawam.punchedOut'));
    expect(inRow('Adham Reda', find.text('Done')), findsOneWidget);
  });

  testWidgets('TEAM-TEM-030 Punch in sends the reason, says so, and the board '
      'reads again', (tester) async {
    final h = await pumpTeam(tester);
    await _openTarek(h);
    await _type(h, '  Forgot it at home ');
    await h.tap(surfaceButton(h.t('dawam.punchIn')));
    final call = h.server.callsTo(punchT).single;
    expect(call.body, {
      'employee_id': SeedIds.employee('tarek'),
      'reason': 'Forgot it at home',
    });
    await h.expectToast(h.t('dawam.punchedIn'));
    expect(find.byType(DashSurface), findsNothing);
    expect(h.server.callsTo(presenceT), hasLength(2));
    expect(
      inRow(
        'Tarek Saber',
        find.byWidgetPredicate((w) => w is DashStatusPill && w.label == 'Late'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-TEM-030 Cancel closes and sends nothing', (tester) async {
    final h = await pumpTeam(tester);
    await _openTarek(h);
    await h.tap(surfaceButton('Cancel'));
    expect(find.byType(DashSurface), findsNothing);
    expect(h.server.callsTo(punchT), isEmpty);
  });

  testWidgets(
    'TEAM-TEM-030 / TEAM-ALL-019 a refusal for want of a reason reads in the '
    'punch\'s own words and keeps the dialog',
    (tester) async {
      final s = teamServer();
      s.server.fail(
        'POST',
        punchT,
        MockResponse.error(
          400,
          'A reason is required.',
          code: 'REASON_REQUIRED',
        ),
      );
      final h = await pumpTeam(tester, s: s);
      await _openTarek(h);
      await h.tap(surfaceButton(h.t('dawam.reasonPhoneDied')));
      await h.tap(surfaceButton(h.t('dawam.punchIn')));
      await h.expectToast(h.t('errors.codes.REASON_REQUIRED_punchFor'));
      expect(find.byType(DashSurface), findsOneWidget);
    },
  );

  testWidgets('TEAM-ALL-017 a punch refused for unsaved rules reads in the '
      'person\'s language', (tester) async {
    final h = await pumpTeam(
      tester,
      locale: 'ar',
      edit: (db) {
        for (final r in db['attendance_settings'].rows) {
          r['rules_saved_at'] = null;
        }
      },
    );
    await _openTarek(h);
    await h.tap(surfaceButton(h.t('dawam.reasonPhoneDied')));
    await h.tap(surfaceButton(h.t('dawam.punchIn')));
    await h.expectToast(h.t('errors.codes.RULES_NOT_SET'));
    expect(
      h.db![TeamTables.attendance].where((r) => r['punch_reason'] != null),
      isEmpty,
    );
  });
}
