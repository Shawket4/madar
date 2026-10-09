// Stock counts: the page through the real shell — header, actions, the
// first-run card, the history table and its states, export, All branches,
// and who may see what (INV-CNT-001…017, -056, -058, -059).
import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' show Stocktake;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const String _all = '00000000-0000-0000-0000-000000000000';

/// The history table's rows, top to bottom, as their Started cells read.
List<String> startedColumn(WidgetTester tester) {
  final rows = tester.widget<DashDataTable<Stocktake>>(table).rows;
  final started = [
    for (final s in rows)
      tester
          .widget<DashDataTable<Stocktake>>(table)
          .columns
          .first
          .text!(s),
  ];
  for (final s in started) {
    expect(inTable(find.text(s)), findsWidgets, reason: s);
  }
  return started;
}

void main() {
  group('header and actions', () {
    testWidgets('INV-CNT-001/002 title, subtitle, Export and Start a count; '
        'the branch\'s list is read', (tester) async {
      final h = await pumpCounts(tester, branch: SeedIds.zamalek);
      expect(inPage(find.text('Stock counts')), findsOneWidget);
      expect(
        inPage(find.text('Count the shelf; everything else follows from the count.')),
        findsOneWidget,
      );
      expect(inPage(byKey('counts-export')), findsOneWidget);
      expect(inPage(find.text('Start a count')), findsOneWidget);
      final calls = h.server.callsTo(listRoute, method: 'GET');
      expect(calls.single.path, '/stocktakes/branches/${SeedIds.zamalek}');
      expect(h.server.callsTo(getRoute), isEmpty, reason: 'no open count');
      expect(h.server.callsTo(catalogRoute), isEmpty);
      expect(h.server.callsTo(categoriesRoute), isEmpty);
      // The muted All-branches line is not there with a branch.
      expect(textHas('Select a branch to start a count'), findsNothing);
    });

    testWidgets('INV-CNT-003 / INV-CNT-056 All branches: the hint, the '
        'sentinel read, no Start, no first-run card, no editor', (tester) async {
      final h = await pumpCounts(tester);
      expect(
        inPage(
          find.text(
            "Select a branch to start a count. The list below shows every "
            "branch's counts.",
          ),
        ),
        findsOneWidget,
      );
      expect(
        h.server.callsTo(listRoute).single.path,
        '/stocktakes/branches/$_all',
      );
      expect(inPage(find.text('Start a count')), findsNothing);
      expect(inPage(byKey('counts-first-run-card')), findsNothing);
      expect(editor, findsNothing);
      expect(h.server.callsTo(getRoute), isEmpty);
    });

    testWidgets('INV-CNT-004 Start shows while the list loads and after it '
        'failed (no open count is known), not with one open', (tester) async {
      final s = countsServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpCounts(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.newCairo,
      );
      expect(inPage(find.text('Start a count')), findsOneWidget);
      gate.release();
      await h.settle();
      expect(inPage(find.text('Start a count')), findsNothing);
      expect(editor, findsOneWidget);
    });

    testWidgets('INV-CNT-004 a failed list still offers Start; the click '
        'opens the scope dialog on Whole branch', (tester) async {
      final s = countsServer();
      s.server.fail(
        'GET',
        listRoute,
        MockResponse.error(500, 'Counts are resting'),
        times: null,
      );
      final h = await pumpCounts(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.newCairo,
      );
      expect(inPage(find.text('Start a count')), findsOneWidget);
      await h.tap(inPage(byKey('counts-start')));
      expect(scopeDialog, findsOneWidget);
      expect(
        inScope(find.text('Whole branch — every ingredient')),
        findsOneWidget,
      );
      expect(inScope(find.text('What do you want to count?')), findsOneWidget);
    });
  });

  group('first run', () {
    testWidgets('INV-CNT-006 a branch never counted: the card, and its button '
        'opens the scope dialog', (tester) async {
      final h = await pumpCounts(tester, branch: SeedIds.heliopolis);
      expect(
        inPage(find.text('This branch has never been counted')),
        findsOneWidget,
      );
      expect(
        inPage(textHas('Start with a whole-branch count.')),
        findsOneWidget,
      );
      await h.tap(inPage(byKey('counts-first-run')));
      expect(scopeDialog, findsOneWidget);
    });

    testWidgets('INV-CNT-006 only a cancelled count still reads as never '
        'counted; not while loading; not with a finalized one', (tester) async {
      final s = countsServer();
      s.db[InvTables.stocktakes].removeWhere(
        (r) => r['branch_id'] == SeedIds.zamalek && r['status'] == 'finalized',
      );
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpCounts(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(inPage(byKey('counts-first-run-card')), findsNothing);
      gate.release();
      await h.settle();
      expect(inPage(byKey('counts-first-run-card')), findsOneWidget);
    });

    testWidgets('INV-CNT-006 a counted branch has no card', (tester) async {
      await pumpCounts(tester, branch: SeedIds.zamalek);
      expect(inPage(byKey('counts-first-run-card')), findsNothing);
    });
  });

  group('history table', () {
    testWidgets('INV-CNT-007/008 an open count: the editor above the table; '
        'the table holds only the closed counts', (tester) async {
      await pumpCounts(tester, branch: SeedIds.newCairo);
      expect(editor, findsOneWidget);
      final editorTop = tester.getTopLeft(editor).dy;
      expect(tester.getTopLeft(table).dy, greaterThan(editorTop));
      expect(startedColumn(tester), ['12 Sept, 11:15 PM']);
      expect(inTable(find.text('In progress')), findsNothing);
    });

    testWidgets('INV-CNT-008/009/010/011/012/013/014 All branches: every '
        'count, newest first, with its branch, scope, by, status and '
        'finalized', (tester) async {
      await pumpCounts(tester);
      expect(inTable(find.text('BRANCH')), findsOneWidget);
      expect(startedColumn(tester), [
        '08 Oct, 08:15 AM',
        '04 Oct, 10:50 PM',
        '30 Sept, 11:00 PM',
        '27 Sept, 10:00 PM',
        '20 Sept, 09:40 PM',
        '12 Sept, 11:15 PM',
        '02 Sept, 10:30 PM',
      ]);
      // The open one: In progress (accent), no finalized date.
      final pills = tester
          .widgetList<DashStatusPill>(inTable(find.byType(DashStatusPill)))
          .toList();
      expect(pills.first.label, 'In progress');
      expect(pills.first.tone, DashTone.accent);
      expect(
        {for (final p in pills) p.label: p.tone},
        {
          'In progress': DashTone.accent,
          'Finalized': DashTone.success,
          'Cancelled': DashTone.danger,
        },
      );
      expect(inTable(find.text('New Cairo')), findsNWidgets(2));
      expect(inTable(textHas('Whole branch · ${ltr('9/25')}')), findsOneWidget);
      expect(inTable(textHas('By category · ${ltr('1/2')}')), findsOneWidget);
      expect(inTable(textHas('Selected items · ${ltr('2/2')}')), findsOneWidget);
      expect(inTable(find.text('Dina Fouad')), findsNWidgets(2));
      expect(inTable(find.text('Karim Adel')), findsNWidgets(3));
      // Finalized: a date, or "—" for the open and the cancelled one.
      expect(inTable(find.text('04 Oct, 11:10 PM')), findsOneWidget);
      expect(inTable(find.text('—')), findsNWidgets(2));
    });

    testWidgets('INV-CNT-010 no Branch column with a branch', (tester) async {
      await pumpCounts(tester, branch: SeedIds.zamalek);
      expect(inTable(find.text('BRANCH')), findsNothing);
      expect(startedColumn(tester), [
        '04 Oct, 10:50 PM',
        '27 Sept, 10:00 PM',
        '20 Sept, 09:40 PM',
      ]);
    });

    testWidgets('INV-CNT-011 a count with no item figures shows the scope '
        'alone; by nobody reads "—"', (tester) async {
      final s = countsServer();
      final st = s.db[InvTables.stocktakes].find(zamalekCancelled)!;
      st['started_by_name'] = null;
      s.db[InvTables.stocktakeItems].removeWhere(
        (i) => i['stocktake_id'] == zamalekCancelled,
      );
      await pumpCounts(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      // total_items 0 is still a figure: "· 0/0".
      expect(inTable(textHas('By category · ${ltr('0/0')}')), findsOneWidget);
      expect(inTable(find.text('—')), findsNWidgets(2));
    });

    testWidgets('INV-CNT-015/016 View report only on finalized rows; the '
        'button and a tap on the row open the report', (tester) async {
      final h = await pumpCounts(tester, branch: SeedIds.zamalek);
      expect(inTable(find.text('View report')), findsNWidgets(2));
      expect(inTable(byKey('counts-report-$zamalekCancelled')), findsNothing);
      await h.tap(inTable(byKey('counts-report-$zamalekMilk')));
      expect(report, findsOneWidget);
      expect(
        h.server.callsTo(reportRoute).single.path,
        '/stocktakes/$zamalekMilk/variance-report',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(report, findsNothing);
      // A tap on the cancelled row does nothing; on a finalized one opens.
      await h.tap(inTable(find.text('27 Sept, 10:00 PM')));
      expect(report, findsNothing);
      await h.tap(inTable(find.text('20 Sept, 09:40 PM')));
      expect(report, findsOneWidget);
      expect(
        h.server.callsTo(reportRoute).last.path,
        '/stocktakes/$zamalekFull/variance-report',
      );
    });

    testWidgets('INV-CNT-016 Enter on a focused finalized row opens it; on '
        'the cancelled row nothing', (tester) async {
      final h = await pumpCounts(tester, branch: SeedIds.zamalek);
      Future<void> focusRow(String text) async {
        Focus.of(tester.element(inTable(find.text(text)))).requestFocus();
        await h.settle();
      }

      await focusRow('27 Sept, 10:00 PM');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await h.settle();
      expect(report, findsNothing);
      await focusRow('04 Oct, 10:50 PM');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await h.settle();
      expect(report, findsOneWidget);
    });

    testWidgets('INV-CNT-058 the Columns menu lists the history columns', (
      tester,
    ) async {
      final h = await pumpCounts(tester);
      await h.tap(inPage(find.text('Columns')));
      for (final c in [
        'Started',
        'Branch',
        'Scope',
        'By',
        'Status',
        'Finalized',
      ]) {
        expect(find.text(c), findsWidgets, reason: c);
      }
      // Hiding a column takes it off the table.
      expect(inTable(find.text('BY')), findsOneWidget);
      await h.tap(find.text('By').last);
      expect(inTable(find.text('BY')), findsNothing);
    });
  });

  group('history states', () {
    testWidgets('INV-CNT-017 loading: skeleton rows, never "No counts yet"', (
      tester,
    ) async {
      final s = countsServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpCounts(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.heliopolis,
      );
      expect(inPage(find.text('No counts yet')), findsNothing);
      expect(inTable(find.byType(DashSkeleton)), findsWidgets);
      gate.release();
      await h.settle();
      expect(inPage(find.text('No counts yet')), findsOneWidget);
    });

    testWidgets('INV-CNT-017 error: "Couldn\'t load this", the server\'s '
        'words, Retry reads only the list again', (tester) async {
      final s = countsServer();
      final boom = MockResponse.error(500, 'Counts are resting');
      s.server.fail('GET', listRoute, boom, times: null);
      final h = await pumpCounts(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(inTable(find.text("Couldn't load this")), findsOneWidget);
      expect(inTable(find.text(h.refusalWords(boom))), findsOneWidget);
      expect(inPage(find.text('No counts yet')), findsNothing);
      final before = h.server.calls.length;
      s.server.clearFailures();
      await h.tap(inTable(find.text('Retry')));
      expect(h.server.calls.length, before + 1);
      expect(h.server.calls.last.template, listRoute);
      expect(inTable(find.text('Karim Adel')), findsNWidgets(3));
    });

    testWidgets('INV-CNT-017 empty: "No counts yet" and its hint', (
      tester,
    ) async {
      await pumpCounts(tester, branch: SeedIds.heliopolis);
      expect(inTable(find.text('No counts yet')), findsOneWidget);
      expect(
        inTable(find.text("Start a count to bring this branch's stock to life.")),
        findsOneWidget,
      );
      final empty = tester.widget<DashEmptyState>(
        inTable(find.byType(DashEmptyState)),
      );
      expect(empty.icon, 'clipboard-list');
    });
  });

  group('export', () {
    testWidgets('INV-CNT-005 with a branch: its closed counts, six columns, '
        'the file name, the toasts', (tester) async {
      final h = await pumpCounts(tester, branch: SeedIds.zamalek);
      await h.tap(inPage(byKey('counts-export')));
      await h.expectToast('Exported 3 rows');
      final spec = h.exports.built.single;
      final sheet = spec.sheets.single;
      expect(sheet.name, 'Stock counts');
      expect(sheet.title, 'Stock counts');
      expect([for (final c in sheet.columns) c.header], [
        'Started',
        'By',
        'Scope',
        'Status',
        'Finalized',
        'Note',
      ]);
      expect([for (final c in sheet.columns) c.width], [20, 20, 16, 14, 20, 30]);
      expect([for (final r in sheet.rows) r.sublist(1, 4)], [
        ['Karim Adel', 'By category', 'Finalized'],
        ['Karim Adel', 'By category', 'Cancelled'],
        ['Karim Adel', 'Whole branch', 'Finalized'],
      ]);
      expect(sheet.rows[1][4], isNull, reason: 'never finalized: blank');
      expect(sheet.rows[1][5], 'Started by mistake');
      expect(sheet.rows[0][5], '');
      expect(sheet.rows[0][0], isNotNull);
      expect(
        h.files.saved.single.filename,
        'Madar-Stocktakes-2026-10-08.xlsx',
      );
    });

    testWidgets('INV-CNT-005 All branches: every closed count, no Branch '
        'column; disabled with nothing closed', (tester) async {
      final h = await pumpCounts(tester);
      await h.tap(inPage(byKey('counts-export')));
      await h.expectToast('Exported 6 rows');
      final sheet = h.exports.built.single.sheets.single;
      expect(sheet.columns, hasLength(6));
      expect(
        sheet.rows.where((r) => r[3] == 'In progress'),
        isEmpty,
        reason: 'the open count is left out',
      );
    });

    testWidgets('INV-CNT-005 nothing closed at the branch: disabled', (
      tester,
    ) async {
      await pumpCounts(tester, branch: SeedIds.heliopolis);
      expect(
        tester.widget<DashExportButton>(inPage(byKey('counts-export'))).enabled,
        isFalse,
      );
    });

    testWidgets('INV-ALL-012/013 spinner while exporting; "Export failed"', (
      tester,
    ) async {
      final h = await pumpCounts(tester, branch: SeedIds.zamalek);
      final hold = Completer<void>();
      h.exports.hold = hold.future;
      await h.tap(inPage(byKey('counts-export')));
      expect(find.text('Gathering data…'), findsOneWidget);
      expect(
        tester.widget<DashExportButton>(inPage(byKey('counts-export'))).loading,
        isTrue,
      );
      hold.complete();
      h.exports.hold = null;
      await h.settle();
      await h.flushTimers();
      h.exports.failNext = StateError('disk full');
      await h.tap(inPage(byKey('counts-export')));
      await h.expectToast('Export failed');
    });
  });

  group('who sees what', () {
    testWidgets('INV-ALL-006 (divergence) limited (no inventory.counts.read): '
        'the shell\'s Restricted, nothing read', (tester) async {
      final h = await pumpCounts(tester, persona: Persona.limited);
      expect(page, findsNothing);
      expect(find.byType(Restricted), findsOneWidget);
      expect(h.server.callsTo(listRoute), isEmpty);
    });

    testWidgets('INV-ALL-005 dawamOnly: not part of this business\'s plan', (
      tester,
    ) async {
      final h = await pumpCounts(tester, persona: Persona.dawamOnly);
      h.allowUnmatched = true;
      expect(page, findsNothing);
      expect(find.text("Not part of this business's plan"), findsOneWidget);
      expect(h.server.callsTo(listRoute), isEmpty);
    });

    testWidgets('INV-CNT-059 manager: All branches lists only what the '
        'manager may see', (tester) async {
      final h = await pumpCounts(tester, persona: Persona.manager);
      expect(inPage(find.text('Start a count')), findsNothing);
      expect(inTable(find.text('Karim Adel')), findsNWidgets(3));
      expect(inTable(find.text('Dina Fouad')), findsNothing);
      expect(h.server.callsTo(listRoute).single.path, '/stocktakes/branches/$_all');
    });

    testWidgets('INV-CNT-017 a refused list shows the server\'s words', (
      tester,
    ) async {
      final s = countsServer();
      final denied = MockResponse.denied('inventory.counts.read');
      s.server.fail('GET', listRoute, denied, times: null);
      final h = await pumpCounts(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(inTable(find.text(h.refusalWords(denied))), findsOneWidget);
    });

    testWidgets('INV-ALL-027 platform with no org: the page renders and '
        'reads the all-branches list (no organization guard)', (tester) async {
      final h = await pumpCounts(tester, persona: Persona.platform);
      expect(page, findsOneWidget);
      expect(inPage(find.text('Stock counts')), findsOneWidget);
      expect(
        h.server.callsTo(listRoute).single.path,
        '/stocktakes/branches/$_all',
      );
    });

    testWidgets('platform in Sabah: every branch\'s counts', (tester) async {
      await pumpCounts(tester, persona: Persona.platform, prefs: sabahPicked());
      expect(startedColumn(tester), hasLength(7));
    });
  });
}
