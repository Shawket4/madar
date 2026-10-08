// `/reports/bundles` Bundles, driven through the real app shell (inventory
// rows REP-BUN-001 to -019): the gate, the request, the KPI strip, the table,
// the Combos / Deals switch, the Mix dialog and the export.
import 'dart:async';
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/mock/staff_pool_bundles_mock.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/bundles_mix_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The seeded sales of [kind] in [from]…[to] at [branches] (every Sabah
/// branch by default), worked out here from the table's rows.
List<MockRow> salesOf(
  MockDb db,
  String kind, {
  String from = defaultFrom,
  String to = defaultTo,
  List<String>? branches,
}) => [
  for (final s in db[BundlesMock.salesTable].rows)
    if (s['kind'] == kind &&
        (branches ?? SeedIds.sabahBranches).contains(s['branch_id']) &&
        '${s['business_date']}'.compareTo(from) >= 0 &&
        '${s['business_date']}'.compareTo(to) <= 0)
      s,
];

int sum(Iterable<MockRow> rows, String field) =>
    rows.fold<int>(0, (a, r) => a + (r[field]! as int));

/// "EGP 1,234.50" for [piastres], as the page writes it in English.
String egp(int piastres) => const DashFormat().fmtMoney(piastres);

String num0(int n) => const DashFormat().fmtNumber(n);

void main() {
  group('the gate', () {
    testWidgets(
      'REP-BUN-001 without reports.bundles: Restricted, nothing asked',
      (tester) async {
        final h = await pumpReports(
          tester,
          path: bundlesPath,
          persona: Persona.limited,
        );
        expect(find.text('Bundles'), findsWidgets);
        expect(find.text('Not available on this account'), findsOneWidget);
        expect(h.server.callsTo(bundlesTpl), isEmpty);
        expect(find.text('Export Excel'), findsNothing);
      },
    );

    testWidgets('REP-BUN-001 the page\'s own gate says who it is for', (
      tester,
    ) async {
      final h = await pumpReports(
        tester,
        path: bundlesPath,
        persona: Persona.limited,
        area: pageGatedArea,
      );
      expect(find.text('Not available on this account'), findsOneWidget);
      expect(
        find.text(
          "Your account can't open this report. The owner can give you access.",
        ),
        findsOneWidget,
      );
      expect(h.server.callsTo(bundlesTpl), isEmpty);
    });

    testWidgets('REP-BUN-001 the manager sees the report for her branch', (
      tester,
    ) async {
      final h = await pumpReports(
        tester,
        path: bundlesPath,
        persona: Persona.manager,
      );
      // As on the web, the scope's branch is not forced into the params: the
      // server narrows a manager to her branch (the header the core sends).
      expect(h.server.callsTo(bundlesTpl), isNotEmpty);
      expect(find.text('Brunch for Two'), findsOneWidget);
    });

    testWidgets('REP-BUN-010 a 403 from the server shows its words', (
      tester,
    ) async {
      final s = reportsServer();
      s.server.fail(
        'GET',
        bundlesTpl,
        MockResponse.denied('reports.bundles'),
        times: null,
      );
      await pumpReports(tester, path: bundlesPath, server: s.server, db: s.db);
      expect(find.text("Couldn't load this"), findsOneWidget);
      expect(textHas("You don't have permission to do this"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('the header and the request', () {
    testWidgets('REP-BUN-002 title, description and one Export Excel button', (
      tester,
    ) async {
      await pumpReports(tester, path: bundlesPath);
      expect(find.text('Bundles'), findsWidgets);
      expect(
        find.text(
          'Each combo and deal as one line. Item sales count the same sales '
          'under each item, at its share of the price.',
        ),
        findsOneWidget,
      );
      expect(find.text('Export Excel'), findsOneWidget);
      await tester.tap(find.text('Export Excel'));
      await tester.pump();
      // A single button, not a menu: no CSV entry appears.
      expect(find.text('Export CSV'), findsNothing);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('REP-BUN-004 all branches: local dates, no branch, combos', (
      tester,
    ) async {
      final h = await pumpReports(tester, path: bundlesPath);
      final q = lastQuery(h, bundlesTpl);
      expect(q['from'], [defaultFrom]);
      expect(q['to'], [defaultTo]);
      expect(q.containsKey('branch_id'), isFalse);
      expect(q['kind'], ['combo']);
    });

    testWidgets('REP-BUN-004 a branch and a custom range, as local dates', (
      tester,
    ) async {
      // Cairo is UTC+3: these instants are the 1st and the 30th, local.
      const from = '2026-08-31T21:00:00.000Z';
      const to = '2026-09-30T20:59:59.999Z';
      final h = await pumpReports(
        tester,
        path:
            '$bundlesPath?branchId=${SeedIds.heliopolis}&preset=custom'
            '&from=$from&to=$to',
      );
      final q = lastQuery(h, bundlesTpl);
      expect(q['from'], ['2026-09-01']);
      expect(q['to'], ['2026-09-30']);
      expect(q['branch_id'], [SeedIds.heliopolis]);
    });

    testWidgets('REP-BUN-004 a scope change asks again', (tester) async {
      final h = await pumpReports(tester, path: bundlesPath);
      final before = h.server.callsTo(bundlesTpl).length;
      await h.go('$bundlesPath?branchId=${SeedIds.maadi}&preset=7d');
      expect(h.server.callsTo(bundlesTpl).length, greaterThan(before));
      final q = lastQuery(h, bundlesTpl);
      expect(q['branch_id'], [SeedIds.maadi]);
      expect(q['from'], ['2026-10-02']);
    });

    testWidgets('REP-BUN-003 Deals asks with kind=deal and relabels', (
      tester,
    ) async {
      final h = await pumpReports(tester, path: bundlesPath);
      expect(find.text('COMBO'), findsOneWidget);
      expect(find.text('SOLD'), findsOneWidget);
      await h.tapText('Deals');
      final q = lastQuery(h, bundlesTpl);
      expect(q['kind'], ['deal']);
      expect(q['from'], [defaultFrom]);
      expect(find.text('DEAL'), findsOneWidget);
      expect(find.text('APPLIED'), findsOneWidget);
      expect(find.text('Applied'), findsOneWidget); // the KPI
      expect(find.text('Any 2 pastries for 150'), findsOneWidget);
      expect(find.text('Morning Croissant Combo'), findsNothing);
      await h.shot('deals');
    });

    testWidgets('REP-ALL-009 a till event refetches the report', (
      tester,
    ) async {
      final h = await pumpReports(
        tester,
        path: '$bundlesPath?branchId=${SeedIds.zamalek}',
      );
      final before = h.server.callsTo(bundlesTpl).length;
      h.realtime.current!.emit('till.closed', data: '{}');
      await h.settle();
      expect(h.server.callsTo(bundlesTpl).length, before + 1);
    });
  });

  group('the KPI strip', () {
    testWidgets('REP-BUN-005 Sold, Revenue and Saving are the period totals', (
      tester,
    ) async {
      final h = await pumpReports(tester, path: bundlesPath);
      final sales = salesOf(h.db!, 'combo');
      expect(statCard(tester, 'Sold').value, sales.length);
      expect(statCard(tester, 'Revenue').value, sum(sales, 'revenue'));
      expect(
        statCard(tester, 'Saving given').value,
        sum(sales, 'list_value') - sum(sales, 'revenue'),
      );
      expect(statCard(tester, 'Sold').format, DashStatFormat.number);
      expect(statCard(tester, 'Revenue').format, DashStatFormat.money);
    });

    testWidgets('REP-BUN-006 no margin while a row\'s cost is unknown', (
      tester,
    ) async {
      final h = await pumpReports(tester, path: bundlesPath);
      // Brunch for Two can pick shakshuka, whose cost nobody knows.
      expect(
        salesOf(h.db!, 'combo').any((s) => s['cost_missing'] == true),
        isTrue,
      );
      expect(statCard(tester, 'Margin').valueText, '—');
    });

    testWidgets('REP-BUN-006 the margin once every cost is known', (
      tester,
    ) async {
      final h = await pumpReports(
        tester,
        path: '$bundlesPath?branchId=${SeedIds.heliopolis}',
      );
      final sales = salesOf(h.db!, 'combo', branches: [SeedIds.heliopolis]);
      expect(sales.any((s) => s['cost_missing'] == true), isFalse);
      final revenue = sum(sales, 'revenue');
      final cost = sum(sales, 'cost');
      expect(
        statCard(tester, 'Margin').valueText,
        const DashFormat().fmtPercent((revenue - cost) / revenue),
      );
    });

    testWidgets('REP-BUN-006 the web\'s own figure: 67.6%', (tester) async {
      final s = reportsServer();
      s.server.on('GET', bundlesTpl, (req) => MockResponse.ok(_fixture()));
      await pumpReports(tester, path: bundlesPath, server: s.server, db: s.db);
      // Family box's cost is unknown: no margin.
      expect(statCard(tester, 'Margin').valueText, '—');
      expect(statCard(tester, 'Sold').value, 15);
      expect(statCard(tester, 'Revenue').value, 270000);
      expect(statCard(tester, 'Saving given').value, 51000);
    });

    testWidgets('REP-BUN-006 every cost known: (270000 − 87540) / 270000', (
      tester,
    ) async {
      final s = reportsServer();
      final f = _fixture();
      for (final r in (f['rows']! as List).cast<MockRow>()) {
        r['cost_missing'] = false;
      }
      s.server.on('GET', bundlesTpl, (req) => MockResponse.ok(f));
      await pumpReports(tester, path: bundlesPath, server: s.server, db: s.db);
      expect(statCard(tester, 'Margin').valueText, '67.6%');
    });
  });

  group('the table', () {
    testWidgets(
      'REP-BUN-007 a combo\'s line: counts, money in pounds, margin',
      (tester) async {
        final s = reportsServer();
        s.server.on('GET', bundlesTpl, (req) => MockResponse.ok(_fixture()));
        await pumpReports(
          tester,
          path: bundlesPath,
          server: s.server,
          db: s.db,
        );
        for (final header in [
          'COMBO',
          'SOLD',
          'ORDERS',
          'REVENUE',
          'SEPARATELY',
          'SAVING GIVEN',
          'COST',
          'MARGIN',
        ]) {
          expect(find.text(header), findsOneWidget, reason: header);
        }
        expect(find.text('Lunch deal'), findsOneWidget);
        expect(figure('12'), findsOneWidget);
        expect(figure('10'), findsOneWidget);
        // Piastres became pounds: 180000 → EGP 1,800.00.
        expect(figure('EGP 1,800.00'), findsOneWidget);
        expect(figure('EGP 2,160.00'), findsOneWidget);
        expect(figure('EGP 360.00'), findsOneWidget);
        expect(figure('EGP 675.40'), findsOneWidget);
        expect(figure('62.5%'), findsOneWidget);
      },
    );

    testWidgets('REP-BUN-008 a partly unknown cost: a floor, no margin', (
      tester,
    ) async {
      final s = reportsServer();
      s.server.on('GET', bundlesTpl, (req) => MockResponse.ok(_fixture()));
      await pumpReports(tester, path: bundlesPath, server: s.server, db: s.db);
      expect(figure('≥ EGP 200.00'), findsOneWidget);
      // Not the server's margin, which rests on a cost it doesn't know.
      expect(figure('77.8%'), findsNothing);
      expect(figure('—'), findsWidgets);
    });

    testWidgets('REP-BUN-007/008 the seeded Brunch for Two at Zamalek', (
      tester,
    ) async {
      final h = await pumpReports(
        tester,
        path: '$bundlesPath?branchId=${SeedIds.zamalek}',
      );
      final brunch = salesOf(
        h.db!,
        'combo',
        branches: [SeedIds.zamalek],
      ).where((s) => s['bundle_key'] == 'brunch-for-two').toList();
      expect(brunch, isNotEmpty);
      expect(find.text('Brunch for Two'), findsOneWidget);
      expect(figure(egp(sum(brunch, 'revenue'))), findsOneWidget);
      final floor = '≥ ${egp(sum(brunch, 'cost'))}';
      expect(
        brunch.any((s) => s['cost_missing'] == true)
            ? figure(floor)
            : figure(egp(sum(brunch, 'cost'))),
        findsOneWidget,
      );
      expect(figure(num0(brunch.length)), findsWidgets);
    });

    testWidgets('REP-BUN-007 Arabic: the names in Arabic', (tester) async {
      await pumpReports(
        tester,
        path: '$bundlesPath?branchId=${SeedIds.zamalek}',
        locale: 'ar',
      );
      expect(find.text('برانش لشخصين'), findsOneWidget);
      expect(find.text('Brunch for Two'), findsNothing);
      expect(find.text('الكومبو'), findsWidgets);
    });

    testWidgets('REP-BUN-009 nothing sold: the combos empty state', (
      tester,
    ) async {
      final s = reportsServer();
      s.db[BundlesMock.salesTable].removeWhere((r) => true);
      await pumpReports(tester, path: bundlesPath, server: s.server, db: s.db);
      expect(find.text('No combos sold in this period'), findsOneWidget);
      expect(
        find.text('Try a longer period or another branch.'),
        findsOneWidget,
      );
      expect(statCard(tester, 'Sold').value, 0);
      expect(statCard(tester, 'Margin').valueText, '—');
    });

    testWidgets('REP-BUN-009 nothing applied: the deals empty state', (
      tester,
    ) async {
      final s = reportsServer();
      s.db[BundlesMock.salesTable].removeWhere((r) => r['kind'] == 'deal');
      final h = await pumpReports(
        tester,
        path: bundlesPath,
        server: s.server,
        db: s.db,
      );
      expect(find.text('Morning Croissant Combo'), findsOneWidget);
      await h.tapText('Deals');
      expect(find.text('No deals applied in this period'), findsOneWidget);
      await h.shot('deals-empty');
    });

    testWidgets('REP-BUN-010 loading: skeleton KPIs and rows', (tester) async {
      final s = reportsServer();
      final gate = s.server.hold('GET', bundlesTpl);
      final h = await pumpReports(
        tester,
        path: bundlesPath,
        server: s.server,
        db: s.db,
      );
      expect(statCard(tester, 'Revenue').loading, isTrue);
      expect(find.byType(DashSkeleton), findsWidgets);
      expect(find.text('Morning Croissant Combo'), findsNothing);
      await h.shot('loading');
      gate.release();
      await h.settle();
      expect(find.text('Morning Croissant Combo'), findsOneWidget);
    });

    testWidgets('REP-BUN-010 a failed load: the words and Retry', (
      tester,
    ) async {
      final s = reportsServer();
      s.server.fail(
        'GET',
        bundlesTpl,
        MockResponse.error(500, 'The report service is down'),
      );
      final h = await pumpReports(
        tester,
        path: bundlesPath,
        server: s.server,
        db: s.db,
      );
      expect(find.text("Couldn't load this"), findsOneWidget);
      expect(find.text('The report service is down'), findsOneWidget);
      expect(find.text('No combos sold in this period'), findsNothing);
      await h.shot('error');
      final before = h.server.callsTo(bundlesTpl).length;
      await h.tapText('Retry');
      expect(h.server.callsTo(bundlesTpl).length, before + 1);
      expect(find.text('Morning Croissant Combo'), findsOneWidget);
    });

    testWidgets('REP-BUN-011 ten rows a page; Columns lists all but the name', (
      tester,
    ) async {
      final s = reportsServer();
      final f = _fixture();
      final base = (f['rows']! as List).cast<MockRow>().first;
      f['rows'] = [
        for (var i = 0; i < 12; i++)
          {...base, 'id': 'c-$i', 'name': 'Combo ${i + 1}'},
      ];
      s.server.on('GET', bundlesTpl, (req) => MockResponse.ok(f));
      final h = await pumpReports(
        tester,
        path: bundlesPath,
        server: s.server,
        db: s.db,
      );
      expect(find.text('Combo 10'), findsOneWidget);
      expect(find.text('Combo 11'), findsNothing);
      expect(find.text('Page 1 of 2'), findsOneWidget);
      await h.tapLabel('Next');
      expect(find.text('Combo 11'), findsOneWidget);
      expect(find.text('Page 2 of 2'), findsOneWidget);

      await h.tapText('Columns');
      for (final label in [
        'Sold',
        'Orders',
        'Revenue',
        'Separately',
        'Saving given',
        'Cost',
        'Margin',
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
      await h.shot('columns-menu');
      // Hiding a column takes it off the table.
      await h.tap(find.text('Separately').last);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(find.text('SEPARATELY'), findsNothing);
    });

    testWidgets('REP-BUN-012 deal rows open nothing', (tester) async {
      final h = await pumpReports(tester, path: bundlesPath);
      await h.tapText('Deals');
      await h.tapText('Any 2 pastries for 150');
      expect(h.server.callsTo(mixTpl), isEmpty);
      expect(find.textContaining('What went into'), findsNothing);
    });
  });

  group('the Mix dialog', () {
    testWidgets('REP-BUN-012/013 a combo row opens its mix for the same scope', (
      tester,
    ) async {
      final h = await pumpReports(
        tester,
        path: '$bundlesPath?branchId=${SeedIds.zamalek}',
      );
      await h.tapText('Brunch for Two');
      expect(find.text('What went into Brunch for Two'), findsOneWidget);
      expect(
        find.text(
          'Every pick per slot in this period, with the extra it brought in.',
        ),
        findsOneWidget,
      );
      final call = h.server.callsTo(mixTpl).last;
      expect(
        call.path,
        '/reports/bundles/combos/${BundlesMock.comboId('brunch-for-two')}/mix',
      );
      expect(call.query['from'], [defaultFrom]);
      expect(call.query['to'], [defaultTo]);
      expect(call.query['branch_id'], [SeedIds.zamalek]);
      expect(find.text('Mains'), findsOneWidget);
      expect(find.text('Drinks'), findsOneWidget);
      await h.shot('mix-dialog');
    });

    testWidgets('REP-BUN-015 most-picked first, share of the slot, extras', (
      tester,
    ) async {
      final s = reportsServer();
      s.server.on('GET', bundlesTpl, (req) => MockResponse.ok(_fixture()));
      s.server.on('GET', mixTpl, (req) => MockResponse.ok(_mix()));
      final h = await pumpReports(
        tester,
        path: bundlesPath,
        server: s.server,
        db: s.db,
      );
      await h.tapText('Lunch deal');
      expect(find.text('What went into Lunch deal'), findsOneWidget);
      expect(find.text('PICK'), findsNWidgets(2));
      expect(find.text('TIMES'), findsNWidgets(2));
      final burger = tester.getTopLeft(find.text('Burger'));
      final wrap = tester.getTopLeft(find.text('Chicken wrap'));
      // Sent wrap-first; shown burger-first (9 picks over 3).
      expect(burger.dy, lessThan(wrap.dy));
      // In the dialog (the report under it has figures of its own).
      Finder inMix(Finder f) =>
          find.descendant(of: find.byType(BundlesMixDialog), matching: f);
      expect(inMix(figure('75%')), findsOneWidget);
      expect(inMix(figure('25%')), findsOneWidget);
      expect(inMix(figure('100%')), findsOneWidget);
      expect(inMix(figure('EGP 45.00')), findsOneWidget);
      expect(inMix(figure('—')), findsNWidgets(2));
    });

    testWidgets('REP-BUN-015 the seeded mix adds up to the combos sold', (
      tester,
    ) async {
      final h = await pumpReports(
        tester,
        path: '$bundlesPath?branchId=${SeedIds.heliopolis}',
      );
      await h.tapText('Coffee & Cookie');
      final sold = salesOf(
        h.db!,
        'combo',
        branches: [SeedIds.heliopolis],
      ).where((s) => s['bundle_key'] == 'coffee-cookie').length;
      // One americano and one cookie per combo: each the whole slot.
      expect(figure(num0(sold)), findsWidgets);
      expect(figure('100%'), findsNWidgets(2));
      expect(find.text('Chocolate Chip Cookie · Standard'), findsOneWidget);
      expect(find.text('Americano · Regular'), findsOneWidget);
    });

    testWidgets('REP-BUN-016 Arabic names, English where none, one size', (
      tester,
    ) async {
      final s = reportsServer();
      s.server.on('GET', bundlesTpl, (req) => MockResponse.ok(_fixture()));
      final m = _mix();
      final slots = (m['slots']! as List).cast<MockRow>();
      slots[0]['name_translations'] = {'ar': 'الطبق الرئيسي'};
      (slots[0]['picks']! as List).cast<MockRow>()[1]['name_translations'] = {
        'ar': 'برجر',
      };
      (slots[0]['picks']! as List).cast<MockRow>()[1]['size_label'] =
          'one_size';
      s.server.on('GET', mixTpl, (req) => MockResponse.ok(m));
      final h = await pumpReports(
        tester,
        path: bundlesPath,
        server: s.server,
        db: s.db,
        locale: 'ar',
      );
      await h.tapText('Lunch deal');
      expect(find.text('الطبق الرئيسي'), findsOneWidget);
      expect(find.text('Main'), findsNothing);
      expect(find.text('برجر · عادي'), findsOneWidget);
      // No Arabic name: the English one shows.
      expect(find.text('Chicken wrap'), findsOneWidget);
      expect(find.text('Drink'), findsOneWidget);
    });

    testWidgets('REP-BUN-014 loading lines, then the slots', (tester) async {
      final s = reportsServer();
      final gate = s.server.hold('GET', mixTpl);
      final h = await pumpReports(
        tester,
        path: '$bundlesPath?branchId=${SeedIds.heliopolis}',
        server: s.server,
        db: s.db,
      );
      await h.tapText('Coffee & Cookie');
      expect(find.byType(DashSkeleton), findsNWidgets(4));
      gate.release();
      await h.settle();
      expect(find.text('Coffee'), findsOneWidget);
    });

    testWidgets('REP-BUN-014 a failed mix: Retry', (tester) async {
      final s = reportsServer();
      s.server.fail('GET', mixTpl, MockResponse.error(500, 'boom'));
      final h = await pumpReports(
        tester,
        path: '$bundlesPath?branchId=${SeedIds.heliopolis}',
        server: s.server,
        db: s.db,
      );
      await h.tapText('Coffee & Cookie');
      expect(find.text("Couldn't load this"), findsOneWidget);
      await h.tapText('Retry');
      expect(find.text('Coffee'), findsOneWidget);
    });

    testWidgets('REP-BUN-014 no picks: the empty words', (tester) async {
      final s = reportsServer();
      s.server.on(
        'GET',
        mixTpl,
        (req) => MockResponse.ok({
          'combo_id': req.param('id'),
          'from': defaultFrom,
          'to': defaultTo,
          'slots': <Object?>[],
        }),
      );
      final h = await pumpReports(
        tester,
        path: '$bundlesPath?branchId=${SeedIds.heliopolis}',
        server: s.server,
        db: s.db,
      );
      await h.tapText('Coffee & Cookie');
      expect(find.text('No picks in this period.'), findsOneWidget);
    });

    testWidgets('REP-BUN-017 closes with X, with Esc and on the overlay', (
      tester,
    ) async {
      final h = await pumpReports(
        tester,
        path: '$bundlesPath?branchId=${SeedIds.heliopolis}',
      );
      const title = 'What went into Coffee & Cookie';
      await h.tapText('Coffee & Cookie');
      expect(find.text(title), findsOneWidget);
      // The dialog's X (the barrier is labelled "Close" too).
      await h.tap(
        find.descendant(
          of: find.byType(BundlesMixDialog),
          matching: find.bySemanticsLabel('Close'),
        ),
      );
      expect(find.text(title), findsNothing);

      await h.tapText('Coffee & Cookie');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(find.text(title), findsNothing);

      await h.tapText('Coffee & Cookie');
      await tester.tapAt(const Offset(4, 4));
      await h.settle();
      expect(find.text(title), findsNothing);
    });

    testWidgets('REP-BUN-017 576 wide on a desktop', (tester) async {
      await pumpReports(
        tester,
        path: '$bundlesPath?branchId=${SeedIds.heliopolis}',
      );
      await tester.tap(find.text('Coffee & Cookie'));
      await tester.pumpAndSettle();
      final surface = find.ancestor(
        of: find.text('What went into Coffee & Cookie'),
        matching: find.byType(DashSurface),
      );
      expect(tester.getSize(surface).width, lessThanOrEqualTo(576));
      expect(tester.getSize(surface).width, greaterThan(512));
    });
  });

  group('the export', () {
    testWidgets('REP-BUN-018 the sheet: headers, units, totals, file name', (
      tester,
    ) async {
      final s = reportsServer();
      s.server.on('GET', bundlesTpl, (req) => MockResponse.ok(_fixture()));
      final h = await pumpReports(
        tester,
        path: bundlesPath,
        server: s.server,
        db: s.db,
      );
      await h.tapText('Export Excel');
      await h.settle();
      expect(h.exports.built, hasLength(1));
      final sheet = h.exports.built.single.sheets.single;
      expect(sheet.name, 'Combos');
      expect(sheet.title, 'Bundles');
      expect(sheet.subtitle, startsWith('09 Sept 2026 to 08 Oct 2026'));
      expect(
        [for (final c in sheet.columns) c.header],
        [
          'Combo',
          'Sold',
          'Orders',
          'Revenue',
          'Separately',
          'Saving given',
          'Cost',
          'Margin',
        ],
      );
      expect(
        [for (final c in sheet.columns) c.numFmt],
        [
          null,
          '#,##0',
          '#,##0',
          '#,##0.00 "EGP"',
          '#,##0.00 "EGP"',
          '#,##0.00 "EGP"',
          '#,##0.00 "EGP"',
          '0.0%',
        ],
      );
      // Money leaves in pounds; the margin a fraction, blank when unknown.
      expect(sheet.rows[0], [
        'Lunch deal',
        12,
        10,
        1800,
        2160,
        360,
        675.4,
        0.6248,
      ]);
      expect(sheet.rows[1][7], isNull);
      // Orders overlap across rows: not totalled.
      final totals = sheet.totalsRow!;
      expect(totals[0], 'TOTALS');
      expect(totals[2], '');
      expect(
        [
          for (final c in totals)
            if (c is ExcelFormula) c.formula,
        ],
        ['SUM(B8:B9)', 'SUM(D8:D9)', 'SUM(E8:E9)', 'SUM(F8:F9)', 'SUM(G8:G9)'],
      );
      final file = h.files.saved.single;
      expect(
        file.filename,
        'Madar-Bundles-Combos-$defaultFrom'
        '_$defaultTo-2026-10-08.xlsx',
      );
      expect(json.decode(utf8.decode(file.bytes)), isA<Map<String, Object?>>());
      expect(find.text('Exported 2 rows'), findsOneWidget);
      await h.flushTimers();
    });

    testWidgets('REP-BUN-018 Deals: its own file and sheet names', (
      tester,
    ) async {
      final h = await pumpReports(tester, path: bundlesPath);
      await h.tapText('Deals');
      await h.tapText('Export Excel');
      await h.settle();
      final sheet = h.exports.built.single.sheets.single;
      expect(sheet.name, 'Deals');
      expect(sheet.columns.first.header, 'Deal');
      expect(sheet.columns[1].header, 'Applied');
      expect(
        h.files.saved.single.filename,
        startsWith('Madar-Bundles-Deals-$defaultFrom'),
      );
      await h.flushTimers();
    });

    testWidgets('REP-BUN-018 Arabic: the sheet in Arabic', (tester) async {
      final h = await pumpReports(
        tester,
        path: '$bundlesPath?branchId=${SeedIds.zamalek}',
        locale: 'ar',
      );
      await h.tapText('تصدير إلى إكسل');
      await h.settle();
      final sheet = h.exports.built.single.sheets.single;
      expect(sheet.name, 'الكومبو');
      expect(sheet.title, 'الكومبو والعروض');
      expect(sheet.rows.any((r) => r.first == 'برانش لشخصين'), isTrue);
      await h.flushTimers();
    });

    testWidgets('REP-BUN-018 disabled with no rows', (tester) async {
      final s = reportsServer();
      s.db[BundlesMock.salesTable].removeWhere((r) => true);
      final h = await pumpReports(
        tester,
        path: bundlesPath,
        server: s.server,
        db: s.db,
      );
      final button = tester.widget<DashButton>(
        find.ancestor(
          of: find.text('Export Excel'),
          matching: find.byType(DashButton),
        ),
      );
      expect(button.onPressed, isNull);
      await h.tapText('Export Excel');
      expect(h.exports.built, isEmpty);
    });

    testWidgets('REP-BUN-019 a failed write says so', (tester) async {
      final h = await pumpReports(tester, path: bundlesPath);
      h.exports.failNext = StateError('disk full');
      await h.tapText('Export Excel');
      await h.settle();
      expect(find.text('Export failed'), findsOneWidget);
      expect(h.files.saved, isEmpty);
      await h.flushTimers();
    });

    testWidgets('REP-ALL-011 the loading toast while the file is written', (
      tester,
    ) async {
      final h = await pumpReports(tester, path: bundlesPath);
      // Held: the recorded export answers at once otherwise.
      final written = Completer<void>();
      h.exports.hold = written.future;
      await tester.tap(find.text('Export Excel'));
      await tester.pump();
      expect(find.text('Gathering data…'), findsOneWidget);
      written.complete();
      await h.settle();
      expect(find.text('Gathering data…'), findsNothing);
      expect(textHas('Exported'), findsOneWidget);
      await h.flushTimers();
    });
  });
}

/// The web test's report (`bundles-report-page.test.tsx`).
MockRow _fixture() => {
  'from': '2026-09-01',
  'to': '2026-09-30',
  'rows': <MockRow>[
    {
      'id': 'c-1',
      'kind': 'combo',
      'name': 'Lunch deal',
      'name_translations': <String, Object?>{},
      'sold': 12,
      'orders': 10,
      'revenue': 180000,
      'list_value': 216000,
      'saving': 36000,
      'cost': 67540,
      'cost_missing': false,
      'margin': '0.6248',
    },
    {
      'id': 'c-2',
      'kind': 'combo',
      'name': 'Family box',
      'name_translations': <String, Object?>{},
      'sold': 3,
      'orders': 2,
      'revenue': 90000,
      'list_value': 105000,
      'saving': 15000,
      'cost': 20000,
      'cost_missing': true,
      'margin': '0.7778',
    },
  ],
  'totals': {
    'sold': 15,
    'revenue': 270000,
    'list_value': 321000,
    'saving': 51000,
    'cost': 87540,
  },
};

/// The web test's mix: Main sent wrap-first.
MockRow _mix() => {
  'combo_id': 'c-1',
  'from': '2026-09-01',
  'to': '2026-09-30',
  'slots': <MockRow>[
    {
      'slot_id': 's-main',
      'name': 'Main',
      'name_translations': <String, Object?>{},
      'picks': <MockRow>[
        {
          'menu_item_id': 'chicken',
          'name': 'Chicken wrap',
          'name_translations': <String, Object?>{},
          'size_label': null,
          'count': 3,
          'surcharge_total': 4500,
        },
        {
          'menu_item_id': 'burger',
          'name': 'Burger',
          'name_translations': <String, Object?>{},
          'size_label': null,
          'count': 9,
          'surcharge_total': 0,
        },
      ],
    },
    {
      'slot_id': 's-drink',
      'name': 'Drink',
      'name_translations': <String, Object?>{},
      'picks': <MockRow>[
        {
          'menu_item_id': 'cola',
          'name': 'Cola',
          'name_translations': <String, Object?>{},
          'size_label': null,
          'count': 12,
          'surcharge_total': 0,
        },
      ],
    },
  ],
};
