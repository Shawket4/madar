// Stock counts' mock backend (`lib/src/mock/counts_mock.dart`) behaves like
// MadarRust's stocktakes handlers: capabilities, branch scoping, the scope
// validation, live book stock while open, the autosave upsert (found items,
// one transaction), finalize's guard and ledger postings, cancel, and the
// variance report's figures against hand-computed ones.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Matcher refused(int status, String words) => throwsA(
  isA<ApiException>()
      .having((e) => e.status, 'status', status)
      .having((e) => e.message, 'message', contains(words)),
);

({DashboardApi api, MockDb db}) backend([Persona p = Persona.owner]) {
  final s = countsServer(persona: p);
  return (api: DashboardApi(s.server), db: s.db);
}

String ing(String key) => InvIds.ingredient(key);

ItemCountInput line(String key, double qty, [String? reason]) => ItemCountInput(
  orgIngredientId: ing(key),
  countedQty: qty,
  varianceReason: reason,
);

void main() {
  group('GET /stocktakes/{id}', () {
    test(
      'the open count: live book stock, category order, threshold',
      () async {
        final b = backend();
        final st = await b.api.stocktakes.getStocktake(id: openNewCairo);
        expect(st.status, 'in_progress');
        expect(st.varianceThresholdPct, invVarianceThresholdPct);
        expect(st.items, hasLength(25));
        // Book = the branch's on hand right now, not the opening snapshot.
        final oat = st.items.firstWhere((i) => i.orgIngredientId == ing('oat'));
        final rec = stockRow(b.db, SeedIds.newCairo, 'oat')!;
        expect(oat.bookQty, rec['on_hand']);
        expect(oat.variance, oat.countedQty! - oat.bookQty);
        rec['on_hand'] = 6000.0;
        final again = await b.api.stocktakes.getStocktake(id: openNewCairo);
        final oat2 = again.items.firstWhere(
          (i) => i.orgIngredientId == ing('oat'),
        );
        expect(oat2.bookQty, 6000);
        expect(oat2.variance, oat2.countedQty! - 6000);
        // By category sort order, then name.
        final cats = [for (final c in b.db[InvTables.categories].rows) c];
        int order(String id) =>
            cats.firstWhere((c) => c['id'] == id)['sort_order']! as int;
        for (var i = 1; i < st.items.length; i++) {
          final a = st.items[i - 1], c = st.items[i];
          final o = order(a.categoryId).compareTo(order(c.categoryId));
          expect(o <= 0, isTrue);
          if (o == 0 && a.categoryId == c.categoryId) {
            expect(a.ingredientName.compareTo(c.ingredientName) < 0, isTrue);
          }
        }
        // Never stocked here: new.
        expect(
          st.items
              .firstWhere((i) => i.orgIngredientId == ing('hibiscus'))
              .isNew,
          isTrue,
        );
      },
    );

    test('a closed count keeps its frozen book stock', () async {
      final b = backend();
      final st = await b.api.stocktakes.getStocktake(id: zamalekMilk);
      final full = st.items.firstWhere(
        (i) => i.orgIngredientId == ing('full-cream'),
      );
      expect(
        full.bookQty,
        itemRow(b.db, zamalekMilk, 'full-cream')['book_qty'],
      );
    });

    test('404, the capability, the branch', () async {
      await expectLater(
        backend().api.stocktakes.getStocktake(id: mockUuid('nope')),
        refused(404, 'Stocktake not found'),
      );
      await expectLater(
        backend(Persona.limited).api.stocktakes.getStocktake(id: maadiSpot),
        refused(403, '(inventory.counts.read)'),
      );
      await expectLater(
        backend(Persona.manager).api.stocktakes.getStocktake(id: maadiSpot),
        refused(403, 'Not assigned to this branch'),
      );
      final mine = await backend(
        Persona.manager,
      ).api.stocktakes.getStocktake(id: zamalekMilk);
      expect(mine.id, zamalekMilk);
    });
  });

  group('POST /stocktakes/branches/{branch_id}', () {
    test('whole branch: every catalog ingredient, stocked or not', () async {
      final b = backend();
      final st = await b.api.stocktakes.createStocktake(
        branchId: SeedIds.zamalek,
        body: const CreateStocktakeRequest(
          explicitNulls: {'note', 'category_id', 'org_ingredient_ids'},
        ),
      );
      expect(st.status, 'in_progress');
      expect(st.scope, {'kind': 'full'});
      expect(st.startedByName, 'Nour El-Sayed');
      final catalog = b.db[InvTables.ingredients].where(
        (i) => i['org_id'] == SeedIds.sabahOrg,
      );
      expect(st.items, hasLength(catalog.length));
      for (final it in st.items) {
        final r = b.db[InvTables.branchStock].firstWhere(
          (s) =>
              s['branch_id'] == SeedIds.zamalek &&
              s['org_ingredient_id'] == it.orgIngredientId,
        );
        expect(it.isNew, r == null);
        expect(it.openingQty, (r?['on_hand'] as num?) ?? 0);
        expect(it.bookQty, it.openingQty);
        expect(it.countedQty, isNull);
      }
      // Listed next, with its progress.
      final list = await b.api.stocktakes.listStocktakes(
        branchId: SeedIds.zamalek,
      );
      expect(list.first.id, st.id);
      expect(list.first.countedItems, 0);
      expect(list.first.totalItems, catalog.length);
    });

    test('one category; chosen items', () async {
      final b = backend();
      final milk = await b.api.stocktakes.createStocktake(
        branchId: SeedIds.zamalek,
        body: CreateStocktakeRequest(categoryId: InvIds.category('milk')),
      );
      expect(milk.scope['kind'], 'category');
      expect(milk.items.map((i) => i.categoryName).toSet(), {'Milk'});
      await b.api.stocktakes.cancelStocktake(id: milk.id);
      final two = await b.api.stocktakes.createStocktake(
        branchId: SeedIds.zamalek,
        body: CreateStocktakeRequest(
          orgIngredientIds: [ing('oat'), ing('sugar')],
        ),
      );
      expect(two.scope, {
        'kind': 'items',
        'org_ingredient_ids': [ing('oat'), ing('sugar')],
      });
      expect(two.items.map((i) => i.ingredientName).toSet(), {
        'Oat Milk',
        'Sugar',
      });
    });

    test('refusals: both scopes, empty list, unknown ids, an open count, '
        'the capability, another branch', () async {
      final b = backend();
      Future<StocktakeFull> make(String branch, CreateStocktakeRequest body) =>
          b.api.stocktakes.createStocktake(branchId: branch, body: body);
      await expectLater(
        make(
          SeedIds.zamalek,
          CreateStocktakeRequest(
            categoryId: InvIds.category('milk'),
            orgIngredientIds: [ing('oat')],
          ),
        ),
        refused(400, 'Pass either category_id or org_ingredient_ids'),
      );
      await expectLater(
        make(
          SeedIds.zamalek,
          const CreateStocktakeRequest(orgIngredientIds: []),
        ),
        refused(400, 'org_ingredient_ids cannot be empty'),
      );
      await expectLater(
        make(
          SeedIds.zamalek,
          CreateStocktakeRequest(categoryId: mockUuid('nope')),
        ),
        refused(400, 'Category not found in this organization'),
      );
      await expectLater(
        make(
          SeedIds.zamalek,
          CreateStocktakeRequest(orgIngredientIds: [mockUuid('nope')]),
        ),
        refused(400, "not in this organization's catalog"),
      );
      await expectLater(
        make(SeedIds.newCairo, const CreateStocktakeRequest()),
        refused(409, 'An open stocktake already exists for this branch'),
      );
      await expectLater(
        backend(Persona.limited).api.stocktakes.createStocktake(
          branchId: SeedIds.maadi,
          body: const CreateStocktakeRequest(),
        ),
        refused(403, '(inventory.counts.create)'),
      );
      await expectLater(
        backend(Persona.manager).api.stocktakes.createStocktake(
          branchId: SeedIds.maadi,
          body: const CreateStocktakeRequest(),
        ),
        refused(403, 'Not assigned to this branch'),
      );
      expect(
        b.db[InvTables.stocktakes].where(
          (s) =>
              s['branch_id'] == SeedIds.zamalek && s['status'] == 'in_progress',
        ),
        isEmpty,
      );
    });
  });

  group('PUT /stocktakes/{id}/items', () {
    test('saves figures and reasons; a found item joins the count', () async {
      final b = backend();
      final st = await b.api.stocktakes.createStocktake(
        branchId: SeedIds.zamalek,
        body: CreateStocktakeRequest(categoryId: InvIds.category('bakery')),
      );
      final saved = await b.api.stocktakes.upsertItems(
        id: st.id,
        body: UpsertItemsRequest(
          items: [line('croissant', 10, 'theft'), line('sugar', 500)],
        ),
      );
      final croissant = saved.items.firstWhere(
        (i) => i.orgIngredientId == ing('croissant'),
      );
      expect(croissant.countedQty, 10);
      expect(croissant.varianceReason, 'theft');
      final sugar = saved.items.firstWhere(
        (i) => i.orgIngredientId == ing('sugar'),
      );
      expect(sugar.countedQty, 500);
      expect(
        sugar.openingQty,
        stockRow(b.db, SeedIds.zamalek, 'sugar')!['on_hand'],
      );
      expect(saved.items, hasLength(st.items.length + 1));
      // A reason sent as null clears it.
      final cleared = await b.api.stocktakes.upsertItems(
        id: st.id,
        body: UpsertItemsRequest(
          items: [
            ItemCountInput(
              orgIngredientId: ing('croissant'),
              countedQty: 11,
              explicitNulls: const {'variance_reason'},
            ),
          ],
        ),
      );
      expect(
        cleared.items
            .firstWhere((i) => i.orgIngredientId == ing('croissant'))
            .varianceReason,
        isNull,
      );
    });

    test('one bad line refuses the whole save', () async {
      final b = backend();
      final before = itemRow(b.db, openNewCairo, 'sugar')['counted_qty'];
      await expectLater(
        b.api.stocktakes.upsertItems(
          id: openNewCairo,
          body: UpsertItemsRequest(items: [line('sugar', 1), line('oat', -2)]),
        ),
        refused(400, 'counted_qty cannot be negative'),
      );
      expect(itemRow(b.db, openNewCairo, 'sugar')['counted_qty'], before);
      await expectLater(
        b.api.stocktakes.upsertItems(
          id: openNewCairo,
          body: UpsertItemsRequest(items: [line('sugar', 1, 'lost')]),
        ),
        refused(400, "Invalid variance reason 'lost'"),
      );
      await expectLater(
        b.api.stocktakes.upsertItems(
          id: openNewCairo,
          body: UpsertItemsRequest(
            items: [
              ItemCountInput(orgIngredientId: mockUuid('x'), countedQty: 1),
            ],
          ),
        ),
        refused(400, "Ingredient not found in this organization's catalog"),
      );
    });

    test('a closed count, the capability', () async {
      final b = backend();
      await expectLater(
        b.api.stocktakes.upsertItems(
          id: zamalekMilk,
          body: UpsertItemsRequest(items: [line('oat', 1)]),
        ),
        refused(
          409,
          'Cannot edit counts on a finalized or cancelled stocktake',
        ),
      );
      await expectLater(
        backend(Persona.limited).api.stocktakes.upsertItems(
          id: maadiSpot,
          body: UpsertItemsRequest(items: [line('oat', 1)]),
        ),
        refused(403, '(inventory.counts.edit)'),
      );
    });
  });

  group('POST /stocktakes/{id}/finalize', () {
    test('a flagged row with no reason is refused, by name', () async {
      final b = backend();
      await expectLater(
        b.api.stocktakes.finalizeStocktake(id: openNewCairo),
        refused(
          409,
          'These items have a large difference and need a reason before '
          'finalizing: Croissant Dough',
        ),
      );
      expect(
        b.db[InvTables.stocktakes].find(openNewCairo)!['status'],
        'in_progress',
      );
    });

    test('posts one stock_count per difference; book frozen; counted '
        'dates stamped; then it is closed', () async {
      final b = backend();
      await b.api.stocktakes.upsertItems(
        id: openNewCairo,
        body: UpsertItemsRequest(items: [line('croissant', 37, 'spoilage')]),
      );
      final book = {
        for (final k in ['croissant', 'oat', 'sugar', 'house-blend'])
          k: (stockRow(b.db, SeedIds.newCairo, k)!['on_hand']! as num)
              .toDouble(),
      };
      final movesBefore = b.db[InvTables.movements].length;
      final done = await b.api.stocktakes.finalizeStocktake(id: openNewCairo);
      expect(done.status, 'finalized');
      expect(done.finalizedAt!.isAtSameMomentAs(b.db.clock.now), isTrue);
      // Croissant 37 (book 48), House Blend 2100, Oat 6390, Cup Lid 639:
      // four differences; Sugar, Full Cream, Skimmed, Paper Cup, Vanilla
      // Syrup were counted at book.
      final moves = b.db[InvTables.movements].rows.sublist(movesBefore);
      expect(moves, hasLength(4));
      final croissant = moves.firstWhere(
        (m) => m['org_ingredient_id'] == ing('croissant'),
      );
      expect(croissant['movement_type'], 'stock_count');
      expect(croissant['quantity'], 37 - book['croissant']!);
      expect(croissant['reason'], 'spoilage');
      expect(croissant['source_id'], openNewCairo);
      expect(stockRow(b.db, SeedIds.newCairo, 'croissant')!['on_hand'], 37);
      expect(stockRow(b.db, SeedIds.newCairo, 'oat')!['on_hand'], 6390);
      expect(
        stockRow(b.db, SeedIds.newCairo, 'sugar')!['last_counted_at'],
        b.db.nowIso,
      );
      expect(
        itemRow(b.db, openNewCairo, 'croissant')['book_qty'],
        book['croissant'],
      );
      // Book stays frozen after the ledger moves on.
      stockRow(b.db, SeedIds.newCairo, 'croissant')!['on_hand'] = 5.0;
      final later = await b.api.stocktakes.getStocktake(id: openNewCairo);
      expect(
        later.items
            .firstWhere((i) => i.orgIngredientId == ing('croissant'))
            .bookQty,
        book['croissant'],
      );
      await expectLater(
        b.api.stocktakes.finalizeStocktake(id: openNewCairo),
        refused(409, 'Stocktake is not open'),
      );
    });

    test('nothing counted: finalizes with no posting', () async {
      final b = backend();
      final st = await b.api.stocktakes.createStocktake(
        branchId: SeedIds.heliopolis,
        body: const CreateStocktakeRequest(),
      );
      final before = b.db[InvTables.movements].length;
      final done = await b.api.stocktakes.finalizeStocktake(id: st.id);
      expect(done.status, 'finalized');
      expect(b.db[InvTables.movements].length, before);
    });

    test('a counted ingredient new here starts its stock row', () async {
      final b = backend();
      final st = await b.api.stocktakes.createStocktake(
        branchId: SeedIds.heliopolis,
        body: CreateStocktakeRequest(orgIngredientIds: [ing('oat')]),
      );
      expect(st.items.single.isNew, isTrue);
      await b.api.stocktakes.upsertItems(
        id: st.id,
        body: UpsertItemsRequest(items: [line('oat', 800, 'other')]),
      );
      await b.api.stocktakes.finalizeStocktake(id: st.id);
      final rec = stockRow(b.db, SeedIds.heliopolis, 'oat')!;
      expect(rec['on_hand'], 800);
      expect(rec['last_counted_at'], b.db.nowIso);
    });
  });

  group('POST /stocktakes/{id}/cancel', () {
    test('cancels an open count once', () async {
      final b = backend();
      final st = await b.api.stocktakes.cancelStocktake(id: openNewCairo);
      expect(st.status, 'cancelled');
      await expectLater(
        b.api.stocktakes.cancelStocktake(id: openNewCairo),
        refused(409, 'Only an open stocktake can be cancelled'),
      );
      await expectLater(
        backend(Persona.limited).api.stocktakes.cancelStocktake(id: maadiSpot),
        refused(403, '(inventory.counts.edit)'),
      );
    });
  });

  group('GET /stocktakes/{id}/variance-report', () {
    test('figures from the raw rows: by name, valued, totals', () async {
      final b = backend();
      for (final id in [
        zamalekFull,
        zamalekMilk,
        maadiSpot,
        zamalekCancelled,
      ]) {
        final r = await b.api.stocktakes.varianceReport(id: id);
        final raw = b.db[InvTables.stocktakeItems].where(
          (i) => i['stocktake_id'] == id,
        );
        var shrink = 0, over = 0, unknown = 0;
        for (final it in raw) {
          final counted = it['counted_qty'] as num?;
          if (counted == null) continue;
          final cost = it['unit_cost'] as num?;
          if (cost == null) {
            unknown++;
            continue;
          }
          final v = (counted - (it['book_qty']! as num)) * cost;
          final rounded = v < 0 ? -((-v) + 0.5).floor() : (v + 0.5).floor();
          if (rounded < 0) {
            shrink += -rounded;
          } else {
            over += rounded;
          }
        }
        expect(r.totalShrinkageValue, shrink, reason: id);
        expect(r.totalOverageValue, over, reason: id);
        expect(r.netVarianceValue, over - shrink, reason: id);
        expect(r.unknownCostCount, unknown, reason: id);
        final names = [for (final row in r.rows) row.ingredientName];
        expect(names, [...names]..sort(), reason: id);
      }
      // Zamalek's milk recount, by hand: Full Cream 72,610 vs 77,240 at 5
      // piastres = −23,150; Oat 3,140 vs 3,020 at 12 = +1,440.
      final milk = await b.api.stocktakes.varianceReport(id: zamalekMilk);
      expect(milk.totalShrinkageValue, 23150);
      expect(milk.totalOverageValue, 1440);
      expect(milk.netVarianceValue, -21710);
      final fullCream = milk.rows.firstWhere(
        (x) => x.ingredientName == 'Full Cream Milk',
      );
      expect(fullCream.isFlagged, isTrue);
      expect(fullCream.varianceReason, 'spoilage');
      expect(fullCream.varianceValue, -23150);
      // The full count has one counted row with no cost (Dried Hibiscus).
      final full = await b.api.stocktakes.varianceReport(id: zamalekFull);
      expect(full.unknownCostCount, 1);
      expect(
        full.rows
            .firstWhere((x) => x.ingredientName == 'Dried Hibiscus')
            .varianceValue,
        isNull,
      );
      // A cancelled count's uncounted row: no figures, not flagged.
      final cancelled = await b.api.stocktakes.varianceReport(
        id: zamalekCancelled,
      );
      final muffin = cancelled.rows.firstWhere(
        (x) => x.ingredientName == 'Blueberry Muffin',
      );
      expect(muffin.countedQty, isNull);
      expect(muffin.variance, isNull);
      expect(muffin.isFlagged, isFalse);
    });

    test('the capability, the branch', () async {
      await expectLater(
        backend(Persona.limited).api.stocktakes.varianceReport(id: maadiSpot),
        refused(403, '(inventory.counts.read)'),
      );
      await expectLater(
        backend(Persona.manager).api.stocktakes.varianceReport(id: maadiSpot),
        refused(403, 'Not assigned to this branch'),
      );
    });
  });
}
