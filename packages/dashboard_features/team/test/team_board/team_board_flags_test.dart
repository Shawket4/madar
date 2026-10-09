// The flag dialog (TEAM-TEM-012…022): what a manager may do with each kind of
// flag, each act on its own right, and what the server answers.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show formatProvider;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'team_board_support.dart';

const List<String> _handler = ['hr.attendance.read', 'hr.attendance.edit'];

String _leftTitle(DashHarness h) =>
    'Karim Adel · ${h.t('dawam.flag_left_mid_shift')}';

Future<void> _openLeft(DashHarness h) => h.tap(rowOf(_leftTitle(h)));

/// The deduct form's amount field.
Finder _amount(DashHarness h) => inSurface(
  find.byWidgetPredicate(
    (w) => w is DashTextField && w.label == h.t('dawam.deductAmount'),
  ),
);

Finder _reason(DashHarness h) => inSurface(
  find.byWidgetPredicate(
    (w) => w is DashTextField && w.label == h.t('dawam.deductReason'),
  ),
);

Future<void> _type(DashHarness h, Finder field, String text) => h.enterText(
  find.descendant(of: field, matching: find.byType(EditableText)),
  text,
);

Map<String, Object?> _lastBody(DashHarness h) =>
    h.server.callsTo(resolveT).last.body! as Map<String, Object?>;

void _coverFlag(MockDb db) =>
    addFlag(db, 'cover', kind: 'cover', employeeKey: 'ziad');

/// An older server: the flag comes back without `deduction_status`; the
/// caller may deduct up to 10 EGP.
Srv _older() {
  final s = teamServer();
  answerAuthz(s.server, [
    ..._handler,
    'hr.deductions.create',
  ], deductLimit: 1000);
  s.server.on('PATCH', resolveT, (req) {
    final f = s.db[TeamTables.flags].update(req.param('id'), {
      'resolution': 'deducted',
    });
    return MockResponse.ok({...f}..remove('deduction_status'));
  });
  return s;
}

