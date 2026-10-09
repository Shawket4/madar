// `/devices`, the Activation codes section and the New code dialog, driven
// through the real app shell (inventory rows ADM-DEV-014..019).
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final _zamalek = atBranch(SeedIds.zamalek);

/// The codes section (the devices table repeats words like "Name").
Finder inCodes(Finder f) => find.descendant(
  of: find.byKey(const ValueKey('activation-codes')),
  matching: f,
);

/// The name field's placeholder (a code in the table is named the same).
Finder placeholder() => find.descendant(
  of: find.byKey(const ValueKey('code-label')),
  matching: find.text('Front counter'),
);

int _codeReads(DashHarness h) =>
    h.server.callsTo(DevicesRoutes.codes, method: 'GET').length;

void main() {
  group('the section', () {
    testWidgets('ADM-DEV-014 with branches.edit: key icon, title, subtitle, '
        'New code; the branch\'s codes read', (tester) async {
      final h = await pumpDevices(tester, query: _zamalek);
      expect(inCodes(find.text('Activation codes')), findsOneWidget);
      expect(
        inCodes(
          find.text(
            'Enter a code on a new tablet to bind it to this branch. Each '
            'code works once, for 24 hours.',
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('issue-code')), findsOneWidget);
      final calls = h.server.callsTo(DevicesRoutes.codes, method: 'GET');
      expect(calls.single.query['branch_id'], [SeedIds.zamalek]);
    });

    testWidgets('ADM-DEV-015 newest first; grouped LTR codes, free bold, the '
        'rest struck; status pills; Expires / used', (tester) async {
      final h = await pumpDevices(tester, query: _zamalek);
      final shown = [
        for (final e in tester.widgetList<Text>(codeCells())) e.data,
      ];
      expect(shown, ['4072 1958', '7721 9034', '5510 2846', '1836 4052']);
      final cells = tester.widgetList<Text>(codeCells()).toList();
      expect(cells.every((c) => c.textDirection == TextDirection.ltr), isTrue);
      expect(cells.first.style!.decoration, isNot(TextDecoration.lineThrough));
      for (final c in cells.skip(1)) {
        expect(c.style!.decoration, TextDecoration.lineThrough);
      }
      for (final (label, tone) in [
        ('Free', DashTone.success),
        ('Used', DashTone.neutral),
        ('Expired', DashTone.warning),
        ('Withdrawn', DashTone.danger),
      ]) {
        final pill = tester.widget<DashStatusPill>(
          inCodes(
            find.byWidgetPredicate(
              (w) => w is DashStatusPill && w.label == label,
            ),
          ),
        );
        expect(pill.tone, tone, reason: label);
      }
      for (final header in [
        'CODE',
        'NAME',
        'TYPE',
        'STATUS',
        'EXPIRES / USED',
      ]) {
        expect(inCodes(find.text(header)), findsOneWidget, reason: header);
      }
      expect(inCodes(find.text('Terrace tablet 2')), findsOneWidget);
      expect(inCodes(find.text('Kitchen screen')), findsWidgets);
      final fmt = h.container.read(formatProvider);
      // used_at ?? revoked_at ?? expires_at.
      final codes = b(h);
      for (final id in ['18364052', '55102846', '77219034']) {
        final row = codes.find(mockUuid('activation-code:$id'))!;
        final at = row['used_at'] ?? row['revoked_at'] ?? row['expires_at'];
        expect(
          inCodes(stampShown(fmt.fmtStamp(DateTime.parse('$at')))),
          findsOneWidget,
          reason: id,
        );
      }
    });

    testWidgets('ADM-DEV-015 ten codes a page', (tester) async {
      final backend = DevicesBackend();
      final now = backend.db.clock.now;
      for (var i = 0; i < 12; i++) {
        backend.codes.insert({
          'id': mockUuid('activation-code:page:$i'),
          'branch_id': SeedIds.zamalek,
          'code': '${90000000 + i}',
          'label': null,
          'kind': 'pos',
          'created_at': now.subtract(Duration(minutes: i)).toIso8601String(),
          'expires_at': now.add(const Duration(hours: 20)).toIso8601String(),
          'used_at': null,
          'used_by_device': null,
          'revoked_at': null,
        }, timestamps: false);
      }
      await pumpDevices(tester, query: _zamalek, backend: backend);
      expect(codeCells(), findsNWidgets(10));
      expect(inCodes(find.text('Page 1 of 2')), findsOneWidget);
    });
  });

  group('states', () {
    testWidgets('ADM-DEV-016 loading: skeleton, never "No codes yet"', (
      tester,
    ) async {
      final backend = DevicesBackend();
      final gate = backend.server.hold('GET', DevicesRoutes.codes);
      final h = await pumpDevices(tester, query: _zamalek, backend: backend);
      expect(codeCells(), findsNothing);
      expect(find.text('No codes yet'), findsNothing);
      expect(inCodes(find.byType(DashSkeleton)), findsWidgets);
      expect(inCodes(find.byType(DashErrorState)), findsNothing);
      gate.release();
      await h.settle();
      expect(codeCells(), findsNWidgets(4));
    });

    testWidgets('ADM-DEV-016 a failed read: the error and Retry, which asks '
        'only for the codes', (tester) async {
      final backend = DevicesBackend();
      backend.server.fail(
        'GET',
        DevicesRoutes.codes,
        MockResponse.error(500, 'Internal error'),
      );
      final h = await pumpDevices(tester, query: _zamalek, backend: backend);
      expect(inCodes(find.byType(DashErrorState)), findsOneWidget);
      expect(find.text('No codes yet'), findsNothing);
      final devices = h.server.callsTo(DevicesRoutes.devices).length;
      final gate = backend.server.hold('GET', DevicesRoutes.codes);
      await h.tap(inCodes(find.text('Retry')));
      // Retrying: the table's Retry spins.
      expect(
        tester
            .widget<DashErrorState>(inCodes(find.byType(DashErrorState)))
            .retrying,
        isTrue,
      );
      gate.release();
      await h.settle();
      expect(codeCells(), findsNWidgets(4));
      expect(_codeReads(h), 2);
      expect(h.server.callsTo(DevicesRoutes.devices), hasLength(devices));
    });

    testWidgets('ADM-DEV-016 no codes: the empty state', (tester) async {
      final backend = DevicesBackend();
      backend.codes.removeWhere((c) => c['branch_id'] == SeedIds.zamalek);
      await pumpDevices(tester, query: _zamalek, backend: backend);
      expect(inCodes(find.text('No codes yet')), findsOneWidget);
      expect(
        inCodes(
          find.text(
            'Issue a code, then type it on the tablet you are setting up.',
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('withdraw', () {
    testWidgets('ADM-DEV-017 only a free code offers Withdraw; confirmed, '
        'the code is withdrawn and the list refetched, no toast', (
      tester,
    ) async {
      final h = await pumpDevices(tester, query: _zamalek);
      final withdraw = inCodes(find.text('Withdraw'));
      expect(withdraw, findsOneWidget);
      await h.tap(withdraw);
      expect(top('Withdraw this code?'), findsOneWidget);
      expect(
        find.text('A tablet can no longer be activated with it.'),
        findsOneWidget,
      );
      await h.tap(top('Withdraw'));
      final call = h.server.callsTo(DevicesRoutes.revoke).single;
      expect(
        call.path,
        '/devices/activation-codes/${mockUuid('activation-code:40721958')}/revoke',
      );
      expect(_codeReads(h), 2);
      expect(inCodes(find.text('Withdraw')), findsNothing);
      expect(
        inCodes(
          find.byWidgetPredicate(
            (w) => w is DashStatusPill && w.label == 'Withdrawn',
          ),
        ),
        findsNWidgets(2),
      );
      expect(
        find.byWidgetPredicate((w) => '${w.runtimeType}' == '_ToastCard'),
        findsNothing,
      );
    });

    testWidgets('ADM-DEV-017 Cancel asks nothing', (tester) async {
      final h = await pumpDevices(tester, query: _zamalek);
      await h.tap(inCodes(find.text('Withdraw')));
      await h.tap(top('Cancel'));
      expect(h.server.callsTo(DevicesRoutes.revoke), isEmpty);
      expect(inCodes(find.text('Withdraw')), findsOneWidget);
    });

    testWidgets('ADM-DEV-017 a refusal toasts its words', (tester) async {
      final backend = DevicesBackend();
      final refusal = MockResponse.conflict(
        'This code was already used; deactivate the device instead',
        code: 'ACTIVATION_CODE_USED',
      );
      backend.server.fail('POST', DevicesRoutes.revoke, refusal);
      final h = await pumpDevices(tester, query: _zamalek, backend: backend);
      await h.tap(inCodes(find.text('Withdraw')));
      await h.tap(top('Withdraw'));
      await h.expectToast(wordsFor(h, refusal));
      expect(_codeReads(h), 1);
    });
  });

  group('New code', () {
    testWidgets('ADM-DEV-018 the dialog: hint, name (placeholder, max 120), '
        'Type POS / Kitchen screen / Waiter (POS), Cancel / New code', (
      tester,
    ) async {
      final h = await pumpDevices(tester, query: _zamalek);
      await h.tap(find.byKey(const ValueKey('issue-code')));
      expect(top('New activation code'), findsOneWidget);
      expect(find.textContaining('Activate with a code'), findsOneWidget);
      expect(top('Tablet name (optional)'), findsOneWidget);
      expect(placeholder(), findsOneWidget);
      final kind = find.byKey(const ValueKey('code-kind'));
      expect(
        find.descendant(of: kind, matching: find.text('POS')),
        findsOneWidget,
      );
      await h.tap(kind);
      for (final k in ['POS', 'Kitchen screen', 'Waiter']) {
        expect(top(k), findsWidgets, reason: k);
      }
      await h.tap(top('Waiter'));
      expect(
        find.descendant(of: kind, matching: find.text('Waiter')),
        findsOneWidget,
      );
      await h.enterText(find.byKey(const ValueKey('code-label')), 'x' * 130);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('code-label')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        hasLength(120),
      );
      expect(top('Cancel'), findsOneWidget);
      await h.tap(top('Cancel'));
      expect(find.text('New activation code'), findsNothing);
      expect(h.server.callsTo(DevicesRoutes.codes, method: 'POST'), isEmpty);
    });

    testWidgets('ADM-DEV-019 issue sends {branch_id, label, kind}; the '
        'dialog shows the code; the list refetched; Done closes', (
      tester,
    ) async {
      final h = await pumpDevices(tester, query: _zamalek);
      await h.tap(find.byKey(const ValueKey('issue-code')));
      await h.enterText(
        find.byKey(const ValueKey('code-label')),
        '  Bar tablet ',
      );
      await h.tap(find.byKey(const ValueKey('code-kind')));
      await h.tap(top('Kitchen screen'));
      await h.tap(find.byKey(const ValueKey('issue-submit')));
      final call = h.server.callsTo(DevicesRoutes.codes, method: 'POST').single;
      expect(call.body, {
        'branch_id': SeedIds.zamalek,
        'label': 'Bar tablet',
        'kind': 'kds',
      });
      final issued = b(h).rows.firstWhere((r) => r['label'] == 'Bar tablet');
      final code = issued['code']! as String;
      final grouped = '${code.substring(0, 4)} ${code.substring(4)}';
      final big = find.descendant(
        of: find.byKey(const ValueKey('issued-code')),
        matching: find.text(grouped),
      );
      expect(big, findsOneWidget);
      expect(tester.widget<Text>(big).textDirection, TextDirection.ltr);
      expect(_codeReads(h), 2);
      expect(inCodes(find.text(grouped)), findsOneWidget);
      await h.tap(top('Done'));
      expect(find.byKey(const ValueKey('issued-code')), findsNothing);
      // A fresh form on the next open.
      await h.tap(find.byKey(const ValueKey('issue-code')));
      expect(find.byKey(const ValueKey('issued-code')), findsNothing);
      expect(placeholder(), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('code-kind')),
          matching: find.text('POS'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('ADM-DEV-019 a blank name is sent as null, the type POS', (
      tester,
    ) async {
      final h = await pumpDevices(tester, query: _zamalek);
      await h.tap(find.byKey(const ValueKey('issue-code')));
      await h.enterText(find.byKey(const ValueKey('code-label')), '   ');
      await h.tap(find.byKey(const ValueKey('issue-submit')));
      final call = h.server.callsTo(DevicesRoutes.codes, method: 'POST').single;
      expect(call.body, {
        'branch_id': SeedIds.zamalek,
        'label': null,
        'kind': 'pos',
      });
    });

    testWidgets('ADM-DEV-019 the button spins; a refusal toasts and keeps '
        'the form', (tester) async {
      final backend = DevicesBackend();
      final gate = backend.server.hold('POST', DevicesRoutes.codes);
      final h = await pumpDevices(tester, query: _zamalek, backend: backend);
      await h.tap(find.byKey(const ValueKey('issue-code')));
      await h.tap(find.byKey(const ValueKey('issue-submit')));
      final submit = find.byKey(const ValueKey('issue-submit'));
      expect(tester.widget<DashButton>(submit).loading, isTrue);
      gate.release();
      await h.settle();
      expect(find.byKey(const ValueKey('issued-code')), findsOneWidget);
      await h.tap(top('Done'));

      final refusal = MockResponse.denied('branches.edit');
      backend.server.fail('POST', DevicesRoutes.codes, refusal);
      await h.tap(find.byKey(const ValueKey('issue-code')));
      await h.tap(find.byKey(const ValueKey('issue-submit')));
      await h.expectToast(wordsFor(h, refusal));
      expect(top('New activation code'), findsOneWidget);
      expect(find.byKey(const ValueKey('issued-code')), findsNothing);
      expect(tester.widget<DashButton>(submit).loading, isFalse);
    });

    testWidgets('ADM-DEV-019 in Arabic: the dialog and the code read right', (
      tester,
    ) async {
      final h = await pumpDevices(tester, query: _zamalek, locale: 'ar');
      await h.tap(find.byKey(const ValueKey('issue-code')));
      expect(top(h.t('devices.activation.issueTitle')), findsOneWidget);
      await h.tap(find.byKey(const ValueKey('issue-submit')));
      expect(find.byKey(const ValueKey('issued-code')), findsOneWidget);
      expect(top(h.t('common.done')), findsOneWidget);
    });
  });
}

/// The codes table of the harness's database.
MockTable b(DashHarness h) => h.db![AdminTables.activationCodes];
