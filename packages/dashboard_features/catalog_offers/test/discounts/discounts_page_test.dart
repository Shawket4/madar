// The Discounts page (OFFR-DSC-001..023, 039..043; OFFR-ALL-012/013/015),
// driven through the real shell on the mock server. One test per inventory
// row, its id first in the name.
import 'dart:async';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show DashSidebar;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The table row (or phone card) that shows [name].
Finder rowOf(String name) => find
    .ancestor(
      of: inTable(find.text(name)),
      matching: find.byType(DashPressable),
    )
    .first;

/// [matching] inside the row showing [name].
Finder inRow(String name, Finder matching) =>
    find.descendant(of: rowOf(name), matching: matching);

/// The status pill button a screen reader calls [label], in [name]'s row.
Finder statusOf(String name, String label) => find
    .descendant(
      of: rowOf(name),
      matching: find.byWidgetPredicate(
        (w) => w is DashPressable && w.semanticLabel == label,
      ),
    )
    .first;

/// The stat card labelled [label].
Finder stat(String label) => find.ancestor(
  of: inPage(find.text(label)),
  matching: find.byType(DashStatCard),
);

/// The table's search box.
Finder get search => inPage(find.byType(DashSearchInput));

/// The confirm dialog.
Finder get confirm => find.byType(DashConfirmDialog);

List<MockCall> lists(DashHarness h) =>
    h.server.callsTo(listRoute, method: 'GET');

