// Menu profitability's Repricing and Decisions tabs (REP-FIN-046…053).
import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/financial/fin_data.dart';
import 'package:dashboard_reports/src/financial/fin_insights_tabs.dart';
import 'package:dashboard_reports/src/mock/financial_mock.dart';
import 'package:design_system/design_system.dart' show MadarColorsX;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder get repricing => find.byType(FinRepricingTab);
Finder get decisions => find.byKey(const ValueKey('fin-decisions'));

Finder inRepricing(Finder f) => find.descendant(of: repricing, matching: f);
Finder inDecisions(Finder f) => find.descendant(of: decisions, matching: f);

/// Replaces the repricing handler with the real answer edited by [edit].
void repricingAnswer(
  ({MockServer server, MockDb db}) s,
  Map<String, Object?> Function(Map<String, Object?> json) edit,
) => s.server.on('GET', repricingRoute, (req) {
  final r = finRepricing(s.db, SeedIds.sabahOrg, req.param('branch_id'));
  return MockResponse.ok(edit(r.toJson()));
});

List<FinDecision> shownDecisions(DashHarness h, {String? branchId}) => h
    .container
    .read(finDecisionsProvider((orgId: SeedIds.sabahOrg, branchId: branchId)))
    .requireValue;

void main() {
  setUpAll(ensureTimeZones);

  group('repricing', () {
    testWidgets('REP-FIN-046 read on open, for the scope branch', (t) async {
      final h = await pumpFin(t, branchId: SeedIds.newCairo);
      expect(callsTo(h, repricingRoute), isEmpty);
      await openInner(h, 'Repricing');
      expect(
        callsTo(h, repricingRoute).single.path,
        '/insights/branches/${SeedIds.newCairo}/repricing',
      );
    });

    testWidgets('REP-FIN-046 loading: a skeleton line and skeleton rows', (
      t,
    ) async {
      final s = finServer();
      final gate = s.server.hold('GET', repricingRoute);
      final h = await pumpFin(t, server: s.server, db: s.db);
      await openInner(h, 'Repricing');
      expect(inRepricing(find.byType(DashSkeleton)), findsWidgets);
      expect(
        inRepricing(find.text('No repricing opportunities')),
        findsNothing,
      );
      gate.release();
      await h.settle();
      expect(inRepricing(find.text('Adjust prices')), findsOneWidget);
    });

    testWidgets('REP-FIN-046 a failure: "Couldn\'t load repricing '
        'suggestions" and Retry', (t) async {
      final s = finServer();
      s.server.fail('GET', repricingRoute, MockResponse.error(500, 'boom'));
      final h = await pumpFin(t, server: s.server, db: s.db);
      await openInner(h, 'Repricing');
      expect(
        inRepricing(find.text("Couldn't load repricing suggestions")),
        findsOneWidget,
      );
      await h.tap(inRepricing(find.text('Retry')));
      expect(callsTo(h, repricingRoute), hasLength(2));
      expect(inRepricing(find.text('Adjust prices')), findsOneWidget);
      await h.shot('financial/repricing-failed');
    });

    testWidgets('REP-FIN-047 the coverage line and Adjust prices', (t) async {
      final s = finServer();
      final h = await pumpFin(t, server: s.server, db: s.db);
      h.allowUnmatched = true;
      await openInner(h, 'Repricing');
      final r = finRepricing(s.db, SeedIds.sabahOrg, allBranchesId);
      expect(
        inRepricing(
          find.text(
            'Target 68% · ${r.skusConsidered - r.skusCostUnknown} of '
            '${r.skusConsidered} priced items have full cost',
          ),
        ),
        findsOneWidget,
      );
      await h.tap(inRepricing(find.text('Adjust prices')));
      expect(h.location.toString(), '/menu/pricing');
    });

    testWidgets('REP-FIN-048 the columns; a below-cost row warns; ten rows a '
        'page', (t) async {
      final s = finServer();
      repricingAnswer(s, (j) {
        final first = (j['suggestions']! as List).first as Map;
        first['below_cost'] = true;
        first['size_label'] = 'Large';
        return j;
      });
      final h = await pumpFin(t, server: s.server, db: s.db);
      await openInner(h, 'Repricing');
      for (final c in [
        'ITEM',
        'CURRENT',
        'COST',
        'MARGIN',
        'SUGGESTED',
        'UPLIFT',
      ]) {
        expect(inRepricing(find.text(c)), findsOneWidget, reason: c);
      }
      final r = finRepricing(s.db, SeedIds.sabahOrg, allBranchesId);
      final first = r.suggestions.first;
      final f = h.container.read(formatProvider);
      final row = find.ancestor(
        of: inRepricing(find.text(first.itemName)).first,
        matching: find.byType(Wrap),
      );
      expect(
        find.descendant(of: row.first, matching: find.byType(DashIcon)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row.first, matching: find.text('Large')),
        findsOneWidget,
      );
      final c = t.element(repricing).madarColors;
      final pct = inRepricing(figure(f.fmtPercent(first.marginPct / 100)));
      expect(
        t.widget<Text>(pct.first).style!.color,
        DashTone.danger.foreground(c),
      );
      expect(
        inRepricing(figure(f.fmtMoney(first.suggestedPrice))),
        findsWidgets,
      );
      if (r.suggestions.length > 10) {
        expect(
          inRepricing(
            find.text('Page 1 of ${(r.suggestions.length / 10).ceil()}'),
          ),
          findsOneWidget,
        );
      }
      expect(inRepricing(find.text('Columns')), findsNothing);
    });

    testWidgets('REP-FIN-049 nothing to reprice, cost gaps: "Add recipe '
        'costs…"', (t) async {
      final s = finServer();
      repricingAnswer(s, (j) => j..['suggestions'] = <Object?>[]);
      final h = await pumpFin(t, server: s.server, db: s.db);
      await openInner(h, 'Repricing');
      expect(
        inRepricing(find.text('No repricing opportunities')),
        findsOneWidget,
      );
      expect(
        inRepricing(
          find.text('Add recipe costs to more items to unlock suggestions.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('REP-FIN-049 nothing to reprice, all costed: "Every costed '
        'item is at or above its target margin."', (t) async {
      final s = finServer();
      repricingAnswer(
        s,
        (j) => j
          ..['suggestions'] = <Object?>[]
          ..['skus_cost_unknown'] = 0,
      );
      final h = await pumpFin(t, server: s.server, db: s.db);
      await openInner(h, 'Repricing');
      expect(
        inRepricing(
          find.text('Every costed item is at or above its target margin.'),
        ),
        findsOneWidget,
      );
    });
  });

  group('decisions', () {
    testWidgets('REP-FIN-050 the log and the org\'s users; narrowed to the '
        'branch when one is picked', (t) async {
      final h = await pumpFin(t);
      await openInner(h, 'Decisions');
      expect(callsTo(h, decisionsRoute).single.query, {
        'org_id': [SeedIds.sabahOrg],
      });
      expect(callsTo(h, usersRoute).single.query['org_id'], [SeedIds.sabahOrg]);
    });

    testWidgets('REP-FIN-050 a branch: &branch_id', (t) async {
      final h = await pumpFin(t, branchId: SeedIds.zamalek);
      await openInner(h, 'Decisions');
      expect(callsTo(h, decisionsRoute).single.query['branch_id'], [
        SeedIds.zamalek,
      ]);
      final rows = shownDecisions(h, branchId: SeedIds.zamalek);
      expect(rows.map((r) => r.d.branchId).toSet(), {SeedIds.zamalek});
    });

    testWidgets('REP-FIN-051 the columns: item, signal pill, action, when '
        'with who, and a hidden status header', (t) async {
      final h = await pumpFin(t);
      await openInner(h, 'Decisions');
      for (final c in [
        'ITEM',
        'SIGNAL',
        'ACTION',
        'WHEN',
        'QTY/DAY',
        'MARGIN %',
      ]) {
        expect(inDecisions(find.text(c)), findsOneWidget, reason: c);
      }
      expect(inDecisions(find.text('STATUS')), findsNothing);
      final rows = shownDecisions(h);
      final f = h.container.read(formatProvider);
      for (final r in rows) {
        expect(inDecisions(find.text(r.d.itemName)), findsWidgets);
        expect(
          inDecisions(figure(f.fmtDateTime(r.d.createdAt.toIso8601String()))),
          findsOneWidget,
        );
      }
      expect(inDecisions(find.text('Nour El-Sayed')), findsWidgets);
      expect(inDecisions(find.text('Karim Adel')), findsOneWidget);
      expect(inDecisions(find.text('Fixed')), findsWidgets);
      expect(inDecisions(find.text('Dismissed')), findsOneWidget);
      expect(inDecisions(find.text('Snoozed')), findsWidgets);
      final pill = t.widget<DashStatusPill>(
        inDecisions(find.widgetWithText(DashStatusPill, 'No sales')),
      );
      expect(pill.tone, DashTone.neutral);
    });

    testWidgets('REP-FIN-051 a complete measurement wears a check named '
        '"Measurement complete"', (t) async {
      final h = await pumpFin(t);
      await openInner(h, 'Decisions');
      final done = shownDecisions(h).where((r) => r.d.impactComplete).length;
      expect(done, greaterThan(0));
      expect(
        inDecisions(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics && w.properties.label == 'Measurement complete',
          ),
        ),
        findsNWidgets(done),
      );
    });

    testWidgets('REP-FIN-052 before → after: Qty/day to 2 dp, Margin % as a '
        'percent; "Measuring…" before any impact', (t) async {
      final h = await pumpFin(t);
      await openInner(h, 'Decisions');
      final f = h.container.read(formatProvider);
      final rows = shownDecisions(h);
      final fresh = rows.where((r) => r.measuring).toList();
      expect(fresh, isNotEmpty);
      expect(inDecisions(find.text('Measuring…')), findsNWidgets(fresh.length));
      final r = rows.firstWhere((x) => !x.measuring);
      double n(Map<String, Object?> m, String k) => (m[k]! as num).toDouble();
      final before = n(r.d.baseline, 'qty_per_day');
      final after = n(r.d.impact, 'qty_per_day');
      String q(double v) =>
          f.fmtNumber(v, const NumberOptions(maximumFractionDigits: 2));
      final cell = find.ancestor(
        of: inDecisions(figure(q(after))).first,
        matching: find.byType(FinBeforeAfter),
      );
      expect(
        find.descendant(of: cell, matching: figure(q(before))),
        findsOneWidget,
      );
      final c = t.element(decisions).madarColors;
      final tone = after > before
          ? DashTone.success.foreground(c)
          : after < before
          ? DashTone.danger.foreground(c)
          : c.textSecondary;
      expect(
        t
            .widget<Text>(find.descendant(of: cell, matching: figure(q(after))))
            .style!
            .color,
        tone,
      );
      expect(
        inDecisions(figure(f.fmtPercent(n(r.d.baseline, 'margin_pct') / 100))),
        findsWidgets,
      );
    });

    testWidgets('REP-FIN-053 loading rows, then an error with Retry', (
      t,
    ) async {
      final s = finServer();
      final gate = s.server.hold('GET', decisionsRoute);
      final h = await pumpFin(t, server: s.server, db: s.db);
      await openInner(h, 'Decisions');
      expect(inDecisions(find.byType(DashSkeleton)), findsWidgets);
      expect(inDecisions(find.text('No decisions yet')), findsNothing);
      gate.release();
      await h.settle();
      s.server.fail(
        'GET',
        decisionsRoute,
        MockResponse.error(500, 'Log down.'),
      );
      h.container.invalidate(finDecisionsProvider);
      await h.settle();
      expect(
        inDecisions(
          find.text(h.refusalWords(MockResponse.error(500, 'Log down.'))),
        ),
        findsOneWidget,
      );
      await h.tap(inDecisions(find.text('Retry')));
      expect(inDecisions(find.text('Measuring…')), findsWidgets);
    });

    testWidgets('REP-FIN-053 empty: "No decisions yet" and how to start', (
      t,
    ) async {
      final s = finServer();
      s.db.lazyTable(finDecisionsTable, () => []);
      final h = await pumpFin(t, server: s.server, db: s.db);
      await openInner(h, 'Decisions');
      expect(inDecisions(find.text('No decisions yet')), findsOneWidget);
      expect(
        inDecisions(
          find.text(
            'Fix, dismiss or snooze a flag on the ledger and its measured '
            'impact shows up here.',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('REP-FIN-053 ten rows a page', (t) async {
      final s = finServer();
      final h = await pumpFin(t, server: s.server, db: s.db);
      for (var i = 0; i < 8; i++) {
        await s.server.send(
          ApiRequest(
            method: 'POST',
            path: decisionsRoute,
            query: {
              'org_id': [SeedIds.sabahOrg],
            },
            body: {
              'menu_item_id': MockSeed.menuItemId('latte'),
              'size_label': 'Regular',
              'signal_kind': 'below_target',
              'action': 'snoozed',
            },
          ),
        );
      }
      await openInner(h, 'Decisions');
      expect(shownDecisions(h), hasLength(13));
      expect(inDecisions(find.text('Page 1 of 2')), findsOneWidget);
    });

    testWidgets('REP-FIN-050 a person who may not list users still sees the '
        'log, without names', (t) async {
      final s = finServer();
      authzCaps(s.server, Persona.owner, drop: {Cap.staffUsersRead});
      s.server.fail(
        'GET',
        usersRoute,
        MockResponse.denied('staff.users.read'),
        times: null,
      );
      final h = await pumpFin(t, server: s.server, db: s.db);
      await openInner(h, 'Decisions');
      expect(inDecisions(find.text('Lemon Tart')), findsOneWidget);
      expect(inDecisions(find.text('Nour El-Sayed')), findsNothing);
    });
  });
}
