// The Members tab: who may see it, the two sources, search, filter, columns,
// the window, empty/loading/error, the export, the card a row opens and the
// platform's wallet action (SET-LOY-052 … 063).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/loyalty/google_object_dialog.dart';
import 'package:dashboard_setup/src/loyalty/member_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _loyaltyOnly = ['loyalty.read', 'loyalty.use', 'loyalty.members.list'];

Future<DashHarness> _members(
  WidgetTester tester, {
  String query = '',
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  ({MockServer server, MockDb db})? backend,
}) async {
  final h = await pumpLoyalty(
    tester,
    query: query,
    persona: persona,
    size: size,
    backend: backend ?? loyaltyServer(persona: persona),
  );
  await openTab(h, 'Members');
  return h;
}

Finder _row(String name) => inPage(
  find.byWidgetPredicate((w) => w is DashPressable && w.semanticLabel == name),
);

Future<void> _search(DashHarness h, String q) async {
  await h.enterText(inPage(find.byType(DashSearchInput)), q);
  await h.tester.pump(const Duration(milliseconds: 350));
  await h.settle();
}

int _memberCount(MockDb db) =>
    db['customers'].rows.where((c) => c['is_member'] == true).length;

void main() {
  testWidgets('SET-LOY-052 without loyalty.members.list: "Members are for '
      'managers", nothing read', (tester) async {
    final m = loyaltyServer();
    grantOnly(m.server, const [
      'loyalty.read',
      'loyalty.use',
      'customers.view',
    ]);
    final h = await _members(tester, backend: m);
    expect(pageText('Members are for managers'), findsOneWidget);
    expect(pageText(h.t('loyalty.membersRestrictedHint')), findsOneWidget);
    expect(h.server.callsTo(LoyaltyRoutes.customers), isEmpty);
    expect(h.server.callsTo(LoyaltyRoutes.members), isEmpty);
  });

  testWidgets('SET-LOY-053 SET-LOY-056 with customers.view: the customers '
      'list locked to members, and its columns', (tester) async {
    final h = await _members(tester);
    final call = h.server.callsTo(LoyaltyRoutes.customers).last;
    expect(q1(call), {'member': 'true', 'limit': '50', 'offset': '0'});
    for (final head in [
      'NAME',
      'PHONE',
      'BALANCE',
      'CAME FROM',
      'ORDERS',
      'TOTAL SPENT',
      'LAST VISIT',
    ]) {
      expect(inPage(find.text(head)), findsOneWidget, reason: head);
    }
    await _search(h, 'Nada');
    expect(_row('Nada Kamal'), findsOneWidget);
    final nada = _row('Nada Kamal');
    expect(
      find.descendant(of: nada, matching: find.text('+20 100 123 4567')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: nada, matching: find.textContaining('6 orders')),
      findsOneWidget,
    );
    // Every row is a member here: no "Member" pill.
    expect(inPage(find.text('Member')), findsNothing);
  });

  testWidgets('SET-LOY-053 SET-LOY-057 with only the loyalty side: the '
      'members endpoint and its columns', (tester) async {
    final m = loyaltyServer();
    grantOnly(m.server, _loyaltyOnly);
    final h = await _members(tester, backend: m);
    expect(h.server.callsTo(LoyaltyRoutes.customers), isEmpty);
    expect(q1(h.server.callsTo(LoyaltyRoutes.members).last), {'limit': '50'});
    for (final head in [
      'NAME',
      'PHONE',
      'BALANCE',
      'TO NEXT REWARD',
      'JOINED',
    ]) {
      expect(inPage(find.text(head)), findsOneWidget, reason: head);
    }
    expect(inPage(find.text('CAME FROM')), findsNothing);
    await _search(h, 'Nada');
    // Six stamps against the four-stamp cookie: a reward is earned.
    expect(
      find.descendant(
        of: _row('Nada Kamal'),
        matching: find.text('Reward earned'),
      ),
      findsOneWidget,
    );
    expect(inPage(find.byType(DashFilterSelect<String>)), findsNothing);
  });

  testWidgets('SET-LOY-053 the members endpoint reads under the header '
      'branch', (tester) async {
    final m = loyaltyServer();
    grantOnly(m.server, _loyaltyOnly);
    final h = await _members(
      tester,
      query: atBranch(SeedIds.zamalek),
      backend: m,
    );
    expect(q1(h.server.callsTo(LoyaltyRoutes.members).last), {
      'branch_id': SeedIds.zamalek,
      'limit': '50',
    });
  });

  testWidgets('SET-LOY-054 search: debounced, trimmed, the window starts '
      'over', (tester) async {
    final h = await _members(tester);
    await h.tap(inPage(find.text('Load more')));
    expect(q1(h.server.callsTo(LoyaltyRoutes.customers).last)['limit'], '100');
    final before = h.server.callsTo(LoyaltyRoutes.customers).length;
    await h.enterText(inPage(find.byType(DashSearchInput)), '  Nada ');
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.server.callsTo(LoyaltyRoutes.customers), hasLength(before));
    await tester.pump(const Duration(milliseconds: 300));
    await h.settle();
    final last = q1(h.server.callsTo(LoyaltyRoutes.customers).last);
    expect(last['q'], 'Nada');
    expect(last['limit'], '50');
  });

  testWidgets('SET-LOY-055 "Came from": any source, then one', (tester) async {
    final h = await _members(tester);
    final select = inPage(find.byType(DashFilterSelect<String>));
    await h.tap(select);
    final options = find.byWidgetPredicate((w) => w is DashOptionList);
    for (final s in ['Any source', 'Till', 'Online order', 'Loyalty sign-up']) {
      expect(
        find.descendant(of: options, matching: find.text(s)),
        findsOneWidget,
        reason: s,
      );
    }
    await h.tap(
      find.descendant(of: options, matching: find.text('Loyalty sign-up')),
    );
    final last = q1(h.server.callsTo(LoyaltyRoutes.customers).last);
    expect(last['source'], 'loyalty');
    expect(last['member'], 'true');
  });

  testWidgets('SET-LOY-058 Load more widens the window by 50', (tester) async {
    final h = await _members(tester);
    expect(inPage(find.byType(DashPressable)).evaluate(), isNotEmpty);
    await h.tap(inPage(find.text('Load more')));
    expect(q1(h.server.callsTo(LoyaltyRoutes.customers).last)['limit'], '100');
  });

  testWidgets('SET-LOY-058 the members source: "Showing 50 of N" while more '
      'exist', (tester) async {
    final m = loyaltyServer();
    grantOnly(m.server, _loyaltyOnly);
    final h = await _members(tester, backend: m);
    final total = _memberCount(m.db);
    expect(pageText('Showing 50 of $total'), findsOneWidget);
    await h.tap(inPage(find.text('Load more')));
    expect(q1(h.server.callsTo(LoyaltyRoutes.members).last)['limit'], '100');
    expect(pageText('Showing 100 of $total'), findsOneWidget);
  });

  testWidgets('SET-LOY-059 no members yet; no match for a search', (
    tester,
  ) async {
    final m = loyaltyServer();
    for (final c in m.db['customers'].rows) {
      c['is_member'] = false;
    }
    final h = await _members(tester, backend: m);
    expect(pageText('No members yet'), findsOneWidget);
    expect(pageText(h.t('loyalty.noMembersHint')), findsOneWidget);
    await _search(h, 'zzz');
    expect(pageText('No members match that search'), findsOneWidget);
    expect(pageText(h.t('customers.emptySearchHint')), findsOneWidget);
  });

  testWidgets('SET-LOY-060 loading: skeleton rows', (tester) async {
    final m = loyaltyServer();
    final gate = m.server.hold('GET', LoyaltyRoutes.customers);
    final h = await _members(tester, backend: m);
    expect(pageText('No members yet'), findsNothing);
    expect(inPage(find.byType(DashSkeleton)), findsWidgets);
    gate.release();
    await h.settle();
    expect(inPage(find.byType(DashSkeleton)), findsNothing);
  });

  testWidgets('SET-LOY-060 a failure: the error and Retry, which reads '
      'again', (tester) async {
    final m = loyaltyServer();
    final boom = MockResponse.error(500, 'Database error: timeout');
    m.server.fail('GET', LoyaltyRoutes.customers, boom, times: null);
    final h = await _members(tester, backend: m);
    expect(pageText(h.refusalWords(boom)), findsOneWidget);
    expect(pageText('No members yet'), findsNothing);
    m.server.clearFailures();
    final reads = h.server.callsTo(LoyaltyRoutes.customers).length;
    await h.tap(inPage(find.text('Retry')));
    expect(h.server.callsTo(LoyaltyRoutes.customers), hasLength(reads + 1));
    expect(pageText(h.refusalWords(boom)), findsNothing);
  });

  testWidgets('SET-LOY-061 export (customers source): every member under '
      'the search, as "Members"', (tester) async {
    final m = loyaltyServer();
    final h = await _members(tester, backend: m);
    await h.tap(pageText('Export Excel'));
    await h.flushTimers();
    final walk = [
      for (final c in h.server.callsTo(LoyaltyRoutes.customers))
        if (c.headers['X-Madar-Export'] == '1') c,
    ];
    expect(q1(walk.first), {'member': 'true', 'limit': '500', 'offset': '0'});
    expect(h.files.saved.single.filename, startsWith('Madar-Loyalty-Members-'));
    final sheet = h.exports.built.single.sheets.single;
    expect(sheet.name, 'Members');
    expect(sheet.title, 'Members');
    expect(sheet.rows, hasLength(_memberCount(m.db)));
    expect(
      [for (final c in sheet.columns) c.header],
      [
        'Name',
        'Phone',
        'Balance',
        'Unit',
        'Came from',
        'Orders',
        'Total spent',
        'Last visit',
      ],
    );
  });

  testWidgets('SET-LOY-061 export (members source): the loyalty columns; '
      'the search is the subtitle', (tester) async {
    final m = loyaltyServer();
    grantOnly(m.server, _loyaltyOnly);
    final h = await _members(tester, backend: m);
    await _search(h, 'Nada');
    await h.tap(pageText('Export Excel'));
    await h.flushTimers();
    final sheet = h.exports.built.single.sheets.single;
    expect(sheet.subtitle, startsWith('Nada'));
    expect(
      [for (final c in sheet.columns) c.header],
      ['Name', 'Phone', 'Balance', 'Unit', 'To next reward', 'Joined'],
    );
    expect(
      {
        for (final c in h.server.calls)
          if (c.headers['X-Madar-Export'] == '1') c.template,
      },
      {LoyaltyRoutes.members},
    );
  });

  testWidgets('SET-LOY-061 export is off with no rows; a failed walk toasts', (
    tester,
  ) async {
    final m = loyaltyServer();
    final h = await _members(tester, backend: m);
    final boom = MockResponse.error(500, 'Database error: timeout');
    m.server.fail('GET', LoyaltyRoutes.customers, boom);
    await h.tap(pageText('Export Excel'));
    await h.expectToast(h.refusalWords(boom));
    await _search(h, 'zzz');
    expect(
      tester
          .widget<DashButton>(
            inPage(
              find.byWidgetPredicate(
                (w) => w is DashButton && w.label == 'Export Excel',
              ),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('SET-LOY-062 a row opens that member\'s card under the scope '
      'branch; the row is selected meanwhile', (tester) async {
    final h = await _members(tester, query: atBranch(SeedIds.zamalek));
    await _search(h, 'Nada');
    await h.tap(_row('Nada Kamal'));
    expect(find.byType(MemberSheet), findsOneWidget);
    final read = h.server.callsTo(LoyaltyRoutes.member).last;
    expect(read.path, '/loyalty/members/$nadaId');
    expect(q1(read), {'branch_id': SeedIds.zamalek});
    expect(tester.widget<DashPressable>(_row('Nada Kamal')).selected, isTrue);
  });

  testWidgets('SET-LOY-063 platform: a wallet action per row opens the '
      'Google object; an owner has none', (tester) async {
    final h = await _members(tester, persona: Persona.platform);
    await _search(h, 'Nada Kamal');
    final wallet = inPage(find.bySemanticsLabel('Google Wallet object'));
    expect(wallet, findsOneWidget);
    await h.tap(wallet);
    expect(find.byType(GoogleObjectDialog), findsOneWidget);
    expect(
      h.server.callsTo(LoyaltyRoutes.googleObject).single.path,
      '/loyalty/members/$nadaId/google-object',
    );
  });

  testWidgets('SET-LOY-063 an owner has no wallet action', (tester) async {
    await _members(tester);
    expect(inPage(find.bySemanticsLabel('Google Wallet object')), findsNothing);
  });

  testWidgets('phone: one card per member', (tester) async {
    final h = await _members(tester, size: DashSize.phone);
    await _search(h, 'Nada');
    expect(_row('Nada Kamal'), findsOneWidget);
    expect(inPage(find.text('CAME FROM')), findsNothing);
  });
}
