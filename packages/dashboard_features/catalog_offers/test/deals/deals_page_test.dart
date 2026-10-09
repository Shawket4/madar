// The Deals list (OFFR-DEA-001..023, 050; OFFR-ALL-011..015 as the list
// shows them), driven through the real shell on the mock server. One test
// per inventory row, its id first in the name.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show DashSidebar;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

List<MockCall> lists(DashHarness h) => callsTo(h, 'GET', listRoute);

void main() {
  group('list', () {
    testWidgets('OFFR-DEA-001 /menu/deals renders the page under its '
        'Catalog ▸ Menu leaf, keeping ?edit beside the scope', (tester) async {
      final h = await pumpDeals(tester);
      expect(page, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DashSidebar),
          matching: find.text('Deals'),
        ),
        findsOneWidget,
      );
      for (final name in seededNames) {
        expect(inTable(find.text(name)), findsOneWidget, reason: name);
      }
      await h.tap(rowOf('Juice trio for 270'));
      expect(h.location.path, dealsPath);
      expect(h.location.queryParameters['edit'], dealId('juice-trio'));
    });

    testWidgets('OFFR-DEA-002 without menu.items.read: Restricted "Deals" '
        'with the default body, and GET /deals is never asked', (tester) async {
      final s = serverWithCaps(['orders.read']);
      final h = await pumpDeals(tester, server: s.server, db: s.db);
      expect(page, findsNothing);
      expect(find.text('Not available on this account'), findsOneWidget);
      expect(find.text(h.t('common.restrictedBody')), findsOneWidget);
      expect(lists(h), isEmpty);
    });

    testWidgets('OFFR-DEA-002 an org without the POS module: the module '
        'gate, and nothing asked', (tester) async {
      final h = await pumpDeals(tester, persona: Persona.dawamOnly);
      expect(page, findsNothing);
      expect(find.text(h.t('dawam.moduleOffTitle')), findsOneWidget);
      expect(lists(h), isEmpty);
    });

    testWidgets('OFFR-DEA-002 a platform admin with no org picked: the '
        'server\'s refusal in words, with Retry', (tester) async {
      final h = await pumpDeals(tester, persona: Persona.platform);
      expect(page, findsOneWidget);
      expect(lists(h).single.status, 403);
      expect(
        inPage(
          find.text(
            h.refusalWords(
              MockResponse.forbidden('A super admin must scope this to an org'),
            ),
          ),
        ),
        findsOneWidget,
      );
      expect(inPage(find.text('Retry')), findsOneWidget);
      expect(inPage(find.text('No deals yet')), findsNothing);
    });

    testWidgets('OFFR-DEA-003 header: title "Deals" and its sentence', (
      tester,
    ) async {
      final h = await pumpDeals(tester);
      expect(inPage(find.text('Deals')), findsOneWidget);
      expect(inPage(find.text(h.t('deals.subtitle'))), findsOneWidget);
    });

    testWidgets('OFFR-DEA-004 "New deal" sets ?edit=new and opens the empty '
        'dialog', (tester) async {
      final h = await pumpDeals(tester);
      await h.tap(inPage(find.text('New deal')).first);
      expect(h.location.queryParameters['edit'], 'new');
      expect(dialog, findsOneWidget);
      expect(inDialog(find.text('New deal')), findsOneWidget);
    });

    testWidgets('OFFR-DEA-005 reads: GET /deals with no params, and the pick '
        'lists (menu items in full, categories, branches) for the org', (
      tester,
    ) async {
      final h = await pumpDeals(tester);
      expect(lists(h).single.query, isEmpty);
      final items = callsTo(h, 'GET', '/menu-items').single.query;
      expect(items['org_id'], [SeedIds.sabahOrg]);
      expect(items['full'], ['true']);
      expect(callsTo(h, 'GET', '/categories').single.query['org_id'], [
        SeedIds.sabahOrg,
      ]);
      expect(callsTo(h, 'GET', '/branches'), isNotEmpty);
    });

    testWidgets('OFFR-DEA-006 rows by sort, then name A→Z', (tester) async {
      final s = dealsServer();
      // Same sort as the pastry pair, a name that sorts before it.
      s.db.table(OffersTables.deals).find(dealId('juice-trio'))!['sort'] = 0;
      final h = await pumpDeals(tester, server: s.server, db: s.db);
      double y(String name) => tester.getTopLeft(rowOf(name)).dy;
      expect(y('Any 2 pastries for 150'), lessThan(y('Juice trio for 270')));
      expect(
        y('Juice trio for 270'),
        lessThan(y('Buy 2 coffees, get a cookie free')),
      );
      expect(
        y('Second iced latte half price'),
        lessThan(y('Weekend breakfast pair for 330')),
      );
      expect(h.server.unmatched, isEmpty);
    });

    testWidgets('OFFR-DEA-007 "Deal": the English name, the Arabic one under '
        'it right to left (never translated)', (tester) async {
      await pumpDeals(tester, locale: 'ar');
      expect(inTable(find.text('Any 2 pastries for 150')), findsOneWidget);
      final ar = inTable(find.text('أي قطعتين مخبوزات بـ 150'));
      expect(ar, findsOneWidget);
      expect(
        tester
            .widget<RichText>(
              find.descendant(of: ar, matching: find.byType(RichText)),
            )
            .textDirection,
        TextDirection.rtl,
      );
    });

    testWidgets('OFFR-DEA-008 "Rule": any N for a price, buy X get Y free, '
        'and at a percent off', (tester) async {
      await pumpDeals(tester);
      expect(inTable(find.text('RULE')), findsOneWidget);
      expect(
        inRow('Any 2 pastries for 150', find.text('Any 2 for EGP 150.00')),
        findsOneWidget,
      );
      expect(
        inRow(
          'Buy 2 coffees, get a cookie free',
          find.text('Buy 2, get 1 free'),
        ),
        findsOneWidget,
      );
      expect(
        inRow(
          'Second iced latte half price',
          find.text('Buy 1, get 1 at 50% off'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('OFFR-DEA-009 "Counts": items and whole categories by name, '
        'a size in brackets, and the separate reward list after an arrow', (
      tester,
    ) async {
      await pumpDeals(tester);
      expect(inTable(find.text('COUNTS')), findsOneWidget);
      expect(
        inRow('Any 2 pastries for 150', find.text('All Bakery')),
        findsOneWidget,
      );
      expect(
        inRow(
          'Buy 2 coffees, get a cookie free',
          find.text('All Hot Coffee → Chocolate Chip Cookie'),
        ),
        findsOneWidget,
      );
      expect(
        inRow('Second iced latte half price', find.text('Iced Latte (Large)')),
        findsOneWidget,
      );
    });

    testWidgets('OFFR-DEA-009 an empty pool reads "—"; entries join with '
        'the Arabic separator in Arabic', (tester) async {
      final s = dealsServer();
      final row = s.db.table(OffersTables.deals).find(dealId('juice-trio'))!;
      row['pool'] = <Object?>[];
      final pastry = s.db
          .table(OffersTables.deals)
          .find(dealId('pastry-pair'))!;
      pastry['pool'] = [
        {
          'menu_item_id': null,
          'category_id': OffersSeed.category('bakery'),
          'size_label': null,
        },
        {
          'menu_item_id': OffersSeed.item('cookie'),
          'category_id': null,
          'size_label': null,
        },
      ];
      await pumpDeals(tester, server: s.server, db: s.db, locale: 'ar');
      expect(inRow('Juice trio for 270', find.text('—')), findsOneWidget);
      expect(
        inRow(
          'Any 2 pastries for 150',
          find.text('كل مخبوزات، كوكيز بالشوكولاتة'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('OFFR-DEA-010 "When": always, one window in a line, several '
        'counted', (tester) async {
      await pumpDeals(tester);
      expect(inTable(find.text('WHEN')), findsOneWidget);
      expect(
        inRow('Any 2 pastries for 150', find.text('Always available')),
        findsOneWidget,
      );
      expect(
        inRow(
          'Second iced latte half price',
          find.text('Mon, Tue, Wed, Thu, Fri · 12:00 to 16:00 · All branches'),
        ),
        findsOneWidget,
      );
      expect(
        inRow(
          'Juice trio for 270',
          find.text('Every day · 2026-06-01 to 2026-08-31 · All branches'),
        ),
        findsOneWidget,
      );
      expect(
        inRow('Weekend breakfast pair for 330', find.text('2 windows')),
        findsOneWidget,
      );
    });

    testWidgets('OFFR-DEA-010 one window at a branch names the branch; an '
        'open end reads "…"', (tester) async {
      final s = dealsServer();
      final row = s.db
          .table(OffersTables.deals)
          .find(dealId('weekend-breakfast'))!;
      row['windows'] = [
        {
          'id': mockUuid('w'),
          'branch_id': SeedIds.zamalek,
          'weekdays': 127,
          'starts_at': null,
          'ends_at': null,
          'valid_from': '2026-10-01',
          'valid_to': null,
        },
      ];
      await pumpDeals(tester, server: s.server, db: s.db);
      expect(
        inRow(
          'Weekend breakfast pair for 330',
          find.text('Every day · 2026-10-01 to … · Zamalek'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('OFFR-DEA-011 "Status": Active / Inactive, and the branch '
        'exceptions pill', (tester) async {
      await pumpDeals(tester);
      expect(
        inRow('Any 2 pastries for 150', find.text('Active')),
        findsOneWidget,
      );
      expect(
        inRow('Any 2 pastries for 150', find.textContaining('exception')),
        findsNothing,
      );
      expect(
        inRow(
          'Buy 2 coffees, get a cookie free',
          find.text('1 branch exception'),
        ),
        findsOneWidget,
      );
      expect(
        inRow('Juice trio for 270', find.text('Inactive')),
        findsOneWidget,
      );
      expect(
        inRow('Juice trio for 270', find.text('2 branch exceptions')),
        findsOneWidget,
      );
    });

    testWidgets('OFFR-DEA-012 a row opens its deal editable with '
        'menu.deals.edit', (tester) async {
      final h = await pumpDeals(tester);
      await h.tap(rowOf('Buy 2 coffees, get a cookie free'));
      expect(h.location.queryParameters['edit'], dealId('coffee-cookie-free'));
      expect(inDialog(find.text('Edit deal')), findsOneWidget);
      expect(inDialog(find.text('Save')), findsOneWidget);
      final name = tester.widget<DashTextInput>(
        find
            .ancestor(
              of: labelled('Name').first,
              matching: find.byType(DashTextInput),
            )
            .first,
      );
      expect(name.enabled, isTrue);
      expect(name.value, 'Buy 2 coffees, get a cookie free');
    });

    testWidgets('OFFR-DEA-012 a row opens read-only with menu.items.read '
        'alone: no Save', (tester) async {
      final h = await pumpDeals(tester, persona: Persona.limited);
      await h.tap(rowOf('Any 2 pastries for 150'));
      expect(dialog, findsOneWidget);
      expect(inDialog(find.text('Save')), findsNothing);
      expect(inDialog(find.text('Close')), findsOneWidget);
    });

    testWidgets('OFFR-DEA-012 Enter on a focused row opens it', (tester) async {
      final h = await pumpDeals(tester);
      Focus.of(
        tester.element(
          find.descendant(
            of: rowOf('Juice trio for 270'),
            matching: find.text('Juice trio for 270'),
          ),
        ),
      ).requestFocus();
      await h.settle(rounds: 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await h.settle();
      expect(h.location.queryParameters['edit'], dealId('juice-trio'));
      expect(dialog, findsOneWidget);
    });

    testWidgets('OFFR-DEA-013 the row pencil opens the deal', (tester) async {
      final h = await pumpDeals(tester);
      await h.tap(inRow('Juice trio for 270', find.bySemanticsLabel('Edit')));
      expect(h.location.queryParameters['edit'], dealId('juice-trio'));
      expect(inDialog(find.text('Edit deal')), findsOneWidget);
    });

    testWidgets('OFFR-DEA-014 the row trash asks first; Cancel does '
        'nothing', (tester) async {
      final h = await pumpDeals(tester);
      await h.tap(inRow('Juice trio for 270', find.bySemanticsLabel('Delete')));
      expect(
        find.descendant(
          of: confirm,
          matching: find.text('Delete Juice trio for 270?'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: confirm,
          matching: find.text(h.t('deals.deleteBody')),
        ),
        findsOneWidget,
      );
      await h.tap(find.descendant(of: confirm, matching: find.text('Cancel')));
      expect(confirm, findsNothing);
      expect(callsTo(h, 'DELETE', itemRoute), isEmpty);
      expect(inTable(find.text('Juice trio for 270')), findsOneWidget);
    });

    testWidgets('OFFR-DEA-014 the confirm names the deal in Arabic on an '
        'Arabic screen', (tester) async {
      final h = await pumpDeals(tester, locale: 'ar');
      await h.tap(
        inRow(
          'Juice trio for 270',
          find.bySemanticsLabel(h.t('common.delete')),
        ),
      );
      expect(
        find.descendant(
          of: confirm,
          matching: find.text('حذف ثلاثة عصائر بـ 270؟'),
        ),
        findsOneWidget,
      );
      await h.tap(
        find.descendant(of: confirm, matching: find.text(h.t('common.cancel'))),
      );
    });

    testWidgets('OFFR-DEA-015 Delete confirmed: DELETE, "Deal deleted", the '
        'list refetches without it', (tester) async {
      final h = await pumpDeals(tester);
      final before = lists(h).length;
      await h.tap(inRow('Juice trio for 270', find.bySemanticsLabel('Delete')));
      await h.tap(find.descendant(of: confirm, matching: find.text('Delete')));
      expect(
        callsTo(h, 'DELETE', itemRoute).single.path,
        '/deals/${dealId('juice-trio')}',
      );
      await h.expectToast('Deal deleted');
      expect(lists(h).length, before + 1);
      expect(inTable(find.text('Juice trio for 270')), findsNothing);
    });

    testWidgets('OFFR-DEA-015 a refused delete toasts the server\'s words '
        'and keeps the row', (tester) async {
      final s = dealsServer();
      final refusal = MockResponse.denied('menu.deals.edit');
      s.server.fail('DELETE', itemRoute, refusal);
      final h = await pumpDeals(tester, server: s.server, db: s.db);
      final before = lists(h).length;
      await h.tap(inRow('Juice trio for 270', find.bySemanticsLabel('Delete')));
      await h.tap(find.descendant(of: confirm, matching: find.text('Delete')));
      await h.expectToast(h.refusalWords(refusal));
      expect(lists(h).length, before);
      expect(inTable(find.text('Juice trio for 270')), findsOneWidget);
    });

    testWidgets('OFFR-DEA-016 menu.items.read alone: the list without New '
        'deal or row actions', (tester) async {
      final h = await pumpDeals(tester, persona: Persona.manager);
      expect(inTable(find.text('Any 2 pastries for 150')), findsOneWidget);
      expect(inTable(find.text('All Bakery')), findsOneWidget);
      expect(inTable(find.text('Buy 2, get 1 free')), findsOneWidget);
      expect(inPage(find.text('New deal')), findsNothing);
      expect(inPage(find.bySemanticsLabel('Edit')), findsNothing);
      expect(inPage(find.bySemanticsLabel('Delete')), findsNothing);
      expect(h.server.unmatched, isEmpty);
    });

    testWidgets('OFFR-DEA-017 no deals: "No deals yet", the example, and New '
        'deal (with the right)', (tester) async {
      final s = dealsServer();
      s.db.table(OffersTables.deals).clear();
      final h = await pumpDeals(tester, server: s.server, db: s.db);
      expect(inPage(find.text('No deals yet')), findsOneWidget);
      expect(inPage(find.text(h.t('deals.emptyHint'))), findsOneWidget);
      expect(inTable(find.text('New deal')), findsOneWidget);
      await h.tap(inTable(find.text('New deal')));
      expect(h.location.queryParameters['edit'], 'new');
      expect(dialog, findsOneWidget);
    });

    testWidgets('OFFR-DEA-017 no deals and no edit right: no button in the '
        'empty state', (tester) async {
      final s = dealsServer(persona: Persona.limited);
      s.db.table(OffersTables.deals).clear();
      await pumpDeals(
        tester,
        persona: Persona.limited,
        server: s.server,
        db: s.db,
      );
      expect(inPage(find.text('No deals yet')), findsOneWidget);
      expect(inPage(find.text('New deal')), findsNothing);
    });

    testWidgets('OFFR-DEA-018 loading shows skeleton rows', (tester) async {
      final s = dealsServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpDeals(tester, server: s.server, db: s.db);
      expect(inPage(find.byType(DashSkeleton)), findsWidgets);
      expect(inTable(find.text('Any 2 pastries for 150')), findsNothing);
      gate.release();
      await h.settle();
      expect(inPage(find.byType(DashSkeleton)), findsNothing);
      expect(inTable(find.text('Any 2 pastries for 150')), findsOneWidget);
    });

    testWidgets('OFFR-DEA-018 a failed load: "Couldn\'t load this", the '
        'server\'s words and Retry, which asks the deals again (only them)', (
      tester,
    ) async {
      final s = dealsServer();
      final boom = MockResponse.error(500, 'Database unavailable');
      s.server.fail('GET', listRoute, boom);
      final h = await pumpDeals(tester, server: s.server, db: s.db);
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      expect(inPage(find.text(h.refusalWords(boom))), findsOneWidget);
      final items = callsTo(h, 'GET', '/menu-items').length;
      await h.tap(inPage(find.text('Retry')));
      expect(lists(h).length, 2);
      expect(callsTo(h, 'GET', '/menu-items').length, items);
      expect(inTable(find.text('Any 2 pastries for 150')), findsOneWidget);
    });

    testWidgets('OFFR-DEA-018 while Retry runs the error stays (no skeleton, '
        'never "No deals yet")', (tester) async {
      final s = dealsServer();
      s.server.fail('GET', listRoute, MockResponse.error(500, 'down'));
      final h = await pumpDeals(tester, server: s.server, db: s.db);
      final gate = s.server.hold('GET', listRoute);
      await h.tap(inPage(find.text('Retry')));
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      expect(inPage(find.text('No deals yet')), findsNothing);
      gate.release();
      await h.settle();
      expect(inTable(find.text('Any 2 pastries for 150')), findsOneWidget);
    });

    testWidgets('OFFR-DEA-018 a failed refetch replaces the rows with the '
        'error (OFFR-ALL-012)', (tester) async {
      final s = dealsServer();
      final h = await pumpDeals(tester, server: s.server, db: s.db);
      expect(inTable(find.text('Any 2 pastries for 150')), findsOneWidget);
      final boom = MockResponse.error(500, 'Database unavailable');
      s.server.fail('GET', listRoute, boom);
      h.container.read(realtimeBusProvider).invalidate(const ['/deals']);
      await h.settle();
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      expect(inPage(find.text(h.refusalWords(boom))), findsOneWidget);
      expect(inTable(find.text('Any 2 pastries for 150')), findsNothing);
    });

    testWidgets('OFFR-DEA-019 ten deals a page; Next / Previous page through '
        'in the client', (tester) async {
      final s = dealsServer();
      addPromoDeals(s.db, 7);
      final h = await pumpDeals(tester, server: s.server, db: s.db);
      expect(inPage(find.text('Page 1 of 2')), findsOneWidget);
      expect(inTable(find.text('Promo deal 05')), findsOneWidget);
      expect(inTable(find.text('Promo deal 06')), findsNothing);
      await h.tap(inPage(find.bySemanticsLabel('Next')));
      expect(inPage(find.text('Page 2 of 2')), findsOneWidget);
      expect(inTable(find.text('Promo deal 06')), findsOneWidget);
      expect(inTable(find.text('Any 2 pastries for 150')), findsNothing);
      expect(lists(h).length, 1, reason: 'paging asks nothing');
      await h.tap(inPage(find.bySemanticsLabel('Previous')));
      expect(inPage(find.text('Page 1 of 2')), findsOneWidget);
    });

    testWidgets('OFFR-DEA-019 ten deals or fewer: no footer', (tester) async {
      await pumpDeals(tester);
      expect(inPage(find.textContaining('Page 1 of')), findsNothing);
    });

    testWidgets('OFFR-ALL-015 a change of the rows puts the table back on '
        'page 1', (tester) async {
      final s = dealsServer();
      addPromoDeals(s.db, 7);
      final h = await pumpDeals(tester, server: s.server, db: s.db);
      await h.tap(inPage(find.bySemanticsLabel('Next')));
      expect(inPage(find.text('Page 2 of 2')), findsOneWidget);
      await h.tap(inRow('Promo deal 07', find.bySemanticsLabel('Delete')));
      await h.tap(find.descendant(of: confirm, matching: find.text('Delete')));
      await h.expectToast('Deal deleted');
      expect(inPage(find.text('Page 1 of 2')), findsOneWidget);
    });

    testWidgets('OFFR-DEA-020 Columns: Rule, Counts, When, Status can be '
        'hidden (Deal cannot)', (tester) async {
      final h = await pumpDeals(tester);
      await h.tap(inPage(find.text('Columns')));
      // The headers read in capitals; the menu lists the labelled columns.
      for (final label in ['Rule', 'Counts', 'When', 'Status']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Deal'), findsNothing);
      await h.tap(find.text('Counts'));
      expect(inTable(find.text('COUNTS')), findsNothing);
      expect(inTable(find.text('All Bakery')), findsNothing);
      expect(inTable(find.text('Any 2 for EGP 150.00')), findsOneWidget);
    });

    testWidgets('OFFR-DEA-021 phone: a card per deal, titled by the name, '
        'Rule / Counts / When / Status as label and value; a tap opens it '
        'full screen', (tester) async {
      final h = await pumpDeals(tester, size: DashSize.phone);
      expect(inPage(find.text('Columns')), findsNothing);
      final card = rowOf('Second iced latte half price');
      for (final label in ['Rule', 'Counts', 'When', 'Status']) {
        expect(
          find.descendant(of: card, matching: find.text(label)),
          findsOneWidget,
          reason: label,
        );
      }
      expect(
        find.descendant(
          of: card,
          matching: find.text('Buy 1, get 1 at 50% off'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.bySemanticsLabel('Edit')),
        findsOneWidget,
      );
      await h.tap(card);
      expect(dialog, findsOneWidget);
      expect(
        tester.getSize(dialog).width,
        tester.view.physicalSize.width / tester.view.devicePixelRatio,
      );
    });

    testWidgets('OFFR-DEA-022 ?edit=<id> opens that deal once the list has '
        'loaded', (tester) async {
      final s = dealsServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpDeals(
        tester,
        path: '$dealsPath?edit=${dealId('iced-latte-half')}',
        server: s.server,
        db: s.db,
      );
      expect(dialog, findsNothing);
      gate.release();
      await h.settle();
      expect(inDialog(find.text('Edit deal')), findsOneWidget);
      expect(
        tester
            .widget<DashTextInput>(
              find
                  .ancestor(
                    of: labelled('Name').first,
                    matching: find.byType(DashTextInput),
                  )
                  .first,
            )
            .value,
        'Second iced latte half price',
      );
    });

    testWidgets('OFFR-DEA-022 an unknown ?edit id opens nothing, and the '
        'param stays', (tester) async {
      final h = await pumpDeals(tester, path: '$dealsPath?edit=nope');
      expect(dialog, findsNothing);
      expect(h.location.queryParameters['edit'], 'nope');
    });

    testWidgets('OFFR-DEA-022 ?edit=new opens a new deal with '
        'menu.deals.edit', (tester) async {
      await pumpDeals(tester, path: '$dealsPath?edit=new');
      expect(inDialog(find.text('New deal')), findsOneWidget);
      expect(inDialog(find.text('Create deal')), findsOneWidget);
    });

    testWidgets('OFFR-DEA-022 ?edit=new opens nothing without '
        'menu.deals.edit, even from the URL', (tester) async {
      await pumpDeals(
        tester,
        path: '$dealsPath?edit=new',
        persona: Persona.limited,
      );
      expect(page, findsOneWidget);
      expect(dialog, findsNothing);
    });

    testWidgets('OFFR-DEA-023 Cancel, ×, Esc and a click outside close the '
        'dialog and drop ?edit', (tester) async {
      final h = await pumpDeals(tester);
      final id = dealId('pastry-pair');

      Future<void> open() async {
        await h.go('$dealsPath?edit=$id');
        expect(dialog, findsOneWidget);
      }

      await open();
      await tapInDialog(h, 'Cancel');
      expect(dialog, findsNothing);
      expect(h.location.queryParameters.containsKey('edit'), isFalse);

      await open();
      await h.tap(inDialog(find.bySemanticsLabel('Close')));
      expect(dialog, findsNothing);
      expect(h.location.queryParameters.containsKey('edit'), isFalse);

      await open();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(dialog, findsNothing);
      expect(h.location.queryParameters.containsKey('edit'), isFalse);

      await open();
      await tester.tapAt(const Offset(4, 450));
      await h.settle();
      expect(dialog, findsNothing);
      expect(h.location.queryParameters.containsKey('edit'), isFalse);
      expect(lists(h).length, 1, reason: 'closing saves nothing');
    });

    testWidgets('OFFR-ALL-006 a resync frame refreshes the deals and the '
        'pick lists; other branch events do not', (tester) async {
      final h = await pumpDeals(tester, branch: SeedIds.maadi);
      final items = callsTo(h, 'GET', '/menu-items').length;
      h.realtime.current!.emit('order.created', data: '{}');
      await h.settle();
      expect(lists(h), hasLength(1));
      h.realtime.current!.emit('resync', data: '{}');
      await h.settle();
      expect(lists(h), hasLength(2));
      expect(callsTo(h, 'GET', '/menu-items').length, items + 1);
    });

    testWidgets('OFFR-DEA-023 (divergence) the open deal leaves the list: '
        'the dialog closes and ?edit goes', (tester) async {
      final h = await pumpDeals(
        tester,
        path: '$dealsPath?edit=${dealId('juice-trio')}',
      );
      expect(dialog, findsOneWidget);
      h.db!
              .table(OffersTables.deals)
              .find(dealId('juice-trio'))!['deleted_at'] =
          h.db!.nowIso;
      h.container.read(realtimeBusProvider).invalidate(const ['/deals']);
      await h.settle();
      expect(dialog, findsNothing);
      expect(h.location.queryParameters.containsKey('edit'), isFalse);
      expect(inTable(find.text('Juice trio for 270')), findsNothing);
    });

    testWidgets('OFFR-DEA-050 while the pick lists load (or fail) the names '
        'read "—" / "All —", and the list still shows', (tester) async {
      final s = dealsServer();
      s.server.fail(
        'GET',
        '/menu-items',
        MockResponse.error(500, 'down'),
        times: null,
      );
      s.server.fail(
        'GET',
        '/categories',
        MockResponse.error(500, 'down'),
        times: null,
      );
      final branches = s.server.hold('GET', '/branches');
      final h = await pumpDeals(tester, server: s.server, db: s.db);
      expect(
        inRow('Any 2 pastries for 150', find.text('All —')),
        findsOneWidget,
      );
      expect(
        inRow('Buy 2 coffees, get a cookie free', find.text('All — → —')),
        findsOneWidget,
      );
      expect(
        inRow('Second iced latte half price', find.text('— (Large)')),
        findsOneWidget,
      );
      expect(inTable(find.text('Any 2 for EGP 150.00')), findsOneWidget);
      branches.release();
      await h.settle();
    });
  });
}
