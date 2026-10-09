// `/settings/loyalty`: the header, the scope card and its code, the tabs and
// the scope rules (SET-LOY-001 … 007, 080 … 082; SET-SHL-020).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/loyalty/members_pane.dart';
import 'package:dashboard_setup/src/loyalty/program_pane.dart';
import 'package:dashboard_setup/src/shared/qr_preview_dialog.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder _tabs() => find.byKey(const ValueKey('loyalty-tabs'));
Finder _tab(String label) =>
    find.descendant(of: _tabs(), matching: find.text(label));

void main() {
  testWidgets('SET-LOY-001 the pane header: "Loyalty" and its description',
      (tester) async {
    final h = await pumpLoyalty(tester);
    expect(pageText('Loyalty'), findsWidgets);
    expect(pageText(h.t('loyalty.subtitle')), findsOneWidget);
  });

  testWidgets('SET-LOY-002 SET-LOY-003 org scope: a locked "Whole '
      'organisation" label and the whole-shop tip', (tester) async {
    final h = await pumpLoyalty(tester);
    final scope = find.byKey(const ValueKey('loyalty-scope'));
    expect(
      find.descendant(of: scope, matching: find.text('Whole organisation')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: scope, matching: find.byWidgetPredicate(
        (w) => w is DashIcon && w.name == 'lock',
      )),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: scope, matching: find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == h.t('loyalty.scopeLocked'),
      )),
      findsOneWidget,
    );
    expect(pageText(h.t('loyalty.qrOrgTip')), findsOneWidget);
    expect(pageText(h.t('loyalty.qrPerBranch')), findsNothing);
  });

  testWidgets('SET-LOY-002 SET-LOY-003 a branch in the header: its name and '
      'the counter-code hint', (tester) async {
    final h = await pumpLoyalty(tester, query: atBranch(SeedIds.zamalek));
    final scope = find.byKey(const ValueKey('loyalty-scope'));
    expect(
      find.descendant(of: scope, matching: find.text('Zamalek')),
      findsOneWidget,
    );
    expect(pageText(h.t('loyalty.qrPerBranch')), findsOneWidget);
  });

  testWidgets('SET-LOY-002 phone: the scope card stacks', (tester) async {
    await pumpLoyalty(tester, size: DashSize.phone);
    final label = tester.getRect(find.byKey(const ValueKey('loyalty-scope')));
    final button = tester.getRect(find.byKey(const ValueKey('loyalty-code')));
    expect(button.top, greaterThan(label.bottom));
  });

  testWidgets('SET-LOY-004 org scope: "Sign-up code" asks for the org code '
      'and opens it as "Join code"', (tester) async {
    final h = await pumpLoyalty(tester);
    expect(buttonAt(tester, 'loyalty-code').label, 'Sign-up code');
    await h.tap(find.byKey(const ValueKey('loyalty-code')));
    final calls = h.server.callsTo(LoyaltyRoutes.orgQr);
    expect(calls, hasLength(1));
    expect(calls.single.path, '/orgs/${SeedIds.sabahOrg}/loyalty-qr');
    expect(find.byType(QrPreviewDialog), findsOneWidget);
    expect(inDialog(find.text('Join code')), findsOneWidget);
  });

  testWidgets('SET-LOY-004 a branch: "Counter code" asks for that branch\'s '
      'code; the button spins meanwhile', (tester) async {
    final m = loyaltyServer();
    final gate = m.server.hold('GET', LoyaltyRoutes.branchQr);
    final h = await pumpLoyalty(
      tester,
      query: atBranch(SeedIds.zamalek),
      backend: m,
    );
    expect(buttonAt(tester, 'loyalty-code').label, 'Counter code');
    await h.tap(find.byKey(const ValueKey('loyalty-code')));
    expect(buttonAt(tester, 'loyalty-code').loading, isTrue);
    gate.release();
    await h.settle();
    expect(
      h.server.callsTo(LoyaltyRoutes.branchQr).single.path,
      '/branches/${SeedIds.zamalek}/loyalty-qr',
    );
    expect(find.byType(QrPreviewDialog), findsOneWidget);
  });

  testWidgets('SET-LOY-004 SET-SHL-020 no org in scope: the code button is '
      'disabled', (tester) async {
    final h = await pumpLoyalty(
      tester,
      persona: Persona.platform,
      pickOrg: false,
    );
    h.allowUnmatched = true;
    expect(buttonAt(tester, 'loyalty-code').onPressed, isNull);
  });

  testWidgets('SET-LOY-005 a programme switched off: the refusal is toasted',
      (tester) async {
    final m = loyaltyServer();
    settingsRow(m.db)['enabled'] = false;
    final h = await pumpLoyalty(tester, backend: m);
    await h.tap(find.byKey(const ValueKey('loyalty-code')));
    expect(find.byType(QrPreviewDialog), findsNothing);
    await h.expectToast(
      h.refusalWords(
        MockResponse.conflict(
          'The loyalty program is switched off for this organisation',
        ),
      ),
    );
    // The refusal is not kept: switched back on, the next press asks again.
    settingsRow(m.db)['enabled'] = true;
    final asked = h.server.callsTo(LoyaltyRoutes.orgQr).length;
    await h.tap(find.byKey(const ValueKey('loyalty-code')));
    expect(h.server.callsTo(LoyaltyRoutes.orgQr), hasLength(asked + 1));
    expect(find.byType(QrPreviewDialog), findsOneWidget);
  });

  testWidgets('SET-LOY-006 tabs: Program (default), Rewards, Members, '
      'Overview with the members list', (tester) async {
    final h = await pumpLoyalty(tester);
    for (final l in ['Program', 'Rewards', 'Members', 'Overview']) {
      expect(_tab(l), findsOneWidget, reason: l);
    }
    expect(find.byType(ProgramPane), findsOneWidget);
    await openTab(h, 'Members');
    expect(find.byType(MembersPane), findsOneWidget);
    expect(h.location.queryParameters, isEmpty);
  });

  testWidgets('SET-LOY-006 SET-LOY-080 without loyalty.members.list: no '
      'Overview tab', (tester) async {
    final m = loyaltyServer();
    grantOnly(m.server, const ['loyalty.read', 'loyalty.use']);
    await pumpLoyalty(tester, backend: m);
    expect(_tab('Program'), findsOneWidget);
    expect(_tab('Overview'), findsNothing);
  });

  testWidgets('SET-LOY-007 a header-branch change reloads the Program for '
      'the new scope', (tester) async {
    final h = await pumpLoyalty(tester);
    expect(
      tester
          .widget<EditableText>(inputOf(programField('program_name')))
          .controller
          .text,
      'Sabah Stamps',
    );
    await h.go('$loyaltyPath${atBranch(SeedIds.zamalek)}');
    expect(
      q1(h.server.callsTo(LoyaltyRoutes.settings).last),
      {'branch_id': SeedIds.zamalek},
    );
    expect(
      tester
          .widget<EditableText>(inputOf(programField('program_name')))
          .controller
          .text,
      'Sabah Stamps — Zamalek',
    );
  });

  testWidgets('SET-LOY-080 a persona without the loyalty capabilities, by '
      'URL: the Program read refuses into its error; Members is restricted; '
      'no Overview', (tester) async {
    final h = await pumpLoyalty(tester, persona: Persona.limited);
    expect(pageText("Couldn't load the program"), findsOneWidget);
    expect(
      pageText(h.refusalWords(MockResponse.denied('loyalty.read'))),
      findsOneWidget,
    );
    expect(_tab('Overview'), findsNothing);
    await openTab(h, 'Members');
    expect(pageText('Members are for managers'), findsOneWidget);
    expect(h.server.callsTo(LoyaltyRoutes.customers), isEmpty);
  });

  testWidgets('SET-LOY-081 (divergence) an inactive branch cannot stay in '
      'scope: label, hint and button all follow the organisation',
      (tester) async {
    final m = loyaltyServer();
    m.db['branches'].find(SeedIds.zamalek)!['is_active'] = false;
    final h = await pumpLoyalty(
      tester,
      query: atBranch(SeedIds.zamalek),
      backend: m,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('loyalty-scope')),
        matching: find.text('Whole organisation'),
      ),
      findsOneWidget,
    );
    expect(pageText(h.t('loyalty.qrOrgTip')), findsOneWidget);
    expect(buttonAt(tester, 'loyalty-code').label, 'Sign-up code');
  });

  testWidgets('SET-LOY-082 a header-branch change keeps the tab and the '
      'Members search', (tester) async {
    final h = await pumpLoyalty(tester);
    await openTab(h, 'Members');
    await h.enterText(
      inPage(find.byType(DashSearchInput)),
      'Nada',
    );
    await h.flushTimers();
    await h.go('$loyaltyPath${atBranch(SeedIds.zamalek)}');
    expect(find.byType(MembersPane), findsOneWidget);
    final input = tester.widget<EditableText>(
      inPage(find.descendant(
        of: find.byType(DashSearchInput),
        matching: find.byType(EditableText),
      )),
    );
    expect(input.controller.text, 'Nada');
    // The customers list is org-wide: the branch does not re-read it.
    final last = q1(h.server.callsTo(LoyaltyRoutes.customers).last);
    expect(last['q'], 'Nada');
    expect(last.containsKey('branch_id'), isFalse);
    // Only the balance unit is read under the branch's programme.
    expect(
      q1(h.server.callsTo(LoyaltyRoutes.settings).last),
      {'branch_id': SeedIds.zamalek},
    );
  });
}
