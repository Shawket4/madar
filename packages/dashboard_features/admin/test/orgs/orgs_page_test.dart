// The Organizations page (ADM-ORG-001..024): the list, its stats, search,
// columns, pages, export, delete, the editor in the address, and its
// loading / empty / error / refused states, driven through the real shell on
// the mock server.
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder _stat(String key, String text) => find.descendant(
  of: find.byKey(ValueKey('orgs-stat-$key')),
  matching: find.text(text),
);

DashButton _button(WidgetTester tester, String label) => tester.widget(
  find.byWidgetPredicate((w) => w is DashButton && w.label == label),
);

Finder _inSidebar(String s) =>
    find.descendant(of: find.byType(DashSidebar), matching: find.text(s));

/// Scrolls the sidebar (it builds lazily) until [label] shows.
Future<void> _scrollSidebarTo(DashHarness h, String label) =>
    h.scrollUntilVisible(
      _inSidebar(label),
      delta: 120,
      scrollable: find
          .descendant(
            of: find.byType(DashSidebar),
            matching: find.byType(Scrollable),
          )
          .first,
    );

Finder _inConfirm(String text) => find.descendant(
  of: find.byType(DashConfirmDialog),
  matching: find.text(text),
);

void main() {
  group('the list', () {
    testWidgets('ADM-ORG-001 the sidebar and the palette offer Organizations '
        'to a platform admin', (tester) async {
      final h = await pumpOrgs(tester);
      await _scrollSidebarTo(h, 'Organizations');
      expect(_inSidebar('Organizations'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await h.settle();
      expect(find.byType(DashCommandPalette), findsOneWidget);
      await h.enterText(find.byType(DashCommandPalette), 'Organ');
      expect(
        find.descendant(
          of: find.byType(DashCommandPalette),
          matching: find.text('Organizations'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('ADM-ORG-001 an owner is not offered Organizations', (
      tester,
    ) async {
      final h = await pumpOrgs(tester, persona: Persona.owner);
      // Branches follows Organizations in the Admin group.
      await _scrollSidebarTo(h, 'Branches');
      expect(_inSidebar('Branches'), findsOneWidget);
      expect(_inSidebar('Organizations'), findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await h.settle();
      await h.enterText(find.byType(DashCommandPalette), 'Organ');
      expect(
        find.descendant(
          of: find.byType(DashCommandPalette),
          matching: find.text('Organizations'),
        ),
        findsNothing,
      );
    });

    testWidgets('ADM-ORG-002 the header: title, subtitle, Export and New', (
      tester,
    ) async {
      final h = await pumpOrgs(tester);
      expect(find.text('Organizations'), findsWidgets);
      expect(
        find.text('Manage all coffee brands and franchises'),
        findsOneWidget,
      );
      expect(find.text('Export Excel'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
      expect(h.t('orgs.subtitle'), 'Manage all coffee brands and franchises');
    });

    testWidgets('ADM-ORG-003 every organization loads, the switched-off one '
        'too', (tester) async {
      final h = await pumpOrgs(tester);
      final reads = h.server.callsTo('/orgs', method: 'GET');
      expect(reads, isNotEmpty);
      expect(reads.every((c) => c.status == 200), isTrue);
      for (final name in [
        'Layali Bistro',
        'Nakhla Bakery',
        'Qahwa Corner',
        'Sabah Coffee',
      ]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
    });

    testWidgets('ADM-ORG-005 the stats: total, active, inactive, average tax '
        '(a percent, one decimal)', (tester) async {
      final s = orgsServer();
      s.db['orgs'].update(AdminSeed.layaliOrg, {'tax_rate': 0.12});
      final h = await pumpOrgs(tester, server: s.server, db: s.db);
      expect(_stat('total', '4'), findsOneWidget);
      expect(_stat('active', '3'), findsOneWidget);
      expect(_stat('inactive', '1'), findsOneWidget);
      expect(_stat('avg-tax', '13.5%'), findsOneWidget);
      expect(h.t('orgs.avgTax'), 'Avg Tax');
      expect(find.text('Avg Tax'), findsOneWidget);
    });

    testWidgets('ADM-ORG-006 the Name cell: the logo or the first two '
        'letters, the name, the slug', (tester) async {
      final s = orgsServer();
      s.db['orgs'].update(SeedIds.sabahOrg, {
        'logo_url': 'data:image/png;base64,${base64Png()}',
      });
      await pumpOrgs(tester, server: s.server, db: s.db);
      expect(find.text('LA'), findsOneWidget);
      expect(find.text('QA'), findsOneWidget);
      expect(find.text('SA'), findsNothing, reason: 'Sabah shows its logo');
      expect(find.byType(Image), findsWidgets);
      expect(find.text('layali-bistro'), findsOneWidget);
      expect(find.text('sabah-coffee'), findsOneWidget);
    });

    testWidgets('ADM-ORG-007 / 008 / 009 / 010 currency badge, tax rate, '
        'custom branding and status', (tester) async {
      final s = orgsServer();
      s.db['orgs'].update(AdminSeed.layaliOrg, {
        'tax_rate': 0.145,
        'currency_code': 'USD',
      });
      await pumpOrgs(tester, server: s.server, db: s.db);
      expect(
        find.descendant(of: find.byType(DashBadge), matching: textHas('USD')),
        findsOneWidget,
      );
      // Mono badges isolate their text (LTR inside Arabic).
      expect(
        find.descendant(of: find.byType(DashBadge), matching: textHas('EGP')),
        findsNWidgets(3),
      );
      expect(textHas('14.5%'), findsOneWidget);
      expect(textHas('14%'), findsNWidgets(3));
      // Sabah is on the branding tier; the others are not.
      expect(
        find.descendant(
          of: find.byType(DashStatusPill),
          matching: find.text('On'),
        ),
        findsOneWidget,
      );
      expect(find.text('Off'), findsNWidgets(3));
      expect(
        find.descendant(
          of: find.byType(DashStatusPill),
          matching: find.text('Active'),
        ),
        findsNWidgets(3),
      );
      expect(
        find.descendant(
          of: find.byType(DashStatusPill),
          matching: find.text('Inactive'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('ADM-ORG-011 search reads the name, the currency and the raw '
        'tax fraction, never the slug', (tester) async {
      final s = orgsServer();
      s.db['orgs'].update(AdminSeed.layaliOrg, {'tax_rate': 0.12});
      s.db['orgs'].update(AdminSeed.qahwaOrg, {'currency_code': 'SAR'});
      final h = await pumpOrgs(tester, server: s.server, db: s.db);
      final search = find.byType(DashSearchInput);
      expect(
        find.descendant(of: search, matching: find.text('Search')),
        findsOneWidget,
      );

      await h.enterText(search, 'nakhla');
      expect(find.text('Nakhla Bakery'), findsOneWidget);
      expect(find.text('Sabah Coffee'), findsNothing);

      await h.enterText(search, 'sar');
      expect(find.text('Qahwa Corner'), findsOneWidget);
      expect(find.text('Layali Bistro'), findsNothing);

      await h.enterText(search, '0.12');
      expect(find.text('Layali Bistro'), findsOneWidget);
      expect(find.text('Nakhla Bakery'), findsNothing);

      // "-bistro" is only in Layali's slug.
      await h.enterText(search, '-bistro');
      expect(find.text('Layali Bistro'), findsNothing);
      expect(find.text('Organizations you add appear here'), findsOneWidget);
    });

    testWidgets('ADM-ORG-012 the Columns menu hides a column', (tester) async {
      final h = await pumpOrgs(tester);
      expect(find.text('CURRENCY'), findsOneWidget);
      await h.tapText('Columns');
      for (final c in [
        'Name',
        'Currency',
        'Tax rate (%)',
        'Custom branding',
        'Status',
      ]) {
        expect(find.text(c), findsWidgets, reason: c);
      }
      await h.tapText('Currency');
      expect(find.text('CURRENCY'), findsNothing);
      expect(find.text('NAME'), findsOneWidget);
    });

    testWidgets('ADM-ORG-013 ten a page, with Previous / Next', (tester) async {
      final s = orgsServer();
      for (var i = 1; i <= 8; i++) {
        s.db['orgs'].insert(
          Org(
            id: mockUuid('org:extra-$i'),
            name: 'Zahra Bakery $i',
            slug: 'zahra-bakery-$i',
            currencyCode: 'EGP',
            timezone: 'Africa/Cairo',
            taxRate: 0.14,
            taxInclusive: true,
            serviceChargeRate: 0,
            serviceChargeTaxable: true,
            requireTableForOrders: false,
            customBranding: false,
            isActive: true,
            modules: const ['pos'],
            socialLinks: const {},
          ).toJson(),
        );
      }
      final h = await pumpOrgs(tester, server: s.server, db: s.db);
      expect(find.text('Page 1 of 2'), findsOneWidget);
      expect(find.text('Zahra Bakery 7'), findsNothing);
      await h.tapLabel('Next');
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(find.text('Zahra Bakery 7'), findsOneWidget);
      expect(find.text('Zahra Bakery 8'), findsOneWidget);
      await h.tapLabel('Previous');
      expect(find.text('Page 1 of 2'), findsOneWidget);
    });

    testWidgets('ADM-ORG-017 a phone shows each organization as a card led '
        'by its name', (tester) async {
      final h = await pumpOrgs(tester, size: DashSize.phone);
      expect(find.text('CURRENCY'), findsNothing);
      final card = find.ancestor(
        of: find.text('Layali Bistro'),
        matching: find.byType(DashCard),
      );
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Currency')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.bySemanticsLabel('Edit')),
        findsOneWidget,
      );
      await h.tap(find.text('Layali Bistro'));
      expect(h.location.queryParameters['edit'], AdminSeed.layaliOrg);
      expect(find.text('Edit Organization'), findsOneWidget);
    });
  });

  group('states', () {
    testWidgets('ADM-ORG-014 loading: skeleton rows and skeleton stats', (
      tester,
    ) async {
      final s = orgsServer();
      final gate = s.server.hold('GET', '/orgs');
      final h = await pumpOrgs(tester, server: s.server, db: s.db);
      expect(find.byType(DashSkeleton), findsAtLeastNWidgets(8));
      expect(find.text('Layali Bistro'), findsNothing);
      gate.release();
      await h.settle();
      expect(find.text('Layali Bistro'), findsOneWidget);
      expect(_stat('total', '4'), findsOneWidget);
    });

    testWidgets('ADM-ORG-015 error: the words and Retry, which asks again', (
      tester,
    ) async {
      final s = orgsServer();
      // Every read of /orgs fails (the page's and the org picker's).
      s.server.fail(
        'GET',
        '/orgs',
        MockResponse.error(500, 'Internal error'),
        times: null,
      );
      final h = await pumpOrgs(tester, server: s.server, db: s.db);
      expect(find.text('Internal error'), findsOneWidget);
      expect(find.text('Layali Bistro'), findsNothing);
      s.server.clearFailures();
      final before = s.server.callsTo('/orgs', method: 'GET').length;
      await h.tapText('Retry');
      expect(
        s.server.callsTo('/orgs', method: 'GET').length,
        greaterThan(before),
      );
      expect(find.text('Layali Bistro'), findsOneWidget);
    });

    testWidgets('ADM-ORG-016 empty: the building and "Organizations you add '
        'appear here"', (tester) async {
      final s = orgsServer();
      s.db['orgs'].clear();
      final h = await pumpOrgs(tester, server: s.server, db: s.db);
      expect(find.text('Organizations you add appear here'), findsOneWidget);
      expect(_stat('total', '0'), findsOneWidget);
      expect(_stat('avg-tax', '—'), findsOneWidget);
      expect(_button(tester, 'Export Excel').onPressed, isNull);
      expect(h.t('orgs.empty'), 'Organizations you add appear here');
    });

    for (final persona in [
      Persona.owner,
      Persona.manager,
      Persona.limited,
      Persona.dawamOnly,
    ]) {
      testWidgets('ADM-ORG-004 refused (${persona.name}): the frame, the '
          'refusal and Retry, zero stats, Export off, New still there', (
        tester,
      ) async {
        final h = await pumpOrgs(tester, persona: persona);
        expect(find.text('Organizations'), findsWidgets);
        expect(
          find.text("You don't have permission to perform this action."),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
        expect(_stat('total', '0'), findsOneWidget);
        expect(_stat('active', '0'), findsOneWidget);
        expect(_stat('inactive', '0'), findsOneWidget);
        expect(_stat('avg-tax', '—'), findsOneWidget);
        expect(_button(tester, 'Export Excel').onPressed, isNull);
        expect(_button(tester, 'New').onPressed, isNotNull);
        final call = h.server.callsTo('/orgs', method: 'GET').single;
        expect(call.status, 403);
      });
    }

    testWidgets('ADM-ORG-004 refused in Arabic: the refusal in Arabic', (
      tester,
    ) async {
      final h = await pumpOrgs(tester, persona: Persona.owner, locale: 'ar');
      expect(find.text(h.t('errors.unauthorized')), findsOneWidget);
      expect(find.text(h.t('common.retry')), findsOneWidget);
    });

    testWidgets('ADM-ORG-004 the wizard opens for anyone; its create is '
        'refused in words', (tester) async {
      final h = await pumpOrgs(tester, persona: Persona.owner);
      await h.tapKey(const ValueKey('orgs-new'));
      expect(find.text('New Organization'), findsOneWidget);
      // The templates read is refused too: the words show under the cards.
      expect(
        find.text("You don't have permission to perform this action."),
        findsNWidgets(2),
      );
    });
  });

  group('row actions', () {
    testWidgets('ADM-ORG-018 a row tap opens the editor through ?edit', (
      tester,
    ) async {
      final h = await pumpOrgs(tester);
      await h.tapText('Qahwa Corner');
      expect(h.location.queryParameters['edit'], AdminSeed.qahwaOrg);
      expect(find.text('Edit Organization'), findsOneWidget);
    });

    testWidgets('ADM-ORG-018 Enter on a focused row opens it too', (
      tester,
    ) async {
      final h = await pumpOrgs(tester);
      Focus.of(tester.element(find.text('Nakhla Bakery'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await h.settle();
      expect(
        h.location.queryParameters['edit'],
        orgNamed(h.db!, 'Nakhla Bakery').id,
      );
    });

    testWidgets('ADM-ORG-019 Edit (pencil, "Edit") opens the editor', (
      tester,
    ) async {
      final h = await pumpOrgs(tester);
      // Rows are by name: Layali, Nakhla, Qahwa, Sabah.
      await h.tap(find.bySemanticsLabel('Edit').at(3));
      expect(h.location.queryParameters['edit'], SeedIds.sabahOrg);
      expect(find.text('Edit Organization'), findsOneWidget);
      expect(find.text('Sabah Coffee'), findsWidgets);
    });

    testWidgets('ADM-ORG-020 Delete asks first; Cancel does nothing', (
      tester,
    ) async {
      final h = await pumpOrgs(tester);
      await h.tap(find.bySemanticsLabel('Delete').at(2));
      expect(find.text('Delete Qahwa Corner?'), findsOneWidget);
      expect(
        find.text(
          'Every branch, user and menu under this organization is removed. '
          'This cannot be undone.',
        ),
        findsOneWidget,
      );
      await h.tap(_inConfirm('Cancel'));
      expect(find.byType(DashConfirmDialog), findsNothing);
      expect(h.server.callsTo('/orgs/{id}', method: 'DELETE'), isEmpty);
      expect(find.text('Qahwa Corner'), findsOneWidget);
    });

    testWidgets('ADM-ORG-021 Delete confirmed: the call, the list again, the '
        'toast', (tester) async {
      final h = await pumpOrgs(tester);
      final before = h.server.callsTo('/orgs', method: 'GET').length;
      await h.tap(find.bySemanticsLabel('Delete').at(2));
      await h.tap(_inConfirm('Delete'));
      final call = h.server.callsTo('/orgs/{id}', method: 'DELETE').single;
      expect(call.path, '/orgs/${AdminSeed.qahwaOrg}');
      expect(call.status, 204);
      expect(
        h.server.callsTo('/orgs', method: 'GET').length,
        greaterThan(before),
      );
      expect(find.text('Qahwa Corner'), findsNothing);
      expect(_stat('total', '3'), findsOneWidget);
      await h.expectToast('Organization deleted');
    });

    testWidgets('ADM-ORG-021 a refused delete says why and keeps the row', (
      tester,
    ) async {
      final h = await pumpOrgs(tester);
      h.server.fail(
        'DELETE',
        '/orgs/{id}',
        MockResponse.notFound('Org not found'),
      );
      await h.tap(find.bySemanticsLabel('Delete').at(0));
      await h.tap(_inConfirm('Delete'));
      await h.expectToast('Org not found');
      expect(find.text('Layali Bistro'), findsOneWidget);
    });
  });

  group('export', () {
    testWidgets('ADM-ORG-022 the workbook: one sheet, five columns, every '
        'organization, the engine\'s toasts', (tester) async {
      final h = await pumpOrgs(tester);
      // Search narrows the table, never the file.
      await h.enterText(find.byType(DashSearchInput), 'qahwa');
      await h.tapText('Export Excel');
      await h.expectToast('Exported 4 rows');
      final spec = h.exports.built.single;
      expect(spec.logoUrl, isNull, reason: "no shop picked: Madar's logo");
      final sheet = spec.sheets.single;
      expect(sheet.name, 'Organizations');
      expect(sheet.title, 'Organizations');
      expect(
        [for (final c in sheet.columns) c.header],
        ['Name', 'Slug', 'Currency', 'Tax rate (%)', 'Status'],
      );
      expect([for (final c in sheet.columns) c.width], [28, 20, 12, 12, 12]);
      expect(sheet.rows.first, [
        'Layali Bistro',
        'layali-bistro',
        'EGP',
        14,
        'Active',
      ]);
      expect(sheet.rows[2], [
        'Qahwa Corner',
        'qahwa-corner',
        'EGP',
        14,
        'Inactive',
      ]);
      expect(
        h.files.saved.single.filename,
        'Madar-Organizations-2026-10-08.xlsx',
      );
    });

    testWidgets('ADM-ORG-022 the header logo is the shop\'s own on the '
        'branding tier', (tester) async {
      final s = orgsServer();
      s.db['orgs'].update(SeedIds.sabahOrg, {
        'logo_url': 'https://cdn.madar.test/sabah/logo.png',
      });
      final h = await pumpOrgs(tester, server: s.server, db: s.db);
      await h.container
          .read(selectedOrgProvider.notifier)
          .select(SeedIds.sabahOrg);
      await h.settle();
      await h.tapText('Export Excel');
      await h.flushTimers();
      expect(
        h.exports.built.single.logoUrl,
        'https://cdn.madar.test/sabah/logo.png',
      );
    });

    testWidgets('ADM-ORG-022 a failed export says "Export failed"', (
      tester,
    ) async {
      final h = await pumpOrgs(tester);
      h.exports.failNext = Exception('disk full');
      await h.tapText('Export Excel');
      await h.expectToast('Export failed');
      expect(h.files.saved, isEmpty);
    });

    testWidgets('ADM-ORG-022 Arabic: the file in Arabic, "Exported" in '
        'Arabic plurals', (tester) async {
      final h = await pumpOrgs(tester, locale: 'ar');
      await h.tapText(h.t('common.export'));
      await h.expectToast(h.t('excel.done', count: 4));
      final sheet = h.exports.built.single.sheets.single;
      expect(sheet.name, h.t('orgs.title'));
      expect(sheet.rows.first.last, h.t('common.active'));
    });
  });

  group('the editor in the address', () {
    testWidgets('ADM-ORG-023 New opens the provision wizard (?edit=new)', (
      tester,
    ) async {
      final h = await pumpOrgs(tester);
      await h.tapKey(const ValueKey('orgs-new'));
      expect(h.location.queryParameters['edit'], 'new');
      expect(find.text('New Organization'), findsOneWidget);
      expect(textHas('Step 1 of 3'), findsOneWidget);
    });

    testWidgets('ADM-ORG-024 ?edit=<id> opens the editor once the list has '
        'it; closing drops ?edit', (tester) async {
      final h = await pumpOrgs(
        tester,
        path: '/orgs?edit=${AdminSeed.layaliOrg}',
      );
      expect(find.text('Edit Organization'), findsOneWidget);
      await h.tapText('Cancel');
      expect(find.text('Edit Organization'), findsNothing);
      expect(h.location.queryParameters.containsKey('edit'), isFalse);
      expect(h.location.path, '/orgs');
    });

    testWidgets('ADM-ORG-024 an unknown id opens nothing', (tester) async {
      final h = await pumpOrgs(tester, path: '/orgs?edit=nope');
      expect(find.text('Edit Organization'), findsNothing);
      expect(find.text('New Organization'), findsNothing);
      expect(find.text('Layali Bistro'), findsOneWidget);
      expect(h.location.queryParameters['edit'], 'nope');
    });

    testWidgets('ADM-ORG-024 ?edit=new opens the wizard; closing drops it', (
      tester,
    ) async {
      final h = await pumpOrgs(tester, path: '/orgs?edit=new');
      expect(find.text('New Organization'), findsOneWidget);
      await h.tapText('Cancel');
      expect(find.text('New Organization'), findsNothing);
      expect(h.location.queryParameters.containsKey('edit'), isFalse);
    });

    testWidgets('ADM-ORG-024 leaving the address closes the editor', (
      tester,
    ) async {
      final h = await pumpOrgs(
        tester,
        path: '/orgs?edit=${AdminSeed.qahwaOrg}',
      );
      expect(find.text('Edit Organization'), findsOneWidget);
      await h.go('/orgs');
      expect(find.text('Edit Organization'), findsNothing);
      expect(find.text('Qahwa Corner'), findsOneWidget);
    });
  });
}
