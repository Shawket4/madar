// Menu profitability's flags and margin target: the flag popover and its
// Fix / Dismiss / Snooze, and the target editor (REP-FIN-029…041, 072).
import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/financial/fin_profitability.dart';
import 'package:dashboard_reports/src/mock/financial_mock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The first ledger row carrying a [kind] flag.
MarginLedgerRow rowWith(DashHarness h, String kind) =>
    served(h).rows.firstWhere((r) => r.flags.any((f) => f.kind == kind));

Finder chipOf(MarginLedgerRow r, String kind) =>
    find.byKey(ValueKey('flag-${r.menuItemId}-${r.sizeLabel}-$kind'));

/// Opens [kind]'s flag on [r] (Flagged only first, so it is on page 1).
Future<void> openFlag(DashHarness h, MarginLedgerRow r, String kind) async {
  final flagged = find.byKey(const ValueKey('fin-flagged-only'));
  if (!h.tester.widget<DashSwitch>(flagged).value) await h.tap(flagged);
  await h.scrollUntilVisible(chipOf(r, kind), scrollable: pageScroll);
  await h.tap(chipOf(r, kind));
}

DashButton button(WidgetTester t, String label) =>
    t.widget<DashButton>(find.widgetWithText(DashButton, label).last);

Finder get trigger => find.byKey(const ValueKey('fin-target-trigger'));

