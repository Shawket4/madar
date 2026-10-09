// `/reports/staff-pool` Staff drinks, driven through the real app shell
// (inventory rows REP-SPL-001 to -021): the gate, the branch rule, the three
// reads, the day's pool, the period's totals, the drink-by-drink table and
// the sale behind a drink.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/mock/staff_pool_bundles_mock.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/staff_drink_order_sheet.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/staff_drinks_summary.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/staff_drinks_table.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/staff_pool_report_page.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The page at [branch] (Heliopolis by default; none with [allBranches])
/// and [preset].
String at({String? branch, bool allBranches = false, String? preset}) {
  final q = [
    if (!allBranches) 'branchId=${branch ?? SeedIds.heliopolis}',
    if (preset != null) 'preset=$preset',
  ];
  return q.isEmpty ? staffPoolPath : '$staffPoolPath?${q.join('&')}';
}

/// Inside the page (the sidebar repeats "Staff drinks").
Finder inPage(Finder f) =>
    find.descendant(of: find.byType(StaffPoolReportPage), matching: f);

Finder inTable(Finder f) =>
    find.descendant(of: find.byType(StaffDrinksTable), matching: f);

Finder inStrip(Finder f) =>
    find.descendant(of: find.byKey(const Key('staff-summary')), matching: f);

int calls(DashHarness h, String tpl) => h.server.callsTo(tpl).length;

/// A drink as the wire carries it (the web test's `drink()`).
MockRow drink({
  String id = 'd-1',
  String? orderId,
  String itemName = 'Latte',
  String? sizeLabel,
  int quantity = 1,
  String note = 'Mostafa, closing shift',
  String businessDate = '2026-10-08',
  bool overspent = false,
  bool onReplay = false,
  int? cost = 1250,
  int? comp,
  int? extras,
  int? reported,
  String recordedAt = '2026-10-08T06:00:00.000Z',
}) => {
  'id': id,
  'branch_id': SeedIds.heliopolis,
  'order_id': orderId,
  'menu_item_id': 'item-a',
  'item_name': itemName,
  'size_label': sizeLabel,
  'quantity': quantity,
  'note': note,
  'business_date': businessDate,
  'allowance_at_record': 3,
  'used_before': 0,
  'overspent': overspent,
  'overspent_on_replay': onReplay,
  'cost_minor': cost,
  'recorded_by': 'u-1',
  'recorded_at': recordedAt,
  'comp_minor': comp,
  'extras_minor': extras,
  'comp_minor_reported': reported,
};

/// The web test's totals.
MockRow totals({
  int drinks = 4,
  int quantity = 5,
  int overspent = 2,
  int comp = 28000,
  int extras = 3500,
  int cost = 6100,
  int mismatches = 0,
  int unpriced = 0,
}) => {
  'drinks': drinks,
  'quantity': quantity,
  'overspent': overspent,
  'comp_minor': comp,
  'extras_minor': extras,
  'cost_minor': cost,
  'comp_mismatches': mismatches,
  'unpriced': unpriced,
};

/// A server answering [rows] for the drinks (and [summary], if given).
({MockServer server, MockDb db}) withDrinks(
  List<MockRow> rows, {
  MockRow? summary,
  Persona persona = Persona.owner,
}) {
  final s = reportsServer(persona: persona);
  s.server.on('GET', drinksTpl, (req) => MockResponse.ok(rows));
  if (summary != null) {
    s.server.on('GET', summaryTpl, (req) => MockResponse.ok(summary));
  }
  return s;
}

Future<DashHarness> pumpPool(
  WidgetTester tester, {
  String? path,
  ({MockServer server, MockDb db})? s,
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
}) => pumpReports(
  tester,
  path: path ?? at(),
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: s?.server,
  db: s?.db,
);

