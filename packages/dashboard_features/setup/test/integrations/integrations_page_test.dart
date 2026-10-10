// The Integrations pane: gates, header, stats, table, search, states
// (SET-INT-001..010, 029, 031).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/integrations/integrations_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('gates', () {
    testWidgets('SET-INT-001 without integrations.read: the lock, and the '
        'list is never asked', (tester) async {
      final h = await pumpIntegrations(tester, persona: Persona.manager);
      final pane = find.byKey(const ValueKey('integrations-restricted'));
      expect(
        find.descendant(of: pane, matching: find.text('Integrations')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: pane,
          matching: find.text('Not available on this account'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: pane,
          matching: find.text(h.t('common.restrictedBody')),
        ),
        findsOneWidget,
      );
      expect(listCalls(h), 0);
    });

    testWidgets('SET-INT-001 a read-only cashier is refused too', (
      tester,
    ) async {
      final h = await pumpIntegrations(tester, persona: Persona.limited);
      expect(
        find.byKey(const ValueKey('integrations-restricted')),
        findsOneWidget,
      );
      expect(listCalls(h), 0);
    });

    testWidgets('SET-INT-002 a platform admin with no org picked: "Select an '
        'organization", nothing asked', (tester) async {
      final h = await pumpIntegrations(
        tester,
        persona: Persona.platform,
        pickOrg: false,
      );
      expect(pageText('Integrations'), findsOneWidget);
      expect(
        inPage(find.byKey(const ValueKey('integrations-pick-org'))),
        findsOneWidget,
      );
      expect(pageText('Select an organization'), findsOneWidget);
      expect(pageText('Issue credential'), findsNothing);
      expect(listCalls(h), 0);
    });

    testWidgets('SET-INT-031 (divergence) nothing shows until the grants '
        'are known: no lock flashes first', (tester) async {
      final m = integrationsServer();
      final gate = m.server.hold('GET', '/authz/me');
      final h = await pumpIntegrations(tester, backend: m);
      expect(
        find.byKey(const ValueKey('integrations-restricted')),
        findsNothing,
      );
      expect(listCalls(h), 0);
      gate.release();
      await h.settle();
      expect(
        find.byKey(const ValueKey('integrations-restricted')),
        findsNothing,
      );
      expect(
        inPage(find.byKey(const ValueKey('integrations-table'))),
        findsOneWidget,
      );
      expect(listCalls(h), 1);
    });
  });

  group('header', () {
    testWidgets('SET-INT-003 SET-INT-004 an org admin audits: the read-only '
        'description, no Issue button', (tester) async {
      final h = await pumpIntegrations(tester);
      expect(pageText(h.t('integrations.hintReadOnly')), findsOneWidget);
      expect(pageText(h.t('integrations.hint')), findsNothing);
      expect(pageText('Issue credential'), findsNothing);
    });

    testWidgets('SET-INT-003 SET-INT-004 a platform admin: the issuing '
        'description and "Issue credential" → ?edit=new', (tester) async {
      final h = await pumpIntegrations(tester, persona: Persona.platform);
      expect(
        pageText(
          "Give a partner read-only access to one branch's order "
          'analytics.',
        ),
        findsOneWidget,
      );
      expect(pageText(h.t('integrations.hintReadOnly')), findsNothing);
      await h.tap(inPage(find.byKey(const ValueKey('integrations-issue'))));
      expect(h.location.queryParameters['edit'], 'new');
      expect(top('New integration credential'), findsOneWidget);
    });
  });

  group('stats and table', () {
    testWidgets('SET-INT-005 Total, Active, Revoked from the list', (
      tester,
    ) async {
      final h = await pumpIntegrations(tester);
      expect(stat(tester, 'integrations-total').label, 'Total');
      expect(stat(tester, 'integrations-total').value, 3);
      expect(stat(tester, 'integrations-active').label, 'Active');
      expect(stat(tester, 'integrations-active').value, 2);
      expect(stat(tester, 'integrations-revoked').label, 'Revoked');
      expect(stat(tester, 'integrations-revoked').value, 1);
      expect(listCalls(h), 1);
    });

    testWidgets('SET-INT-005 SET-INT-008 loading: stat skeletons and the '
        'table skeleton, never "no integrations"', (tester) async {
      final m = integrationsServer();
      final gate = m.server.hold('GET', IntegrationsRoutes.list);
      final h = await pumpIntegrations(tester, backend: m);
      expect(stat(tester, 'integrations-total').loading, isTrue);
      expect(stat(tester, 'integrations-revoked').loading, isTrue);
      expect(
        tester
            .widget<DashDataTable<Object?>>(
              find.byKey(const ValueKey('integrations-table')),
            )
            .loading,
        isTrue,
      );
      expect(pageText('No integrations yet'), findsNothing);
      gate.release();
      await h.settle();
      expect(stat(tester, 'integrations-total').loading, isFalse);
      expect(inTable(find.text('Rue — One Ninety')), findsOneWidget);
    });

    testWidgets('SET-INT-006 Label (name + username), Branch, Last used '
        '(date-time or Never), Status', (tester) async {
      final h = await pumpIntegrations(tester);
      for (final header in ['LABEL', 'BRANCH', 'LAST USED', 'STATUS']) {
        expect(inTable(find.text(header)), findsOneWidget, reason: header);
      }
      expect(inTable(find.text('Rue — One Ninety')), findsOneWidget);
      expect(inTable(find.text('rue-one-ninety-k7m2xq')), findsOneWidget);
      expect(inTable(find.text('Zamalek')), findsOneWidget);
      expect(inTable(find.text('Heliopolis')), findsOneWidget);
      // Used two hours before the mock's now (2026-10-08 10:00 Cairo).
      final fmt = h.container.read(formatProvider);
      final used = fmt.fmtDateTime(DateTime.utc(2026, 10, 8, 5));
      expect(inTable(find.text(used)), findsOneWidget);
      // Talabat has never called; Cairo Analytics' last call shows.
      expect(inTable(find.text('Never')), findsOneWidget);
      expect(inTable(find.text('Active')), findsNWidgets(2));
      expect(inTable(find.text('Revoked')), findsOneWidget);
      // Newest first: Talabat (12 days), Rue (41), Cairo Analytics (96).
      double y(String s) => tester.getTopLeft(inTable(find.text(s))).dy;
      expect(y('Talabat Insights'), lessThan(y('Rue — One Ninety')));
      expect(y('Rue — One Ninety'), lessThan(y('Cairo Analytics Co.')));
    });

    testWidgets('SET-INT-007 search: the label and the branch, case-blind; '
        'never the username', (tester) async {
      final h = await pumpIntegrations(tester);
      final search = inTable(find.byType(EditableText));
      expect(inTable(find.text('Search')), findsOneWidget);
      await h.enterText(search, 'ZAMA');
      expect(inTable(find.text('Rue — One Ninety')), findsOneWidget);
      expect(inTable(find.text('Talabat Insights')), findsNothing);
      await h.enterText(search, 'insights');
      expect(inTable(find.text('Talabat Insights')), findsOneWidget);
      expect(inTable(find.text('Rue — One Ninety')), findsNothing);
      await h.enterText(search, 'k7m2xq');
      expect(inTable(find.text('Rue — One Ninety')), findsNothing);
    });

    testWidgets('SET-INT-007 Last used is not searched when the first row '
        'was never used', (tester) async {
      final h = await pumpIntegrations(tester);
      await h.enterText(inTable(find.byType(EditableText)), '2026-10-08');
      expect(inTable(find.text('Rue — One Ninety')), findsNothing);
    });

    testWidgets('SET-INT-007 Last used is searched by its raw timestamp when '
        'the first row was used', (tester) async {
      final m = integrationsServer();
      m.db[IntegrationsSeed.table].delete(IntegrationsSeed.id('talabat'));
      final h = await pumpIntegrations(tester, backend: m);
      await h.enterText(inTable(find.byType(EditableText)), '2026-10-08t05');
      expect(inTable(find.text('Rue — One Ninety')), findsOneWidget);
      expect(inTable(find.text('Cairo Analytics Co.')), findsNothing);
    });

    testWidgets('SET-INT-007 ten a page', (tester) async {
      final m = integrationsServer();
      final t = m.db[IntegrationsSeed.table];
      for (var i = 0; i < 9; i++) {
        t.insert({
          'org_id': SeedIds.sabahOrg,
          'branch_id': SeedIds.maadi,
          'name': 'Partner $i',
          'username': 'partner-$i-abcdef',
          'created_at': DateTime.utc(2026, 1, 1 + i).toIso8601String(),
          'last_used_at': null,
          'revoked_at': null,
        }, timestamps: false);
      }
      await pumpIntegrations(tester, backend: m);
      expect(
        tester
            .widget<DashDataTable<Object?>>(
              find.byKey(const ValueKey('integrations-table')),
            )
            .pageSize,
        10,
      );
      expect(stat(tester, 'integrations-total').value, 12);
      expect(inTable(find.text('Partner 0')), findsNothing);
    });

    testWidgets('SET-INT-008 a failed load: "Couldn\'t load this", the '
        'words, Retry asks again; no stats meanwhile', (tester) async {
      final m = integrationsServer();
      final boom = MockResponse.error(500, 'The database is restarting');
      m.server.fail('GET', IntegrationsRoutes.list, boom, times: null);
      final h = await pumpIntegrations(tester, backend: m);
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      expect(inPage(find.text(h.refusalWords(boom))), findsOneWidget);
      expect(find.byKey(const ValueKey('integrations-total')), findsNothing);
      expect(pageText('No integrations yet'), findsNothing);
      m.server.clearFailures();
      await h.tap(inPage(find.text('Retry')));
      expect(listCalls(h), 2);
      expect(inTable(find.text('Rue — One Ninety')), findsOneWidget);
      expect(stat(tester, 'integrations-total').value, 3);
    });

    testWidgets('SET-INT-009 empty: the key and "No integrations yet"', (
      tester,
    ) async {
      final m = integrationsServer();
      m.db[IntegrationsSeed.table].clear();
      final h = await pumpIntegrations(tester, backend: m);
      expect(pageText('No integrations yet'), findsOneWidget);
      expect(pageText(h.t('integrations.emptyHint')), findsOneWidget);
      expect(stat(tester, 'integrations-total').value, 0);
    });

    testWidgets('SET-INT-010 a platform admin gets Rotate and Revoke on live '
        'credentials only', (tester) async {
      await pumpIntegrations(tester, persona: Persona.platform);
      for (final key in ['rue', 'talabat']) {
        final id = IntegrationsSeed.id(key);
        expect(find.byKey(ValueKey('integrations-rotate-$id')), findsOneWidget);
        expect(find.byKey(ValueKey('integrations-revoke-$id')), findsOneWidget);
      }
      final revoked = IntegrationsSeed.id('cairo-analytics');
      expect(
        find.byKey(ValueKey('integrations-rotate-$revoked')),
        findsNothing,
      );
      expect(inTable(find.bySemanticsLabel('Rotate')), findsNWidgets(2));
      expect(inTable(find.bySemanticsLabel('Revoke')), findsNWidgets(2));
    });

    testWidgets('SET-INT-010 an org admin sees no actions at all', (
      tester,
    ) async {
      await pumpIntegrations(tester);
      expect(inTable(find.bySemanticsLabel('Rotate')), findsNothing);
      expect(inTable(find.bySemanticsLabel('Revoke')), findsNothing);
      expect(
        tester
            .widget<DashDataTable<Object?>>(
              find.byKey(const ValueKey('integrations-table')),
            )
            .rowActions,
        isNull,
      );
    });
  });

  group('phone', () {
    testWidgets('SET-INT-029 cards titled by the label and username; the '
        'three stats stay in one row', (tester) async {
      await pumpIntegrations(
        tester,
        persona: Persona.platform,
        size: DashSize.phone,
      );
      final ys = {
        for (final k in [
          'integrations-total',
          'integrations-active',
          'integrations-revoked',
        ])
          tester.getTopLeft(find.byKey(ValueKey(k))).dy,
      };
      expect(ys, hasLength(1));
      expect(inTable(find.text('Rue — One Ninety')), findsOneWidget);
      expect(inTable(find.text('rue-one-ninety-k7m2xq')), findsOneWidget);
      expect(find.byType(IntegrationsPage), findsOneWidget);
      expect(inTable(find.bySemanticsLabel('Rotate')), findsWidgets);
    });
  });
}
