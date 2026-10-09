// `/menu/combos` driven through the real app shell (inventory rows
// OFFR-CMB-001..037). Expectations come from the area seed: six combos,
// by name "Brunch for Two", "Coffee & Cookie" (fixed, no category),
// "Iced Afternoon" (15:00-19:00, not on sale at the seed's 10:00),
// "Kids' Cocoa & Cookie" (fixed, Fri/Sat only), "Morning Croissant Combo"
// and the inactive "Ramadan Suhoor Box".
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:dashboard_catalog_offers/src/combos/combos_page.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _brunch = 'Brunch for Two';
const _cookie = 'Coffee & Cookie';
const _iced = 'Iced Afternoon';
const _kids = "Kids' Cocoa & Cookie";
const _morning = 'Morning Croissant Combo';
const _suhoor = 'Ramadan Suhoor Box';
const _all = [_brunch, _cookie, _iced, _kids, _morning, _suhoor];

/// The option [label] in the open select's list.
Finder option(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is DashOptionList),
  matching: find.text(label),
);

/// Waits out the search's 300 ms pause.
Future<void> afterDebounce(DashHarness h) async {
  await h.tester.pump(const Duration(milliseconds: 300));
  await h.settle();
}

/// The query of the last `GET /combos`.
Map<String, List<String>> lastQuery(DashHarness h) =>
    callsTo(h, combosApi).last.query;

