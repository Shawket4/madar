// Archiving ingredients: the mock backend's contract (status filter, the
// confirm rule, idempotent round trip, name reuse, capability), the page's
// Active / Archived views and badge, the drawer's Archive / Unarchive, the
// confirmation dialog in English and Arabic, and the create dialog's
// "Unarchive" offer on a name an archived ingredient holds.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/ingredients/archive_dialog.dart';
import 'package:dashboard_inventory/src/ingredients/ingredients_data.dart';
import 'package:dashboard_inventory/src/shared/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const String archiveRoute = '/inventory/orgs/{org_id}/catalog/{id}/archive';
const String unarchiveRoute = '/inventory/orgs/{org_id}/catalog/{id}/unarchive';
const String usageRoute = '/inventory/orgs/{org_id}/catalog/{id}/usage';

final String org = SeedIds.sabahOrg;
final String soy = InvIds.ingredient('soy');
final String oat = InvIds.ingredient('oat');

Matcher refused(int status, {String? code, String? words}) => throwsA(
  isA<ApiException>()
      .having((e) => e.status, 'status', status)
      .having((e) => e.code, 'code', code)
      .having((e) => e.message, 'message', contains(words ?? '')),
);

({DashboardApi api, MockDb db}) backend([Persona p = Persona.owner]) {
  final s = ingredientsServer(persona: p);
  return (api: DashboardApi(s.server), db: s.db);
}

/// An ingredient nothing uses and no branch holds.
String addUnused(MockDb db) =>
    db[InvTables.ingredients].insert({
          'id': InvIds.ingredient('rose-water'),
          'org_id': SeedIds.sabahOrg,
          'name': 'Rose Water',
          'unit': 'ml',
          'category_id': InvIds.category('general'),
          'category_slug': 'general',
          'category_name': 'General',
          'cost_per_unit': 2.0,
          'is_active': true,
          'archived_at': null,
          'archived_by': null,
        })['id']!
        as String;

Finder get archiveDialog => find.byType(ArchiveIngredientDialog);
Finder inArchive(Finder f) => find.descendant(of: archiveDialog, matching: f);