void main() {
  group('the gate', () {
    testWidgets(
      'REP-SPL-001 / REP-ALL-005 without the capability: the page\'s own '
      'Restricted says who it is for, nothing asked',
      (tester) async {
        final h = await pumpPool(tester, persona: Persona.limited);
        expect(find.text('Staff drinks'), findsWidgets);
        expect(find.text('Not available on this account'), findsOneWidget);
        expect(find.text(h.t('reports.noAccess')), findsOneWidget);
        for (final tpl in [todayTpl, drinksTpl, summaryTpl]) {
          expect(h.server.callsTo(tpl), isEmpty, reason: tpl);
        }
      },
    );

    testWidgets('REP-SPL-001 an owner who lacks only this cap is refused too', (
      tester,
    ) async {
      final s = reportsServer();
      authzWithout(s.server, Persona.owner, {'orders.staff_drink.record'});
      final h = await pumpPool(tester, s: s);
      expect(find.text(h.t('reports.noAccess')), findsOneWidget);
      expect(h.server.callsTo(todayTpl), isEmpty);
    });

    testWidgets('REP-SPL-001 / REP-ALL-030 while the rights load the page '
        'renders and asks nothing; then its three reads', (tester) async {
      final s = reportsServer();
      final gate = s.server.hold('GET', '/authz/me');
      final h = await pumpPool(tester, s: s);
      expect(find.byType(StaffPoolReportPage), findsOneWidget);
      expect(find.text('Not available on this account'), findsNothing);
      // Divergence: a skeleton, not the web's zero cards.
      expect(inPage(find.text('Allowance')), findsNothing);
      for (final tpl in [todayTpl, drinksTpl, summaryTpl]) {
        expect(h.server.callsTo(tpl), isEmpty, reason: tpl);
      }
      gate.release();
      await h.settle();
      for (final tpl in [todayTpl, drinksTpl, summaryTpl]) {
        expect(h.server.callsTo(tpl), hasLength(1), reason: tpl);
      }
      expect(inPage(find.text('Every drink, and its note')), findsOneWidget);
    });

    testWidgets(
      'REP-ALL-004 a Dawam-only org: the POS-off page, nothing asked',
      (tester) async {
        final h = await pumpPool(tester, persona: Persona.dawamOnly);
        expect(find.text("Not part of this business's plan"), findsOneWidget);
        expect(find.byType(StaffPoolReportPage), findsNothing);
        for (final tpl in [todayTpl, drinksTpl, summaryTpl]) {
          expect(h.server.callsTo(tpl), isEmpty, reason: tpl);
        }
      },
    );

    testWidgets('REP-SPL-001 the manager reads her own branch', (tester) async {
      final h = await pumpPool(
        tester,
        persona: Persona.manager,
        path: at(branch: SeedIds.zamalek),
      );
      expect(lastQuery(h, todayTpl)['branch_id'], [SeedIds.zamalek]);
      expect(inPage(find.text('Every drink, and its note')), findsOneWidget);
    });

    testWidgets('REP-SPL-007 a 403 from the server: the error and Retry', (
      tester,
    ) async {
      final s = reportsServer();
      s.server.fail(
        'GET',
        todayTpl,
        MockResponse.denied('orders.staff_drink.record'),
        times: null,
      );
      await pumpPool(tester, s: s);
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      expect(inPage(find.text('Retry')), findsOneWidget);
    });
  });

  group('the header and the branch', () {
    testWidgets('REP-SPL-002 the title, and the period\'s last day under it', (
      tester,
    ) async {
      await pumpPool(tester);
      expect(inPage(find.text('Staff drinks')), findsOneWidget);
      expect(inPage(find.text('08 Oct 2026')), findsOneWidget);
      expect(
        inPage(
          find.byWidgetPredicate(
            (w) => w is DashIcon && w.name == 'calendar-range',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('REP-SPL-003 all branches: choose one; nothing asked', (
      tester,
    ) async {
      final h = await pumpPool(tester, path: at(allBranches: true));
      expect(inPage(find.text('Choose a branch')), findsOneWidget);
      expect(
        inPage(
          find.text(
            "The staff drinks pool belongs to one branch's day, so there is "
            'no all-branches total to show.',
          ),
        ),
        findsOneWidget,
      );
      for (final tpl in [todayTpl, drinksTpl, summaryTpl]) {
        expect(h.server.callsTo(tpl), isEmpty, reason: tpl);
      }
      await h.shot('pick-branch');
    });
  });

  group('the three reads', () {
    testWidgets('REP-SPL-004 the pool is the period\'s LAST day, local', (
      tester,
    ) async {
      final h = await pumpPool(tester);
      final q = lastQuery(h, todayTpl);
      expect(q['branch_id'], [SeedIds.heliopolis]);
      expect(q['business_date'], [defaultTo]);
      expect(calls(h, todayTpl), 1);
    });

    testWidgets('REP-SPL-004 a custom range: the local day of its end', (
      tester,
    ) async {
      // Cairo is UTC+3: the end instant is the 30th, local, not the 1st.
      const from = '2026-09-19T21:00:00.000Z';
      const to = '2026-09-30T20:59:59.999Z';
      final h = await pumpPool(
        tester,
        path: '${at()}&preset=custom&from=$from&to=$to',
      );
      expect(lastQuery(h, todayTpl)['business_date'], ['2026-09-30']);
      expect(lastQuery(h, drinksTpl)['from'], ['2026-09-20']);
      expect(lastQuery(h, drinksTpl)['to'], ['2026-09-30']);
    });

    testWidgets('REP-SPL-005 the drinks: the WHOLE period, as local dates', (
      tester,
    ) async {
      final h = await pumpPool(tester);
      final q = lastQuery(h, drinksTpl);
      expect(q['branch_id'], [SeedIds.heliopolis]);
      expect(q['from'], [defaultFrom]);
      expect(q['to'], [defaultTo]);
      expect(q.containsKey('overspent_only'), isFalse);
    });

    testWidgets('REP-SPL-006 the totals: the same filter as the list', (
      tester,
    ) async {
      final h = await pumpPool(tester);
      expect(lastQuery(h, summaryTpl), lastQuery(h, drinksTpl));
    });

    testWidgets('REP-SPL-004…006 a scope change asks all three again', (
      tester,
    ) async {
      final h = await pumpPool(tester);
      await h.go(at(branch: SeedIds.zamalek, preset: '7d'));
      expect(lastQuery(h, todayTpl)['branch_id'], [SeedIds.zamalek]);
      expect(lastQuery(h, drinksTpl)['from'], ['2026-10-02']);
      expect(lastQuery(h, summaryTpl)['from'], ['2026-10-02']);
    });

    testWidgets(
      'REP-ALL-009 only a resync refreshes the pool, not a till event',
      (tester) async {
        final h = await pumpPool(tester);
        final before = {
          for (final t in [todayTpl, drinksTpl, summaryTpl]) t: calls(h, t),
        };
        h.realtime.current!.emit('till.closed', data: '{}');
        await h.settle();
        for (final e in before.entries) {
          expect(calls(h, e.key), e.value, reason: '${e.key} on till.closed');
        }
        h.realtime.current!.emit('resync', data: '{}');
        await h.settle();
        for (final e in before.entries) {
          expect(calls(h, e.key), e.value + 1, reason: '${e.key} on resync');
        }
      },
    );
  });

  group('the day\'s pool', () {
    testWidgets('REP-SPL-007 loading: two skeletons; the drinks still asked', (
      tester,
    ) async {
      final s = reportsServer();
      final gate = s.server.hold('GET', todayTpl);
      final h = await pumpPool(tester, s: s);
      expect(inPage(find.byType(DashSkeleton)), findsNWidgets(2));
      expect(inPage(find.text('Every drink, and its note')), findsNothing);
      // REP-SPL-021: the drinks do not wait for the pool.
      expect(calls(h, drinksTpl), 1);
      expect(calls(h, summaryTpl), 1);
      await h.shot('pool-loading');
      gate.release();
      await h.settle();
      expect(inPage(find.text('Every drink, and its note')), findsOneWidget);
    });

    testWidgets('REP-SPL-007 a failed pool: Retry asks only the pool', (
      tester,
    ) async {
      final s = reportsServer();
      s.server.fail('GET', todayTpl, MockResponse.error(500, 'boom'));
      final h = await pumpPool(tester, s: s);
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      // REP-SPL-021: no drinks card under a failed pool.
      expect(find.byType(StaffDrinksTable), findsNothing);
      await h.shot('pool-error');
      final drinks = calls(h, drinksTpl);
      final before = calls(h, todayTpl);
      await h.tap(inPage(find.text('Retry')));
      expect(calls(h, todayTpl), before + 1);
      expect(calls(h, drinksTpl), drinks);
      expect(find.byType(StaffDrinksTable), findsOneWidget);
    });

    testWidgets('REP-SPL-007 a retry in flight: the error stays, spinning', (
      tester,
    ) async {
      final s = reportsServer();
      s.server.fail('GET', todayTpl, MockResponse.error(500, 'boom'));
      final h = await pumpPool(tester, s: s);
      final gate = s.server.hold('GET', todayTpl);
      await h.tap(inPage(find.text('Retry')));
      final error = tester.widget<DashErrorState>(
        inPage(find.byType(DashErrorState)),
      );
      expect(error.retrying, isTrue);
      expect(inPage(find.byType(DashSkeleton)), findsNothing);
      gate.release();
      await h.settle();
      expect(find.byType(StaffDrinksTable), findsOneWidget);
    });

    testWidgets('REP-SPL-008/021 switched off: the off words, no drinks card', (
      tester,
    ) async {
      final h = await pumpPool(tester, path: at(branch: SeedIds.newCairo));
      expect(
        inPage(find.text('Staff drinks are off at this branch')),
        findsOneWidget,
      );
      expect(
        inPage(
          find.text(
            'Nobody can ring one up here. Turn the pool on, and choose the '
            'items that count, under Settings.',
          ),
        ),
        findsOneWidget,
      );
      // New Cairo rang drinks until 30 Sep: asked for, but hidden (web rule).
      expect(
        StaffPoolMock.drinksIn(h.db!, SeedIds.newCairo, defaultFrom, defaultTo),
        isNotEmpty,
      );
      expect(calls(h, drinksTpl), 1);
      expect(find.byType(StaffDrinksTable), findsNothing);
      expect(find.byType(StaffDrinksSummaryStrip), findsNothing);
      await h.shot('pool-off');
    });

    testWidgets('REP-SPL-008 a switch on with nothing to spend on is off', (
      tester,
    ) async {
      final s = reportsServer();
      final rows = s.db[StaffPoolMock.settingsTable].rows;
      final helio = rows.firstWhere(
        (r) => r['branch_id'] == SeedIds.heliopolis,
      );
      helio['eligible_item_ids'] = <String>[];
      await pumpPool(tester, s: s);
      expect(
        inPage(find.text('Staff drinks are off at this branch')),
        findsOneWidget,
      );
    });

    testWidgets('REP-SPL-009 "The pool on <the last day>"', (tester) async {
      await pumpPool(tester);
      expect(inPage(find.text('The pool on 08 Oct 2026')), findsOneWidget);
    });

    testWidgets(
      'REP-SPL-010 Heliopolis went over: the loud card and its hint',
      (tester) async {
        final h = await pumpPool(tester);
        // The seed's morning: five drinks against an allowance of four.
        expect(statCard(tester, 'Allowance').value, 4);
        expect(statCard(tester, 'Allowance').icon, 'cup-soda');
        expect(statCard(tester, 'Given out').value, 5);
        expect(statCard(tester, 'Left').value, 0);
        expect(statCard(tester, 'Left').tone, DashTone.neutral);
        final over = statCard(tester, 'Over allowance');
        expect(over.value, 1);
        expect(over.tone, DashTone.danger);
        expect(
          over.hint,
          'Allowed, and recorded. The notes below say who each one was for.',
        );
        for (final l in ['Allowance', 'Given out', 'Left', 'Over allowance']) {
          expect(statCard(tester, l).format, DashStatFormat.number, reason: l);
        }
        await h.shot('over');
      },
    );

    testWidgets('REP-SPL-010 Zamalek has some left: success, no hint at 0', (
      tester,
    ) async {
      await pumpPool(tester, path: at(branch: SeedIds.zamalek));
      expect(statCard(tester, 'Allowance').value, 5);
      expect(statCard(tester, 'Given out').value, 3);
      expect(statCard(tester, 'Left').value, 2);
      expect(statCard(tester, 'Left').tone, DashTone.success);
      final over = statCard(tester, 'Over allowance');
      expect(over.value, 0);
      expect(over.tone, DashTone.neutral);
      expect(over.hint, isNull);
    });

    testWidgets('REP-SPL-010 four across from 1280, two from 640, one below', (
      tester,
    ) async {
      final h = await pumpPool(tester);
      // Rows of cards: distinct tops.
      int rows() => {
        for (final e in find.byType(DashStatCard).evaluate())
          tester.getTopLeft(find.byWidget(e.widget)).dy,
      }.length;
      expect(rows(), 1); // four across at 1440
      tester.view.physicalSize = const Size(1100, 900) * DashSize.pixelRatio;
      await h.settle();
      expect(rows(), 2);
      tester.view.physicalSize = const Size(600, 900) * DashSize.pixelRatio;
      await h.settle();
      expect(rows(), 4);
    });
  });

  group('the drinks card', () {
    testWidgets('REP-SPL-011 one day: the day itself under the title', (
      tester,
    ) async {
      await pumpPool(tester, path: at(preset: 'today'));
      final card = find.ancestor(
        of: find.text('Every drink, and its note'),
        matching: find.byType(DashCard),
      );
      expect(
        find.descendant(of: card, matching: find.text('08 Oct 2026')),
        findsOneWidget,
      );
    });

    testWidgets('REP-SPL-011 a range: "<from> to <to>"', (tester) async {
      final h = await pumpPool(tester);
      final f = h.container.read(formatProvider);
      final scope = h.container.read(currentScopeProvider);
      expect(
        inPage(find.text('${f.fmtDate(scope.from)} to ${f.fmtDate(scope.to)}')),
        findsOneWidget,
      );
    });

    testWidgets('REP-SPL-012 the totals load on their own: a 56 bar', (
      tester,
    ) async {
      final s = reportsServer();
      final gate = s.server.hold('GET', summaryTpl);
      final h = await pumpPool(tester, s: s);
      final bar = find.byKey(const Key('staff-summary-loading'));
      expect(bar, findsOneWidget);
      expect(tester.getSize(bar).height, 56);
      // The rows are already there.
      expect(inTable(find.text('Courier from the roastery')), findsWidgets);
      gate.release();
      await h.settle();
      expect(bar, findsNothing);
      expect(find.byKey(const Key('staff-summary')), findsOneWidget);
    });

    testWidgets('REP-SPL-012 failed totals: an alert and Retry; rows stay', (
      tester,
    ) async {
      final s = reportsServer();
      s.server.fail('GET', summaryTpl, MockResponse.error(500, 'boom'));
      final h = await pumpPool(tester, s: s);
      expect(
        find.text("Couldn't load the totals for this period."),
        findsOneWidget,
      );
      expect(inTable(find.text('Courier from the roastery')), findsWidgets);
      await h.shot('summary-failed');
      final drinks = calls(h, drinksTpl);
      final before = calls(h, summaryTpl);
      await h.tap(
        find.descendant(
          of: find.byType(StaffDrinksSummaryStrip),
          matching: find.text('Retry'),
        ),
      );
      expect(calls(h, summaryTpl), before + 1);
      expect(calls(h, drinksTpl), drinks);
      expect(find.byKey(const Key('staff-summary')), findsOneWidget);
    });

    testWidgets('REP-SPL-012 an empty period: no row of zeroes', (
      tester,
    ) async {
      final s = withDrinks(
        const [],
        summary: totals(
          drinks: 0,
          quantity: 0,
          overspent: 0,
          comp: 0,
          extras: 0,
          cost: 0,
        ),
      );
      await pumpPool(tester, s: s);
      expect(find.byKey(const Key('staff-summary')), findsNothing);
      expect(
        find.text("Couldn't load the totals for this period."),
        findsNothing,
      );
    });

    testWidgets('REP-SPL-013 the figures the endpoint returns', (tester) async {
      final s = withDrinks([drink(comp: 7000, extras: 0)], summary: totals());
      final h = await pumpPool(tester, s: s);
      Offset below(String label) =>
          tester.getTopLeft(inStrip(find.text(label)));
      for (final (label, value) in [
        ('Drinks', '5'), // the QUANTITY, not the rows
        ('Given free', 'EGP 280.00'),
        ('Extras charged', 'EGP 35.00'),
        ('Cost to make', 'EGP 61.00'),
        ('Over allowance', '2'),
      ]) {
        final v = inStrip(figure(value));
        expect(v, findsOneWidget, reason: label);
        expect(tester.getTopLeft(v).dy, greaterThan(below(label).dy));
      }
      expect(inStrip(find.text('Till differs')), findsNothing);
      final strip = tester.getSemantics(find.byKey(const Key('staff-summary')));
      expect(strip.label, startsWith('Totals for this period'));
      await h.shot('summary');
    });

    testWidgets('REP-SPL-013 over tinted red; Till differs shows when > 0', (
      tester,
    ) async {
      final s = withDrinks([
        drink(comp: 7000, extras: 0),
      ], summary: totals(mismatches: 1));
      final h = await pumpPool(tester, s: s);
      final c = h.tester.element(find.byType(StaffDrinksSummaryStrip));
      final colors = c.madarColors;
      Text text(String v) => tester.widget<Text>(inStrip(figure(v)));
      expect(text('2').style!.color, DashTone.danger.foreground(colors));
      expect(inStrip(find.text('Till differs')), findsOneWidget);
      expect(text('1').style!.color, DashTone.warning.foreground(colors));
    });

    testWidgets('REP-SPL-014 the unpriced footnote', (tester) async {
      final s = withDrinks([
        drink(comp: 7000, extras: 0),
      ], summary: totals(unpriced: 3));
      await pumpPool(tester, s: s);
      expect(
        find.text(
          '3 of these were rung before staff drinks were priced. They count '
          'as drinks, but have no figure in Given free or Extras charged.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('REP-SPL-013/014 the seeded Maadi month adds up', (
      tester,
    ) async {
      final h = await pumpPool(tester, path: at(branch: SeedIds.maadi));
      final rows = StaffPoolMock.drinksIn(
        h.db!,
        SeedIds.maadi,
        defaultFrom,
        defaultTo,
      );
      final qty = rows.fold<int>(0, (a, r) => a + (r['quantity']! as int));
      final comp = rows.fold<int>(
        0,
        (a, r) => a + ((r['comp_minor'] as int?) ?? 0),
      );
      final unpriced = rows.where((r) => r['comp_minor'] == null).length;
      expect(unpriced, greaterThan(0)); // the old till before 15 Sep
      expect(inStrip(figure('$qty')), findsWidgets);
      expect(
        inStrip(figure(const DashFormat().fmtMoney(comp))),
        findsOneWidget,
      );
      expect(
        find.text(h.t('staffPool.sumUnpriced', count: unpriced)),
        findsOneWidget,
      );
    });
  });

  group('the table', () {
    testWidgets('REP-SPL-015 one day: the time; the item with size and qty', (
      tester,
    ) async {
      final s = withDrinks([
        drink(
          itemName: 'Latte',
          sizeLabel: 'Large',
          quantity: 2,
          comp: 7000,
          extras: 0,
        ),
        drink(id: 'd-2', itemName: 'Iced tea', comp: 7000, extras: 0),
      ]);
      await pumpPool(
        tester,
        s: s,
        path: at(preset: 'today'),
      );
      for (final h in ['TIME', 'ITEM', 'NOTE', 'GIVEN FREE', 'COST']) {
        expect(inTable(find.text(h)), findsOneWidget, reason: h);
      }
      expect(inTable(find.text('Latte · Large × 2')), findsOneWidget);
      expect(inTable(find.text('Iced tea')), findsOneWidget);
      // 06:00Z is nine in the morning in Cairo.
      expect(inTable(figure('09:00 AM')), findsNWidgets(2));
    });

    testWidgets('REP-SPL-015 a range: the business day before the time', (
      tester,
    ) async {
      final s = withDrinks([
        // Poured at 1am on the 20th, for the day the branch was still on.
        drink(
          businessDate: '2026-09-19',
          recordedAt: '2026-09-19T22:00:00.000Z',
          comp: 7000,
          extras: 0,
        ),
      ]);
      await pumpPool(tester, s: s);
      expect(inTable(figure('19 Sept 2026 · 01:00 AM')), findsOneWidget);
    });

    testWidgets('REP-SPL-015 the seed\'s rows: newest first, as sent', (
      tester,
    ) async {
      final h = await pumpPool(tester, path: at(preset: 'today'));
      final notes = [
        'Courier from the roastery',
        'The plumber fixing the sink',
        'Rana (manager), stock count',
      ];
      final ys = [
        for (final n in notes) tester.getTopLeft(inTable(find.text(n))).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
      expect(inTable(figure('09:45 AM')), findsOneWidget);
      await h.shot('today');
    });

    testWidgets('REP-SPL-016 the note in full, its own direction', (
      tester,
    ) async {
      const long =
          'The electrician, waiting on the fridge, which has been leaking '
          'since the morning delivery and needs a part from Heliopolis';
      final s = withDrinks([
        drink(note: long, comp: 7000, extras: 0),
        drink(id: 'd-2', note: 'فريدة — بداية الشيفت', comp: 7000, extras: 0),
      ]);
      await pumpPool(tester, s: s);
      final note = tester.widget<Text>(inTable(find.text(long)));
      expect(note.maxLines, isNull);
      expect(note.overflow, isNull);
      expect(note.textDirection, TextDirection.ltr);
      final ar = tester.widget<Text>(
        inTable(find.text('فريدة — بداية الشيفت')),
      );
      expect(ar.textDirection, TextDirection.rtl);
    });

    testWidgets('REP-SPL-016/017 a till that claimed another comp', (
      tester,
    ) async {
      final s = withDrinks([
        drink(id: 'd-1', comp: 7000, reported: 9000, extras: 0),
        drink(id: 'd-2', comp: 7000, reported: 7000, extras: 0),
        drink(id: 'd-3', comp: 7000, extras: 0),
      ]);
      final h = await pumpPool(tester, s: s);
      final notes = find.byKey(const Key('comp-mismatch'));
      expect(notes, findsOneWidget);
      expect(
        tester.widget<Text>(notes).data,
        'The till reported EGP 90.00; the server priced it at EGP 70.00.',
      );
      expect(inTable(find.text('Till differs')), findsOneWidget);
      await h.shot('mismatch');
    });

    testWidgets('REP-SPL-017 the comp and the extras, as money', (
      tester,
    ) async {
      final s = withDrinks([drink(orderId: 'o-1', comp: 7000, extras: 1500)]);
      await pumpPool(tester, s: s);
      expect(inTable(find.text('EXTRAS CHARGED')), findsOneWidget);
      expect(inTable(figure('EGP 70.00')), findsOneWidget);
      expect(inTable(figure('EGP 15.00')), findsOneWidget);
      expect(inTable(figure('EGP 12.50')), findsOneWidget);
      expect(find.byKey(const Key('comp-unpriced')), findsNothing);
      expect(find.text(h0('unpricedNote')), findsNothing);
    });

    testWidgets('REP-SPL-017 a free drink with nothing extra is EGP 0.00', (
      tester,
    ) async {
      final s = withDrinks([drink(comp: 7000, extras: 0)]);
      await pumpPool(tester, s: s);
      expect(inTable(figure('EGP 0.00')), findsOneWidget);
    });

    testWidgets(
      'REP-SPL-017/020 an old till\'s drink: a dash and why, never 0',
      (tester) async {
        final s = withDrinks([drink(cost: null)]);
        final h = await pumpPool(tester, s: s);
        final cells = find.byKey(const Key('comp-unpriced'));
        expect(cells, findsNWidgets(2));
        // Read out as its reason, not as a bare dash (the row reads as one).
        expect(
          find.bySemanticsLabel(RegExp('Rung before staff drinks were priced')),
          findsWidgets,
        );
        expect(inTable(figure('EGP 0.00')), findsNothing);
        // Cost unknown too: a plain dash.
        expect(inTable(figure('—')), findsNWidgets(3));
        expect(find.text(h0('unpricedNote')), findsOneWidget);
        // The reason on hold, too (a touch screen has no hover).
        await tester.longPress(cells.first);
        await h.settle();
        expect(find.text('Rung before staff drinks were priced'), findsWidgets);
        await h.shot('unpriced');
        await h.flushTimers();
      },
    );

    testWidgets('REP-SPL-018 only the drinks that went over wear the badge', (
      tester,
    ) async {
      final s = withDrinks([
        drink(id: 'd-1', comp: 7000, extras: 0),
        drink(id: 'd-2', overspent: true, comp: 7000, extras: 0),
      ]);
      await pumpPool(tester, s: s);
      expect(find.byKey(const Key('over-badge')), findsOneWidget);
      expect(textHas('· on recount'), findsNothing);
    });

    testWidgets('REP-SPL-018 a recount made it over: "· on recount" + why', (
      tester,
    ) async {
      final s = withDrinks([
        drink(overspent: true, onReplay: true, comp: 7000, extras: 0),
      ]);
      final h = await pumpPool(tester, s: s);
      expect(textHas('· on recount'), findsOneWidget);
      await tester.longPress(find.byKey(const Key('over-badge')));
      await h.settle();
      expect(
        find.text(
          "The till didn't count this as over at the time — the server "
          'did, once it had the whole day.',
        ),
        findsWidgets,
      );
      await h.flushTimers();
    });

    testWidgets('REP-SPL-019 View order opens the sale; none without a sale', (
      tester,
    ) async {
      final h = await pumpPool(tester, path: at(preset: 'today'));
      final rows = StaffPoolMock.drinksIn(
        h.db!,
        SeedIds.heliopolis,
        defaultTo,
        defaultTo,
      );
      expect(inTable(find.text('View order')), findsNWidgets(rows.length));
      final first = rows.first; // the newest: the courier's
      final order = h.db![StaffPoolMock.ordersTable].find(
        first['order_id']! as String,
      )!;
      await h.tap(inTable(find.text('View order')));
      expect(
        h.server.callsTo(orderTpl).last.path,
        '/orders/${first['order_id']}',
      );
      final sheet = find.byType(StaffDrinkOrderSheet);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(
          of: sheet,
          matching: find.text('${order['order_ref']}'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Staff drink')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('staff-line')), findsOneWidget);
      await h.shot('order-sheet');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(sheet, findsNothing);
    });

    testWidgets('REP-SPL-019 a record-only drink offers no link', (
      tester,
    ) async {
      final s = withDrinks([
        drink(id: 'd-1', orderId: 'o-77', comp: 7000, extras: 0),
        drink(id: 'd-2'),
      ]);
      await pumpPool(tester, s: s);
      expect(inTable(find.text('View order')), findsOneWidget);
    });

    testWidgets('REP-SPL-019 without orders.read: no link drawn', (
      tester,
    ) async {
      final s = withDrinks([drink(orderId: 'o-77', comp: 7000, extras: 0)]);
      authzWithout(s.server, Persona.owner, {'orders.read'});
      final h = await pumpPool(tester, s: s);
      expect(inTable(find.text('Mostafa, closing shift')), findsOneWidget);
      expect(find.text('View order'), findsNothing);
      expect(h.server.callsTo(orderTpl), isEmpty);
    });

    testWidgets('REP-SPL-019 the sale\'s figures add up, comp put back', (
      tester,
    ) async {
      final h = await pumpPool(tester, path: at(preset: 'today'));
      final newest = StaffPoolMock.drinksIn(
        h.db!,
        SeedIds.heliopolis,
        defaultTo,
        defaultTo,
      ).first;
      final order = h.db![StaffPoolMock.ordersTable].find(
        newest['order_id']! as String,
      )!;
      final line = (order['items']! as List).cast<MockRow>().single;
      final comp = line['staff_comp_minor']! as int;
      final subtotal = order['subtotal']! as int;
      await h.tap(inTable(find.text('View order')));
      final sheet = find.byType(StaffDrinkOrderSheet);
      Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);
      const f = DashFormat();
      expect(inSheet(find.text('Items at normal price')), findsOneWidget);
      expect(inSheet(figure(f.fmtMoney(subtotal + comp))), findsWidgets);
      expect(inSheet(find.text('Staff drinks · given free')), findsOneWidget);
      expect(inSheet(figure(f.fmtMoney(-comp))), findsWidgets);
      expect(inSheet(find.text('Subtotal')), findsOneWidget);
      expect(inSheet(figure(f.fmtMoney(subtotal))), findsWidgets);
    });

    testWidgets('REP-SPL-019 a failed sale: the words and Retry', (
      tester,
    ) async {
      final s = reportsServer();
      // Twice: the press's warm-up, then the sheet's own read.
      s.server.fail(
        'GET',
        orderTpl,
        MockResponse.error(500, 'Order gone'),
        times: 2,
      );
      final h = await pumpPool(
        tester,
        s: s,
        path: at(preset: 'today'),
      );
      await h.tap(inTable(find.text('View order')));
      final sheet = find.byType(StaffDrinkOrderSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('Order gone')),
        findsOneWidget,
      );
      await h.tap(find.descendant(of: sheet, matching: find.text('Retry')));
      expect(
        find.descendant(of: sheet, matching: find.text('Staff drink')),
        findsOneWidget,
      );
    });

    testWidgets('REP-SPL-020 loading rows; the pool already drawn', (
      tester,
    ) async {
      final s = reportsServer();
      final gate = s.server.hold('GET', drinksTpl);
      final h = await pumpPool(tester, s: s);
      expect(statCard(tester, 'Allowance').value, 4);
      expect(inTable(find.byType(DashSkeleton)), findsWidgets);
      expect(
        inTable(find.text('No staff drinks in this period')),
        findsNothing,
      );
      await h.shot('drinks-loading');
      gate.release();
      await h.settle();
      expect(inTable(find.text('Courier from the roastery')), findsWidgets);
    });

    testWidgets('REP-SPL-020 a failed list: the words and Retry, only it', (
      tester,
    ) async {
      final s = reportsServer();
      s.server.fail('GET', drinksTpl, MockResponse.error(500, 'List down'));
      final h = await pumpPool(tester, s: s);
      expect(inTable(find.text("Couldn't load this")), findsOneWidget);
      expect(inTable(find.text('List down')), findsOneWidget);
      expect(
        inTable(find.text('No staff drinks in this period')),
        findsNothing,
      );
      final today = calls(h, todayTpl);
      final summary = calls(h, summaryTpl);
      final before = calls(h, drinksTpl);
      await h.tap(inTable(find.text('Retry')));
      expect(calls(h, drinksTpl), before + 1);
      expect(calls(h, todayTpl), today);
      expect(calls(h, summaryTpl), summary);
      expect(inTable(find.text('Courier from the roastery')), findsWidgets);
    });

    testWidgets('REP-SPL-020 nothing rung: the empty words', (tester) async {
      final s = withDrinks(const []);
      final h = await pumpPool(tester, s: s);
      expect(
        inTable(find.text('No staff drinks in this period')),
        findsOneWidget,
      );
      await h.shot('empty');
    });

    testWidgets('REP-SPL-020 ten rows a page; the Columns menu', (
      tester,
    ) async {
      final s = withDrinks([
        for (var i = 0; i < 12; i++)
          drink(id: 'd-$i', note: 'Note ${i + 1}', comp: 7000, extras: 0),
      ]);
      final h = await pumpPool(tester, s: s);
      expect(inTable(find.text('Note 10')), findsOneWidget);
      expect(inTable(find.text('Note 11')), findsNothing);
      expect(find.text('Page 1 of 2'), findsOneWidget);
      await h.tapLabel('Next');
      expect(inTable(find.text('Note 11')), findsOneWidget);
      await h.tapText('Columns');
      for (final label in [
        'Time',
        'Item',
        'Note',
        'Given free',
        'Extras charged',
        'Cost',
        'Over allowance',
      ]) {
        expect(
          find.descendant(
            of: find.byType(Overlay).last,
            matching: find.text(label),
          ),
          findsWidgets,
          reason: label,
        );
      }
      await h.tap(find.text('Extras charged').last);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(inTable(find.text('EXTRAS CHARGED')), findsNothing);
    });
  });

  group('phone and Arabic', () {
    testWidgets('REP-SPL-010/015/019 phone: one column of cards, item first', (
      tester,
    ) async {
      final s = withDrinks([
        drink(
          orderId: 'o-77',
          itemName: 'Latte',
          sizeLabel: 'Large',
          comp: 7000,
          extras: 1500,
          overspent: true,
        ),
      ], summary: totals());
      final h = await pumpPool(tester, s: s, size: DashSize.phone);
      final cards = find.byType(DashStatCard);
      expect(
        {
          for (final e in cards.evaluate())
            tester.getTopLeft(find.byWidget(e.widget)).dx,
        }.length,
        1,
      );
      expect(inTable(find.text('Latte · Large')), findsOneWidget);
      expect(inTable(find.text('View order')), findsOneWidget);
      expect(find.byKey(const Key('over-badge')), findsOneWidget);
      await h.shot('phone-row');
      await h.tap(inTable(find.text('View order')));
      expect(find.byType(StaffDrinkOrderSheet), findsOneWidget);
    });

    testWidgets('REP-SPL-013…018 Arabic: every word in Arabic', (tester) async {
      final s = withDrinks([
        drink(
          id: 'd-1',
          orderId: 'o-1',
          comp: 7000,
          reported: 9000,
          extras: 1500,
          overspent: true,
          onReplay: true,
        ),
        drink(id: 'd-2'),
      ], summary: totals(mismatches: 1, unpriced: 1));
      final h = await pumpPool(tester, s: s, locale: 'ar');
      expect(inPage(find.text(h.t('staffPool.reportTitle'))), findsOneWidget);
      expect(find.text(h.t('staffPool.compMismatchBadge')), findsWidgets);
      expect(textHas(h.t('staffPool.overOnReplay')), findsOneWidget);
      expect(find.text(h.t('staffPool.unpricedNote')), findsOneWidget);
      await h.shot('arabic');
    });
  });
}

/// An English word of the page (the harness's own `t` needs a harness).
String h0(String key) => switch (key) {
  'unpricedNote' =>
    '— means the drink was rung before staff drinks were priced, so there is '
        'no figure for it. It still counted against the allowance.',
  _ => throw ArgumentError(key),
};
