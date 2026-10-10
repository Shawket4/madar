// `/menu/pricing` driven through the real app shell (inventory rows
// MENU-PRC-001..033, and MENU-AREA-007/008/010 where they touch it).
// Expectations come from the area seed. Page 1 of the items (24 of 40, by
// name) runs from Almond Croissant to Iced Mocha; at Zamalek, Iced Latte
// Regular costs EGP 145 for Outside delivery (catalog 130), oat milk costs
// EGP 30 in-store (catalog 25) and almond milk is hidden for In-mall.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/items/items_widgets.dart'
    show MenuImageTile;
import 'package:dashboard_catalog_menu/src/pricing/pricing_widgets.dart';
import 'package:dashboard_catalog_menu/src/shared/unsaved_bar.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart' show MadarHoldHint;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final String _iced = sizeId('iced_latte', 'Regular');
final String _icedL = sizeId('iced_latte', 'Large');
final String _oat = optionId('milk', 'oat');
final String _almond = optionId('milk', 'almond');

Finder get _bar => find.byType(MenuUnsavedBar);

Finder _inBar(String text) =>
    find.descendant(of: _bar, matching: find.text(text));

Future<void> _save(DashHarness h) => h.tap(_inBar('Save'));

Future<void> _addonsTab(DashHarness h) => h.tap(pageText('Add-ons'));

/// Types into the toolbar search and lets the 300 ms debounce run.
Future<void> _search(DashHarness h, String q) async {
  await h.enterText(inPage(find.byType(DashSearchInput)), q);
  await h.tester.pump(DashSearchInput.listDelay);
  await h.settle();
}

/// The PUT / DELETE bodies sent so far.
List<Map<String, Object?>> _writes(DashHarness h, String method) => [
  for (final c in h.server.callsTo(overrideT, method: method))
    (c.body! as Map).cast<String, Object?>(),
];