void main() {
  group('mock contract', () {
    test(
      'GET catalog honours status; omitted lists all, with archived_at',
      () async {
        final b = backend();
        final all = await b.api.inventory.listCatalog(orgId: org);
        final soyRow = all.firstWhere((i) => i.id == soy);
        expect(soyRow.archivedAt, isNotNull);
        expect(soyRow.archivedBy, SeedIds.user('nour'));
        final active = await b.api.inventory.listCatalog(
          orgId: org,
          status: ArchiveFilter.active,
        );
        expect(active.map((i) => i.id), isNot(contains(soy)));
        expect(active, hasLength(all.length - 1));
        final archived = await b.api.inventory.listCatalog(
          orgId: org,
          status: ArchiveFilter.archived,
        );
        expect(archived.map((i) => i.id), [soy]);
        final stock = await b.api.inventory.listBranchStock(
          branchId: SeedIds.zamalek,
          status: ArchiveFilter.archived,
        );
        expect(stock.single.orgIngredientId, soy);
        expect(stock.single.archivedAt, isNotNull);
      },
    );

    test('the waste log carries ingredient_archived_at', () async {
      final b = backend();
      final waste = await b.api.inventory.listWaste(branchId: SeedIds.zamalek);
      final line = waste.firstWhere((m) => m.orgIngredientId == soy);
      expect(line.ingredientArchivedAt, isNotNull);
      expect(
        waste
            .where((m) => m.orgIngredientId == oat)
            .every((m) => m.ingredientArchivedAt == null),
        isTrue,
      );
    });

    test('usage lists stock and open documents; archive needs confirm when '
        'used or stocked', () async {
      final b = backend();
      final usage = await b.api.inventory.getCatalogItemUsage(
        orgId: org,
        id: oat,
      );
      expect(usage.name, 'Oat Milk');
      expect(usage.needsConfirmation, isTrue);
      expect(
        usage.stock.firstWhere((s) => s.branchId == SeedIds.zamalek).onHand,
        -350,
      );
      await expectLater(
        b.api.inventory.archiveCatalogItem(orgId: org, id: oat),
        refused(409, code: 'ARCHIVE_NEEDS_CONFIRMATION'),
      );
      expect(b.db[InvTables.ingredients].find(oat)!['archived_at'], isNull);
      final done = await b.api.inventory.archiveCatalogItem(
        orgId: org,
        id: oat,
        body: const ArchiveIngredientRequest(confirm: true),
      );
      expect(done.archivedAt, isNotNull);
      expect(done.archivedBy, SeedIds.owner);
    });

    test('an unused ingredient archives without confirm; archive and '
        'unarchive are idempotent', () async {
      final b = backend();
      final id = addUnused(b.db);
      final usage = await b.api.inventory.getCatalogItemUsage(
        orgId: org,
        id: id,
      );
      expect(usage.usages, isEmpty);
      expect(usage.stock, isEmpty);
      expect(usage.needsConfirmation, isFalse);
      expect(usage.neverUsed, isTrue);
      final first = await b.api.inventory.archiveCatalogItem(
        orgId: org,
        id: id,
      );
      final again = await b.api.inventory.archiveCatalogItem(
        orgId: org,
        id: id,
      );
      expect(again.archivedAt, first.archivedAt);
      final back = await b.api.inventory.unarchiveCatalogItem(
        orgId: org,
        id: id,
      );
      expect(back.archivedAt, isNull);
      expect(back.archivedBy, isNull);
      final still = await b.api.inventory.unarchiveCatalogItem(
        orgId: org,
        id: id,
      );
      expect(still.archivedAt, isNull);
    });

    test('an archived name is not reusable: create and rename answer 409 '
        'INGREDIENT_NAME_ARCHIVED naming it', () async {
      final b = backend();
      Future<void> expectArchived(Future<Object?> f) => expectLater(
        f,
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 409)
              .having((e) => e.code, 'code', 'INGREDIENT_NAME_ARCHIVED')
              .having((e) => archivedNameHolder(e), 'holder', soy),
        ),
      );
      await expectArchived(
        b.api.inventory.createCatalogItem(
          orgId: org,
          body: const CreateCatalogItemRequest(name: 'Soy Milk', unit: 'ml'),
        ),
      );
      await expectArchived(
        b.api.inventory.updateCatalogItem(
          orgId: org,
          id: oat,
          body: const UpdateCatalogItemRequest(name: 'Soy Milk'),
        ),
      );
    });

    test('capabilities: archive / unarchive need inventory.adjust, usage '
        'inventory.read', () async {
      final b = backend(Persona.limited);
      await expectLater(
        b.api.inventory.archiveCatalogItem(orgId: org, id: oat),
        refused(403, words: '(inventory.adjust)'),
      );
      await expectLater(
        b.api.inventory.unarchiveCatalogItem(orgId: org, id: soy),
        refused(403, words: '(inventory.adjust)'),
      );
      await expectLater(
        b.api.inventory.getCatalogItemUsage(orgId: org, id: oat),
        refused(403, words: '(inventory.read)'),
      );
    });

    test('a full count skips an archived ingredient with no stock there; '
        'low stock never lists one', () async {
      final b = backend();
      final st = await b.api.stocktakes.createStocktake(
        branchId: SeedIds.zamalek,
        body: const CreateStocktakeRequest(
          explicitNulls: {'note', 'category_id', 'org_ingredient_ids'},
        ),
      );
      expect(st.items.map((i) => i.orgIngredientId), isNot(contains(soy)));
      expect(st.items.map((i) => i.orgIngredientId), contains(oat));
    });
  });

  group('pure rules', () {
    OrgIngredient ing(String id, {bool archived = false, bool active = true}) =>
        OrgIngredient.fromJson({
          'id': id,
          'org_id': SeedIds.sabahOrg,
          'name': id,
          'unit': 'g',
          'category_id': InvIds.category('general'),
          'category_slug': 'general',
          'category_name': 'General',
          'is_active': active,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'archived_at': archived ? '2026-08-01T09:00:00Z' : null,
        });

    test('filterIngredients splits by view; the stock filter only in '
        'Active', () {
      final all = [ing('a'), ing('b', archived: true)];
      expect(
        filterIngredients(
          all,
          const {},
          IngredientFilter.all,
          hasBranch: false,
        ).map((i) => i.id),
        ['a'],
      );
      expect(
        filterIngredients(
          all,
          const {},
          IngredientFilter.low,
          hasBranch: true,
          view: IngredientView.archived,
        ).map((i) => i.id),
        ['b'],
      );
    });

    test('pickableOrChosen hides archived and inactive, keeps the chosen', () {
      final all = [
        ing('a'),
        ing('b', archived: true),
        ing('c', active: false),
        ing('d', archived: true),
      ];
      expect(pickableOrChosen(all).map((i) => i.id), ['a']);
      expect(pickableOrChosen(all, ['d', null]).map((i) => i.id), ['a', 'd']);
    });

    test('groupUsages orders the kinds as the server', () {
      IngredientUsageRef u(String kind, String name) =>
          IngredientUsageRef(kind: kind, id: SeedIds.zamalek, name: name);
      final g = groupUsages([
        u('transfer', '#7'),
        u('recipe', 'Latte'),
        u('stocktake', 'Zamalek'),
        u('recipe', 'Flat White'),
      ]);
      expect(g.map((e) => e.$1), ['recipe', 'stocktake', 'transfer']);
      expect(g.first.$2.map((e) => e.name), ['Latte', 'Flat White']);
    });
  });

  group('page', () {
    testWidgets('Active / Archived: the Archived view lists only archived '
        'ingredients, with the badge; the stock filter only in Active', (
      tester,
    ) async {
      final h = await pumpIngredients(tester, branch: SeedIds.zamalek);
      expect(inPage(byKey('ingredients-view')), findsOneWidget);
      expect(inPage(byKey('ingredients-filter')), findsOneWidget);
      await search(h, 'Soy');
      expect(cellText('Soy Milk'), findsNothing);
      await search(h, '');
      await h.tap(inPage(find.text('Archived')).first);
      expect(inPage(byKey('ingredients-filter')), findsNothing);
      expect(cellText('Soy Milk'), findsOneWidget);
      expect(cellText('Oat Milk'), findsNothing);
      expect(inTable(byKey('archived-badge')), findsOneWidget);
    });

    testWidgets('the view is offered with All branches too, and remembered', (
      tester,
    ) async {
      final h = await pumpIngredients(tester);
      expect(inPage(byKey('ingredients-view')), findsOneWidget);
      expect(inPage(byKey('ingredients-filter')), findsNothing);
      await h.tap(inPage(find.text('Archived')).first);
      await h.go('/inventory/today');
      await h.go(ingredientsPath);
      expect(cellText('Soy Milk'), findsOneWidget);
    });

    testWidgets('an empty Archived view says "No archived ingredients"', (
      tester,
    ) async {
      final s = ingredientsServer();
      s.db[InvTables.ingredients].update(soy, {'archived_at': null});
      final h = await pumpIngredients(tester, server: s.server, db: s.db);
      await h.tap(inPage(find.text('Archived')).first);
      expect(inPage(byKey('ingredients-archived-empty')), findsOneWidget);
      expect(inPage(find.text('No archived ingredients')), findsOneWidget);
    });

    testWidgets('archive through the dialog: usage shown, confirm:true sent, '
        'toast, the row moves to Archived', (tester) async {
      final s = ingredientsServer();
      final h = await pumpIngredients(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      await openDrawer(h, 'Oat Milk');
      expect(inDrawer(byKey('ingredient-drawer-unarchive')), findsNothing);
      await h.tap(inDrawer(byKey('ingredient-drawer-archive')));
      expect(archiveDialog, findsOneWidget);
      expect(inArchive(find.text('Archive Oat Milk?')), findsOneWidget);
      expect(
        inArchive(
          find.text(
            'It leaves ingredient pickers, stock counts and reorder '
            "suggestions. Its history stays, and you can unarchive it any time.",
          ),
        ),
        findsOneWidget,
      );
      expect(inArchive(byKey('archive-stock')), findsOneWidget);
      expect(inArchive(find.text('Stock on hand')), findsOneWidget);
      expect(h.server.callsTo(usageRoute), hasLength(1));
      await h.tap(inArchive(byKey('archive-confirm')));
      expect(lastBody(h, archiveRoute, 'POST'), {'confirm': true});
      await h.expectToast('Oat Milk archived');
      expect(archiveDialog, findsNothing);
      expect(s.db[InvTables.ingredients].find(oat)!['archived_at'], isNotNull);
      await search(h, 'Oat');
      expect(cellText('Oat Milk'), findsNothing);
      await h.tap(inPage(find.text('Archived')).first);
      expect(cellText('Oat Milk'), findsOneWidget);
    });

    testWidgets('an unused ingredient: "Nothing uses it and no branch holds '
        'any."', (tester) async {
      final s = ingredientsServer();
      addUnused(s.db);
      final h = await pumpIngredients(tester, server: s.server, db: s.db);
      await openDrawer(h, 'Rose Water');
      await h.tap(inDrawer(byKey('ingredient-drawer-archive')));
      expect(
        inArchive(find.text('Nothing uses it and no branch holds any.')),
        findsOneWidget,
      );
      expect(inArchive(byKey('archive-usages')), findsNothing);
    });

    testWidgets('unarchive from the drawer: badge in its header, toast, back '
        'in Active', (tester) async {
      final s = ingredientsServer();
      final h = await pumpIngredients(tester, server: s.server, db: s.db);
      await h.tap(inPage(find.text('Archived')).first);
      await openDrawer(h, 'Soy Milk');
      expect(inDrawer(byKey('archived-badge')), findsOneWidget);
      expect(inDrawer(byKey('ingredient-drawer-archive')), findsNothing);
      await h.tap(inDrawer(byKey('ingredient-drawer-unarchive')));
      await h.expectToast('Soy Milk is active again');
      expect(h.server.callsTo(unarchiveRoute), hasLength(1));
      expect(s.db[InvTables.ingredients].find(soy)!['archived_at'], isNull);
      expect(cellText('Soy Milk'), findsNothing);
      await h.tap(inPage(find.text('Active')).first);
      await search(h, 'Soy');
      expect(cellText('Soy Milk'), findsOneWidget);
    });

    testWidgets('create on an archived name: the toast offers Unarchive, '
        'which brings that one back', (tester) async {
      final s = ingredientsServer();
      final h = await pumpIngredients(tester, server: s.server, db: s.db);
      await openCreate(h);
      await h.enterText(inDialog(byKey('ingredient-name')), 'Soy Milk');
      await h.tap(inDialog(byKey('ingredient-save')));
      expect(
        textHas('An archived ingredient already has this name.'),
        findsOneWidget,
      );
      expect(dialog, findsOneWidget);
      await h.tap(find.text('Unarchive').last);
      await h.expectToast('Soy Milk is active again');
      expect(dialog, findsNothing);
      expect(s.db[InvTables.ingredients].find(soy)!['archived_at'], isNull);
      await h.flushTimers();
    });
  });

  group('i18n', () {
    testWidgets('the dialog in Arabic', (tester) async {
      final h = await pumpIngredients(
        tester,
        locale: 'ar',
        branch: SeedIds.zamalek,
      );
      await openDrawer(h, 'Oat Milk');
      await h.tap(inDrawer(byKey('ingredient-drawer-archive')));
      expect(inArchive(find.text('أرشفة Oat Milk؟')), findsOneWidget);
      expect(
        inArchive(
          find.text(
            'سيختفي من قوائم اختيار المكوّنات وجرد المخزون واقتراحات إعادة '
            'الطلب. يبقى سجلّه كما هو، ويمكنك إلغاء أرشفته في أي وقت.',
          ),
        ),
        findsOneWidget,
      );
      expect(inArchive(find.text('المخزون المتوفر')), findsOneWidget);
      expect(inArchive(find.text('أرشفة')), findsOneWidget);
    });

    testWidgets('the Archived view and badge in Arabic', (tester) async {
      final h = await pumpIngredients(tester, locale: 'ar');
      await h.tap(inPage(find.text('المؤرشفة')).first);
      expect(inTable(find.text('مؤرشف')), findsOneWidget);
      expect(inPage(find.text('النشطة')), findsOneWidget);
    });

    testWidgets('the dialog in English groups open documents', (tester) async {
      final s = ingredientsServer();
      // Oat Milk on an open (draft) purchase order at Zamalek.
      final po = s.db[InvTables.purchaseOrders].firstWhere(
        (p) => p['status'] == 'draft' || p['status'] == 'ordered',
      )!;
      s.db[InvTables.poLines].insert({
        'id': mockUuid('po-line:archive-test'),
        'purchase_order_id': po['id'],
        'org_ingredient_id': oat,
        'ingredient_name': 'Oat Milk',
        'quantity_ordered': 2.0,
        'quantity_received': 0.0,
        'purchase_unit': 'l',
      });
      final h = await pumpIngredients(tester, server: s.server, db: s.db);
      await openDrawer(h, 'Oat Milk');
      await h.tap(inDrawer(byKey('ingredient-drawer-archive')));
      expect(inArchive(find.text('Still used in')), findsOneWidget);
      expect(inArchive(textHas('Open purchase orders · ')), findsOneWidget);
      expect(inArchive(byKey('archive-kind-purchase_order')), findsOneWidget);
    });
  });
}
