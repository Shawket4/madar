// The Waste log page (INV-WST-001…013, -024…030), driven through the real
// shell on the seeded mock. Expectations are worked out by hand from the
// area seed (`invWaste`, the catalog's costs, Zamalek's House Blend at 92.4
// piastres/g).
import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' show StockMovement;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/waste/waste_dialog.dart';
import 'package:dashboard_inventory/src/waste/waste_page.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Zamalek's eight waste lines, latest first (by when they happened).
const List<String> zamalekOrder = [
  'Full Cream Milk', // spoiled, 06:29 (from the Latte), sorts before House
  'House Blend Beans',
  'Croissant Dough',
  'Full Cream Milk',
  'Whipped Cream',
  'Matcha Powder',
  'Vanilla Ice Cream',
  'Cocoa Powder',
];

DashDataTable<StockMovement> logTable(WidgetTester tester) =>
    tester.widget(find.byType(DashDataTable<StockMovement>));

/// The by-reason lines as (label, value).
List<(String, String)> summary(WidgetTester tester) => [
  for (final l in tester.widgetList<DashSummaryLine>(
    inReasons(find.byType(DashSummaryLine)),
  ))
    (l.label, l.value),
];

void main() {
  group('header and reads', () {
    testWidgets('INV-WST-001 title, Export and Record waste', (tester) async {
      await pumpWaste(tester, branch: SeedIds.zamalek);
      expect(
        find.descendant(
          of: find.byType(DashPageHeader),
          matching: find.text('Waste log'),
        ),
        findsOneWidget,
      );
      final export = tester.widget<DashExportButton>(
        inPage(byKey('waste-export')),
      );
      expect(export.enabled, isTrue);
      final record = tester.widget<DashButton>(inPage(byKey('waste-record')));
      expect(record.label, 'Record waste');
      expect(record.icon, 'trash-2');
      expect(record.variant, DashButtonVariant.primary);
    });

    testWidgets('INV-WST-002 the branch\'s log (the server\'s default page) '
        'and the period\'s report', (tester) async {
      final h = await pumpWaste(tester, branch: SeedIds.zamalek);
      final log = h.server.callsTo(logRoute, method: 'GET').single;
      expect(log.path, '/inventory/branches/${SeedIds.zamalek}/waste');
      expect(log.query, isEmpty);
      final scope = h.container.read(currentScopeProvider);
      final report = h.server.callsTo(reportRoute).single;
      expect(report.path, '/reports/branches/${SeedIds.zamalek}/waste-report');
      expect(
        DateTime.parse(report.query['from']!.single),
        DateTime.parse(scope.from),
      );
      expect(
        DateTime.parse(report.query['to']!.single),
        DateTime.parse(scope.to),
      );
      expect(logTable(tester).rows.length, 8);
    });

    testWidgets('INV-WST-002 / INV-WST-030 All branches: the sentinel for '
        'both reads, the org rolled up', (tester) async {
      final h = await pumpWaste(tester);
      expect(
        h.server.callsTo(logRoute).single.path,
        '/inventory/branches/$allBranches/waste',
      );
      expect(
        h.server.callsTo(reportRoute).single.path,
        '/reports/branches/$allBranches/waste-report',
      );
      expect(logTable(tester).rows.length, invWaste.length);
    });

    testWidgets('INV-WST-025 the log does not follow the period; the report '
        'does', (tester) async {
      final h = await pumpWaste(tester, branch: SeedIds.zamalek);
      await h.container
          .read(scopeProvider.notifier)
          .setPreset(ScopePreset.today);
      await h.settle();
      expect(h.server.callsTo(logRoute).length, 1);
      expect(h.server.callsTo(reportRoute).length, 2);
      // Today at Zamalek: 500 ml × 4.5 expired; the Latte's 3,326 + 1,980
      // spoiled; 4 × 900 damaged.
      expect(summary(tester), [
        ('Spoiled', 'EGP 53.06'),
        ('Damaged', 'EGP 36.00'),
        ('Expired', 'EGP 22.50'),
        ('Total this period', 'EGP 111.56'),
      ]);
    });
  });

  group('Record waste', () {
    testWidgets('INV-WST-003 opens the dialog for the branch', (tester) async {
      final h = await pumpWaste(tester, branch: SeedIds.zamalek);
      await h.tap(inPage(byKey('waste-record')));
      final d = tester.widget<RecordWasteDialog>(dialog);
      expect(d.branchId, SeedIds.zamalek);
      expect(d.presetIngredientId, isNull);
    });

    testWidgets('INV-WST-003 / INV-WST-030 hidden with All branches', (
      tester,
    ) async {
      await pumpWaste(tester);
      expect(inPage(byKey('waste-record')), findsNothing);
      expect(inPage(byKey('waste-export')), findsOneWidget);
    });

    testWidgets('INV-WST-003 hidden without inventory.waste.record', (
      tester,
    ) async {
      final s = wasteServer(persona: Persona.manager);
      grantOnly(s.server, Persona.manager, const [
        'inventory.read',
        'inventory.waste.read',
      ]);
      await pumpWaste(
        tester,
        persona: Persona.manager,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(page, findsOneWidget);
      expect(inPage(byKey('waste-record')), findsNothing);
    });

    testWidgets('INV-WST-003 hidden while the capabilities are unknown', (
      tester,
    ) async {
      final s = wasteServer(persona: Persona.manager);
      final gate = s.server.hold('GET', '/authz/me');
      await pumpWaste(
        tester,
        persona: Persona.manager,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(inPage(byKey('waste-record')), findsNothing);
      gate.release();
      await tester.pump();
    });

    testWidgets('INV-WST-003 the manager at Zamalek may record', (
      tester,
    ) async {
      await pumpWaste(
        tester,
        persona: Persona.manager,
        branch: SeedIds.zamalek,
      );
      expect(inPage(byKey('waste-record')), findsOneWidget);
    });
  });

  group('columns', () {
    testWidgets('INV-WST-005…011 the cells of Zamalek\'s log', (tester) async {
      final h = await pumpWaste(tester, branch: SeedIds.zamalek);
      final t = logTable(tester);
      expect(
        [for (final c in t.columns) c.label],
        ['Date', 'Ingredient', 'Quantity', 'Reason', 'By', 'Source'],
      );
      expect([for (final m in t.rows) m.ingredientName], zamalekOrder);
      // INV-WST-005: when it happened; the offline till's line says when it
      // arrived (06 Oct 19:20 Cairo, received 07 Oct 10:05).
      expect(inTable(find.text('06 Oct, 07:20 PM')), findsOneWidget);
      expect(inTable(find.text('Received 07 Oct, 10:05 AM')), findsOneWidget);
      expect(inTable(textHas('Received')), findsOneWidget);
      // INV-WST-007: the Latte's ingredient lines.
      expect(inTable(find.text('From Latte (Medium) × 2')), findsNWidgets(2));
      // INV-WST-008: |quantity| and the unit.
      expect(inTable(find.text('500 ml')), findsOneWidget);
      expect(inTable(find.text('4 pcs')), findsOneWidget);
      // INV-WST-009: reasons in words.
      expect(inTable(find.text('Expired')), findsNWidgets(3));
      expect(inTable(find.text('Spoiled')), findsNWidgets(2));
      expect(inTable(find.text('Theft')), findsOneWidget);
      // INV-WST-010: who, and the manager who approved it on the till.
      expect(inTable(find.text('Approved by Karim Adel')), findsNWidgets(2));
      // INV-WST-011: the source badge; a till's names its device.
      expect(inTable(find.text('Till')), findsNWidgets(4));
      expect(inTable(find.text('Dashboard')), findsNWidgets(4));
      expect(inTable(find.text('Device Counter 1')), findsNWidgets(4));
      final till = tester.widget<SourceBadge>(
        inTable(find.byType(SourceBadge)).first,
      );
      expect(till.filled, isTrue);
      expect(h.server.callsTo(stockRoute), isEmpty);
    });

    testWidgets('INV-WST-006 / INV-WST-011 All branches: the Branch column; '
        'a refund names its order; a voided order is its own source', (
      tester,
    ) async {
      final h = await pumpWaste(tester);
      final t = logTable(tester);
      expect(t.columns[1].label, 'Branch');
      // Page 2 holds the older lines.
      expect(inTable(find.text('Refund')), findsOneWidget);
      await h.tap(inTable(find.bySemanticsLabel('Next')));
      expect(inTable(find.text('Page 2 of 2')), findsOneWidget);
      expect(inTable(find.text('Refund')), findsNothing);
      expect(inTable(find.text('Cocoa Powder')), findsOneWidget);
      await h.tap(inTable(find.bySemanticsLabel('Previous')));
      expect(
        inTable(find.text('Refund of order MD-261006-T1-0031')),
        findsOneWidget,
      );
      expect(inTable(find.text('Refunded sale')), findsOneWidget);
      expect(inTable(find.text('Voided order')), findsNWidgets(2));
      expect(inTable(find.text('Maadi')), findsWidgets);
    });

    testWidgets('INV-WST-011 an older server: no waste_source, the source '
        'type decides', (tester) async {
      final s = wasteServer();
      for (final m in s.db[InvTables.movements].rows) {
        if (m['movement_type'] == 'waste') m['waste_source'] = null;
      }
      await pumpWaste(tester, server: s.server, db: s.db);
      // Seeded source types: pos → Dashboard; refund → Refund; order →
      // Voided order.
      expect(inTable(find.text('Till')), findsNothing);
      expect(inTable(find.text('Refund')), findsOneWidget);
    });
  });

  group('search and paging', () {
    testWidgets('INV-WST-012 search over the raw values (reason code, '
        'signed quantity, recorder); the page\'s empty words on no match', (
      tester,
    ) async {
      final h = await pumpWaste(tester, branch: SeedIds.zamalek);
      final search = inTable(find.byType(DashSearchInput));
      await h.enterText(search, 'expired');
      expect(logTable(tester).rows.length, 8);
      expect(inTable(find.text('Expired')), findsNWidgets(3));
      expect(inTable(find.text('Spoiled')), findsNothing);
      await h.enterText(search, '-500');
      expect(inTable(find.text('500 ml')), findsOneWidget);
      expect(inTable(find.text('500 g')), findsOneWidget);
      expect(inTable(find.text('4 pcs')), findsNothing);
      await h.enterText(search, 'mariam');
      expect(inTable(find.text('Mariam Fathy')), findsNWidgets(2));
      await h.enterText(search, 'Till');
      expect(inTable(find.text('No waste recorded')), findsOneWidget);
    });

    testWidgets('INV-WST-012 ten rows a page over the loaded rows', (
      tester,
    ) async {
      await pumpWaste(tester);
      expect(logTable(tester).pageSize, 10);
      expect(inTable(find.text('Page 1 of 2')), findsOneWidget);
    });
  });

  group('states', () {
    testWidgets('INV-WST-013 loading: skeleton rows, no empty words', (
      tester,
    ) async {
      final s = wasteServer();
      final gate = s.server.hold('GET', logRoute);
      await pumpWaste(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(logTable(tester).loading, isTrue);
      expect(inTable(find.text('No waste recorded')), findsNothing);
      expect(
        tester.widget<DashExportButton>(inPage(byKey('waste-export'))).enabled,
        isFalse,
      );
      gate.release();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(logTable(tester).rows.length, 8);
    });

    testWidgets('INV-WST-013 error: the server\'s words and Retry (only the '
        'log asked again)', (tester) async {
      final s = wasteServer();
      final boom = MockResponse.error(500, 'The waste log is unavailable');
      s.server.fail('GET', logRoute, boom);
      final h = await pumpWaste(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(inTable(find.text("Couldn't load this")), findsOneWidget);
      expect(inTable(find.text(h.refusalWords(boom))), findsOneWidget);
      expect(inTable(find.text('No waste recorded')), findsNothing);
      final reports = h.server.callsTo(reportRoute).length;
      await h.tap(inTable(find.text('Retry')));
      expect(h.server.callsTo(logRoute).length, 2);
      expect(h.server.callsTo(reportRoute).length, reports);
      expect(logTable(tester).rows.length, 8);
    });

    testWidgets('INV-WST-013 empty: "No waste recorded"; Export disabled', (
      tester,
    ) async {
      final h = await pumpWaste(tester, branch: SeedIds.heliopolis);
      expect(inTable(find.text('No waste recorded')), findsOneWidget);
      final empty = tester.widget<DashEmptyState>(
        inTable(find.byType(DashEmptyState)),
      );
      expect(empty.icon, 'trash-2');
      expect(
        tester.widget<DashExportButton>(inPage(byKey('waste-export'))).enabled,
        isFalse,
      );
      expect(h.exports.built, isEmpty);
    });

    testWidgets('INV-ALL-006 a refused log shows the server\'s words', (
      tester,
    ) async {
      final s = wasteServer(persona: Persona.manager);
      final denied = MockResponse.denied('inventory.waste.read');
      s.server.fail('GET', logRoute, denied, times: null);
      final h = await pumpWaste(
        tester,
        persona: Persona.manager,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(inTable(find.text(h.refusalWords(denied))), findsOneWidget);
    });
  });

  group('by reason', () {
    testWidgets('INV-WST-024 / INV-WST-025 per reason, largest value first, '
        'and the period\'s total', (tester) async {
      await pumpWaste(tester, branch: SeedIds.zamalek);
      expect(inReasons(find.text('By reason')), findsOneWidget);
      final lines = tester
          .widgetList<DashSummaryLine>(inReasons(find.byType(DashSummaryLine)))
          .toList();
      // expired: 500 ml × 4.5 + 250 g × 20 + 500 g × 18 = 162.50;
      // spoiled: 36 g × 92.4 (3,326.4 → 3,326) + 440 ml × 4.5 = 53.06;
      // theft: 20 g × 250 = 50.00; damaged: 4 × 900 = 36.00;
      // other: 100 g × 25 = 25.00. Total 326.56.
      expect(
        [for (final l in lines) (l.label, l.value, l.emphasis)],
        [
          ('Expired', 'EGP 162.50', false),
          ('Spoiled', 'EGP 53.06', false),
          ('Theft', 'EGP 50.00', false),
          ('Damaged', 'EGP 36.00', false),
          ('Other', 'EGP 25.00', false),
          ('Total this period', 'EGP 326.56', true),
        ],
      );
    });

    testWidgets('INV-WST-025 a reason with no cost reads "—"', (tester) async {
      final s = wasteServer();
      s.db[InvTables.ingredients].find(
        InvIds.ingredient('cocoa'),
      )!['cost_per_unit'] = null;
      for (final m in s.db[InvTables.movements].rows) {
        if (m['org_ingredient_id'] == InvIds.ingredient('cocoa')) {
          m
            ..['unit_cost'] = null
            ..['unit_cost_exact'] = null;
        }
      }
      await pumpWaste(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(summary(tester), contains(('Other', '—')));
      expect(summary(tester).last, ('Total this period', 'EGP 301.56'));
    });

    testWidgets('INV-WST-026 loading: four skeleton line pairs', (
      tester,
    ) async {
      final s = wasteServer();
      final gate = s.server.hold('GET', reportRoute);
      await pumpWaste(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(inReasons(byKey('waste-reasons-loading')), findsOneWidget);
      expect(inReasons(find.byType(DashSkeleton)), findsNWidgets(8));
      gate.release();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('INV-WST-027 error: its own title and Retry, no server line', (
      tester,
    ) async {
      final s = wasteServer();
      final boom = MockResponse.error(500, 'Reports are down');
      s.server.fail('GET', reportRoute, boom);
      final h = await pumpWaste(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(
        inReasons(find.text("Couldn't load waste by reason")),
        findsOneWidget,
      );
      expect(inReasons(find.text(h.refusalWords(boom))), findsNothing);
      final logs = h.server.callsTo(logRoute).length;
      await h.tap(inReasons(find.text('Retry')));
      expect(h.server.callsTo(reportRoute).length, 2);
      expect(h.server.callsTo(logRoute).length, logs);
      expect(inReasons(find.text('Total this period')), findsOneWidget);
    });

    testWidgets('INV-ALL-015 a till event refetches the report, not the log', (
      tester,
    ) async {
      final h = await pumpWaste(tester, branch: SeedIds.zamalek);
      int n(String r) => h.server.callsTo(r, method: 'GET').length;
      final reports = n(reportRoute);
      final logs = n(logRoute);
      h.realtime.current!.emit('till.closed', data: '{}');
      await h.settle();
      expect(n(reportRoute), reports + 1);
      expect(n(logRoute), logs);
    });

    testWidgets('INV-WST-028 empty in this period', (tester) async {
      await pumpWaste(tester, branch: SeedIds.heliopolis);
      expect(
        inReasons(
          find.text(
            'Waste by reason appears once waste is logged in this period.',
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('layout', () {
    testWidgets('INV-WST-029 ≥ 1024: the log beside the reasons, 2 : 1', (
      tester,
    ) async {
      await pumpWaste(tester, branch: SeedIds.zamalek);
      final log = tester.getRect(table);
      final side = tester.getRect(reasons);
      expect(side.top, log.top);
      expect(side.left, greaterThan(log.right));
      expect(log.width / side.width, closeTo(2, 0.15));
    });

    testWidgets('INV-WST-029 below 1024: stacked, the log first', (
      tester,
    ) async {
      await pumpWaste(tester, branch: SeedIds.zamalek, size: DashSize.phone);
      expect(
        tester.getTopLeft(reasons).dy,
        greaterThan(tester.getBottomLeft(table).dy),
      );
    });

    testWidgets('INV-WST-029 phone: cards led by the ingredient', (
      tester,
    ) async {
      await pumpWaste(tester, branch: SeedIds.zamalek, size: DashSize.phone);
      final ing = logTable(
        tester,
      ).columns.firstWhere((c) => c.id == 'ingredient_name');
      expect(ing.phone, DashPhoneRole.title);
      expect(inTable(find.text('Columns')), findsNothing);
    });

    testWidgets('INV-WST-029 desktop: a Columns menu lists the columns', (
      tester,
    ) async {
      final h = await pumpWaste(tester);
      await h.tap(inTable(find.text('Columns')));
      for (final c in [
        'Date',
        'Branch',
        'Ingredient',
        'Quantity',
        'Reason',
        'By',
        'Source',
      ]) {
        expect(find.text(c), findsWidgets, reason: c);
      }
    });
  });

  group('export', () {
    testWidgets('INV-WST-004 walks the whole log as an export and files it '
        'as Madar-Waste', (tester) async {
      final h = await pumpWaste(tester, branch: SeedIds.zamalek);
      await h.tap(inPage(byKey('waste-export')));
      final walk = h.server.callsTo(logRoute).skip(1).toList();
      expect([for (final c in walk) c.query['offset']!.single], ['0', '8']);
      for (final c in walk) {
        expect(c.query['limit'], ['500']);
        expect(c.headers['X-Madar-Export'], '1');
      }
      await h.expectToast('Exported 8 rows');
      final sheet = h.exports.built.single.sheets.single;
      expect(sheet.name, 'Waste log');
      expect(sheet.title, 'Waste log');
      expect(
        [for (final c in sheet.columns) c.header],
        [
          'Date',
          'Received',
          'Ingredient',
          'Quantity',
          'Unit',
          'Reason',
          'By',
          'Approved by',
          'Menu item',
          'Source',
          'Device',
          'Order',
        ],
      );
      expect([for (final r in sheet.rows) r[2]], zamalekOrder);
      final latte = sheet.rows.first;
      expect(latte[1], isNull, reason: 'received within 5 minutes');
      expect(latte[3], 440);
      expect(latte[4], 'ml');
      expect(latte[5], 'Spoiled');
      expect(latte[6], 'Youssef Samir');
      expect(latte[7], 'Karim Adel');
      expect(latte[8], 'Latte');
      expect(latte[9], 'Till');
      expect(latte[10], 'Counter 1');
      final whipped = sheet.rows.firstWhere((r) => r[2] == 'Whipped Cream');
      expect(whipped[1], isNotNull, reason: 'received a day late');
      final cocoa = sheet.rows.last;
      expect(cocoa[7], '');
      expect(cocoa[8], '');
      expect(cocoa[9], 'Dashboard');
      expect(h.files.saved.single.filename, 'Madar-Waste-2026-10-08.xlsx');
    });

    testWidgets('INV-WST-004 / INV-ALL-014 All branches walks the sentinel; '
        'a failing walk toasts the server\'s words', (tester) async {
      final s = wasteServer();
      final h = await pumpWaste(tester, server: s.server, db: s.db);
      final boom = MockResponse.error(500, 'Export throttled');
      s.server.fail('GET', logRoute, boom);
      await h.tap(inPage(byKey('waste-export')));
      expect(
        h.server.callsTo(logRoute).last.path,
        '/inventory/branches/$allBranches/waste',
      );
      await h.expectToast(h.refusalWords(boom));
      expect(h.exports.built, isEmpty);
      expect(
        tester.widget<DashExportButton>(inPage(byKey('waste-export'))).loading,
        isFalse,
      );
    });

    testWidgets('INV-ALL-012 spinner while exporting', (tester) async {
      final h = await pumpWaste(tester, branch: SeedIds.zamalek);
      final hold = Completer<void>();
      h.exports.hold = hold.future;
      await h.tap(inPage(byKey('waste-export')));
      expect(find.text('Gathering data…'), findsOneWidget);
      expect(
        tester.widget<DashExportButton>(inPage(byKey('waste-export'))).loading,
        isTrue,
      );
      hold.complete();
      await h.settle();
      await h.expectToast('Exported 8 rows');
    });
  });

  group('refusals', () {
    testWidgets('INV-ALL-006 (divergence) limited (no inventory.waste.read): '
        'Restricted, no reads', (tester) async {
      final h = await pumpWaste(tester, persona: Persona.limited);
      expect(page, findsNothing);
      expect(find.byType(Restricted), findsOneWidget);
      expect(h.server.callsTo(logRoute), isEmpty);
      expect(h.server.callsTo(reportRoute), isEmpty);
    });

    testWidgets('INV-ALL-005 dawamOnly: not part of this business\'s plan', (
      tester,
    ) async {
      final h = await pumpWaste(tester, persona: Persona.dawamOnly);
      h.allowUnmatched = true;
      expect(page, findsNothing);
      expect(find.text("Not part of this business's plan"), findsOneWidget);
    });

    testWidgets('manager at All branches: only Zamalek rolls up', (
      tester,
    ) async {
      await pumpWaste(tester, persona: Persona.manager);
      final rows = logTable(tester).rows;
      expect(rows.length, 8);
      expect(rows.every((m) => m.branchId == SeedIds.zamalek), isTrue);
    });
  });
}