void main() {
  group('MENU-PRC-001..007 the page shell', () {
    testWidgets('MENU-PRC-001 title and subtitle', (tester) async {
      final h = await pumpPricing(tester);
      expect(pageText('Pricing & availability'), findsOneWidget);
      expect(pageText(h.t('menu.pricing.matrixSubtitle')), findsOneWidget);
    });

    testWidgets('MENU-PRC-002 / MENU-AREA-010 no org: the header and "Select '
        'an organization to manage pricing"', (tester) async {
      final h = await pumpPricing(tester, persona: Persona.platform);
      expect(pageText('Pricing & availability'), findsOneWidget);
      expect(
        pageText('Select an organization to manage pricing'),
        findsOneWidget,
      );
      expect(h.server.callsTo(catalogT), isEmpty);
      expect(h.server.callsTo(addonCatalogT), isEmpty);
    });

    testWidgets('MENU-PRC-003 branches loading: two skeleton blocks', (
      tester,
    ) async {
      final s = pricingServer();
      final gate = s.server.hold('GET', '/branches');
      final h = await pumpPricing(tester, seeded: s);
      expect(inPage(find.byType(DashSkeleton)), findsNWidgets(2));
      expect(inPage(find.byType(DashSegmentedControl<String>)), findsNothing);
      await h.shot('pricing/branches-loading');
      gate.release();
      await h.settle();
      expect(inPage(find.byType(DashSegmentedControl<String>)), findsOneWidget);
      expect(pageText('Almond Croissant'), findsOneWidget);
    });

    testWidgets('MENU-PRC-004 all branches: "Pick a specific branch", no '
        'toolbar, nothing read', (tester) async {
      final h = await pumpPricing(tester, allBranches: true);
      expect(pageText('Pick a specific branch'), findsOneWidget);
      expect(pageText(h.t('menu.pricing.pickBranchHint')), findsOneWidget);
      expect(inPage(find.byType(DashSegmentedControl<String>)), findsNothing);
      expect(h.server.callsTo(catalogT), isEmpty);
      expect(h.server.callsTo(channelAddonT), isEmpty);
      await h.shot('pricing/pick-branch');
    });

    testWidgets('MENU-PRC-005 toolbar: tabs, search, branch, legend', (
      tester,
    ) async {
      await pumpPricing(tester);
      final seg = tester.widget<DashSegmentedControl<String>>(
        inPage(find.byType(DashSegmentedControl<String>)),
      );
      expect(seg.value, 'items');
      expect(seg.options.map((o) => o.label), ['Menu items', 'Add-ons']);
      expect(inPage(find.byType(DashSearchInput)), findsOneWidget);
      expect(inPage(find.bySemanticsLabel('Search')), findsWidgets);
      expect(pageText('Zamalek'), findsOneWidget);
      expect(inPage(find.byType(PricingLegend)), findsOneWidget);
    });

    testWidgets('MENU-PRC-006 legend: Unsaved, Inherited (muted), Hidden '
        'here', (tester) async {
      await pumpPricing(tester);
      final legend = find.byType(PricingLegend);
      for (final w in ['Unsaved', 'Inherited (muted)', 'Hidden here']) {
        expect(
          find.descendant(of: legend, matching: find.text(w)),
          findsOneWidget,
        );
      }
    });

    testWidgets('MENU-PRC-007 switching the branch drops every staged edit', (
      tester,
    ) async {
      final h = await pumpPricing(tester);
      await expand(h, 'Iced Latte');
      await typePrice(h, _iced, 'in_store', '135');
      expect(_inBar('1 unsaved changes'), findsOneWidget);
      await h.container.read(scopeProvider.notifier).setBranch(SeedIds.maadi);
      await h.settle();
      expect(_bar, findsNothing);
      expect(pageText('Maadi'), findsOneWidget);
    });
  });

  group('MENU-PRC-008..018 the items tab', () {
    testWidgets('MENU-PRC-008 24 per page, the org, no search', (tester) async {
      final h = await pumpPricing(tester);
      final call = h.server.callsTo(catalogT).single;
      expect(call.query, {
        'org_id': [SeedIds.sabahOrg],
        'page': ['1'],
        'per_page': ['24'],
      });
      expect(inPage(find.byType(PricingItemHead)), findsNWidgets(24));
    });

    testWidgets('MENU-PRC-008 the search waits 300 ms, then asks the server', (
      tester,
    ) async {
      final h = await pumpPricing(tester);
      await tester.enterText(inPage(find.byType(EditableText)).first, 'latte');
      await tester.pump(const Duration(milliseconds: 200));
      expect(h.server.callsTo(catalogT), hasLength(1));
      await tester.pump(const Duration(milliseconds: 100));
      await h.settle();
      final q = h.server.callsTo(catalogT).last.query;
      expect(q['search'], ['latte']);
      expect(q['page'], ['1']);
      expect(pageText('Caffè Latte'), findsOneWidget);
      expect(pageText('Americano'), findsNothing);
    });

    testWidgets('MENU-PRC-009 loading: one skeleton block', (tester) async {
      final s = pricingServer();
      final gate = s.server.hold('GET', catalogT);
      final h = await pumpPricing(tester, seeded: s);
      expect(inPage(find.byType(DashSkeleton)), findsOneWidget);
      expect(inPage(find.byType(PricingMatrix)), findsNothing);
      await h.shot('pricing/loading');
      gate.release();
      await h.settle();
      expect(inPage(find.byType(PricingMatrix)), findsOneWidget);
    });

    testWidgets('MENU-PRC-009 error: "Couldn\'t load items", the server\'s '
        'words, Retry asks again', (tester) async {
      final s = pricingServer();
      final down = MockResponse.error(500, 'Database down');
      s.server.fail('GET', catalogT, down);
      final h = await pumpPricing(tester, seeded: s);
      expect(pageText("Couldn't load items"), findsOneWidget);
      expect(pageText(h.refusalWords(down)), findsOneWidget);
      await h.shot('pricing/error');
      final addons = h.server.callsTo(addonCatalogT).length;
      await h.tap(pageText('Retry'));
      expect(h.server.callsTo(catalogT), hasLength(2));
      expect(h.server.callsTo(addonCatalogT), hasLength(addons));
      expect(inPage(find.byType(PricingMatrix)), findsOneWidget);
    });

    testWidgets('MENU-PRC-009 empty: "No menu items"', (tester) async {
      final h = await pumpPricing(tester);
      await _search(h, 'nothing like this');
      expect(pageText('No menu items'), findsOneWidget);
      expect(inPage(find.byType(DashPagination)), findsNothing);
      await h.shot('pricing/empty');
    });

    testWidgets('MENU-PRC-010 desktop matrix: the head row', (tester) async {
      final h = await pumpPricing(tester);
      expect(inPage(find.byType(PricingMatrix)), findsOneWidget);
      expect(pageText('Item / size'), findsOneWidget);
      expect(
        inPage(find.text('Catalog (ref)', findRichText: true)),
        findsOneWidget,
      );
      for (final w in [
        'In-store',
        'In-mall',
        'Outside',
        'Umbrella',
        'Pickup',
      ]) {
        expect(pageText(w), findsOneWidget, reason: w);
      }
      expect(h.server.callsTo(studioT), isEmpty);
    });

    testWidgets('MENU-PRC-010 narrower than the matrix: it scrolls sideways '
        'and the first column stays', (tester) async {
      await pumpPricing(tester, size: DashSize.tablet);
      final name = pageText('Almond Croissant');
      final pickup = pageText('Pickup');
      final x0 = tester.getTopLeft(name).dx;
      final p0 = tester.getTopLeft(pickup).dx;
      await tester.dragFrom(
        tester.getCenter(pageText('In-mall')),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(name).dx, x0);
      expect(tester.getTopLeft(pickup).dx, lessThan(p0));
    });

    testWidgets('MENU-PRC-010 in Arabic the first column stays at the '
        'right while the rest scrolls', (tester) async {
      await pumpPricing(tester, size: DashSize.tablet, locale: 'ar');
      final name = pageText('كرواسون لوز');
      final pickup = pageText('الاستلام');
      final x0 = tester.getTopRight(name).dx;
      final p0 = tester.getTopLeft(pickup).dx;
      expect(p0, lessThan(0), reason: 'Pickup starts off-screen, at the left');
      await tester.dragFrom(
        tester.getCenter(pageText('داخل المول')),
        const Offset(400, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopRight(name).dx, x0);
      expect(tester.getTopLeft(pickup).dx, greaterThan(p0));
    });

    testWidgets('MENU-PRC-011 a collapsed item: chevron, tile, name, "Expand '
        'to price sizes"; tap → "Collapse"', (tester) async {
      final h = await pumpPricing(tester);
      final head = find.ancestor(
        of: pageText('Iced Latte'),
        matching: find.byType(PricingItemHead),
      );
      expect(
        find.descendant(of: head, matching: find.byType(MenuImageTile)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: head, matching: find.text('Expand to price sizes')),
        findsOneWidget,
      );
      await expand(h, 'Iced Latte');
      expect(
        find.descendant(of: head, matching: find.text('Collapse')),
        findsOneWidget,
      );
      await h.tap(head);
      expect(
        find.descendant(of: head, matching: find.text('Expand to price sizes')),
        findsOneWidget,
      );
      expect(cellOf(_iced, 'in_store'), findsNothing);
    });

    testWidgets('MENU-PRC-011 the dirty dot', (tester) async {
      final h = await pumpPricing(tester);
      final head = find.ancestor(
        of: pageText('Iced Latte'),
        matching: find.byType(PricingItemHead),
      );
      await expand(h, 'Iced Latte');
      expect(
        find.descendant(of: head, matching: find.byType(PricingDirtyDot)),
        findsNothing,
      );
      await typePrice(h, _iced, 'in_store', '135');
      expect(
        find.descendant(of: head, matching: find.byType(PricingDirtyDot)),
        findsOneWidget,
      );
      await h.tap(head);
      expect(
        find.descendant(of: head, matching: find.byType(PricingDirtyDot)),
        findsOneWidget,
        reason: 'still staged while collapsed',
      );
    });

    testWidgets('MENU-PRC-012 expanding reads the studio once; loading row', (
      tester,
    ) async {
      final s = pricingServer();
      final gate = s.server.hold('GET', studioT);
      final h = await pumpPricing(tester, seeded: s);
      await expand(h, 'Iced Latte');
      expect(
        h.server.callsTo(studioT).single.path,
        '/menu-items/${MenuSeedIds.item('iced_latte')}/studio',
      );
      expect(
        find.descendant(
          of: find.byType(PricingMatrix),
          matching: find.byType(DashSkeleton),
        ),
        findsOneWidget,
      );
      gate.release();
      await h.settle();
      expect(cellOf(_iced, 'in_store'), findsOneWidget);
    });

    testWidgets('MENU-PRC-012 a failed studio read: "Couldn\'t load items" '
        'in the row', (tester) async {
      final s = pricingServer();
      // Twice: the press's touch warms the read first, and a failed warm is
      // dropped so the expanded row asks again.
      s.server.fail('GET', studioT, MockResponse.error(500, 'boom'), times: 2);
      final h = await pumpPricing(tester, seeded: s);
      await expand(h, 'Iced Latte');
      expect(
        find.descendant(
          of: find.byType(PricingMatrix),
          matching: find.text("Couldn't load items"),
        ),
        findsOneWidget,
      );
    });

    testWidgets('MENU-PRC-012 an item with no sizes: "No sizes to price"', (
      tester,
    ) async {
      final s = pricingServer();
      final item = MenuSeedIds.item('green_tea');
      s.db[MenuTables.sizes].removeWhere((r) => r['menu_item_id'] == item);
      final h = await pumpPricing(tester, seeded: s);
      await expand(h, 'Green Tea');
      expect(pageText('No sizes to price'), findsOneWidget);
    });

    testWidgets('MENU-PRC-013 size rows: pill, catalog price, five cells', (
      tester,
    ) async {
      final h = await pumpPricing(tester);
      await expand(h, 'Iced Latte');
      expect(pageText('Regular'), findsOneWidget);
      expect(pageText('Large'), findsOneWidget);
      expect(pageText('EGP 130.00'), findsOneWidget);
      expect(pageText('EGP 150.00'), findsOneWidget);
      for (final col in [
        'in_store',
        'in_mall',
        'outside',
        'umbrella',
        'pickup',
      ]) {
        expect(cellOf(_iced, col), findsOneWidget, reason: col);
        expect(cellOf(_icedL, col), findsOneWidget, reason: col);
      }
      expect(pageText('inactive'), findsNothing);
    });

    testWidgets('MENU-PRC-014 an explicit price shows bold; an inherited cell '
        'is blank with the effective price as placeholder', (tester) async {
      final h = await pumpPricing(tester);
      await expand(h, 'Iced Latte');
      expect(priceText(tester, _iced, 'outside'), '145');
      expect(priceText(tester, _iced, 'in_store'), '');
      final outside = tester.widget<PriceField>(
        find.descendant(
          of: cellOf(_iced, 'outside'),
          matching: find.byType(PriceField),
        ),
      );
      expect(outside.strong, isTrue);
      final inStore = tester.widget<PriceField>(
        find.descendant(
          of: cellOf(_iced, 'in_store'),
          matching: find.byType(PriceField),
        ),
      );
      expect(inStore.strong, isFalse);
      expect(inStore.placeholder, '130');
      expect(inStore.label, 'Price (EGP)');
      await typePrice(h, _iced, 'in_store', '135');
      expect(controlOf(tester, _iced, 'in_store').draft.price, '135');
    });

    testWidgets('MENU-PRC-015 "Set here", "↳ Catalog", "↳ Branch" (hint '
        '"↳ branch")', (tester) async {
      final s = pricingServer();
      // A Zamalek branch price on Iced Latte Large: its channels inherit it.
      s.db[MenuTables.priceOverrides].insert({
        'scope': 'branch',
        'branch_id': SeedIds.zamalek,
        'channel': null,
        'target_type': 'menu_item_size',
        'target_id': _icedL,
        'price': 15500,
        'is_available': null,
      });
      final h = await pumpPricing(tester, seeded: s);
      await expand(h, 'Iced Latte');
      Finder inCell(String id, String col, String text) =>
          find.descendant(of: cellOf(id, col), matching: find.text(text));
      expect(inCell(_iced, 'outside', 'Set here'), findsOneWidget);
      expect(inCell(_iced, 'in_store', 'Catalog'), findsOneWidget);
      expect(inCell(_icedL, 'in_store', 'Set here'), findsOneWidget);
      expect(inCell(_icedL, 'pickup', 'Branch'), findsOneWidget);
      final hint = tester.widget<MadarHoldHint>(
        find
            .descendant(
              of: cellOf(_icedL, 'pickup'),
              matching: find.byType(MadarHoldHint),
            )
            .first,
      );
      expect(hint.message, '↳ branch');
      expect(
        tester
            .widget<PriceField>(
              find.descendant(
                of: cellOf(_icedL, 'pickup'),
                matching: find.byType(PriceField),
              ),
            )
            .placeholder,
        '155',
      );
    });

    testWidgets('MENU-PRC-016 the availability switch: effective state, red '
        'when hidden', (tester) async {
      final s = pricingServer();
      s.db[MenuTables.priceOverrides].insert({
        'scope': 'branch',
        'branch_id': SeedIds.zamalek,
        'channel': null,
        'target_type': 'menu_item_size',
        'target_id': _icedL,
        'price': null,
        'is_available': false,
      });
      final h = await pumpPricing(tester, seeded: s);
      await expand(h, 'Iced Latte');
      expect(controlOf(tester, _icedL, 'in_store').draft.available, isFalse);
      // A channel inherits the branch's hide.
      expect(controlOf(tester, _icedL, 'umbrella').draft.available, isFalse);
      expect(controlOf(tester, _iced, 'in_store').draft.available, isTrue);
      expect(
        find.descendant(
          of: toggleOf(_iced, 'in_store'),
          matching: find.bySemanticsLabel('Available'),
        ),
        findsOneWidget,
      );
      await toggle(h, _iced, 'in_store');
      expect(controlOf(tester, _iced, 'in_store').draft.available, isFalse);
      expect(
        find.descendant(
          of: toggleOf(_iced, 'in_store'),
          matching: find.bySemanticsLabel('Hidden'),
        ),
        findsOneWidget,
      );
      final tip = tester.widget<MadarHoldHint>(
        find
            .ancestor(
              of: find.descendant(
                of: toggleOf(_iced, 'in_store'),
                matching: find.byType(DashIcon),
              ),
              matching: find.byType(MadarHoldHint),
            )
            .first,
      );
      expect(tip.message, 'Show at this scope');
    });

    testWidgets('MENU-PRC-017 Remove override: on an explicit untouched cell; '
        'stages blank + available; Save deletes the row', (tester) async {
      final h = await pumpPricing(tester);
      await expand(h, 'Iced Latte');
      expect(clearOf(_iced, 'outside'), findsOneWidget);
      expect(clearOf(_iced, 'in_store'), findsNothing);
      await h.tap(clearOf(_iced, 'outside'));
      expect(priceText(tester, _iced, 'outside'), '');
      expect(clearOf(_iced, 'outside'), findsNothing);
      expect(_inBar('1 unsaved changes'), findsOneWidget);
      await _save(h);
      expect(_writes(h, 'DELETE'), [
        {
          'branch_id': SeedIds.zamalek,
          'channel': 'outside',
          'is_available': null,
          'price': null,
          'scope': 'branch_channel',
          'target_id': _iced,
          'target_type': 'menu_item_size',
        },
      ]);
      expect(rowsFor(h.db!, SeedIds.zamalek, _iced), isEmpty);
      await h.expectToast('Saved 1 changes');
    });

    testWidgets('MENU-PRC-017/029 Remove override under a branch hide '
        'still DELETEs the channel row', (tester) async {
      final s = pricingServer();
      final rows = s.db[MenuTables.priceOverrides];
      rows.insert({
        'scope': 'branch',
        'branch_id': SeedIds.zamalek,
        'channel': null,
        'target_type': 'menu_item_size',
        'target_id': _icedL,
        'price': null,
        'is_available': false,
      });
      rows.insert({
        'scope': 'branch_channel',
        'branch_id': SeedIds.zamalek,
        'channel': 'outside',
        'target_type': 'menu_item_size',
        'target_id': _icedL,
        'price': 16000,
        'is_available': null,
      });
      final h = await pumpPricing(tester, seeded: s);
      await expand(h, 'Iced Latte');
      expect(priceText(tester, _icedL, 'outside'), '160');
      await reveal(h, clearOf(_icedL, 'outside'));
      await h.tap(clearOf(_icedL, 'outside'));
      expect(controlOf(tester, _icedL, 'outside').draft.available, isFalse);
      await _save(h);
      expect(h.server.callsTo(overrideT, method: 'PUT'), isEmpty);
      expect(_writes(h, 'DELETE'), [
        {
          'branch_id': SeedIds.zamalek,
          'channel': 'outside',
          'is_available': null,
          'price': null,
          'scope': 'branch_channel',
          'target_id': _icedL,
          'target_type': 'menu_item_size',
        },
      ]);
      expect(rowsFor(s.db, SeedIds.zamalek, _icedL).map((r) => r['scope']), [
        'branch',
      ]);
      await h.expectToast('Saved 1 changes');
    });

    testWidgets('MENU-PRC-017 an edit after Remove override is a normal '
        'edit again', (tester) async {
      final h = await pumpPricing(tester);
      await expand(h, 'Iced Latte');
      await h.tap(clearOf(_iced, 'outside'));
      await typePrice(h, _iced, 'outside', '150');
      await _save(h);
      expect(_writes(h, 'PUT').single['price'], 15000);
      expect(h.server.callsTo(overrideT, method: 'DELETE'), isEmpty);
      await h.expectToast('Saved 1 changes');
    });

    testWidgets('MENU-PRC-018 a dirty cell is tinted; back to the server '
        'value it is clean again', (tester) async {
      final h = await pumpPricing(tester);
      await expand(h, 'Iced Latte');
      Color? tint() => tester
          .widget<MatrixCell>(
            find.ancestor(
              of: cellOf(_iced, 'outside'),
              matching: find.byType(MatrixCell),
            ),
          )
          .color;
      final clean = tint();
      await typePrice(h, _iced, 'outside', '150');
      expect(tint(), isNot(clean));
      expect(_inBar('1 unsaved changes'), findsOneWidget);
      await typePrice(h, _iced, 'outside', '145');
      expect(tint(), clean);
      expect(_bar, findsNothing);
    });
  });

  group('MENU-PRC-019..021 the add-ons tab', () {
    testWidgets('MENU-PRC-019 reads: the add-on page, the branch rows and one '
        'read per channel, all on mount', (tester) async {
      final h = await pumpPricing(tester);
      expect(h.server.callsTo(addonCatalogT).single.query, {
        'org_id': [SeedIds.sabahOrg],
        'page': ['1'],
        'per_page': ['24'],
      });
      expect(h.server.callsTo(branchAddonT).single.query, {
        'branch_id': [SeedIds.zamalek],
      });
      expect(
        h.server.callsTo(channelAddonT).map((c) => c.query['channel']!.single),
        unorderedEquals(['in_mall', 'outside', 'umbrella', 'pickup']),
      );
      await _addonsTab(h);
      expect(h.server.callsTo(addonCatalogT), hasLength(1));
      expect(pageText('Oat milk'), findsOneWidget);
    });

    testWidgets('MENU-PRC-020 loading: a skeleton', (tester) async {
      final s = pricingServer();
      final gate = s.server.hold('GET', branchAddonT);
      final h = await pumpPricing(tester, seeded: s);
      await _addonsTab(h);
      expect(inPage(find.byType(DashSkeleton)), findsOneWidget);
      gate.release();
      await h.settle();
      expect(pageText('Oat milk'), findsOneWidget);
    });

    testWidgets('MENU-PRC-020 error: the server\'s words; Retry refetches', (
      tester,
    ) async {
      final s = pricingServer();
      final lost = MockResponse.error(500, 'Lost it');
      s.server.fail('GET', addonCatalogT, lost);
      final h = await pumpPricing(tester, seeded: s);
      await _addonsTab(h);
      expect(pageText("Couldn't load items"), findsOneWidget);
      expect(pageText(h.refusalWords(lost)), findsOneWidget);
      final branch = h.server.callsTo(branchAddonT).length;
      await h.tap(pageText('Retry'));
      expect(h.server.callsTo(addonCatalogT), hasLength(2));
      expect(h.server.callsTo(branchAddonT).length, branch + 1);
      expect(pageText('Oat milk'), findsOneWidget);
    });

    testWidgets('MENU-PRC-020 empty: "No add-ons"', (tester) async {
      final h = await pumpPricing(tester);
      await _addonsTab(h);
      await _search(h, 'nothing like this');
      expect(h.server.callsTo(addonCatalogT).last.query['search'], [
        'nothing like this',
      ]);
      expect(pageText('No add-ons'), findsOneWidget);
    });

    testWidgets('MENU-PRC-021 an add-on row: tag tile, name, default price, '
        'five cells', (tester) async {
      final h = await pumpPricing(tester);
      await _addonsTab(h);
      await h.shot('pricing/addons');
      expect(pageText('Add-on'), findsOneWidget);
      final row = find
          .ancestor(of: pageText('Oat milk'), matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: row, matching: find.byType(MenuImageTile)),
        findsOneWidget,
      );
      expect(priceText(tester, _oat, 'in_store'), '30');
      expect(
        tester
            .widget<PriceField>(
              find.descendant(
                of: cellOf(_oat, 'pickup'),
                matching: find.byType(PriceField),
              ),
            )
            .placeholder,
        '30',
      );
      expect(controlOf(tester, _almond, 'in_mall').draft.available, isFalse);
      expect(controlOf(tester, _almond, 'outside').draft.available, isTrue);
      await typePrice(h, _almond, 'in_store', '32');
      expect(
        find.descendant(of: row, matching: find.byType(PricingDirtyDot)),
        findsNothing,
      );
      final almondRow = find
          .ancestor(of: pageText('Almond milk'), matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: almondRow, matching: find.byType(PricingDirtyDot)),
        findsOneWidget,
      );
    });
  });

  group('MENU-PRC-022 phone', () {
    testWidgets('MENU-PRC-022 cards: tap to expand; per size the catalog line '
        'and one row per scope; the same staged edits', (tester) async {
      final h = await pumpPricing(tester, size: DashSize.phone);
      expect(inPage(find.byType(PricingMatrix)), findsNothing);
      await expand(h, 'Iced Latte');
      expect(pageText('Catalog (ref)'), findsNWidgets(2));
      expect(pageText('In-store'), findsNWidgets(2));
      expect(pageText('Pickup'), findsNWidgets(2));
      expect(controlOf(tester, _iced, 'outside').touch, isTrue);
      await typePrice(h, _iced, 'umbrella', '140');
      expect(_inBar('1 unsaved changes'), findsOneWidget);
      // The first edit brings the bar up without moving the page.
      expect(tester.getRect(cellOf(_iced, 'umbrella')).top, lessThan(844));
      await reveal(h, pageText('Iced Latte'));
      await h.shot('pricing/phone-expanded');
      await _save(h);
      expect(_writes(h, 'PUT').single['price'], 14000);
      await h.expectToast('Saved 1 changes');
    });

    testWidgets('MENU-PRC-022 add-on cards', (tester) async {
      final h = await pumpPricing(tester, size: DashSize.phone);
      await _addonsTab(h);
      expect(inPage(find.byType(MenuImageTile)), findsWidgets);
      await reveal(h, cellOf(_oat, 'in_store'));
      expect(priceText(tester, _oat, 'in_store'), '30');
    });
  });

  group('MENU-PRC-023..028 paging and Save', () {
    testWidgets('MENU-PRC-023 the pager: "Page 1 of 2", Previous off, Next '
        'asks page 2', (tester) async {
      final h = await pumpPricing(tester);
      final pager = inPage(find.byType(DashPagination));
      await reveal(h, pager);
      expect(
        find.descendant(of: pager, matching: find.text('Page 1 of 2')),
        findsOneWidget,
      );
      await h.tap(
        find.descendant(of: pager, matching: find.bySemanticsLabel('Next')),
      );
      expect(h.server.callsTo(catalogT).last.query['page'], ['2']);
      expect(pageText('Spanish Latte'), findsOneWidget);
      expect(
        find.descendant(of: pager, matching: find.text('Page 2 of 2')),
        findsOneWidget,
      );
    });

    testWidgets('MENU-PRC-023 no pager on a single page (add-ons)', (
      tester,
    ) async {
      final h = await pumpPricing(tester);
      await _addonsTab(h);
      expect(inPage(find.byType(DashPagination)), findsNothing);
    });

    testWidgets('MENU-PRC-024 the save bar: count, Discard, a busy Save; '
        'edits survive tab and page switches', (tester) async {
      final s = pricingServer();
      final h = await pumpPricing(tester, seeded: s);
      await expand(h, 'Iced Latte');
      await typePrice(h, _iced, 'in_store', '135');
      await toggle(h, _icedL, 'pickup');
      expect(_inBar('2 unsaved changes'), findsOneWidget);
      await _addonsTab(h);
      await typePrice(h, _oat, 'in_store', '31');
      expect(_inBar('3 unsaved changes'), findsOneWidget);
      await h.tap(pageText('Menu items'));
      expect(_inBar('3 unsaved changes'), findsOneWidget);
      final pager = inPage(find.byType(DashPagination));
      await reveal(h, pager);
      await h.tap(
        find.descendant(of: pager, matching: find.bySemanticsLabel('Next')),
      );
      expect(pageText('Spanish Latte'), findsOneWidget);
      expect(_inBar('3 unsaved changes'), findsOneWidget);
      await h.tap(
        find.descendant(of: pager, matching: find.bySemanticsLabel('Previous')),
      );
      await expand(h, 'Iced Latte');
      expect(priceText(tester, _iced, 'in_store'), '135');
      await h.tap(_inBar('Discard'));
      expect(_bar, findsNothing);

      await typePrice(h, _iced, 'in_store', '135');
      final gate = s.server.hold('PUT', overrideT);
      await h.tap(_inBar('Save'));
      final save = tester.widget<MenuUnsavedBar>(_bar);
      expect(save.saving, isTrue);
      await h.shot('pricing/saving');
      gate.release();
      await h.settle();
      expect(_bar, findsNothing);
      await h.expectToast('Saved 1 changes');
    });

    testWidgets('MENU-PRC-025 an invalid price: "Enter a valid price for '
        '…", nothing written', (tester) async {
      final h = await pumpPricing(tester);
      await expand(h, 'Iced Latte');
      await typePrice(h, _iced, 'in_store', '-5');
      await _save(h);
      await h.shot('pricing/invalid');
      await h.expectToast('Enter a valid price for Iced Latte');
      expect(h.server.callsTo(overrideT), isEmpty);
      expect(_inBar('1 unsaved changes'), findsOneWidget);
    });

    testWidgets('MENU-PRC-026 the writes: a price and a hide PUT, a cleared '
        'row DELETEs, in one go', (tester) async {
      final h = await pumpPricing(tester);
      await expand(h, 'Iced Latte');
      await typePrice(h, _iced, 'in_store', '132.5');
      await toggle(h, _icedL, 'in_mall');
      await typePrice(h, _iced, 'outside', '');
      await _addonsTab(h);
      await typePrice(h, _oat, 'umbrella', '28');
      await _save(h);
      final puts = _writes(h, 'PUT');
      expect(puts, hasLength(3));
      expect(
        puts,
        contains(
          equals({
            'branch_id': SeedIds.zamalek,
            'channel': null,
            'is_available': null,
            'price': 13250,
            'scope': 'branch',
            'target_id': _iced,
            'target_type': 'menu_item_size',
          }),
        ),
      );
      expect(
        puts,
        contains(
          equals({
            'branch_id': SeedIds.zamalek,
            'channel': 'in_mall',
            'is_available': false,
            'price': null,
            'scope': 'branch_channel',
            'target_id': _icedL,
            'target_type': 'menu_item_size',
          }),
        ),
      );
      expect(
        puts,
        contains(
          equals({
            'branch_id': SeedIds.zamalek,
            'channel': 'umbrella',
            'is_available': null,
            'price': 2800,
            'scope': 'branch_channel',
            'target_id': _oat,
            'target_type': 'modifier_option',
          }),
        ),
      );
      expect(_writes(h, 'DELETE').single['target_id'], _iced);
      await h.expectToast('Saved 4 changes');
    });

    testWidgets('MENU-PRC-027 all saved: toast, cleared, the overrides and '
        'the studio read again', (tester) async {
      final h = await pumpPricing(tester);
      await expand(h, 'Iced Latte');
      final studio = h.server.callsTo(studioT).length;
      final branch = h.server.callsTo(branchAddonT).length;
      final channels = h.server.callsTo(channelAddonT).length;
      final catalog = h.server.callsTo(catalogT).length;
      await typePrice(h, _iced, 'in_store', '135');
      await _save(h);
      await h.expectToast('Saved 1 changes');
      expect(_bar, findsNothing);
      expect(h.server.callsTo(studioT).length, studio + 1);
      expect(h.server.callsTo(branchAddonT).length, branch + 1);
      expect(h.server.callsTo(channelAddonT).length, channels + 4);
      expect(
        h.server.callsTo(catalogT).length,
        catalog,
        reason:
            'not '
            'invalidated by the web',
      );
      expect(priceText(tester, _iced, 'in_store'), '135');
      expect(clearOf(_iced, 'in_store'), findsOneWidget);
    });

    testWidgets('MENU-PRC-027 some failed: "Saved 1, 1 failed" with the '
        'server\'s words; only the failed cell stays', (tester) async {
      final s = pricingServer();
      final h = await pumpPricing(tester, seeded: s);
      await expand(h, 'Iced Latte');
      await typePrice(h, _iced, 'in_store', '135');
      await typePrice(h, _icedL, 'in_store', '155');
      final bad = MockResponse.badRequest('price must be >= 0');
      s.server.fail('PUT', overrideT, bad);
      await _save(h);
      expect(find.text('Saved 1, 1 failed'), findsOneWidget);
      expect(find.text(h.refusalWords(bad)), findsOneWidget);
      await h.shot('pricing/partial');
      await h.flushTimers();
      expect(_inBar('1 unsaved changes'), findsOneWidget);
    });

    testWidgets('MENU-PRC-028 (divergence) an add-on staged on another page '
        'is still saved', (tester) async {
      final s = pricingServer();
      final extras = s.db[MenuTables.groups].rows.firstWhere(
        (g) => g['legacy_addon_type'] == 'milk_type',
      );
      final options = (extras['options'] as List).cast<Map<String, Object?>>();
      for (var i = 0; i < 30; i++) {
        options.add({
          ...options.first,
          'id': mockUuid('pricing-test-option:$i'),
          'name': 'Zz milk ${i.toString().padLeft(2, '0')}',
        });
      }
      final h = await pumpPricing(tester, seeded: s);
      await _addonsTab(h);
      await typePrice(h, _oat, 'in_store', '27');
      final pager = inPage(find.byType(DashPagination));
      await reveal(h, pager);
      await h.tap(
        find.descendant(of: pager, matching: find.bySemanticsLabel('Next')),
      );
      expect(h.server.callsTo(addonCatalogT).last.query['page'], ['2']);
      expect(cellOf(_oat, 'in_store'), findsNothing);
      await _save(h);
      expect(_writes(h, 'PUT').single['target_id'], _oat);
      await h.expectToast('Saved 1 changes');
    });
  });

  group('MENU-PRC-029..033 the inventory\'s critic rows', () {
    testWidgets('MENU-PRC-029 (divergence) showing a channel the branch '
        'hides writes is_available true and stays shown', (tester) async {
      final s = pricingServer();
      s.db[MenuTables.priceOverrides].insert({
        'scope': 'branch',
        'branch_id': SeedIds.zamalek,
        'channel': null,
        'target_type': 'menu_item_size',
        'target_id': _icedL,
        'price': null,
        'is_available': false,
      });
      final h = await pumpPricing(tester, seeded: s);
      await expand(h, 'Iced Latte');
      expect(controlOf(tester, _icedL, 'outside').draft.available, isFalse);
      await toggle(h, _icedL, 'outside');
      await _save(h);
      expect(_writes(h, 'PUT').single, {
        'branch_id': SeedIds.zamalek,
        'channel': 'outside',
        'is_available': true,
        'price': null,
        'scope': 'branch_channel',
        'target_id': _icedL,
        'target_type': 'menu_item_size',
      });
      await h.expectToast('Saved 1 changes');
      expect(controlOf(tester, _icedL, 'outside').draft.available, isTrue);
      expect(controlOf(tester, _icedL, 'in_store').draft.available, isFalse);
    });

    testWidgets('MENU-PRC-030 (divergence) a new search starts at page 1', (
      tester,
    ) async {
      final h = await pumpPricing(tester);
      final pager = inPage(find.byType(DashPagination));
      await reveal(h, pager);
      await h.tap(
        find.descendant(of: pager, matching: find.bySemanticsLabel('Next')),
      );
      await _search(h, 'latte');
      final q = h.server.callsTo(catalogT).last.query;
      expect(q['page'], ['1']);
      expect(q['search'], ['latte']);
      expect(pageText('Spanish Latte'), findsOneWidget);
      expect(pageText('No menu items'), findsNothing);
    });

    testWidgets('MENU-PRC-031 (divergence) the invalid-price toast names an '
        'item from another page', (tester) async {
      final h = await pumpPricing(tester);
      await expand(h, 'Iced Latte');
      await typePrice(h, _iced, 'in_store', '-1');
      final pager = inPage(find.byType(DashPagination));
      await reveal(h, pager);
      await h.tap(
        find.descendant(of: pager, matching: find.bySemanticsLabel('Next')),
      );
      await _save(h);
      await h.expectToast('Enter a valid price for Iced Latte');
    });

    testWidgets('MENU-PRC-032 (divergence) the channel reads gate the add-ons '
        'tab: a skeleton while one loads', (tester) async {
      final s = pricingServer();
      final gate = s.server.hold('GET', channelAddonT);
      final h = await pumpPricing(tester, seeded: s);
      await _addonsTab(h);
      expect(inPage(find.byType(DashSkeleton)), findsOneWidget);
      expect(cellOf(_almond, 'in_mall'), findsNothing);
      gate.release();
      await h.settle();
      expect(controlOf(tester, _almond, 'in_mall').draft.available, isFalse);
    });

    testWidgets('MENU-PRC-032 (divergence) a failed channel read: the error '
        'and Retry on the add-ons tab', (tester) async {
      final s2 = pricingServer();
      final down = MockResponse.error(500, 'Channel store down');
      s2.server.fail('GET', channelAddonT, down);
      final h2 = await pumpPricing(tester, seeded: s2);
      await _addonsTab(h2);
      expect(pageText("Couldn't load items"), findsOneWidget);
      expect(pageText(h2.refusalWords(down)), findsOneWidget);
      await h2.tap(pageText('Retry'));
      expect(cellOf(_almond, 'in_mall'), findsOneWidget);
    });

    testWidgets('MENU-PRC-033 every size, by sort, inactive ones marked; a '
        'simple item\'s size reads "One size"', (tester) async {
      final s = pricingServer();
      s.db[MenuTables.sizes].update(_icedL, {'is_active': false});
      final h = await pumpPricing(tester, seeded: s);
      await expand(h, 'Iced Latte');
      expect(pageText('inactive'), findsOneWidget);
      expect(cellOf(_icedL, 'in_store'), findsOneWidget);
      expect(
        tester.getTopLeft(pageText('Regular')).dy,
        lessThan(tester.getTopLeft(pageText('Large')).dy),
      );
      await expand(h, 'Butter Croissant');
      expect(pageText('One size'), findsOneWidget);
      expect(pageText('one_size'), findsNothing);
    });
  });

  group('MENU-PRC-009/020/027 loading, retry and refresh rules', () {
    testWidgets('MENU-PRC-009 a Retry in flight keeps the error up with a '
        'spinner; no empty state meanwhile', (tester) async {
      final s = pricingServer();
      s.server.fail('GET', catalogT, MockResponse.error(500, 'Database down'));
      final h = await pumpPricing(tester, seeded: s);
      final gate = s.server.hold('GET', catalogT);
      await h.tap(pageText('Retry'));
      final err = tester.widget<DashErrorState>(
        inPage(find.byType(DashErrorState)),
      );
      expect(err.retrying, isTrue);
      expect(pageText('No menu items'), findsNothing);
      gate.release();
      await h.settle();
      expect(inPage(find.byType(PricingMatrix)), findsOneWidget);
    });

    testWidgets('MENU-PRC-009 a new search after an empty one shows the '
        'skeleton, not "No menu items", while it loads', (tester) async {
      final s = pricingServer();
      final h = await pumpPricing(tester, seeded: s);
      await _search(h, 'nothing like this');
      expect(pageText('No menu items'), findsOneWidget);
      final gate = s.server.hold('GET', catalogT);
      await _search(h, 'latte');
      expect(pageText('No menu items'), findsNothing);
      expect(inPage(find.byType(DashSkeleton)), findsOneWidget);
      gate.release();
      await h.settle();
      expect(pageText('Caffè Latte'), findsOneWidget);
    });

    testWidgets('MENU-PRC-027 the refresh still runs when the page closes '
        'mid-save', (tester) async {
      final s = pricingServer();
      final h = await pumpPricing(tester, seeded: s);
      await expand(h, 'Iced Latte');
      await typePrice(h, _iced, 'in_store', '135');
      int epoch() =>
          h.container.read(realtimeEpochProvider('/branch-addon-overrides'));
      final before = epoch();
      final gate = s.server.hold('PUT', overrideT);
      await _save(h);
      await h.go('/menu/bases');
      gate.release();
      await h.settle();
      expect(epoch(), greaterThan(before));
      expect(
        rowsFor(
          s.db,
          SeedIds.zamalek,
          _iced,
        ).singleWhere((r) => r['scope'] == 'branch')['price'],
        13500,
      );
      await h.expectToast('Saved 1 changes');
    });

    testWidgets('MENU-PRC-027 a save that fails after the page closed still '
        'says so', (tester) async {
      final s = pricingServer();
      final denied = MockResponse.denied('menu.items.edit');
      s.server.on('PUT', overrideT, (req) => denied);
      final h = await pumpPricing(tester, seeded: s);
      await expand(h, 'Iced Latte');
      await typePrice(h, _iced, 'in_store', '135');
      int epoch() =>
          h.container.read(realtimeEpochProvider('/branch-addon-overrides'));
      final before = epoch();
      final gate = s.server.hold('PUT', overrideT);
      await _save(h);
      await h.go('/menu/bases');
      gate.release();
      await h.settle();
      expect(epoch(), greaterThan(before));
      expect(find.text('Saved 0, 1 failed'), findsOneWidget);
      expect(find.text(h.refusalWords(denied)), findsOneWidget);
      await h.flushTimers();
    });

    testWidgets('MENU-PRC-024 (divergence) a cell typed while Save runs stays '
        'staged', (tester) async {
      final s = pricingServer();
      final h = await pumpPricing(tester, seeded: s);
      await expand(h, 'Iced Latte');
      await typePrice(h, _iced, 'in_store', '135');
      final gate = s.server.hold('PUT', overrideT);
      await _save(h);
      await typePrice(h, _icedL, 'in_store', '155');
      await typePrice(h, _iced, 'umbrella', '140');
      gate.release();
      await h.settle();
      await h.expectToast('Saved 1 changes');
      expect(_inBar('2 unsaved changes'), findsOneWidget);
      expect(priceText(tester, _icedL, 'in_store'), '155');
      expect(priceText(tester, _iced, 'in_store'), '135');
    });

    testWidgets('MENU-PRC-024 (divergence) Save drops a staged cell a refresh '
        'made match the server', (tester) async {
      final s = pricingServer();
      final h = await pumpPricing(tester, seeded: s);
      await expand(h, 'Iced Latte');
      await typePrice(h, _iced, 'outside', '150');
      expect(_inBar('1 unsaved changes'), findsOneWidget);
      // Someone else sets the same price; the studio refetches.
      s.db[MenuTables.priceOverrides].rows.firstWhere(
        (r) => r['target_id'] == _iced,
      )['price'] = 15000;
      h.container.read(realtimeBusProvider).invalidate(const [
        '/menu-items/*/studio',
      ]);
      await h.settle();
      await _save(h);
      expect(h.server.callsTo(overrideT), isEmpty);
      expect(_bar, findsNothing);
    });
  });

  group('refusals, modules and the route', () {
    testWidgets('MENU-AREA-008 a person without menu.items.edit: no sidebar '
        'row, the page by address, Save refused with the server\'s words', (
      tester,
    ) async {
      final h = await pumpPricing(
        tester,
        persona: Persona.limited,
        branch: SeedIds.maadi,
      );
      expect(
        find.descendant(
          of: find.byType(DashSidebar),
          matching: find.text('Pricing & Availability'),
        ),
        findsNothing,
      );
      expect(pageText('Pricing & availability'), findsOneWidget);
      await expand(h, 'Iced Latte');
      await typePrice(h, _iced, 'in_store', '135');
      await _save(h);
      expect(find.text('Saved 0, 1 failed'), findsOneWidget);
      expect(
        find.text(h.refusalWords(MockResponse.denied('menu.items.edit'))),
        findsOneWidget,
      );
      await h.flushTimers();
      expect(_inBar('1 unsaved changes'), findsOneWidget);
    });

    testWidgets('a refused list read shows the refusal in the error state', (
      tester,
    ) async {
      final s = pricingServer();
      final denied = MockResponse.denied('menu.items.read');
      s.server.fail('GET', catalogT, denied);
      final h = await pumpPricing(tester, seeded: s);
      expect(pageText("Couldn't load items"), findsOneWidget);
      expect(pageText(h.refusalWords(denied)), findsOneWidget);
    });

    testWidgets('the branch manager prices their own branch', (tester) async {
      final h = await pumpPricing(tester, persona: Persona.manager);
      expect(pageText('Zamalek'), findsOneWidget);
      await _addonsTab(h);
      expect(priceText(tester, _oat, 'in_store'), '30');
    });

    testWidgets('a Dawam-only org: the module gate, no reads', (tester) async {
      final h = await pumpPricing(
        tester,
        persona: Persona.dawamOnly,
        prefs: const {},
      );
      expect(find.text('Not part of this business\'s plan'), findsOneWidget);
      expect(h.server.callsTo(catalogT), isEmpty);
    });

    testWidgets('MENU-AREA-007 /menu/overrides lands on /menu/pricing', (
      tester,
    ) async {
      final h = await pumpPricing(tester, path: '/menu/overrides');
      expect(h.location.path, pricingPath);
      expect(pageText('Pricing & availability'), findsOneWidget);
    });

    testWidgets('prefetch: pointing at the sidebar row warms the page\'s '
        'reads; opening it asks nothing again', (tester) async {
      final h = await pumpPricing(tester, path: '/menu/bases');
      int n(String t) => h.server.callsTo(t, method: 'GET').length;
      final before = {
        for (final t in [catalogT, addonCatalogT, branchAddonT, channelAddonT])
          t: n(t),
      };
      final row = find.descendant(
        of: find.byType(DashSidebar),
        matching: find.text('Pricing & Availability'),
      );
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find
            .descendant(
              of: find.byType(DashSidebar),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await h.settle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(row));
      await h.settle();
      expect(n(catalogT), before[catalogT]! + 1);
      expect(n(addonCatalogT), before[addonCatalogT]! + 1);
      expect(n(branchAddonT), before[branchAddonT]! + 1);
      expect(n(channelAddonT), before[channelAddonT]! + 4);

      await h.tap(row);
      expect(h.location.path, pricingPath);
      expect(pageText('Almond Croissant'), findsOneWidget);
      expect(n(catalogT), before[catalogT]! + 1, reason: 'served warm');
      expect(n(addonCatalogT), before[addonCatalogT]! + 1);
      expect(n(branchAddonT), before[branchAddonT]! + 1);
      expect(n(channelAddonT), before[channelAddonT]! + 4);
    });
  });
}