void main() {
  group('the page', () {
    testWidgets('OFFR-CMB-001 the sidebar leaf "Combos" opens the list in '
        'the shell', (tester) async {
      final h = await pumpCombos(tester, path: '/menu/deals');
      final leaf = find.descendant(
        of: find.byType(DashSidebar),
        matching: find.text('Combos'),
      );
      await h.tap(leaf);
      expect(h.location.path, combosPath);
      expect(find.byType(CombosPage), findsOneWidget);
      expect(find.byType(DashSidebar), findsOneWidget);
      expect(shownNames(tester), _all);
    });

    testWidgets('OFFR-CMB-002 without menu.items.read: the Restricted state '
        'and no request at all', (tester) async {
      final s = serverWithCaps(['menu.combos.edit', 'org.settings.read']);
      final h = await pumpCombos(tester, seeded: s);
      expect(pageText('Combos'), findsOneWidget);
      expect(pageText('Not available on this account'), findsOneWidget);
      expect(
        pageText(
          "Your account can't see the menu. The owner can give you access.",
        ),
        findsOneWidget,
      );
      expect(searchBox(), findsNothing);
      expect(inPage(find.byWidgetPredicate((w) => w is DashDataTable)), findsNothing);
      expect(pageButton('New combo'), findsNothing);
      expect(callsTo(h, combosApi), isEmpty);
      expect(callsTo(h, categoriesApi), isEmpty);
    });

    testWidgets('OFFR-CMB-003 header: the title and the description', (
      tester,
    ) async {
      await pumpCombos(tester);
      expect(
        find.descendant(
          of: find.byType(DashPageHeader),
          matching: find.text('Combos'),
        ),
        findsOneWidget,
      );
      expect(
        pageText(
          'Meal deals and fixed bundles: a set price for items picked from '
          'slots. Each item keeps its own recipe, station and stock.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('OFFR-CMB-004 "Channels and margin" goes to the combo '
        'settings; shown for org.settings.read or menu.combos.edit', (
      tester,
    ) async {
      final h = await pumpCombos(tester);
      final link = pageButton('Channels and margin');
      expect(link, findsOneWidget);
      expect(tester.widget<DashButton>(link).trailingIcon, 'arrow-right');
      expect(
        tester.widget<DashButton>(link).variant,
        DashButtonVariant.ghost,
      );
      h.allowUnmatched = true; // /settings/combos is the setup area's
      await h.tap(link);
      expect(h.location.path, '/settings/combos');
    });

    testWidgets('OFFR-CMB-004 the link per right', (tester) async {
      Future<bool> shows(List<String> caps) async {
        await pumpCombos(tester, seeded: serverWithCaps(caps));
        return pageButton('Channels and margin').evaluate().isNotEmpty;
      }

      expect(await shows(['menu.items.read']), isFalse);
      expect(await shows(['menu.items.read', 'org.settings.read']), isTrue);
      expect(await shows(['menu.items.read', 'menu.combos.edit']), isTrue);
    });

    testWidgets('OFFR-CMB-004 the arrow points the reading way in Arabic', (
      tester,
    ) async {
      await pumpCombos(tester, locale: 'ar');
      final link = pageButton('القنوات والهامش');
      expect(tester.widget<DashButton>(link).trailingIcon, 'arrow-left');
    });

    testWidgets('OFFR-CMB-005 "New combo" opens the editor at '
        '/menu/combos/new', (tester) async {
      final h = await pumpCombos(tester);
      h.allowUnmatched = true; // the editor is its own unit
      await h.tap(pageButton('New combo'));
      expect(h.location.path, '/menu/combos/new');
    });

    testWidgets('OFFR-CMB-005 / -023 with menu.items.read only: no New '
        'combo; with menu.combos.edit as well: New combo', (tester) async {
      await pumpCombos(
        tester,
        seeded: serverWithCaps(['menu.items.read', 'menu.categories.read']),
      );
      expect(pageButton('New combo'), findsNothing);
      await pumpCombos(
        tester,
        seeded: serverWithCaps([
          'menu.items.read',
          'menu.categories.read',
          'menu.combos.edit',
        ]),
      );
      expect(pageButton('New combo'), findsOneWidget);
    });
  });

  group('search and filters', () {
    testWidgets('OFFR-CMB-006 the search: its words, 300 ms, then `q`; the '
        'English or the Arabic name', (tester) async {
      final h = await pumpCombos(tester);
      final box = searchBox();
      expect(
        tester.widget<DashSearchInput>(box).placeholder,
        'Search combos',
      );
      expect(find.bySemanticsLabel('Search combos'), findsWidgets);
      expect(tester.getSize(box).width, CombosMetrics.search);
      final before = callsTo(h, combosApi).length;
      await h.enterText(box, 'cookie');
      expect(callsTo(h, combosApi), hasLength(before), reason: 'debounced');
      await afterDebounce(h);
      expect(callsTo(h, combosApi), hasLength(before + 1));
      expect(lastQuery(h)['q'], ['cookie']);
      expect(shownNames(tester), [_cookie, _kids]);

      await h.enterText(box, 'عصرية');
      await afterDebounce(h);
      expect(lastQuery(h)['q'], ['عصرية']);
      expect(shownNames(tester), [_iced]);

      // Empty: no `q` — the first page's own key, still fresh in the cache.
      final asked = callsTo(h, combosApi).length;
      await h.enterText(box, '');
      await afterDebounce(h);
      expect(callsTo(h, combosApi), hasLength(asked), reason: 'from cache');
      expect(callsTo(h, combosApi).first.query.containsKey('q'), isFalse);
      expect(shownNames(tester), _all);
    });

    testWidgets('OFFR-CMB-007 Category: "All categories", then the org\'s '
        'categories; a pick sends category_id, All omits it', (tester) async {
      final h = await pumpCombos(tester);
      final select = filterSelect('Category');
      expect(select, findsOneWidget);
      expect(find.bySemanticsLabel('Category: All categories'), findsWidgets);
      await h.tap(select);
      final names = [
        for (final e in find
            .descendant(
              of: find.byWidgetPredicate((w) => w is DashOptionList),
              matching: find.byType(Text),
            )
            .evaluate())
          (e.widget as Text).data,
      ];
      expect(names.first, 'All categories');
      expect(
        names,
        containsAllInOrder([
          'All categories',
          'Hot Coffee',
          'Iced Coffee',
          'Tea & More',
          'Fresh Juice',
          'Bakery',
          'Desserts',
          'Breakfast',
        ]),
      );
      await h.tap(option('Breakfast'));
      expect(lastQuery(h)['category_id'], [OffersSeed.category('breakfast')]);
      expect(shownNames(tester), [_brunch, _suhoor]);

      final asked = callsTo(h, combosApi).length;
      await h.tap(filterSelect('Category'));
      await h.tap(option('All categories'));
      expect(callsTo(h, combosApi), hasLength(asked), reason: 'from cache');
      expect(shownNames(tester), _all);
    });

    testWidgets('OFFR-CMB-008 Status: both (default), Active, Inactive', (
      tester,
    ) async {
      final h = await pumpCombos(tester);
      expect(
        find.bySemanticsLabel('Status: Active and inactive'),
        findsWidgets,
      );
      expect(lastQuery(h).containsKey('is_active'), isFalse);
      await h.tap(filterSelect('Status'));
      await h.tap(option('Active'));
      expect(lastQuery(h)['is_active'], ['true']);
      expect(shownNames(tester), [_brunch, _cookie, _iced, _kids, _morning]);
      await h.tap(filterSelect('Status'));
      await h.tap(option('Inactive'));
      expect(lastQuery(h)['is_active'], ['false']);
      expect(shownNames(tester), [_suhoor]);
      final asked = callsTo(h, combosApi).length;
      await h.tap(filterSelect('Status'));
      await h.tap(option('Active and inactive'));
      expect(callsTo(h, combosApi), hasLength(asked), reason: 'from cache');
      expect(shownNames(tester), _all);
    });

    testWidgets('OFFR-CMB-009 a search, category or status change returns '
        'to page 1', (tester) async {
      final s = combosServer();
      addCombos(s.db, 30);
      final h = await pumpCombos(tester, seeded: s);
      Future<void> toPage2() async {
        await h.tap(inPage(find.bySemanticsLabel('Next')));
        expect(lastQuery(h)['page'], ['2']);
      }

      await toPage2();
      await h.tap(filterSelect('Status'));
      await h.tap(option('Active'));
      expect(lastQuery(h)['page'], ['1']);
      expect(lastQuery(h)['is_active'], ['true']);

      await toPage2();
      await h.enterText(searchBox(), 'combo');
      await afterDebounce(h);
      expect(lastQuery(h)['page'], ['1']);
      expect(lastQuery(h)['q'], ['combo']);

      await toPage2();
      await h.tap(filterSelect('Category'));
      await h.tap(option('Bakery'));
      expect(lastQuery(h)['page'], ['1']);
    });

    testWidgets('OFFR-CMB-010 the request: page 1, 25 a page, nothing else; '
        'rows in the server\'s order', (tester) async {
      final h = await pumpCombos(tester);
      final calls = callsTo(h, combosApi);
      expect(calls, hasLength(1));
      expect(calls.single.query, {
        'page': ['1'],
        'per_page': ['25'],
      });
      expect(callsTo(h, categoriesApi).single.query, {
        'org_id': [SeedIds.sabahOrg],
      });
      expect(shownNames(tester), _all);
    });
  });

  group('columns', () {
    testWidgets('OFFR-CMB-011 Combo: the tile, the English name, Fixed only '
        'on fixed bundles, the Arabic name under it', (tester) async {
      final s = combosServer();
      OffersSeed.loadInto(s.db);
      s.db.table(OffersTables.menuItems).find(comboId('morning-croissant'))![
          'image_url'] = 'https://cdn.madar.test/combos/morning.jpg';
      await pumpCombos(tester, seeded: s);
      expect(inPage(find.text('Fixed')), findsNWidgets(2));
      expect(inRow(_cookie, find.text('Fixed')), findsOneWidget);
      expect(inRow(_kids, find.text('Fixed')), findsOneWidget);
      expect(inRow(_brunch, find.text('Fixed')), findsNothing);
      expect(inRow(_cookie, find.text('قهوة وكوكيز')), findsOneWidget);
      // An image (its glyph while it cannot load), else the glyph alone.
      expect(inRow(_morning, find.byType(Image)), findsOneWidget);
      expect(inRow(_brunch, find.byType(Image)), findsNothing);
      expect(
        inRow(
          _brunch,
          find.byWidgetPredicate(
            (w) => w is DashIcon && w.name == 'utensils-crossed',
          ),
        ),
        findsOneWidget,
      );
      final tile = tester.getSize(inRow(_brunch, find.byType(ComboThumb)));
      expect(tile, const Size.square(40));
    });

    testWidgets('OFFR-CMB-012 Category: the translated name, "—" when none', (
      tester,
    ) async {
      await pumpCombos(tester);
      expect(inRow(_brunch, find.text('Breakfast')), findsOneWidget);
      expect(inRow(_iced, find.text('Iced Coffee')), findsOneWidget);
      expect(inRow(_cookie, find.text('—')), findsOneWidget);
    });

    testWidgets('OFFR-CMB-013 / -014 Price in money, Slots as counted', (
      tester,
    ) async {
      final h = await pumpCombos(tester);
      final f = h.container.read(formatProvider);
      expect(f.fmtMoney(12000), 'EGP 120.00');
      expect(inRow(_cookie, find.text(ltr(f.fmtMoney(12000)))), findsOneWidget);
      expect(inRow(_brunch, find.text(ltr(f.fmtMoney(52000)))), findsOneWidget);
      expect(inRow(_suhoor, find.text(ltr('3'))), findsOneWidget);
      expect(inRow(_cookie, find.text(ltr('2'))), findsOneWidget);
    });

    testWidgets('OFFR-CMB-015 Margin: the warnings chip only where the '
        'server warns, then the default margin', (tester) async {
      await pumpCombos(tester);
      // Hand figures: (120 − 15 − 18) / 120 = 72.5 %; (150 − 31 − 18) / 150.
      expect(inRow(_cookie, find.text(ltr('72.5%'))), findsOneWidget);
      expect(inRow(_kids, find.text(ltr('67.3%'))), findsOneWidget);
      expect(inRow(_cookie, find.textContaining('warning')), findsNothing);
      expect(inRow(_brunch, find.text('2 warnings')), findsOneWidget);
      expect(inRow(_brunch, find.text(ltr('—'))), findsOneWidget);
      expect(inRow(_iced, find.text('1 warning')), findsOneWidget);
    });

    testWidgets('OFFR-CMB-016 Status: Inactive, On sale now, Not on sale '
        'now', (tester) async {
      await pumpCombos(tester);
      DashStatusPill pill(String row) => tester.widget<DashStatusPill>(
        inRow(row, find.byType(DashStatusPill)).last,
      );
      expect(pill(_suhoor).label, 'Inactive');
      expect(pill(_suhoor).tone, DashTone.neutral);
      expect(pill(_cookie).label, 'On sale now');
      expect(pill(_cookie).tone, DashTone.success);
      expect(pill(_iced).label, 'Not on sale now');
      expect(pill(_iced).tone, DashTone.accent);
      expect(pill(_kids).label, 'Not on sale now');
    });
  });

  group('opening and deleting', () {
    testWidgets('OFFR-CMB-017 a row opens the combo for every reader', (
      tester,
    ) async {
      final h = await pumpCombos(
        tester,
        seeded: serverWithCaps(['menu.items.read', 'menu.categories.read']),
      );
      h.allowUnmatched = true;
      await h.tap(rowOf(_iced));
      expect(h.location.path, '/menu/combos/${comboId('iced-afternoon')}');
    });

    testWidgets('OFFR-CMB-017 Enter on a focused row opens it', (
      tester,
    ) async {
      final h = await pumpCombos(tester);
      h.allowUnmatched = true;
      final inner = find
          .descendant(of: rowOf(_cookie), matching: find.byType(GestureDetector))
          .first;
      Focus.of(tester.element(inner)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await h.settle();
      expect(h.location.path, '/menu/combos/${comboId('coffee-cookie')}');
    });

    testWidgets('OFFR-CMB-018 the pencil opens that combo', (tester) async {
      final h = await pumpCombos(tester);
      h.allowUnmatched = true;
      await h.tap(rowButton(_kids, 'Edit'));
      expect(h.location.path, '/menu/combos/${comboId('kids-cocoa')}');
    });

    testWidgets('OFFR-CMB-019 Delete asks first: the name, the words, a red '
        'Delete', (tester) async {
      final h = await pumpCombos(tester);
      expect(inPage(find.bySemanticsLabel('Delete')), findsNWidgets(6));
      await h.tap(rowButton(_iced, 'Delete'));
      final dialog = find.byType(DashConfirmDialog);
      expect(dialog, findsOneWidget);
      final d = tester.widget<DashConfirmDialog>(dialog);
      expect(d.title, 'Delete Iced Afternoon?');
      expect(
        d.description,
        'It leaves the menu at every branch and on every channel. Past '
        'orders keep their lines and still show in the Bundles report.',
      );
      expect(d.confirmLabel, 'Delete');
      expect(d.destructive, isTrue);
      expect(
        tester
            .widget<DashButton>(
              find.descendant(
                of: dialog,
                matching: find.byWidgetPredicate(
                  (w) => w is DashButton && w.label == 'Delete',
                ),
              ),
            )
            .variant,
        DashButtonVariant.destructive,
      );
      await h.tapText('Cancel');
    });

    testWidgets('OFFR-CMB-019 in Arabic the title names the Arabic name', (
      tester,
    ) async {
      final h = await pumpCombos(tester, locale: 'ar');
      await h.tap(rowButton(_iced, 'حذف'));
      expect(
        tester.widget<DashConfirmDialog>(find.byType(DashConfirmDialog)).title,
        'حذف عصرية مثلجة؟',
      );
      await h.tapText('إلغاء');
    });

    testWidgets('OFFR-CMB-020 / OFFR-ALL-014 Cancel, Escape and a click outside do nothing', (
      tester,
    ) async {
      final h = await pumpCombos(tester);
      await h.tap(rowButton(_iced, 'Delete'));
      await h.tapText('Cancel');
      expect(find.byType(DashConfirmDialog), findsNothing);
      await h.tap(rowButton(_iced, 'Delete'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(find.byType(DashConfirmDialog), findsNothing);
      await h.tap(rowButton(_iced, 'Delete'));
      await tester.tapAt(const Offset(4, 4));
      await h.settle();
      expect(find.byType(DashConfirmDialog), findsNothing);
      expect(callsTo(h, deleteApi, method: 'DELETE'), isEmpty);
      expect(shownNames(tester), _all);
      expect(find.text('Combo deleted'), findsNothing);
    });

    testWidgets('OFFR-CMB-021 confirming deletes it as a menu item, says so '
        'and refetches the list', (tester) async {
      final h = await pumpCombos(tester);
      final lists = callsTo(h, combosApi).length;
      final cats = callsTo(h, categoriesApi).length;
      await h.tap(rowButton(_iced, 'Delete'));
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      final del = callsTo(h, deleteApi, method: 'DELETE');
      expect(del, hasLength(1));
      expect(del.single.path, '/menu-items/${comboId('iced-afternoon')}');
      await h.expectToast('Combo deleted');
      expect(callsTo(h, combosApi), hasLength(lists + 1));
      expect(callsTo(h, categoriesApi), hasLength(cats), reason: 'not stale');
      expect(shownNames(tester), [_brunch, _cookie, _kids, _morning, _suhoor]);
    });

    testWidgets('OFFR-CMB-022 a combos editor without menu.items.delete is '
        'refused: the words, and the row stays', (tester) async {
      final s = serverWithCaps([
        'menu.items.read',
        'menu.categories.read',
        'menu.combos.edit',
      ]);
      final h = await pumpCombos(tester, seeded: s);
      await h.tap(rowButton(_iced, 'Delete'));
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      expect(callsTo(h, deleteApi, method: 'DELETE').single.status, 403);
      await h.expectToast(
        h.refusalWords(MockResponse.denied('menu.items.delete')),
      );
      expect(shownNames(tester), _all);
    });

    testWidgets('OFFR-CMB-022 a failed delete toasts the transport\'s words', (
      tester,
    ) async {
      final s = combosServer();
      final failure = MockResponse.error(500, 'Database error: connection reset');
      s.server.fail('DELETE', deleteApi, failure);
      final h = await pumpCombos(tester, seeded: s);
      await h.tap(rowButton(_iced, 'Delete'));
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      await h.expectToast(h.refusalWords(failure));
      expect(shownNames(tester), _all);
    });

    testWidgets('OFFR-CMB-023 without menu.combos.edit: no New combo, no '
        'Edit or Delete, the empty actions cell stays', (tester) async {
      await pumpCombos(
        tester,
        seeded: serverWithCaps(['menu.items.read', 'menu.categories.read']),
      );
      expect(pageButton('New combo'), findsNothing);
      expect(inPage(find.byType(DashIconButton)), findsNothing);
      // The name column still ends where it would with the actions shown.
      expect(inPage(find.byType(ComboNameCell)), findsNWidgets(6));
    });
  });

  group('pages and states', () {
    testWidgets('OFFR-CMB-024 / OFFR-ALL-013 the server\'s pages: "Page 1 of 2", Next and '
        'Previous keep the filters', (tester) async {
      final s = combosServer();
      addCombos(s.db, 30);
      final h = await pumpCombos(tester, seeded: s);
      expect(pageText('Page 1 of 2'), findsOneWidget);
      expect(shownNames(tester), hasLength(25));
      await h.tap(filterSelect('Status'));
      await h.tap(option('Active'));
      expect(pageText('Page 1 of 2'), findsOneWidget);
      await h.tap(inPage(find.bySemanticsLabel('Next')));
      expect(lastQuery(h), {
        'is_active': ['true'],
        'page': ['2'],
        'per_page': ['25'],
      });
      expect(pageText('Page 2 of 2'), findsOneWidget);
      expect(shownNames(tester), hasLength(10));
      final next = tester.widget<DashIconButton>(
        inPage(
          find.byWidgetPredicate(
            (w) => w is DashIconButton && w.semanticLabel == 'Next',
          ),
        ),
      );
      expect(next.onPressed, isNull);
      final asked = callsTo(h, combosApi).length;
      await h.tap(inPage(find.bySemanticsLabel('Previous')));
      expect(pageText('Page 1 of 2'), findsOneWidget);
      expect(callsTo(h, combosApi), hasLength(asked), reason: 'from cache');
    });

    testWidgets('OFFR-CMB-024 one page: no footer', (tester) async {
      await pumpCombos(tester);
      expect(inPage(find.byType(DashPagination)), findsNothing);
    });

    testWidgets('OFFR-CMB-025 no combos yet: the hint and New combo', (
      tester,
    ) async {
      final s = combosServer();
      clearCombos(s.db);
      final h = await pumpCombos(tester, seeded: s);
      expect(pageText('No combos yet'), findsOneWidget);
      expect(
        pageText(
          'A combo sells several items at one price: a burger meal with a '
          'side and a drink, or a coffee and a cake.',
        ),
        findsOneWidget,
      );
      final buttons = pageButton('New combo');
      expect(buttons, findsNWidgets(2), reason: 'header and empty state');
      h.allowUnmatched = true;
      await h.tap(
        find.descendant(of: find.byType(DashEmptyState), matching: buttons),
      );
      expect(h.location.path, '/menu/combos/new');
    });

    testWidgets('OFFR-CMB-025 no combos and no right to add one: no button', (
      tester,
    ) async {
      final s = serverWithCaps(['menu.items.read', 'menu.categories.read']);
      clearCombos(s.db);
      await pumpCombos(tester, seeded: s);
      expect(pageText('No combos yet'), findsOneWidget);
      expect(pageButton('New combo'), findsNothing);
    });

    testWidgets('OFFR-CMB-026 nothing matches the filters: one line, no '
        'button', (tester) async {
      final h = await pumpCombos(tester);
      await h.enterText(searchBox(), 'falafel');
      await afterDebounce(h);
      expect(pageText('No combo matches these filters'), findsOneWidget);
      expect(pageText('No combos yet'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(DashEmptyState),
          matching: find.byType(DashButton),
        ),
        findsNothing,
      );
      final empty = tester.widget<DashEmptyState>(
        inPage(find.byType(DashEmptyState)),
      );
      expect(empty.description, isNull);
    });

    testWidgets('OFFR-CMB-027 / OFFR-ALL-012 loading: skeleton rows in the table, then the '
        'rows', (tester) async {
      final s = combosServer();
      final gate = s.server.hold('GET', combosApi);
      final h = await pumpCombos(tester, seeded: s);
      expect(inPage(find.byType(DashSkeleton)), findsWidgets);
      expect(inPage(find.text('COMBO')), findsOneWidget, reason: 'header');
      expect(shownNames(tester), isEmpty);
      gate.release();
      await h.settle();
      expect(inPage(find.byType(DashSkeleton)), findsNothing);
      expect(shownNames(tester), _all);
    });

    testWidgets('OFFR-CMB-027 loading on a phone: four skeleton cards', (
      tester,
    ) async {
      final s = combosServer();
      final gate = s.server.hold('GET', combosApi);
      final h = await pumpCombos(tester, seeded: s, size: DashSize.phone);
      expect(inPage(find.byType(DashSkeleton)), findsNWidgets(4));
      gate.release();
      await h.settle();
      expect(shownNames(tester), _all);
    });

    testWidgets('OFFR-CMB-028 / OFFR-ALL-012 a failed list: the words, the server\'s '
        'reason, Retry asks the list again', (tester) async {
      final s = combosServer();
      final failure = MockResponse.error(500, 'Database error: pool timed out');
      s.server.fail('GET', combosApi, failure);
      final h = await pumpCombos(tester, seeded: s);
      expect(pageText("Couldn't load this"), findsOneWidget);
      expect(pageText(h.refusalWords(failure)), findsOneWidget);
      expect(shownNames(tester), isEmpty);
      final cats = callsTo(h, categoriesApi).length;
      // While the Retry runs the failure stays, never "no combos".
      final gate = h.server.hold('GET', combosApi);
      await h.tap(inPage(find.text('Retry')));
      expect(pageText("Couldn't load this"), findsOneWidget);
      expect(pageText('No combos yet'), findsNothing);
      expect(inPage(find.byType(DashSkeleton)), findsNothing);
      gate.release();
      await h.settle();
      expect(callsTo(h, combosApi), hasLength(2));
      expect(callsTo(h, categoriesApi), hasLength(cats));
      expect(pageText("Couldn't load this"), findsNothing);
      expect(shownNames(tester), _all);
    });

    testWidgets('OFFR-CMB-029 / OFFR-ALL-010 Columns: Category, Price, Slots, Margin and '
        'Status can be hidden, Combo cannot', (tester) async {
      final h = await pumpCombos(tester);
      await h.tap(pageButton('Columns'));
      final menu = tester.widget<DashMenu>(inPage(find.byType(DashMenu)));
      expect(
        [for (final i in menu.items) i.label],
        ['Category', 'Price', 'Slots', 'Margin', 'Status'],
      );
      await h.tap(find.text('Category').last);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(inPage(find.text('CATEGORY')), findsNothing);
      expect(inRow(_brunch, find.text('Breakfast')), findsNothing);
      expect(inPage(find.text('COMBO')), findsOneWidget);
    });

    testWidgets('OFFR-CMB-030 / OFFR-ALL-011 a phone: full-width search, each combo a '
        'card with its actions and label/value pairs; a tap opens it', (
      tester,
    ) async {
      final h = await pumpCombos(tester, size: DashSize.phone);
      final pageWidth = tester.getSize(
        inPage(find.byWidgetPredicate((w) => w is DashDataTable)),
      );
      expect(tester.getSize(searchBox()).width, pageWidth.width);
      expect(pageButton('Columns'), findsNothing);
      expect(inPage(find.byType(DashCard)), findsWidgets);
      for (final label in ['Category', 'Price', 'Slots', 'Margin', 'Status']) {
        expect(inRow(_brunch, find.text(label)), findsOneWidget, reason: label);
      }
      expect(rowButton(_brunch, 'Edit'), findsOneWidget);
      expect(rowButton(_brunch, 'Delete'), findsOneWidget);
      h.allowUnmatched = true;
      await h.tap(inRow(_brunch, find.text('Breakfast')));
      expect(h.location.path, '/menu/combos/${comboId('brunch-for-two')}');
    });

    testWidgets('OFFR-CMB-031 a platform admin with no org picked: "No '
        'combos yet", nothing asked', (tester) async {
      final h = await pumpCombos(tester, persona: Persona.platform);
      expect(h.container.read(orgIdProvider), isNull);
      expect(find.byType(CombosPage), findsOneWidget);
      expect(pageText('No combos yet'), findsOneWidget);
      expect(callsTo(h, combosApi), isEmpty);
      expect(callsTo(h, categoriesApi), isEmpty);
    });

    testWidgets('OFFR-CMB-032 Arabic: words in Arabic, the English name '
        'leads with the Arabic under it, Latin digits', (tester) async {
      await pumpCombos(tester, locale: 'ar');
      expect(
        find.descendant(
          of: find.byType(DashPageHeader),
          matching: find.text('الكومبو'),
        ),
        findsOneWidget,
      );
      expect(inPage(find.text('كومبو جديد')), findsOneWidget);
      expect(inRow(_brunch, find.text('برانش لشخصين')), findsOneWidget);
      expect(inRow(_brunch, find.text('فطور')), findsOneWidget);
      expect(inRow(_brunch, find.text('تنبيهان')), findsOneWidget);
      expect(inRow(_cookie, find.text('ثابت')), findsOneWidget);
      expect(inRow(_suhoor, find.text('غير نشط')), findsOneWidget);
      expect(inRow(_cookie, find.text('متاح للبيع الآن')), findsOneWidget);
      expect(inRow(_cookie, find.textContaining('120.00')), findsOneWidget);
      expect(inRow(_cookie, find.textContaining('72.5')), findsOneWidget);
      expect(
        find.bySemanticsLabel('الفئة: كل الفئات'),
        findsWidgets,
        reason: 'the Category filter in Arabic',
      );
    });

    testWidgets('OFFR-CMB-033 a deep link with the shell\'s scope opens the '
        'list in that scope', (tester) async {
      final h = await pumpCombos(
        tester,
        path: '$combosPath?branchId=${SeedIds.zamalek}&preset=today',
      );
      expect(find.byType(CombosPage), findsOneWidget);
      expect(h.container.read(currentScopeProvider).branchId, SeedIds.zamalek);
      expect(shownNames(tester), _all);
    });

    testWidgets('OFFR-CMB-034 search, filters and page are not kept: back '
        'from a combo starts afresh', (tester) async {
      final h = await pumpCombos(tester);
      await h.enterText(searchBox(), 'cookie');
      await afterDebounce(h);
      await h.tap(filterSelect('Status'));
      await h.tap(option('Active'));
      expect(shownNames(tester), [_cookie, _kids]);
      h.allowUnmatched = true;
      await h.tap(rowOf(_cookie));
      await h.go(combosPath);
      expect(shownNames(tester), _all);
      expect(tester.widget<DashSearchInput>(searchBox()).value, '');
      expect(find.bySemanticsLabel('Status: Active and inactive'), findsWidgets);
    });

    testWidgets('OFFR-CMB-035 (divergence) opening a combo keeps the scope', (
      tester,
    ) async {
      final h = await pumpCombos(
        tester,
        path: '$combosPath?branchId=${SeedIds.zamalek}',
      );
      h.allowUnmatched = true;
      await h.tap(rowOf(_brunch));
      expect(h.location.path, '/menu/combos/${comboId('brunch-for-two')}');
      expect(h.container.read(currentScopeProvider).branchId, SeedIds.zamalek);
    });

    testWidgets('OFFR-CMB-036 (divergence) deleting the only combo of the '
        'last page steps back to the page before', (tester) async {
      final s = combosServer();
      addCombos(s.db, 20); // 26 combos: the last page holds one
      final h = await pumpCombos(tester, seeded: s);
      await h.tap(inPage(find.bySemanticsLabel('Next')));
      expect(shownNames(tester), [_suhoor]);
      await h.tap(rowButton(_suhoor, 'Delete'));
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      await h.expectToast('Combo deleted');
      await h.settle();
      expect(lastQuery(h)['page'], ['1']);
      expect(shownNames(tester), hasLength(25));
      expect(pageText('No combos yet'), findsNothing);
    });

    testWidgets('OFFR-CMB-037 categories failing: only "All categories", '
        'every Category cell "—", no error', (tester) async {
      final s = combosServer();
      s.server.fail(
        'GET',
        categoriesApi,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpCombos(tester, seeded: s);
      expect(pageText("Couldn't load this"), findsNothing);
      expect(inPage(find.text('—')), findsNWidgets(_all.length));
      await h.tap(filterSelect('Category'));
      expect(
        find.descendant(
          of: find.byWidgetPredicate((w) => w is DashOptionList),
          matching: find.byType(Text),
        ),
        findsOneWidget,
      );
      expect(option('All categories'), findsOneWidget);
    });
  });
}