void main() {
  group('page', () {
    testWidgets('OFFR-DSC-001 /discounts renders the page from its Catalog '
        'leaf', (tester) async {
      final h = await pumpDiscounts(tester);
      expect(page, findsOneWidget);
      final leaf = find.descendant(
        of: find.byType(DashSidebar),
        matching: find.text('Discounts'),
      );
      expect(leaf, findsOneWidget);
      expect(lists(h).single.query['org_id'], [SeedIds.sabahOrg]);
      for (final name in seededNames) {
        expect(inTable(find.text(name)), findsOneWidget);
      }
    });

    testWidgets('OFFR-DSC-002 no org in scope: "Select an organization", '
        'nothing asked', (tester) async {
      final h = await pumpDiscounts(tester, persona: Persona.platform);
      expect(inPage(find.text('Discounts')), findsOneWidget);
      expect(inPage(find.text('Select an organization')), findsOneWidget);
      expect(inPage(find.text('New discount')), findsNothing);
      expect(inPage(find.text('Export Excel')), findsNothing);
      expect(lists(h), isEmpty);
    });

    testWidgets('OFFR-DSC-003 without discounts.read the page still shows '
        'and the list is refused in words, with Retry', (tester) async {
      final h = await pumpDiscounts(tester, persona: Persona.limited);
      expect(page, findsOneWidget);
      expect(lists(h).single.status, 403);
      expect(
        find.descendant(
          of: find.byType(DashSidebar),
          matching: find.text('Discounts'),
        ),
        findsNothing,
      );
      expect(
        inPage(find.text("You don't have permission to perform this action.")),
        findsOneWidget,
      );
      expect(inPage(find.text('Retry')), findsOneWidget);
      // Nothing is hidden: the server refuses.
      expect(inPage(find.text('New discount')), findsOneWidget);
    });

    testWidgets('OFFR-DSC-003 a manager (read + edit, no create or delete) '
        'sees every action; the server refuses create and delete in words', (
      tester,
    ) async {
      final h = await pumpDiscounts(tester, persona: Persona.manager);
      const refused = "You don't have permission to perform this action.";

      await h.tap(inRow('Staff Meal', find.bySemanticsLabel('Delete')));
      await h.tap(find.descendant(of: confirm, matching: find.text('Delete')));
      await h.expectToast(refused);
      expect(inTable(find.text('Staff Meal')), findsOneWidget);

      await h.tap(inPage(find.text('New discount')));
      await h.enterText(dialogField('Discount name'), 'Ramadan Iftar');
      await h.tap(inDialog(find.text('Create')));
      await h.expectToast(refused);
      expect(dialog, findsOneWidget, reason: 'stays open with the values');
      expect(h.server.callsTo(listRoute, method: 'POST').single.status, 403);
      await h.tap(inDialog(find.text('Cancel')));

      // discounts.edit is a manager default: the toggle goes through.
      await h.tap(statusOf('Staff Meal', 'Deactivate discount'));
      expect(h.server.callsTo(itemRoute, method: 'PATCH').single.status, 200);
    });

    testWidgets('OFFR-DSC-003 a refused toggle (no discounts.edit) reads '
        '"You don\'t have permission…"', (tester) async {
      final s = discountsServer();
      s.server.fail('PATCH', itemRoute, MockResponse.denied('discounts.edit'));
      final h = await pumpDiscounts(tester, server: s.server, db: s.db);
      await h.tap(statusOf('Staff Meal', 'Deactivate discount'));
      await h.expectToast("You don't have permission to perform this action.");
      expect(inRow('Staff Meal', find.text('Active')), findsOneWidget);
    });

    testWidgets('OFFR-DSC-004 header: title, subtitle, Export then New', (
      tester,
    ) async {
      await pumpDiscounts(tester);
      expect(inPage(find.text('Discounts')), findsWidgets);
      expect(
        inPage(find.text('Percentage and fixed-amount discounts')),
        findsOneWidget,
      );
      final export = tester.getCenter(inPage(find.text('Export Excel')));
      final create = tester.getCenter(inPage(find.text('New discount')));
      expect(export.dx, lessThan(create.dx));
    });

    testWidgets('OFFR-DSC-005 four counts over the whole list; skeletons '
        'while it loads', (tester) async {
      final s = discountsServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpDiscounts(tester, server: s.server, db: s.db);
      for (final c in tester.widgetList<DashStatCard>(
        inPage(find.byType(DashStatCard)),
      )) {
        expect(c.loading, isTrue);
      }
      gate.release();
      await h.settle();
      expect(
        {
          for (final c in tester.widgetList<DashStatCard>(
            inPage(find.byType(DashStatCard)),
          ))
            c.label: c.value,
        },
        {'Total': 7, 'Active': 6, 'Percentage': 5, 'Fixed amount': 2},
      );
      // Two a row below 1024, four from it: the desktop shows one row.
      final ys = {
        for (final l in ['Total', 'Active', 'Percentage', 'Fixed amount'])
          tester.getTopLeft(stat(l)).dy,
      };
      expect(ys, hasLength(1));
    });
  });

  group('export', () {
    testWidgets('OFFR-DSC-006 Export is off with no discount; spinner while '
        'it runs', (tester) async {
      final s = discountsServer();
      s.db.table(OffersTables.discounts).clear();
      await pumpDiscounts(tester, server: s.server, db: s.db);
      expect(
        tester.widget<DashExportButton>(find.byType(DashExportButton)).enabled,
        isFalse,
      );
    });

    testWidgets('OFFR-DSC-006 the button spins while the file is built', (
      tester,
    ) async {
      final h = await pumpDiscounts(tester);
      final wait = Completer<void>();
      h.exports.hold = wait.future;
      await h.tap(inPage(find.text('Export Excel')));
      expect(
        tester.widget<DashExportButton>(find.byType(DashExportButton)).loading,
        isTrue,
      );
      expect(find.text('Gathering data…'), findsOneWidget);
      wait.complete();
      await h.settle();
      expect(
        tester.widget<DashExportButton>(find.byType(DashExportButton)).loading,
        isFalse,
      );
      await h.expectToast('Exported 7 rows');
    });

    testWidgets('OFFR-DSC-007 the workbook: one sheet "Discounts", four '
        'typed columns, every discount, "Exported 7 rows"', (tester) async {
      final h = await pumpDiscounts(tester);
      await h.tap(inPage(find.text('Export Excel')));
      await h.expectToast('Exported 7 rows');
      final spec = h.exports.built.single;
      final sheet = spec.sheets.single;
      expect(sheet.name, 'Discounts');
      expect(sheet.title, 'Discounts');
      expect(
        [for (final c in sheet.columns) c.header],
        ['Discount name', 'Type', 'Value', 'Status'],
      );
      expect([for (final c in sheet.columns) c.width], [28, 16, 14, 12]);
      expect(sheet.columns[2].numFmt, excelNumFmt(ExcelColumnType.number));
      expect(sheet.rows, hasLength(7));
      expect(sheet.rows[0], [
        'Corporate: Vodafone',
        'Percentage',
        12.5,
        'Active',
      ]);
      expect(sheet.rows[1], [
        'Late Order Apology',
        'Fixed amount',
        50,
        'Active',
      ]);
      expect(sheet.rows[4], ['Opening Week', 'Percentage', 20, 'Inactive']);
      final day = h.server.clock.now.toUtc().toIso8601String().substring(0, 10);
      expect(h.files.saved.single.filename, 'Madar-Discounts-$day.xlsx');
    });

    testWidgets('OFFR-DSC-007 the shop\'s logo on the branding tier', (
      tester,
    ) async {
      final s = discountsServer();
      s.db['orgs'].update(SeedIds.sabahOrg, {
        'logo_url': 'https://cdn.madar.test/sabah/logo.png',
        'custom_branding': true,
      });
      final h = await pumpDiscounts(tester, server: s.server, db: s.db);
      await h.tap(inPage(find.text('Export Excel')));
      await h.flushTimers();
      expect(
        h.exports.built.single.logoUrl,
        'https://cdn.madar.test/sabah/logo.png',
      );
    });

    testWidgets('OFFR-DSC-007 the logo address is trimmed; a blank one is '
        'Madar\'s', (tester) async {
      final s = discountsServer();
      s.db['orgs'].update(SeedIds.sabahOrg, {
        'logo_url': '  https://cdn.madar.test/sabah/logo.png ',
        'custom_branding': true,
      });
      final h = await pumpDiscounts(tester, server: s.server, db: s.db);
      await h.tap(inPage(find.text('Export Excel')));
      await h.flushTimers();
      expect(
        h.exports.built.single.logoUrl,
        'https://cdn.madar.test/sabah/logo.png',
      );
    });

    testWidgets('OFFR-DSC-007 a blank logo address exports Madar\'s', (
      tester,
    ) async {
      final s = discountsServer();
      s.db['orgs'].update(SeedIds.sabahOrg, {
        'logo_url': '   ',
        'custom_branding': true,
      });
      final h = await pumpDiscounts(tester, server: s.server, db: s.db);
      await h.tap(inPage(find.text('Export Excel')));
      await h.flushTimers();
      expect(h.exports.built.single.logoUrl, isNull);
    });

    testWidgets('OFFR-DSC-007 a failed export says "Export failed"', (
      tester,
    ) async {
      final h = await pumpDiscounts(tester);
      h.exports.failNext = Exception('disk full');
      await h.tap(inPage(find.text('Export Excel')));
      await h.expectToast('Export failed');
      expect(h.files.saved, isEmpty);
    });

    testWidgets('OFFR-DSC-040 Export writes every discount while the search '
        'narrows the table', (tester) async {
      final h = await pumpDiscounts(tester);
      await h.enterText(search, 'staff');
      expect(inTable(find.text('Corporate: Vodafone')), findsNothing);
      await h.tap(inPage(find.text('Export Excel')));
      await h.expectToast('Exported 7 rows');
      expect(h.exports.built.single.sheets.single.rows, hasLength(7));
    });
  });

  group('table', () {
    testWidgets('OFFR-DSC-008 New discount puts ?edit=new and opens the new '
        'dialog', (tester) async {
      final h = await pumpDiscounts(tester);
      await h.tap(inPage(find.text('New discount')));
      expect(h.location.queryParameters['edit'], 'new');
      expect(inDialog(find.text('New discount')), findsOneWidget);
    });

    testWidgets('OFFR-DSC-009 search: name, type code and legacy value, '
        'back to page 1; nothing found reads "No discounts yet"', (
      tester,
    ) async {
      final s = discountsServer();
      addPromos(s.db, 6);
      final h = await pumpDiscounts(tester, server: s.server, db: s.db);
      await h.tap(inPage(find.bySemanticsLabel('Next')));
      expect(inTable(find.text('Staff Meal')), findsOneWidget);

      await h.enterText(search, 'o');
      expect(
        inTable(find.text('Corporate: Vodafone')),
        findsOneWidget,
        reason: 'back on page 1',
      );

      await h.enterText(search, 'FIXED');
      expect(inTable(find.text('Late Order Apology')), findsOneWidget);
      expect(inTable(find.text('Loyalty Welcome')), findsOneWidget);
      expect(inTable(find.text('Staff Meal')), findsNothing);

      // 12.5 % travels as the legacy 13.
      await h.enterText(search, '13');
      expect(inTable(find.text('Corporate: Vodafone')), findsOneWidget);
      expect(inTable(find.text('Student Discount')), findsNothing);

      await h.enterText(search, 'zzz');
      expect(inPage(find.text('No discounts yet')), findsOneWidget);
      expect(
        inPage(find.text('Create your first discount to use at checkout.')),
        findsOneWidget,
      );
    });

    testWidgets('OFFR-DSC-041 search: case-insensitive, untrimmed, never the '
        'Arabic name or the status; Esc and × empty it', (tester) async {
      final h = await pumpDiscounts(tester);
      await h.enterText(search, 'STAFF');
      expect(inTable(find.text('Staff Meal')), findsOneWidget);
      expect(inTable(find.text('Student Discount')), findsNothing);

      await h.enterText(search, ' meal');
      expect(inTable(find.text('Staff Meal')), findsOneWidget);
      await h.enterText(search, 'meal ');
      expect(inPage(find.text('No discounts yet')), findsOneWidget);

      await h.enterText(search, 'وجبة');
      expect(inPage(find.text('No discounts yet')), findsOneWidget);
      await h.enterText(search, 'inactive');
      expect(inPage(find.text('No discounts yet')), findsOneWidget);

      await h.tap(search);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      for (final name in seededNames) {
        expect(inTable(find.text(name)), findsOneWidget);
      }

      await h.enterText(search, 'staff');
      await h.tap(labelled('Clear'));
      expect(inTable(find.text('Student Discount')), findsOneWidget);
    });

    testWidgets('OFFR-DSC-010 name cell: the type glyph tile and the name', (
      tester,
    ) async {
      await pumpDiscounts(tester);
      final glyphs = [
        for (final w in tester.widgetList<MadarIcon>(
          inRow('Staff Meal', find.byType(MadarIcon)),
        ))
          w.name,
      ];
      expect(glyphs, contains('percent'));
      final fixed = [
        for (final w in tester.widgetList<MadarIcon>(
          inRow('Late Order Apology', find.byType(MadarIcon)),
        ))
          w.name,
      ];
      expect(fixed, contains('banknote'));
    });

    testWidgets('OFFR-DSC-011 Type: "Percentage" or "Fixed amount"', (
      tester,
    ) async {
      await pumpDiscounts(tester);
      expect(inRow('Staff Meal', find.text('Percentage')), findsOneWidget);
      expect(
        inRow('Late Order Apology', find.text('Fixed amount')),
        findsOneWidget,
      );
    });

    testWidgets('OFFR-DSC-012 Value: the rate as a percent, a fixed amount as '
        'money', (tester) async {
      await pumpDiscounts(tester);
      expect(inRow('Corporate: Vodafone', find.text('12.5%')), findsOneWidget);
      expect(inRow('Manager Comp', find.text('100%')), findsOneWidget);
      expect(inRow('Staff Meal', find.text('50%')), findsOneWidget);
      expect(
        inRow('Late Order Apology', find.text('EGP 50.00')),
        findsOneWidget,
      );
    });

    testWidgets('OFFR-DSC-013 the status pill flips the discount at once: no '
        'confirm, no toast, never opens the row', (tester) async {
      final s = discountsServer();
      final h = await pumpDiscounts(tester, server: s.server, db: s.db);
      final before = lists(h).length;
      final gate = s.server.hold('PATCH', itemRoute);
      await h.tap(statusOf('Staff Meal', 'Deactivate discount'));
      expect(
        tester
            .widget<DashPressable>(
              statusOf('Staff Meal', 'Deactivate discount'),
            )
            .enabled,
        isFalse,
        reason: 'disabled while its request runs',
      );
      gate.release();
      await h.settle();
      final call = h.server.callsTo(itemRoute, method: 'PATCH').single;
      expect(call.path, '/discounts/${discountId('staff-meal')}');
      expect(call.body, {'is_active': false});
      expect(lists(h).length, before + 1, reason: 'the list refetches');
      expect(inRow('Staff Meal', find.text('Inactive')), findsOneWidget);
      expect(statusOf('Staff Meal', 'Activate discount'), findsOneWidget);
      expect(h.location.queryParameters['edit'], isNull);
      expect(dialog, findsNothing);
      expect(find.text('Discount updated'), findsNothing);
    });

    testWidgets('OFFR-DSC-013 a refused toggle toasts and leaves the pill', (
      tester,
    ) async {
      final s = discountsServer();
      final refusal = MockResponse.notFound('Discount not found');
      s.server.fail('PATCH', itemRoute, refusal);
      final h = await pumpDiscounts(tester, server: s.server, db: s.db);
      await h.tap(statusOf('Staff Meal', 'Deactivate discount'));
      await h.expectToast(refusalText(h, refusal));
      expect(inRow('Staff Meal', find.text('Active')), findsOneWidget);
    });

    testWidgets('OFFR-DSC-014 a row tap opens its edit dialog', (tester) async {
      final h = await pumpDiscounts(tester);
      await h.tap(inTable(find.text('Loyalty Welcome')));
      expect(h.location.queryParameters['edit'], discountId('loyalty-welcome'));
      expect(inDialog(find.text('Edit discount')), findsOneWidget);
    });

    testWidgets('OFFR-DSC-014 a row opens from the keyboard (Enter)', (
      tester,
    ) async {
      final h = await pumpDiscounts(tester);
      final row = tester.widget<DashPressable>(rowOf('Student Discount'));
      expect(row.onTap, isNotNull);
      Focus.of(
        tester.element(inTable(find.text('Student Discount'))),
      ).requestFocus();
      await h.settle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await h.settle();
      expect(h.location.queryParameters['edit'], discountId('student'));
      expect(inDialog(find.text('Edit discount')), findsOneWidget);
    });

    testWidgets('OFFR-DSC-015 the pencil opens the edit dialog', (
      tester,
    ) async {
      final h = await pumpDiscounts(tester);
      await h.tap(inRow('Manager Comp', find.bySemanticsLabel('Edit')));
      expect(h.location.queryParameters['edit'], discountId('manager-comp'));
      expect(dialogField('Discount name'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: dialogField('Discount name'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'Manager Comp',
      );
    });

    testWidgets('OFFR-DSC-016 the trash asks first; Cancel does nothing', (
      tester,
    ) async {
      final h = await pumpDiscounts(tester);
      await h.tap(inRow('Opening Week', find.bySemanticsLabel('Delete')));
      expect(
        find.descendant(
          of: confirm,
          matching: find.text('Delete "Opening Week"?'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: confirm,
          matching: find.text(
            'Cashiers can no longer apply it at checkout. Past orders keep '
            'the discount they were given.',
          ),
        ),
        findsOneWidget,
      );
      expect(tester.widget<DashConfirmDialog>(confirm).destructive, isTrue);
      await h.tap(find.descendant(of: confirm, matching: find.text('Cancel')));
      expect(confirm, findsNothing);
      expect(h.server.callsTo(itemRoute, method: 'DELETE'), isEmpty);
      expect(inTable(find.text('Opening Week')), findsOneWidget);
      expect(h.location.queryParameters['edit'], isNull);
    });

    testWidgets('OFFR-DSC-016 (divergence) the Arabic confirm names the '
        'discount in Arabic, not its raw English name', (tester) async {
      final h = await pumpDiscounts(tester, locale: 'ar');
      await h.tap(
        inRow('أسبوع الافتتاح', find.bySemanticsLabel(h.t('common.delete'))),
      );
      expect(
        find.descendant(
          of: confirm,
          matching: find.text(
            h.t('common.confirmDelete', args: {'name': 'أسبوع الافتتاح'}),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: confirm,
          matching: find.textContaining('Opening Week'),
        ),
        findsNothing,
      );
      await h.tap(
        find.descendant(of: confirm, matching: find.text(h.t('common.cancel'))),
      );
    });

    testWidgets('OFFR-DSC-017 Delete: the call, the refreshed list, '
        '"Discount deleted"', (tester) async {
      final h = await pumpDiscounts(tester);
      final before = lists(h).length;
      await h.tap(inRow('Opening Week', find.bySemanticsLabel('Delete')));
      await h.tap(find.descendant(of: confirm, matching: find.text('Delete')));
      await h.expectToast('Discount deleted');
      expect(
        h.server.callsTo(itemRoute, method: 'DELETE').single.path,
        '/discounts/${discountId('opening-week')}',
      );
      expect(lists(h).length, before + 1);
      expect(inTable(find.text('Opening Week')), findsNothing);
    });

    testWidgets('OFFR-DSC-017 a failed delete toasts and keeps the row', (
      tester,
    ) async {
      final s = discountsServer();
      final failure = MockResponse.error(
        500,
        'Database error: connection reset',
      );
      s.server.fail('DELETE', itemRoute, failure);
      final h = await pumpDiscounts(tester, server: s.server, db: s.db);
      await h.tap(inRow('Opening Week', find.bySemanticsLabel('Delete')));
      await h.tap(find.descendant(of: confirm, matching: find.text('Delete')));
      await h.expectToast(refusalText(h, failure));
      expect(inTable(find.text('Opening Week')), findsOneWidget);
    });

    testWidgets('OFFR-DSC-018 empty: "No discounts yet", no button in it', (
      tester,
    ) async {
      final s = discountsServer();
      s.db.table(OffersTables.discounts).clear();
      await pumpDiscounts(tester, server: s.server, db: s.db);
      final empty = find.ancestor(
        of: inPage(find.text('No discounts yet')),
        matching: find.byType(DashEmptyState),
      );
      expect(empty, findsOneWidget);
      expect(
        find.descendant(
          of: empty,
          matching: find.text('Create your first discount to use at checkout.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: empty, matching: find.byType(DashButton)),
        findsNothing,
      );
      expect(tester.widget<DashEmptyState>(empty).icon, 'tag');
    });

    testWidgets('OFFR-DSC-019 loading: skeleton rows', (tester) async {
      final s = discountsServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpDiscounts(tester, server: s.server, db: s.db);
      expect(inTable(find.byType(DashSkeleton)), findsWidgets);
      expect(inTable(find.text('Staff Meal')), findsNothing);
      gate.release();
      await h.settle();
      expect(inTable(find.byType(DashSkeleton)), findsNothing);
      expect(inTable(find.text('Staff Meal')), findsOneWidget);
    });

    testWidgets('OFFR-DSC-019 failed: "Couldn\'t load this", the server\'s '
        'words, Retry refetches the list', (tester) async {
      final s = discountsServer();
      final failure = MockResponse.error(500, 'Database unavailable');
      s.server.fail('GET', listRoute, failure, times: null);
      final h = await pumpDiscounts(tester, server: s.server, db: s.db);
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      expect(inPage(find.text(refusalText(h, failure))), findsOneWidget);
      final before = lists(h).length;
      s.server.clearFailures();
      await h.tap(inPage(find.text('Retry')));
      expect(lists(h).length, before + 1);
      expect(inTable(find.text('Staff Meal')), findsOneWidget);
    });

    testWidgets('OFFR-DSC-042 list failed: the counts read 0 (no skeleton) '
        'and Export stays off', (tester) async {
      final s = discountsServer();
      s.server.fail(
        'GET',
        listRoute,
        MockResponse.error(500, 'Database unavailable'),
        times: null,
      );
      await pumpDiscounts(tester, server: s.server, db: s.db);
      for (final c in tester.widgetList<DashStatCard>(
        inPage(find.byType(DashStatCard)),
      )) {
        expect(c.loading, isFalse);
        expect(c.value, 0);
      }
      expect(
        tester.widget<DashExportButton>(find.byType(DashExportButton)).enabled,
        isFalse,
      );
    });

    testWidgets('OFFR-ALL-012 a failed refetch replaces the loaded rows with '
        'the error state', (tester) async {
      final s = discountsServer();
      final h = await pumpDiscounts(tester, server: s.server, db: s.db);
      expect(inTable(find.text('Staff Meal')), findsOneWidget);
      s.server.fail(
        'GET',
        listRoute,
        MockResponse.error(500, 'Database unavailable'),
        times: null,
      );
      h.container.read(realtimeBusProvider).invalidate(const ['/discounts']);
      await h.settle();
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      expect(inTable(find.text('Staff Meal')), findsNothing);
    });

    testWidgets('OFFR-DSC-020 / OFFR-ALL-013 ten a page; Page 1 of 2, '
        'Previous and Next', (tester) async {
      final s = discountsServer();
      addPromos(s.db, 6);
      final h = await pumpDiscounts(tester, server: s.server, db: s.db);
      expect(inPage(find.text('Page 1 of 2')), findsOneWidget);
      expect(inTable(find.text('Promo 05')), findsOneWidget);
      expect(inTable(find.text('Promo 06')), findsNothing);
      await h.tap(inPage(find.bySemanticsLabel('Next')));
      expect(inPage(find.text('Page 2 of 2')), findsOneWidget);
      expect(inTable(find.text('Promo 06')), findsOneWidget);
      expect(inTable(find.text('Student Discount')), findsOneWidget);
      await h.tap(inPage(find.bySemanticsLabel('Previous')));
      expect(inTable(find.text('Corporate: Vodafone')), findsOneWidget);
    });

    testWidgets('OFFR-DSC-020 seven discounts: no page footer', (tester) async {
      await pumpDiscounts(tester);
      expect(inPage(find.byType(DashPagination)), findsNothing);
    });

    testWidgets('OFFR-ALL-015 a status toggle on page 2 puts the table back '
        'on page 1', (tester) async {
      final s = discountsServer();
      addPromos(s.db, 6);
      final h = await pumpDiscounts(tester, server: s.server, db: s.db);
      await h.tap(inPage(find.bySemanticsLabel('Next')));
      await h.tap(statusOf('Staff Meal', 'Deactivate discount'));
      expect(inPage(find.text('Page 1 of 2')), findsOneWidget);
      expect(inTable(find.text('Corporate: Vodafone')), findsOneWidget);
    });

    testWidgets('OFFR-DSC-021 Columns: only Value can be hidden', (
      tester,
    ) async {
      final h = await pumpDiscounts(tester);
      await h.tap(inPage(find.text('Columns')));
      // The headers read in capitals; the menu lists the labelled column.
      expect(find.text('Value'), findsOneWidget);
      for (final other in ['Discount name', 'Type', 'Status']) {
        expect(find.text(other), findsNothing);
      }
      await h.tap(find.text('Value'));
      expect(inTable(find.text('VALUE')), findsNothing);
      expect(inTable(find.text('12.5%')), findsNothing);
      expect(inTable(find.text('TYPE')), findsOneWidget);
    });

    testWidgets('OFFR-DSC-043 the server\'s order (by name), kept in Arabic', (
      tester,
    ) async {
      final s = discountsServer();
      final h = await pumpDiscounts(
        tester,
        locale: 'ar',
        server: s.server,
        db: s.db,
      );
      final ar = [
        for (final key in [
          'corporate-vodafone',
          'late-order',
          'loyalty-welcome',
          'manager-comp',
          'opening-week',
          'staff-meal',
          'student',
        ])
          s.db
                  .table(OffersTables.discounts)
                  .find(discountId(key))!['name_translations']
              as Map,
      ];
      final ys = [
        for (final names in ar)
          tester.getTopLeft(inTable(find.text(names['ar']! as String))).dy,
      ];
      expect(ys, [...ys]..sort());
      expect(h.locale, 'ar');
    });
  });

  group('deep links', () {
    testWidgets('OFFR-DSC-023 ?edit=new opens the new dialog; closing it '
        'removes edit', (tester) async {
      final h = await pumpDiscounts(tester, path: '/discounts?edit=new');
      expect(inDialog(find.text('New discount')), findsOneWidget);
      await h.tap(inDialog(find.text('Cancel')));
      expect(dialog, findsNothing);
      expect(h.location.queryParameters.containsKey('edit'), isFalse);
      expect(h.location.path, '/discounts');
    });

    testWidgets('OFFR-DSC-023 ?edit=<id> opens once the list holds it', (
      tester,
    ) async {
      final s = discountsServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpDiscounts(
        tester,
        path: '/discounts?edit=${discountId('student')}',
        server: s.server,
        db: s.db,
      );
      expect(dialog, findsNothing);
      gate.release();
      await h.settle();
      expect(inDialog(find.text('Edit discount')), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: dialogField('Discount name'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'Student Discount',
      );
    });

    testWidgets('OFFR-DSC-023 an unknown id opens nothing', (tester) async {
      final h = await pumpDiscounts(
        tester,
        path: '/discounts?edit=${mockUuid('nope')}',
      );
      expect(dialog, findsNothing);
      expect(inTable(find.text('Staff Meal')), findsOneWidget);
      expect(h.location.queryParameters['edit'], mockUuid('nope'));
    });

    testWidgets('OFFR-DSC-001 ?edit=<id> on arrival opens that discount', (
      tester,
    ) async {
      await pumpDiscounts(
        tester,
        path: '/discounts?edit=${discountId('late-order')}',
      );
      expect(inDialog(find.text('Edit discount')), findsOneWidget);
      expect(inDialog(find.text('Amount (EGP)')), findsOneWidget);
    });
  });

  group('phone', () {
    testWidgets('OFFR-DSC-022 phone: counts 2×2, a card per discount with '
        'Edit/Delete and Type, Value, Status pairs', (tester) async {
      final h = await pumpDiscounts(tester, size: DashSize.phone);
      final total = tester.getTopLeft(stat('Total'));
      final active = tester.getTopLeft(stat('Active'));
      final pct = tester.getTopLeft(stat('Percentage'));
      expect(total.dy, active.dy);
      expect(pct.dy, greaterThan(total.dy));
      expect(inTable(find.byType(DashCard)), findsNWidgets(7));
      expect(
        inRow('Staff Meal', find.bySemanticsLabel('Edit')),
        findsOneWidget,
      );
      expect(
        inRow('Staff Meal', find.bySemanticsLabel('Delete')),
        findsOneWidget,
      );
      for (final label in ['Type', 'Value', 'Status']) {
        expect(inRow('Staff Meal', find.text(label)), findsOneWidget);
      }
      expect(inPage(find.text('Columns')), findsNothing);
      // The pill stays a button on the card.
      await h.tap(statusOf('Staff Meal', 'Deactivate discount'));
      expect(h.server.callsTo(itemRoute, method: 'PATCH').single.body, {
        'is_active': false,
      });
      expect(dialog, findsNothing);
      // The card opens the full-screen dialog.
      await h.tap(inTable(find.text('Student Discount')));
      expect(inDialog(find.text('Edit discount')), findsOneWidget);
    });
  });

  group('Arabic', () {
    testWidgets('OFFR-DSC-039 Arabic: words, names and counts in Arabic; '
        'figures left to right in Latin digits', (tester) async {
      final h = await pumpDiscounts(tester, locale: 'ar');
      expect(inPage(find.text(h.t('discounts.title'))), findsWidgets);
      expect(inPage(find.text(h.t('discounts.new'))), findsOneWidget);
      expect(inTable(find.text('وجبة الموظفين')), findsOneWidget);
      expect(inTable(find.text('Staff Meal')), findsNothing);
      expect(
        inRow('الشركات: فودافون', find.text(ltr('12.5%'))),
        findsOneWidget,
      );
      expect(
        inRow('اعتذار عن تأخر الطلب', find.text(h.t('discounts.fixed'))),
        findsOneWidget,
      );
      final money = tester
          .widgetList<RichText>(
            inRow('اعتذار عن تأخر الطلب', find.byType(RichText)),
          )
          .map((r) => r.text.toPlainText())
          .firstWhere((s) => s.contains('50.00'));
      expect(money, contains('ج.م'));
      await h.tap(inPage(find.text(h.t('discounts.new'))));
      expect(inDialog(find.text(h.t('discounts.newTitle'))), findsOneWidget);
    });
  });
}