void main() {
  setUpAll(ensureTimeZones);

  group('flags', () {
    testWidgets('REP-FIN-029/034/035 a flag is a toned pill; its popover '
        'says why and offers Fix, Dismiss and Snooze', (t) async {
      final h = await pumpFin(t);
      final r = rowWith(h, 'below_target');
      await h.tap(find.byKey(const ValueKey('fin-flagged-only')));
      final pill = t.widget<DashStatusPill>(
        find.descendant(
          of: chipOf(r, 'below_target'),
          matching: find.byType(DashStatusPill),
        ),
      );
      expect(pill.label, 'Below target');
      expect(pill.tone, DashTone.warning);
      await h.tap(chipOf(r, 'below_target'));
      final s = r.flags.firstWhere((f) => f.kind == 'below_target');
      final f = h.container.read(formatProvider);
      String pct(Object? v) =>
          f.fmtNumber(v! as num, const NumberOptions(maximumFractionDigits: 1));
      expect(
        find.text(
          'Margin ${pct(s.params['margin_pct'])}% is under the '
          '${pct(s.params['target_pct'])}% target',
        ),
        findsOneWidget,
      );
      for (final (label, icon) in [
        ('Fix', 'wrench'),
        ('Dismiss', 'x'),
        ('Snooze', 'bell-off'),
      ]) {
        expect(button(t, label).icon, icon);
        expect(button(t, label).onPressed, isNotNull);
      }
      expect(button(t, 'Fix').variant, DashButtonVariant.primary);
      expect(button(t, 'Dismiss').variant, DashButtonVariant.outline);
      await h.shot('financial/flag-open');
    });

    testWidgets('REP-FIN-034 the other kinds\' pills: cost spike (warning), '
        'no recipe (neutral)', (t) async {
      final h = await pumpFin(t);
      await h.tap(find.byKey(const ValueKey('fin-flagged-only')));
      for (final (kind, label, tone) in [
        ('cost_spike', 'Cost spike', DashTone.warning),
        ('recipe_incomplete', 'No recipe', DashTone.neutral),
      ]) {
        final r = rowWith(h, kind);
        await h.scrollUntilVisible(chipOf(r, kind), scrollable: pageScroll);
        final pill = t.widget<DashStatusPill>(
          find.descendant(
            of: chipOf(r, kind),
            matching: find.byType(DashStatusPill),
          ),
        );
        expect((pill.label, pill.tone), (label, tone));
      }
    });

    testWidgets('REP-FIN-030 Fix records "acted" with the evidence and goes '
        'straight to Pricing; the decision then refreshes /insights', (
      t,
    ) async {
      final s = finServer();
      final gate = s.server.hold('POST', decisionsRoute);
      final h = await pumpFin(t, server: s.server, db: s.db);
      h.allowUnmatched = true;
      final r = rowWith(h, 'below_target');
      final sig = r.flags.firstWhere((f) => f.kind == 'below_target');
      await openFlag(h, r, 'below_target');
      await h.tap(find.widgetWithText(DashButton, 'Fix'));
      // Navigated without waiting for the decision.
      expect(h.location.path, '/menu/pricing');
      final post = callsTo(h, decisionsRoute, method: 'POST').single;
      expect(post.query['org_id'], [SeedIds.sabahOrg]);
      expect(post.body, {
        'action': 'acted',
        'branch_id': null,
        'detail': sig.params,
        'menu_item_id': r.menuItemId,
        'signal_kind': 'below_target',
        'size_label': r.sizeLabel,
      });
      final epoch = h.container.read(
        realtimeEpochProvider('/insights/decisions'),
      );
      gate.release();
      await h.settle();
      expect(
        h.container.read(realtimeEpochProvider('/insights/decisions')),
        epoch + 1,
      );
    });

    testWidgets('REP-FIN-030 a recipe flag\'s Fix opens the item on its '
        'recipe tab', (t) async {
      final h = await pumpFin(t);
      h.allowUnmatched = true;
      final r = rowWith(h, 'recipe_incomplete');
      await openFlag(h, r, 'recipe_incomplete');
      await h.tap(find.widgetWithText(DashButton, 'Fix'));
      expect(h.location.toString(), '/menu/items/${r.menuItemId}?tab=recipe');
    });

    testWidgets('REP-FIN-030 a branch picked rides on the decision', (t) async {
      final h = await pumpFin(t, branchId: SeedIds.heliopolis);
      h.allowUnmatched = true;
      final r = rowWith(h, 'cost_spike');
      await openFlag(h, r, 'cost_spike');
      await h.tap(find.widgetWithText(DashButton, 'Fix'));
      expect(
        (callsTo(h, decisionsRoute, method: 'POST').single.body!
            as Map)['branch_id'],
        SeedIds.heliopolis,
      );
      // A cost spike's fix is the recipe.
      expect(h.location.toString(), '/menu/items/${r.menuItemId}?tab=recipe');
    });

    testWidgets('REP-FIN-029/031 Dismiss waits for the server (every button '
        'disabled meanwhile), then the flag is gone and the popover closed', (
      t,
    ) async {
      final s = finServer();
      final h = await pumpFin(t, server: s.server, db: s.db);
      final r = rowWith(h, 'below_target');
      final gate = s.server.hold('POST', decisionsRoute);
      await openFlag(h, r, 'below_target');
      await h.tap(find.widgetWithText(DashButton, 'Dismiss'));
      for (final b in ['Fix', 'Dismiss', 'Snooze']) {
        expect(button(t, b).onPressed, isNull, reason: b);
      }
      expect(
        (callsTo(h, decisionsRoute, method: 'POST').single.body!
            as Map)['action'],
        'dismissed',
      );
      final ledgers = callsTo(h, ledgerRoute).length;
      gate.release();
      await h.settle();
      expect(callsTo(h, ledgerRoute), hasLength(ledgers + 1));
      expect(chipOf(r, 'below_target'), findsNothing);
      expect(find.widgetWithText(DashButton, 'Dismiss'), findsNothing);
    });

    testWidgets('REP-FIN-032 Snooze records "snoozed" and silences the flag', (
      t,
    ) async {
      final h = await pumpFin(t);
      final r = rowWith(h, 'cost_spike');
      await openFlag(h, r, 'cost_spike');
      await h.tap(find.widgetWithText(DashButton, 'Snooze'));
      expect(
        (callsTo(h, decisionsRoute, method: 'POST').single.body!
            as Map)['action'],
        'snoozed',
      );
      expect(chipOf(r, 'cost_spike'), findsNothing);
    });

    testWidgets('REP-FIN-030 a refused Fix still navigates and shows no '
        'toast', (t) async {
      final h = await pumpFin(t, persona: Persona.manager);
      h.allowUnmatched = true;
      final r = rowWith(h, 'below_target');
      await openFlag(h, r, 'below_target');
      await h.tap(find.widgetWithText(DashButton, 'Fix'));
      expect(h.location.path, '/menu/pricing');
      await h.flushTimers();
      expect(find.text('Something went wrong'), findsNothing);
    });

    testWidgets('REP-FIN-033 a refused decision (the manager may not edit '
        'the menu) toasts "Something went wrong" and closes', (t) async {
      final h = await pumpFin(t, persona: Persona.manager);
      final r = rowWith(h, served(h).rows.expand((x) => x.flags).first.kind);
      final kind = r.flags.first.kind;
      await openFlag(h, r, kind);
      await h.tap(find.widgetWithText(DashButton, 'Dismiss'));
      await h.expectToast('Something went wrong');
      expect(find.widgetWithText(DashButton, 'Dismiss'), findsNothing);
      // Nothing was silenced.
      expect(chipOf(r, kind), findsOneWidget);
    });
  });

  group('margin target', () {
    testWidgets('REP-FIN-036 the trigger names its source: org, branch, or '
        'the built-in default', (t) async {
      await pumpFin(t);
      expect(pageText('Org target 68%'), findsOneWidget);
      expect(
        t
            .widget<DashIcon>(
              find.descendant(of: trigger, matching: find.byType(DashIcon)),
            )
            .name,
        'target',
      );
    });

    testWidgets('REP-FIN-036 Zamalek: "Branch target 72%"', (t) async {
      await pumpFin(t, branchId: SeedIds.zamalek);
      expect(pageText('Branch target 72%'), findsOneWidget);
    });

    testWidgets('REP-FIN-036 nothing set: "Default 60% — set yours"', (
      t,
    ) async {
      final s = finServer();
      s.db.lazyTable(finTargetsTable, () => []);
      await pumpFin(t, server: s.server, db: s.db);
      expect(pageText('Default 60% — set yours'), findsOneWidget);
    });

    testWidgets('REP-FIN-037 the targets are read on open, skeletons while '
        'loading, then seeded: the org default and the branch override', (
      t,
    ) async {
      final s = finServer();
      final h = await pumpFin(
        t,
        server: s.server,
        db: s.db,
        branchId: SeedIds.zamalek,
      );
      expect(callsTo(h, targetsRoute), isEmpty);
      final gate = s.server.hold('GET', targetsRoute);
      await h.tap(trigger);
      expect(find.text('Margin target'), findsOneWidget);
      expect(
        find.text('Rows under this gross-margin bar get flagged.'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(FinTargetForm),
          matching: find.byType(DashSkeleton),
        ),
        findsNWidgets(2),
      );
      gate.release();
      await h.settle();
      expect(callsTo(h, targetsRoute).single.query['org_id'], [
        SeedIds.sabahOrg,
      ]);
      final org = t.widget<DashTextInput>(
        find.byKey(const ValueKey('fin-target-org')),
      );
      final branch = t.widget<DashTextInput>(
        find.byKey(const ValueKey('fin-target-branch')),
      );
      expect((org.value, branch.value), ('68', '72'));
      expect(org.textDirection, TextDirection.ltr);
      expect(org.placeholder, '60');
      expect(branch.placeholder, '68');
      expect(button(t, 'Save').onPressed, isNull, reason: 'nothing changed');
    });

    testWidgets('REP-FIN-039 with All branches only the org field shows', (
      t,
    ) async {
      final h = await pumpFin(t);
      await h.tap(trigger);
      expect(find.byKey(const ValueKey('fin-target-org')), findsOneWidget);
      expect(find.byKey(const ValueKey('fin-target-branch')), findsNothing);
      expect(find.text('This branch %'), findsNothing);
    });

    testWidgets('REP-FIN-038/040 0, 100 and letters are invalid; empty means '
        'unchanged; Save needs a valid change', (t) async {
      final h = await pumpFin(t);
      await h.tap(trigger);
      final field = find.byKey(const ValueKey('fin-target-org'));
      for (final bad in ['0', '100', '-5']) {
        await h.enterText(field, bad);
        expect(t.widget<DashTextInput>(field).invalid, isTrue, reason: bad);
        expect(button(t, 'Save').onPressed, isNull, reason: bad);
      }
      await h.enterText(field, '');
      expect(t.widget<DashTextInput>(field).invalid, isFalse);
      expect(button(t, 'Save').onPressed, isNull);
      await h.enterText(field, '55.5');
      expect(button(t, 'Save').onPressed, isNotNull);
    });

    testWidgets('REP-FIN-040 Save puts the org default, then the branch '
        'override, toasts, closes and re-ranks the ledger', (t) async {
      final h = await pumpFin(t, branchId: SeedIds.zamalek);
      await h.tap(trigger);
      await h.enterText(find.byKey(const ValueKey('fin-target-org')), '70');
      await h.enterText(
        find.byKey(const ValueKey('fin-target-branch')),
        '75.5',
      );
      final ledgers = callsTo(h, ledgerRoute).length;
      await h.tap(find.widgetWithText(DashButton, 'Save'));
      final puts = callsTo(h, targetsRoute, method: 'PUT');
      expect(
        [for (final p in puts) p.body],
        [
          {'target_pct': 70.0},
          {'branch_id': SeedIds.zamalek, 'target_pct': 75.5},
        ],
      );
      await h.expectToast('Changes saved');
      expect(find.byType(FinTargetForm), findsNothing);
      expect(callsTo(h, ledgerRoute), hasLength(ledgers + 1));
      expect(pageText('Branch target 75.5%'), findsOneWidget);
    });

    testWidgets('REP-FIN-040 only what changed is sent', (t) async {
      final h = await pumpFin(t, branchId: SeedIds.zamalek);
      await h.tap(trigger);
      await h.enterText(find.byKey(const ValueKey('fin-target-branch')), '80');
      await h.tap(find.widgetWithText(DashButton, 'Save'));
      expect(
        [for (final p in callsTo(h, targetsRoute, method: 'PUT')) p.body],
        [
          {'branch_id': SeedIds.zamalek, 'target_pct': 80.0},
        ],
      );
      await h.flushTimers();
    });

    testWidgets('REP-FIN-041 a failed save toasts "Something went wrong" and '
        'stays open', (t) async {
      final s = finServer();
      s.server.fail('PUT', targetsRoute, MockResponse.error(500, 'boom'));
      final h = await pumpFin(t, server: s.server, db: s.db);
      await h.tap(trigger);
      await h.enterText(find.byKey(const ValueKey('fin-target-org')), '70');
      await h.tap(find.widgetWithText(DashButton, 'Save'));
      await h.expectToast('Something went wrong');
      expect(find.byType(FinTargetForm), findsOneWidget);
      expect(button(t, 'Save').onPressed, isNotNull);
    });

    testWidgets('REP-FIN-041 the manager may not move the target: refused, '
        'the same words', (t) async {
      final h = await pumpFin(t, persona: Persona.manager);
      await h.tap(trigger);
      await h.enterText(find.byKey(const ValueKey('fin-target-org')), '70');
      await h.tap(find.widgetWithText(DashButton, 'Save'));
      await h.expectToast('Something went wrong');
    });

    testWidgets('REP-FIN-040 (divergence) the org default saved before a '
        'failed branch PUT is shown: /insights is refreshed', (t) async {
      final s = finServer();
      final h = await pumpFin(
        t,
        server: s.server,
        db: s.db,
        branchId: SeedIds.zamalek,
      );
      await h.tap(trigger);
      await h.enterText(find.byKey(const ValueKey('fin-target-org')), '70');
      await h.enterText(find.byKey(const ValueKey('fin-target-branch')), '75');
      final ledgers = callsTo(h, ledgerRoute).length;
      final targets = callsTo(h, targetsRoute).length;
      var n = 0;
      s.server.on('PUT', targetsRoute, (req) {
        if (n++ == 1) req.fail(MockResponse.error(500, 'boom'));
        s.db[finTargetsTable].put({
          'id': 'org:${SeedIds.sabahOrg}',
          'org_id': SeedIds.sabahOrg,
          'branch_id': null,
          'target_pct': 70,
        });
        return MockResponse.ok({
          'org_default_pct': 70,
          'branches': <Object?>[],
          'builtin_default_pct': 60,
        });
      });
      await h.tap(find.widgetWithText(DashButton, 'Save'));
      await h.expectToast('Something went wrong');
      expect(find.byType(FinTargetForm), findsOneWidget);
      expect(callsTo(h, ledgerRoute), hasLength(ledgers + 1));
      expect(callsTo(h, targetsRoute), hasLength(targets + 1));
    });
  });

  testWidgets('REP-FIN-072 (divergence) Fix keeps the scope: the branch and '
      'period stay picked', (t) async {
    final h = await pumpFin(t, branchId: SeedIds.maadi);
    h.allowUnmatched = true;
    await h.container
        .read(scopeProvider.notifier)
        .setPreset(ScopePreset.last7Days);
    await h.settle();
    final r = rowWith(h, 'below_target');
    await openFlag(h, r, 'below_target');
    await h.tap(find.widgetWithText(DashButton, 'Fix'));
    expect(h.location.path, '/menu/pricing');
    final scope = h.container.read(currentScopeProvider);
    expect(
      (scope.branchId, scope.preset),
      (SeedIds.maadi, ScopePreset.last7Days),
    );
  });
}