void main() {
  testWidgets('TEAM-TEM-012 the dialog names the person and kind and says '
      'what the kind means', (tester) async {
    final h = await pumpTeam(
      tester,
      edit: (db) =>
          addFlag(db, 'off', kind: 'tracking_off', employeeKey: 'ziad'),
    );
    await _openLeft(h);
    expect(surfaceText(_leftTitle(h)), findsOneWidget);
    expect(
      surfaceText(h.t('dawam.flagHint_left_mid_shift', args: {'m': 25})),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    await h.tap(rowOf('Ziad Amr · ${h.t('dawam.flag_tracking_off')}'));
    expect(surfaceText(h.t('dawam.flagHint_tracking_off')), findsOneWidget);
  });

  testWidgets('TEAM-TEM-013 the manager\'s own flag offers nothing: someone '
      'else decides it', (tester) async {
    final h = await pumpTeam(tester, persona: Persona.manager);
    await _openLeft(h);
    expect(surfaceText(h.t('dawam.ownFlag')), findsOneWidget);
    expect(inSurface(find.byType(DashButton)), findsNothing);
    expect(h.server.callsTo(employeesT), isNotEmpty);
  });

  testWidgets('TEAM-TEM-013 the own-flag words in Arabic', (tester) async {
    final h = await pumpTeam(tester, persona: Persona.manager, locale: 'ar');
    await h.tap(rowOf('Karim Adel · ${h.t('dawam.flag_left_mid_shift')}'));
    expect(surfaceText(h.t('dawam.ownFlag')), findsOneWidget);
    expect(h.t('dawam.ownFlag'), isNot(contains('Someone')));
  });

  testWidgets('TEAM-TEM-014 / TEAM-TEM-022 "Excuse, paid" resolves the flag, '
      'says so and the board reads again', (tester) async {
    final h = await pumpTeam(tester);
    await _openLeft(h);
    await h.tap(surfaceButton(h.t('dawam.excusePaid')));
    expect(_lastBody(h), {
      'action': 'excuse_paid',
      'amount_piastres': null,
      'reason': null,
    });
    expect(
      h.server.callsTo(resolveT).single.path,
      '/staff/flags/${flagId('left-mid-shift')}',
    );
    await h.expectToast(h.t('dawam.flagHandled'));
    expect(find.byType(DashSurface), findsNothing);
    expect(boardHas('Karim Adel · '), findsNothing);
    expect(h.server.callsTo(flagsT), hasLength(2));
    expect(h.server.callsTo(presenceT), hasLength(2));
  });

  testWidgets('TEAM-TEM-015 "Excuse, unpaid" deducts the time away at the '
      'minute rate', (tester) async {
    final h = await pumpTeam(tester);
    await _openLeft(h);
    await h.tap(surfaceButton(h.t('dawam.excuseUnpaid')));
    expect(_lastBody(h)['action'], 'excuse_unpaid');
    await h.flushTimers();
    final line = h.db![TeamTables.adjustments].firstWhere(
      (a) => a['source'] == 'excused_unpaid',
    );
    expect(line?['value_piastres'], 3606);
  });

  testWidgets('TEAM-TEM-015 without the deduction right there is no unpaid '
      'excuse', (tester) async {
    final s = teamServer();
    answerAuthz(s.server, _handler);
    final h = await pumpTeam(tester, s: s);
    await _openLeft(h);
    expect(surfaceButton(h.t('dawam.excuseUnpaid')), findsNothing);
    expect(surfaceButton(h.t('dawam.excusePaid')), findsOneWidget);
  });

  testWidgets('TEAM-TEM-015 someone who may ask for a deduction is offered '
      'it', (tester) async {
    final s = teamServer();
    answerAuthz(s.server, _handler, ask: ['hr.deductions.create']);
    final h = await pumpTeam(tester, s: s);
    await _openLeft(h);
    expect(surfaceButton(h.t('dawam.excuseUnpaid')), findsOneWidget);
    expect(_amount(h), findsOneWidget);
  });

  testWidgets('TEAM-TEM-016 the deduction is the typed amount, prefilled with '
      'the suggestion, with the reason the employee sees', (tester) async {
    final h = await pumpTeam(tester);
    await _openLeft(h);
    expect(tester.widget<DashTextField>(_amount(h)).value, '36.06');
    expect(
      surfaceText(
        h.t(
          'dawam.suggested',
          args: {'amount': h.container.read(formatProvider).fmtMoney(3606)},
        ),
      ),
      findsOneWidget,
    );
    await _type(h, _amount(h), '50');
    await _type(h, _reason(h), ' Long phone call ');
    await h.tap(surfaceButton(h.t('dawam.deduct')));
    expect(_lastBody(h), {
      'action': 'deduct',
      'amount_piastres': 5000,
      'reason': 'Long phone call',
    });
    await h.expectToast(h.t('dawam.flagHandled'));
  });

  testWidgets('TEAM-TEM-016 a deduction of nothing is refused and sends '
      'nothing', (tester) async {
    final h = await pumpTeam(tester);
    await _openLeft(h);
    await _type(h, _amount(h), '0');
    await h.tap(surfaceButton(h.t('dawam.deduct')));
    expect(surfaceText(h.t('dawam.badAmount')), findsOneWidget);
    expect(h.server.callsTo(resolveT), isEmpty);
    await _type(h, _amount(h), '');
    await h.tap(surfaceButton(h.t('dawam.deduct')));
    expect(h.server.callsTo(resolveT), isEmpty);
  });

  testWidgets('TEAM-TEM-017 without the deduction right the dialog says why '
      'there is no money act', (tester) async {
    final s = teamServer();
    answerAuthz(s.server, _handler);
    final h = await pumpTeam(tester, s: s);
    await _openLeft(h);
    expect(surfaceText(h.t('dawam.deductNeedsRight')), findsOneWidget);
    expect(_amount(h), findsNothing);
    expect(surfaceButton(h.t('dawam.deduct')), findsNothing);
  });

  testWidgets('TEAM-TEM-018 the server\'s pending deduction waits for the '
      'owner', (tester) async {
    // Karim (manager) deducts 1,500 EGP from Adham: above his limit.
    final h = await pumpTeam(
      tester,
      persona: Persona.manager,
      edit: (db) => addFlag(
        db,
        'adham',
        kind: 'left_mid_shift',
        employeeKey: 'adham',
        minutesAway: 30,
        suggested: 4000,
      ),
    );
    await h.tap(rowOf('Adham Reda · ${h.t('dawam.flag_left_mid_shift')}'));
    await _type(h, _amount(h), '1500');
    await h.tap(surfaceButton(h.t('dawam.deduct')));
    expect(_lastBody(h)['amount_piastres'], 150000);
    await h.expectToast(h.t('dawam.payLinePending'));
    expect(
      h.db![TeamTables.flags].find(flagId('adham'))!['deduction_status'],
      'pending',
    );
  });

  testWidgets('TEAM-TEM-018 with no status from the server, over the limit '
      'waits', (tester) async {
    final h = await pumpTeam(tester, s: _older());
    await _openLeft(h);
    await _type(h, _amount(h), '50');
    await h.tap(surfaceButton(h.t('dawam.deduct')));
    await h.expectToast(h.t('dawam.payLinePending'));
  });

  testWidgets('TEAM-TEM-018 with no status from the server, within the limit '
      'is handled', (tester) async {
    final h = await pumpTeam(tester, s: _older());
    await _openLeft(h);
    await _type(h, _amount(h), '5');
    await h.tap(surfaceButton(h.t('dawam.deduct')));
    await h.expectToast(h.t('dawam.flagHandled'));
  });

  testWidgets('TEAM-TEM-019 a new phone is revoked with the staff-edit right', (
    tester,
  ) async {
    final h = await pumpTeam(tester);
    await h.tap(rowOf('Dina Fouad · ${h.t('dawam.flag_new_phone')}'));
    await h.tap(surfaceButton(h.t('dawam.revokePhone')));
    expect(_lastBody(h)['action'], 'revoke');
    await h.expectToast(h.t('dawam.flagHandled'));
  });

  testWidgets('TEAM-TEM-019 without the staff-edit right only Ignore', (
    tester,
  ) async {
    final s = teamServer();
    answerAuthz(s.server, _handler);
    final h = await pumpTeam(tester, s: s);
    await h.tap(rowOf('Dina Fouad · ${h.t('dawam.flag_new_phone')}'));
    expect(surfaceButton(h.t('dawam.revokePhone')), findsNothing);
    expect(surfaceButton(h.t('dawam.ignore')), findsOneWidget);
  });

  testWidgets('TEAM-TEM-020 a cover is confirmed or rejected, never ignored', (
    tester,
  ) async {
    final h = await pumpTeam(tester, edit: _coverFlag);
    await h.tap(rowOf('Ziad Amr · ${h.t('dawam.flag_cover')}'));
    expect(surfaceText(h.t('dawam.flagHint_cover')), findsOneWidget);
    expect(surfaceButton(h.t('dawam.ignore')), findsNothing);
    expect(surfaceButton(h.t('dawam.rejectCover')), findsOneWidget);
    await h.tap(surfaceButton(h.t('dawam.confirmCover')));
    expect(_lastBody(h)['action'], 'confirm');
    await h.expectToast(h.t('dawam.flagHandled'));
  });

  testWidgets('TEAM-TEM-020 without the cover right the dialog says why', (
    tester,
  ) async {
    final s = teamServer(edit: _coverFlag);
    answerAuthz(s.server, _handler);
    final h = await pumpTeam(tester, s: s);
    await h.tap(rowOf('Ziad Amr · ${h.t('dawam.flag_cover')}'));
    expect(surfaceText(h.t('dawam.coverNeedsRight')), findsOneWidget);
    expect(inSurface(find.byType(DashButton)), findsNothing);
  });

  testWidgets('TEAM-TEM-021 every other kind can be ignored', (tester) async {
    final h = await pumpTeam(
      tester,
      edit: (db) =>
          addFlag(db, 'spoof', kind: 'suspicious', employeeKey: 'ziad'),
    );
    await h.tap(rowOf('Ziad Amr · ${h.t('dawam.flag_suspicious')}'));
    await h.tap(surfaceButton(h.t('dawam.ignore')));
    expect(_lastBody(h), {
      'action': 'ignore',
      'amount_piastres': null,
      'reason': null,
    });
    await h.expectToast(h.t('dawam.flagHandled'));
    expect(
      h.db![TeamTables.flags].find(flagId('spoof'))!['resolution'],
      'ignored',
    );
  });

  testWidgets('TEAM-TEM-022 every act waits while one runs', (tester) async {
    final s = teamServer();
    final gate = s.server.hold('PATCH', resolveT);
    final h = await pumpTeam(tester, s: s);
    await _openLeft(h);
    await h.tap(surfaceButton(h.t('dawam.excusePaid')));
    for (final b in tester.widgetList<DashButton>(
      inSurface(find.byType(DashButton)),
    )) {
      expect(b.onPressed, isNull, reason: b.label);
    }
    gate.release();
    await h.settle();
    await h.flushTimers();
  });

  testWidgets('TEAM-TEM-022 handled by someone else first: the words, the '
      'board reads again and the dialog closes', (tester) async {
    final s = teamServer();
    s.server.fail(
      'PATCH',
      resolveT,
      MockResponse.error(
        404,
        'That flag is already handled.',
        code: 'FLAG_HANDLED',
      ),
    );
    final h = await pumpTeam(tester, s: s);
    await _openLeft(h);
    await h.tap(surfaceButton(h.t('dawam.ignore')));
    await h.expectToast(h.t('errors.codes.FLAG_HANDLED'));
    expect(find.byType(DashSurface), findsNothing);
    expect(h.server.callsTo(flagsT), hasLength(2));
  });

  testWidgets('TEAM-TEM-022 any other refusal keeps the dialog open with the '
      'server\'s words (OWN_DECISION)', (tester) async {
    final s = teamServer();
    s.server.fail(
      'PATCH',
      resolveT,
      MockResponse.error(
        403,
        'Someone else has to decide this one.',
        code: 'OWN_DECISION',
      ),
    );
    final h = await pumpTeam(tester, s: s);
    await _openLeft(h);
    await h.tap(surfaceButton(h.t('dawam.ignore')));
    await h.expectToast(h.t('errors.codes.OWN_DECISION'));
    expect(find.byType(DashSurface), findsOneWidget);
    expect(h.server.callsTo(flagsT), hasLength(1));
  });

  testWidgets('TEAM-TEM-022 a capability refusal reads the person\'s words', (
    tester,
  ) async {
    final s = teamServer();
    final denied = MockResponse.denied('hr.attendance.edit');
    s.server.fail('PATCH', resolveT, denied);
    final h = await pumpTeam(tester, s: s);
    await _openLeft(h);
    await h.tap(surfaceButton(h.t('dawam.ignore')));
    // An uncoded 403 reads the area's words, never the server's English.
    await h.expectToast(h.t('errors.unauthorized'));
  });
}
