// The menu export and paste rows (MENU-ITEMS-029..038, 111, 114) driven
// through the real shell.
import 'dart:async';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder get _export => inPage(find.text('Export Excel'));

Future<void> _openPaste(DashHarness h) =>
    h.tap(inPage(find.text('Paste rows')));

Future<void> _paste(DashHarness h, String text) async {
  await h.enterText(fieldIn(surface, 'Paste rows'), text);
  await h.tap(inSurface(find.text('Next')));
}

void main() {
  group('export', () {
    testWidgets('MENU-ITEMS-029 / 032 Export Excel: busy while it runs, '
        'then "Exported n rows"', (tester) async {
      final s = itemsServer();
      final h = await pumpItems(tester, seeded: s);
      expect(_export, findsOneWidget);
      final hold = Completer<void>();
      h.exports.hold = hold.future;
      await h.tap(_export);
      expect(find.text('Gathering data…'), findsWidgets);
      final button = tester.widget<DashButton>(
        find.ancestor(of: _export, matching: find.byType(DashButton)).first,
      );
      expect(button.loading, isTrue);
      hold.complete();
      await h.settle();
      final addons = CatalogMenuData(s.db).addonItems().length;
      await h.expectToast('Exported ${40 + 7 + addons} rows');
    });

    testWidgets('MENU-ITEMS-030 the walk: the grid filters, 500 a page, '
        'marked as an export', (tester) async {
      final h = await pumpItems(tester);
      await h.tap(find.byKey(const ValueKey('filter-category')));
      await pickOption(h, 'Hot Coffee');
      final before = callsOf(h, 'GET', catalogPath).length;
      await h.tap(_export);
      await h.settle();
      final walk = callsOf(h, 'GET', catalogPath).sublist(before);
      expect(walk, hasLength(1), reason: 'the total is reached on page 1');
      expect(walk.single.query, {
        'org_id': [sabahOrg],
        'category_id': [category('hot')],
        'page': ['1'],
        'per_page': ['500'],
      });
      expect(walk.single.headers['X-Madar-Export'], '1');
      await h.flushTimers();
    });

    testWidgets('MENU-ITEMS-030 too many rows: the too-large words', (
      tester,
    ) async {
      final s = itemsServer();
      final h = await pumpItems(tester, seeded: s);
      s.server.fail(
        'GET',
        catalogPath,
        MockResponse.ok({
          'data': const <Object?>[],
          'total': 60000,
          'page': 1,
          'per_page': 500,
          'total_pages': 120,
        }),
      );
      await h.tap(_export);
      await h.expectToast(
        'That is about 60,000 rows, and a spreadsheet built in the browser '
        'tops out around 50,000. Narrow the dates or the branch and try again.',
      );
      expect(h.exports.built, isEmpty);
    });

    testWidgets('MENU-ITEMS-031 / 114 the workbook: name, three sheets, '
        'columns, totals, the org logo', (tester) async {
      final s = itemsServer();
      s.db['orgs'].update(sabahOrg, {
        'logo_url': 'https://cdn.madar.test/sabah-logo.png',
      });
      final h = await pumpItems(tester, seeded: s);
      expect(lastCall(h, 'GET', '/public/orgs/brand').query['org_id'], [
        sabahOrg,
      ]);
      await h.tap(_export);
      await h.settle();
      final spec = h.exports.built.single;
      final saved = h.files.saved.single;
      expect(
        saved.filename,
        matches(RegExp(r'^Madar-Menu-\d{4}-\d{2}-\d{2}\.xlsx$')),
      );
      expect(spec.logoUrl, 'https://cdn.madar.test/sabah-logo.png');
      // A blank logo is no logo (use-brand.ts: `logo_url?.trim() || null`).
      s.db['orgs'].update(sabahOrg, {'logo_url': '   '});
      h.container.invalidate(publicBrandProvider);
      await h.settle();
      await h.tap(_export);
      await h.settle();
      expect(h.exports.built.last.logoUrl, isNull);
      expect(
        [for (final sh in spec.sheets) sh.title],
        ['Items', 'Categories', 'Addons'],
      );
      final items = spec.sheets[0];
      expect(
        [for (final c in items.columns) c.header],
        ['Name', 'Category', 'Price', 'Status'],
      );
      expect([for (final c in items.columns) c.width], [26, 20, 14, 12]);
      expect(items.rows, hasLength(40));
      expect(items.rows.first.first, 'Almond Croissant');
      expect(items.rows.first[1], 'Bakery');
      expect(items.rows.first[3], 'Active');
      expect(items.totalsRow!.first, 'TOTALS');
      expect(items.subtitle, startsWith('Generated: '));
      final cats = spec.sheets[1];
      expect([for (final c in cats.columns) c.header], ['Name', 'Status']);
      expect(cats.totalsRow, isNull);
      expect(cats.rows, hasLength(7));
      final addons = spec.sheets[2];
      expect(
        [for (final c in addons.columns) c.header],
        ['Name', 'Type', 'Price', 'Status'],
      );
      expect(addons.totalsRow, isNotNull);
      await h.flushTimers();
    });

    testWidgets('MENU-ITEMS-031 in Arabic: the Arabic names', (tester) async {
      final h = await pumpItems(tester, locale: 'ar');
      await h.tap(inPage(find.text(h.t('common.export'))));
      await h.settle();
      final items = h.exports.built.single.sheets[0];
      expect(items.rows.first.first, 'كرواسون لوز');
      expect(items.rows.first[1], 'مخبوزات');
      await h.flushTimers();
    });

    testWidgets('MENU-ITEMS-032 a failed build: "Export failed"', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      h.exports.failNext = StateError('disk full');
      await h.tap(_export);
      await h.settle();
      await h.expectToast('Export failed');
    });

    testWidgets('MENU-ITEMS-032 nothing at all: "Nothing to export"', (
      tester,
    ) async {
      final s = itemsServer();
      for (final m in liveItems(s.db)) {
        m['deleted_at'] = '2026-09-01T09:00:00Z';
      }
      for (final c in s.db[MenuTables.categories].rows) {
        c['deleted_at'] = '2026-09-01T09:00:00Z';
      }
      for (final g in s.db[MenuTables.groups].rows) {
        g['legacy_addon_type'] = null;
      }
      final h = await pumpItems(tester, seeded: s);
      await h.tap(_export);
      await h.settle();
      await h.expectToast('Nothing to export');
      expect(h.exports.built, isEmpty);
    });
  });

  group('paste rows', () {
    testWidgets('MENU-ITEMS-033 / 034 the dialog: words, Next off when empty', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      await _openPaste(h);
      expect(inSurface(find.text('Paste rows')), findsWidgets);
      expect(
        inSurface(
          find.text(
            'Paste rows from a spreadsheet (tab- or '
            'comma-separated), one row per line.',
          ),
        ),
        findsOneWidget,
      );
      final next = tester.widget<DashButton>(
        find
            .ancestor(
              of: inSurface(find.text('Next')),
              matching: find.byType(DashButton),
            )
            .first,
      );
      expect(next.onPressed, isNull);
      await h.tap(inSurface(find.text('Cancel')));
      expect(find.byType(DashSurface), findsNothing);
    });

    testWidgets('MENU-ITEMS-035 / 036 mapping, preview, reasons, summary', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      await _openPaste(h);
      await _paste(
        h,
        'Rose Latte\t125\tHot Coffee\tSteamed milk and rose\n'
        '\t40\tHot Coffee\n'
        'Dates Shake\tabc\tFresh Juice\n'
        'Cold Foam\t60\tSmoothies\n',
      );
      for (var i = 1; i <= 4; i++) {
        expect(inSurface(find.text('Column $i')), findsOneWidget);
      }
      expect(inSurface(find.text('Price (EGP)')), findsOneWidget);
      expect(inSurface(find.text('Name required')), findsOneWidget);
      expect(inSurface(find.text('Invalid price')), findsOneWidget);
      expect(
        inSurface(find.text('Category must match an existing category')),
        findsOneWidget,
      );
      expect(inSurface(find.text('1 of 4 rows are valid')), findsOneWidget);
      // Ignoring the description column strikes it through.
      await chooseIn(h, surface, 'Column 4', '— ignore —');
      final cell = tester.widget<Text>(
        inSurface(find.text('Steamed milk and rose')),
      );
      expect(cell.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('MENU-ITEMS-037 / 038 Create n: the valid rows, toast, '
        'listed', (tester) async {
      final s = itemsServer();
      final h = await pumpItems(tester, seeded: s);
      await _openPaste(h);
      await _paste(
        h,
        'Rose Latte,125.5,hot coffee ,Steamed milk and rose\n'
        'Dates Shake,90,Fresh Juice\n'
        'Bad,x,Fresh Juice\n',
      );
      await h.tap(inSurface(find.text('Create 2')));
      final posts = callsOf(h, 'POST', '/menu-items');
      expect(posts.map((c) => c.body).toSet(), {
        {
          'base_price': 12550,
          'category_id': category('hot'),
          'description': 'Steamed milk and rose',
          'name': 'Rose Latte',
          'org_id': sabahOrg,
        },
        {
          'base_price': 9000,
          'category_id': category('juice'),
          'description': null,
          'name': 'Dates Shake',
          'org_id': sabahOrg,
        },
      });
      expect(find.byType(DashSurface), findsNothing);
      await h.expectToast('Created 2 items');
      expect(liveItems(s.db).length, 42);
      expect(find.bySemanticsLabel('Items 42'), findsOneWidget);
    });

    testWidgets('MENU-ITEMS-038 some failed: the error toast, and "Retry '
        'failed" re-runs only those', (tester) async {
      final s = itemsServer();
      final h = await pumpItems(tester, seeded: s);
      s.server.fail('POST', '/menu-items', MockResponse.error(500, 'boom'));
      await _openPaste(h);
      await _paste(
        h,
        'Rose Latte\t125\tHot Coffee\nDates Shake\t90\tFresh Juice\n',
      );
      await h.tap(inSurface(find.text('Create 2')));
      expect(find.text('Created 1, 1 failed'), findsWidgets);
      await h.tap(find.text('Retry failed'));
      final posts = callsOf(h, 'POST', '/menu-items');
      expect(posts, hasLength(3));
      expect(posts.last.body, posts.first.body);
      await h.expectToast('Created 1 items');
    });

    testWidgets('MENU-ITEMS-111 no header detection, "45 EGP" is 45, an '
        'Arabic category never matches', (tester) async {
      final h = await pumpItems(tester);
      await _openPaste(h);
      await _paste(
        h,
        'Name\tPrice\tCategory\n'
        'Rose Latte\t45 EGP\tHot Coffee\n'
        'Mint Tea\t30\tشاي وأكثر\n',
      );
      expect(inSurface(find.text('Invalid price')), findsOneWidget);
      expect(
        inSurface(find.text('Category must match an existing category')),
        findsOneWidget,
      );
      expect(inSurface(find.text('1 of 3 rows are valid')), findsOneWidget);
      await h.tap(inSurface(find.text('Create 1')));
      expect(lastCall(h, 'POST', '/menu-items').body, {
        'base_price': 4500,
        'category_id': category('hot'),
        'description': null,
        'name': 'Rose Latte',
        'org_id': sabahOrg,
      });
      await h.flushTimers();
    });

    testWidgets('MENU-ITEMS-111 Cancel on the map step discards; reopening '
        'starts empty', (tester) async {
      final h = await pumpItems(tester);
      await _openPaste(h);
      await _paste(h, 'Rose Latte\t45\tHot Coffee\n');
      await h.tap(inSurface(find.text('Cancel')));
      await _openPaste(h);
      expect(inSurface(find.text('Next')), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: fieldIn(surface, 'Paste rows'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '',
      );
    });
  });
}
