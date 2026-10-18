// The area-wide rows (OFFR-ALL-001..019) as the combos list meets them:
// the nav, the module gate, rights loading, failure wording, caching and
// retries, live updates, the combos invalidation and the shared table.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/src/combos/combos_page.dart';
import 'package:dashboard_catalog_offers/src/combos/combos_providers.dart';
import 'package:dashboard_catalog_offers/src/shared/offers_cache.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _all = [
  'Brunch for Two',
  'Coffee & Cookie',
  'Iced Afternoon',
  "Kids' Cocoa & Cookie",
  'Morning Croissant Combo',
  'Ramadan Suhoor Box',
];

/// The sidebar row reading [text].
Finder sideText(String text) =>
    find.descendant(of: find.byType(DashSidebar), matching: find.text(text));

Future<void> confirmDelete(DashHarness h, String name) async {
  await h.tap(rowButton(name, 'Delete'));
  await h.tap(
    find.descendant(
      of: find.byType(DashConfirmDialog),
      matching: find.text('Delete'),
    ),
  );
}

void main() {
  group('nav and gates', () {
    testWidgets('OFFR-ALL-001 Catalog ▸ Menu: Items, Choice groups, Combos, '
        'Deals, Pricing & Availability, Recipe bases, Packaging rules; then '
        'Discounts', (tester) async {
      final h = await pumpCombos(tester);
      final order = [
        'Catalog',
        'Menu',
        'Items',
        'Choice groups',
        'Combos',
        'Deals',
        'Pricing & Availability',
        'Recipe bases',
        'Packaging rules',
        'Discounts',
      ];
      final ys = [for (final t in order) tester.getTopLeft(sideText(t)).dy];
      expect(ys, orderedEquals([...ys]..sort()), reason: '$order');
      final combos = dashNav
          .expand((g) => g.entries)
          .whereType<NavParent>()
          .expand((p) => p.children)
          .firstWhere((l) => l.to == combosPath);
      expect(combos.lucide, 'sandwich');
      expect(combos.caps, ['menu.items.read']);
      expect(combos.module, 'pos');

      // The same leaves in the command palette.
      await h.tap(
        find.descendant(
          of: find.byType(DashHeader),
          matching: find.text('Search'),
        ),
      );
      final palette = find.byType(DashCommandPalette);
      expect(palette, findsOneWidget);
      for (final (q, t) in [
        ('combo', 'Combos'),
        ('deal', 'Deals'),
        ('discount', 'Discounts'),
      ]) {
        await h.enterText(palette, q);
        expect(
          find.descendant(of: palette, matching: find.text(t)),
          findsOneWidget,
          reason: t,
        );
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
    });

    testWidgets('OFFR-ALL-001 without menu.items.read the Combos and Deals '
        'leaves (and the Menu parent) are gone; Discounts stays', (
      tester,
    ) async {
      await pumpCombos(
        tester,
        seeded: serverWithCaps(['discounts.read', 'orders.read']),
      );
      expect(sideText('Combos'), findsNothing);
      expect(sideText('Deals'), findsNothing);
      expect(sideText('Menu'), findsNothing);
      expect(sideText('Discounts'), findsOneWidget);
    });

    testWidgets('OFFR-ALL-002 POS switched off: "Not part of this '
        'business\'s plan", no Combos leaf, nothing asked', (tester) async {
      final s = combosServer();
      s.db['orgs'].find(SeedIds.sabahOrg)!['modules'] = ['dawam'];
      final h = await pumpCombos(tester, seeded: s);
      expect(find.text("Not part of this business's plan"), findsOneWidget);
      expect(
        find.text(
          'Madar POS is switched off for this business. Ask Madar to switch '
          'it on.',
        ),
        findsOneWidget,
      );
      expect(find.byType(CombosPage), findsNothing);
      expect(sideText('Combos'), findsNothing);
      expect(callsTo(h, combosApi), isEmpty);
    });

    testWidgets('OFFR-ALL-002 the modules read failing: the words, the '
        'reason and Retry', (tester) async {
      final s = combosServer();
      s.server.fail(
        'GET',
        '/orgs/{id}/modules',
        MockResponse.error(500, 'Database error: timed out'),
      );
      final h = await pumpCombos(tester, seeded: s);
      expect(
        find.textContaining(
          "Couldn't check what this business has switched on",
        ),
        findsOneWidget,
      );
      expect(callsTo(h, combosApi), isEmpty);
      await h.tapText('Retry');
      expect(find.byType(CombosPage), findsOneWidget);
      expect(shownNames(tester), _all);
    });

    testWidgets('OFFR-ALL-003 / -018 (divergence) while the rights load: '
        'the skeleton and nothing asked; then the page', (tester) async {
      final s = combosServer();
      final gate = s.server.hold('GET', '/authz/me');
      final h = await pumpCombos(tester, seeded: s);
      expect(inPage(find.byType(DashSkeleton)), findsWidgets);
      expect(pageText('No combos yet'), findsNothing);
      expect(pageButton('New combo'), findsNothing);
      expect(pageText('Not available on this account'), findsNothing);
      expect(callsTo(h, combosApi), isEmpty);
      expect(callsTo(h, categoriesApi), isEmpty);
      gate.release();
      await h.settle();
      expect(callsTo(h, combosApi), hasLength(1));
      expect(shownNames(tester), _all);
      expect(pageButton('New combo'), findsOneWidget);
    });

    testWidgets('OFFR-ALL-003 a platform admin holds every right', (
      tester,
    ) async {
      final h = await pumpCombos(tester, persona: Persona.platform);
      await h.container
          .read(selectedOrgProvider.notifier)
          .select(SeedIds.sabahOrg);
      await h.settle();
      expect(pageButton('New combo'), findsOneWidget);
      expect(pageButton('Channels and margin'), findsOneWidget);
      expect(shownNames(tester), _all);
    });
  });

  group('words for a failure', () {
    testWidgets('OFFR-ALL-004 a coded refusal: the transport\'s words in a '
        'toast; the row stays', (tester) async {
      final s = combosServer();
      final refusal = MockResponse.unprocessable(
        'Combo is used by a deal',
        code: 'COMBO_IN_USE',
      );
      s.server.fail('DELETE', deleteApi, refusal);
      final h = await pumpCombos(tester, seeded: s);
      await confirmDelete(h, 'Iced Afternoon');
      await h.expectToast(h.refusalWords(refusal));
      expect(shownNames(tester), _all);
    });

    testWidgets('OFFR-ALL-004 a 429 and an uncoded 403 in Arabic', (
      tester,
    ) async {
      final s = combosServer();
      final busy = MockResponse.error(429, 'Too many requests');
      s.server.fail('DELETE', deleteApi, busy);
      final h = await pumpCombos(tester, seeded: s, locale: 'ar');
      await confirmDeleteAr(h, 'Iced Afternoon');
      await h.expectToast(h.refusalWords(busy));
      final denied = MockResponse.denied('menu.items.delete');
      h.server.fail('DELETE', deleteApi, denied);
      await confirmDeleteAr(h, 'Iced Afternoon');
      await h.expectToast(h.refusalWords(denied));
      expect(shownNames(tester), _all);
    });
  });

  group('caching, retries, live updates', () {
    testWidgets('OFFR-ALL-005 back within 30 s: from the cache; after 30 s: '
        'shown at once and refetched behind', (tester) async {
      final h = await pumpCombos(tester);
      h.allowUnmatched = true; // the editor is its own unit
      expect(callsTo(h, combosApi), hasLength(1));
      await h.tap(rowOf('Coffee & Cookie'));
      await h.go(combosPath);
      expect(callsTo(h, combosApi), hasLength(1), reason: 'fresh');
      // One categories entry for the list and the editor, as on the web.
      expect(callsTo(h, categoriesApi), hasLength(1), reason: 'shared');
      expect(shownNames(tester), _all);

      await h.tap(rowOf('Coffee & Cookie'));
      h.db!.clock.advance(const Duration(seconds: 31));
      final gate = h.server.hold('GET', combosApi);
      await h.go(combosPath);
      expect(callsTo(h, combosApi), hasLength(2), reason: 'stale');
      expect(shownNames(tester), _all, reason: 'old rows meanwhile');
      expect(inPage(find.byType(DashSkeleton)), findsNothing);
      gate.release();
      await h.settle();
      expect(shownNames(tester), _all);
    });

    testWidgets('OFFR-ALL-005 the retry policy: a refusal once, a failure '
        'twice, a 429 four times; no focus refetch', (tester) async {
      Future<int> asks(MockResponse answer) async {
        final s = combosServer();
        s.server.fail('GET', combosApi, answer, times: null);
        final c = ProviderContainer(
          retry: webRetry,
          overrides: [
            transportProvider.overrideWithValue(s.server),
            orgIdProvider.overrideWithValue(SeedIds.sabahOrg),
          ],
        );
        const key = (q: null, categoryId: null, isActive: null, page: 1);
        final sub = c.listen(combosListProvider(key), (_, _) {});
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(seconds: 1));
        }
        sub.close();
        c.dispose();
        return s.server.callsTo(combosApi).length;
      }

      expect(await asks(MockResponse.denied('menu.items.read')), 1);
      expect(await asks(MockResponse.error(500, 'boom')), 2);
      expect(await asks(MockResponse.error(429, 'Slow down')), 4);
    });

    testWidgets('OFFR-ALL-006 a resync frame refreshes the list; a branch '
        'settings change does not', (tester) async {
      final h = await pumpCombos(
        tester,
        path: '$combosPath?branchId=${SeedIds.zamalek}',
      );
      final conn = h.realtime.current;
      expect(conn, isNotNull);
      final lists = callsTo(h, combosApi).length;
      conn!.emit('branch.settings_changed', data: '{}');
      await h.settle();
      expect(callsTo(h, combosApi), hasLength(lists));
      conn.emit('resync', data: '{}');
      await h.settle();
      expect(callsTo(h, combosApi), hasLength(lists + 1));
      expect(shownNames(tester), _all);
    });

    testWidgets('OFFR-ALL-015 the combos list is paged by the server: a '
        'refetch keeps its page', (tester) async {
      final s = combosServer();
      addCombos(s.db, 30);
      final h = await pumpCombos(
        tester,
        seeded: s,
        path: '$combosPath?branchId=${SeedIds.zamalek}',
      );
      await h.tap(inPage(find.bySemanticsLabel('Next')));
      expect(pageText('Page 2 of 2'), findsOneWidget);
      final asked = callsTo(h, combosApi).length;
      h.realtime.current!.emit('resync', data: '{}');
      await h.settle();
      expect(callsTo(h, combosApi).length, greaterThan(asked));
      expect(callsTo(h, combosApi).last.query['page'], ['2']);
      expect(pageText('Page 2 of 2'), findsOneWidget);
      expect(shownNames(tester), hasLength(11));
    });

    testWidgets('OFFR-ALL-007 a combo delete invalidates every combos, '
        'deals, combo settings, Bundles, menu-items and costing read', (
      tester,
    ) async {
      final h = await pumpCombos(tester);
      final seen = <List<String>>[];
      final sub = h.container
          .read(realtimeBusProvider)
          .invalidations
          .listen(seen.add);
      addTearDown(sub.cancel);
      await confirmDelete(h, 'Iced Afternoon');
      await h.expectToast('Combo deleted');
      expect(seen, [combosInvalidationPrefixes]);
      expect(combosInvalidationPrefixes, [
        '/combos',
        '/deals',
        '/settings/combos',
        '/reports/bundles',
        '/menu-items',
        '/costing',
      ]);
    });
  });

  group('the shared table', () {
    testWidgets('OFFR-ALL-009 header labels, 56 rows, end-aligned figures, '
        'no sorting; the actions cell never opens the row', (tester) async {
      final h = await pumpCombos(tester);
      for (final l in ['COMBO', 'CATEGORY', 'PRICE', 'SLOTS', 'MARGIN']) {
        expect(pageText(l), findsOneWidget, reason: l);
      }
      expect(tester.getSize(rowOf('Coffee & Cookie')).height, 56);
      // Price ends where its header ends.
      final head = tester.getTopRight(pageText('PRICE'));
      final cell = tester.getTopRight(
        inRow('Coffee & Cookie', find.textContaining('120.00')),
      );
      expect((cell.dx - head.dx).abs(), lessThan(2));
      // A header tap sorts nothing and asks nothing.
      final asked = callsTo(h, combosApi).length;
      await h.tap(pageText('PRICE'));
      expect(shownNames(tester), _all);
      expect(callsTo(h, combosApi), hasLength(asked));
      // The trash opens its confirm, not the combo.
      await h.tap(rowButton('Coffee & Cookie', 'Delete'));
      expect(h.location.path, combosPath);
      await h.tapText('Cancel');
      expect(h.location.path, combosPath);
    });

    testWidgets('OFFR-ALL-009 Space on a focused row opens it', (tester) async {
      final h = await pumpCombos(tester);
      h.allowUnmatched = true;
      final inner = find
          .descendant(
            of: rowOf('Iced Afternoon'),
            matching: find.byType(GestureDetector),
          )
          .first;
      Focus.of(tester.element(inner)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await h.settle();
      expect(h.location.path, '/menu/combos/${comboId('iced-afternoon')}');
    });

    testWidgets('OFFR-ALL-012 a failed refetch replaces rows already shown '
        'with the error state', (tester) async {
      final h = await pumpCombos(tester);
      expect(shownNames(tester), _all);
      final failure = MockResponse.error(500, 'Database error: gone');
      h.server.fail('GET', combosApi, failure, times: null);
      await confirmDelete(h, 'Iced Afternoon');
      await h.flushTimers();
      expect(pageText("Couldn't load this"), findsOneWidget);
      expect(pageText(h.refusalWords(failure)), findsOneWidget);
      expect(shownNames(tester), isEmpty);
      expect(pageText('No combos yet'), findsNothing, reason: 'error wins');
      expect(inPage(find.byType(DashPagination)), findsNothing);
    });

    testWidgets('OFFR-ALL-013 the footer in Arabic: the words and chevrons '
        'the reading way', (tester) async {
      final s = combosServer();
      addCombos(s.db, 30);
      final h = await pumpCombos(tester, seeded: s, locale: 'ar');
      expect(pageText('صفحة 1 من 2'), findsOneWidget);
      DashIconButton btn(String label) => tester.widget<DashIconButton>(
        inPage(
          find.byWidgetPredicate(
            (w) => w is DashIconButton && w.semanticLabel == label,
          ),
        ),
      );
      expect(btn('السابق').icon, 'chevron-right');
      expect(btn('السابق').onPressed, isNull);
      expect(btn('التالي').icon, 'chevron-left');
      await h.tap(inPage(find.bySemanticsLabel('التالي')));
      expect(pageText('صفحة 2 من 2'), findsOneWidget);
      expect(btn('التالي').onPressed, isNull);
    });

    testWidgets('OFFR-ALL-014 the confirm: a red warning disc, Cancel and '
        'the red confirm', (tester) async {
      final h = await pumpCombos(tester);
      await h.tap(rowButton('Iced Afternoon', 'Delete'));
      final dialog = find.byType(DashConfirmDialog);
      expect(
        find.descendant(
          of: dialog,
          matching: find.byWidgetPredicate(
            (w) => w is DashIcon && w.name == 'alert-triangle',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('Cancel')),
        findsOneWidget,
      );
      await h.tapText('Cancel');
      expect(callsTo(h, deleteApi, method: 'DELETE'), isEmpty);
    });

    testWidgets('OFFR-ALL-016 (divergence) the list\'s thumbnail is the '
        'combo\'s image_url; it never polls an asset job', (tester) async {
      final s = combosServer();
      clearCombos(s.db);
      addCombos(s.db, 1);
      s.db.table('menu_items').find(mockUuid('combo:extra:1'))!['image_url'] =
          'https://cdn.madar.test/combos/extra.jpg';
      final h = await pumpCombos(tester, seeded: s);
      final image = tester.widget<Image>(
        inRow('Extra combo 01', find.byType(Image)),
      );
      // Decoded at the tile's size (a ResizeImage over the network one).
      final provider = image.image as ResizeImage;
      expect(provider.width, isNotNull);
      expect(
        (provider.imageProvider as NetworkImage).url,
        'https://cdn.madar.test/combos/extra.jpg',
      );
      expect(
        h.server.calls.where((c) => c.path.startsWith('/assets')),
        isEmpty,
      );
    });
  });

  testWidgets('OFFR-ALL-008 invalidateDiscounts: every /discounts read, '
      'nothing else', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final seen = <List<String>>[];
    final sub = container
        .read(realtimeBusProvider)
        .invalidations
        .listen(seen.add);
    addTearDown(sub.cancel);
    late WidgetRef widgetRef;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) {
            widgetRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    invalidateDiscounts(widgetRef);
    await tester.pump();
    expect(seen, [
      ['/discounts'],
    ]);
    expect(pathInvalidatedBy('/discounts', seen.single.single), isTrue);
    expect(pathInvalidatedBy('/combos', seen.single.single), isFalse);
  });

  test('OFFR-ALL-005 the key is the request: per page fixed at 25', () {
    expect(combosPerPage, 25);
    const a = (q: 'x', categoryId: null, isActive: true, page: 2);
    const b = (q: 'x', categoryId: null, isActive: true, page: 2);
    expect(a, b);
  });
}

/// [confirmDelete] with the Arabic words.
Future<void> confirmDeleteAr(DashHarness h, String name) async {
  await h.tap(rowButton(name, 'حذف'));
  await h.tap(
    find.descendant(
      of: find.byType(DashConfirmDialog),
      matching: find.text('حذف'),
    ),
  );
}
