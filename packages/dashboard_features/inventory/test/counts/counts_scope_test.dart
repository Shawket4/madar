// "What do you want to count?" — the scope dialog: its reads, the three
// scopes, the pickers, starting a count and the refusals (INV-CNT-018…023,
// -061, -062).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder get _start => inScope(byKey('count-scope-start'));

bool _enabled(WidgetTester tester) =>
    tester.widget<DashButton>(_start).onPressed != null;

Future<void> _scope(DashHarness h, String label) =>
    pick(h, inScope(byKey('count-scope')), label);

void main() {
  testWidgets('INV-CNT-018/019 title, hint, Whole branch by default; the '
      'categories and the catalog are read only while it is open', (
    tester,
  ) async {
    final h = await pumpCounts(tester, branch: SeedIds.zamalek);
    expect(h.server.callsTo(categoriesRoute), isEmpty);
    expect(h.server.callsTo(catalogRoute), isEmpty);
    await h.tap(inPage(byKey('counts-start')));
    expect(inScope(find.text('What do you want to count?')), findsOneWidget);
    expect(
      inScope(
        find.text(
          'A whole-branch count lists every ingredient in your catalog. A '
          'targeted count is faster and leaves everything else untouched.',
        ),
      ),
      findsOneWidget,
    );
    expect(h.server.callsTo(categoriesRoute), hasLength(1));
    expect(h.server.callsTo(catalogRoute), hasLength(1));
    final select = tester.widget<DashSelect<Object?>>(
      inScope(byKey('count-scope')),
    );
    expect(
      [for (final o in select.options) o.label],
      [
        'Whole branch — every ingredient',
        'One category',
        'Specific ingredients',
      ],
    );
    expect(
      inScope(find.text('Whole branch — every ingredient')),
      findsOneWidget,
    );
    expect(_enabled(tester), isTrue);
    // Cancel closes it.
    await h.tap(inScope(find.text('Cancel')));
    expect(scopeDialog, findsNothing);
  });

  testWidgets('INV-CNT-020/022 One category: a category list with counts; '
      'Start waits for a pick; the body names the category', (tester) async {
    final h = await pumpCounts(tester, branch: SeedIds.zamalek);
    await h.tap(inPage(byKey('counts-start')));
    await _scope(h, 'One category');
    expect(inScope(find.text('Category')), findsOneWidget);
    expect(_enabled(tester), isFalse);
    final select = tester.widget<DashSelect<String>>(
      inScope(byKey('count-scope-category')),
    );
    expect(select.options.map((o) => o.label), [
      'General (1)',
      'Coffee Beans (4)',
      'Milk (5)',
      'Dairy & Eggs (3)',
      'Syrups & Sauces (4)',
      'Dry Goods (5)',
      'Bakery (2)',
      'Packaging (2)',
    ]);
    await pick(h, inScope(byKey('count-scope-category')), 'Milk (5)');
    expect(_enabled(tester), isTrue);
    await h.tap(_start);
    final post = h.server.callsTo(listRoute, method: 'POST').single;
    expect(post.path, '/stocktakes/branches/${SeedIds.zamalek}');
    expect(post.body, {
      'category_id': InvIds.category('milk'),
      'note': null,
      'org_ingredient_ids': null,
    });
    await h.expectToast('Started');
    expect(scopeDialog, findsNothing);
    // The list refetched: the new count is open in the editor.
    expect(editor, findsOneWidget);
    expect(inPage(find.text('Start a count')), findsNothing);
    expect(inEditor(find.text('Full Cream Milk')), findsOneWidget);
    await h.flushTimers();
  });

  testWidgets('INV-CNT-021/022 Specific ingredients: pick, list, remove; the '
      'picker hides what is chosen and hints the category', (tester) async {
    final h = await pumpCounts(tester, branch: SeedIds.zamalek);
    await h.tap(inPage(byKey('counts-start')));
    await _scope(h, 'Specific ingredients');
    expect(_enabled(tester), isFalse);
    DashSelect<String> picker() =>
        tester.widget<DashSelect<String>>(inScope(byKey('count-scope-add')));
    expect(picker().placeholder, 'Add an item…');
    expect(picker().searchable, isTrue);
    final oatOption = picker().options.firstWhere((o) => o.label == 'Oat Milk');
    expect(oatOption.hint, 'Milk');
    await pickSearch(h, inScope(byKey('count-scope-add')), 'Oat Milk');
    await pickSearch(h, inScope(byKey('count-scope-add')), 'Sugar');
    await pickSearch(h, inScope(byKey('count-scope-add')), 'Cup Lid');
    expect(
      picker().options.map((o) => o.label),
      isNot(anyOf(contains('Oat Milk'), contains('Sugar'))),
    );
    final rows = inScope(byKey('count-scope-items'));
    expect(
      find.descendant(of: rows, matching: find.byType(DashIconButton)),
      findsNWidgets(3),
    );
    // ✕ removes Sugar.
    await h.tap(
      find.descendant(
        of: inScope(byKey('count-scope-item-${InvIds.ingredient('sugar')}')),
        matching: find.byType(DashIconButton),
      ),
    );
    expect(inScope(find.text('Sugar')), findsNothing);
    expect(picker().options.map((o) => o.label), contains('Sugar'));
    expect(_enabled(tester), isTrue);
    await h.tap(_start);
    expect(lastBody(h, listRoute, 'POST'), {
      'category_id': null,
      'note': null,
      'org_ingredient_ids': [
        InvIds.ingredient('oat'),
        InvIds.ingredient('cup-lid'),
      ],
    });
    await h.expectToast('Started');
    expect(inEditor(find.text('Oat Milk')), findsOneWidget);
    expect(inEditor(find.text('Cup Lid')), findsOneWidget);
    expect(inEditor(find.text('Sugar')), findsNothing);
    await h.flushTimers();
  });

  testWidgets('INV-CNT-022/062 Whole branch: the body has no scope; the '
      'toast says "Started"; a spinner while it starts', (tester) async {
    final s = countsServer();
    final gate = s.server.hold('POST', listRoute);
    final h = await pumpCounts(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.heliopolis,
    );
    await h.tap(inPage(byKey('counts-first-run')));
    await h.tap(_start);
    expect(tester.widget<DashButton>(_start).loading, isTrue);
    gate.release();
    await h.settle();
    expect(lastBody(h, listRoute, 'POST'), {
      'category_id': null,
      'note': null,
      'org_ingredient_ids': null,
    });
    await h.expectToast('Started');
    expect(inPage(byKey('counts-first-run-card')), findsNothing);
    expect(editor, findsOneWidget);
    await h.flushTimers();
  });

  testWidgets('INV-CNT-023 an open count elsewhere: the server\'s 409 is the '
      'toast and the dialog stays', (tester) async {
    final s = countsServer();
    final h = await pumpCounts(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    await h.tap(inPage(byKey('counts-start')));
    // Another device opened one meanwhile.
    s.db[InvTables.stocktakes].insert({
      'id': mockUuid('stocktake:elsewhere'),
      'org_id': SeedIds.sabahOrg,
      'branch_id': SeedIds.zamalek,
      'status': 'in_progress',
      'scope': {'kind': 'full'},
      'started_at': s.db.nowIso,
      'started_by': SeedIds.user('karim'),
      'started_by_name': 'Karim Adel',
    });
    await h.tap(_start);
    final words = h.refusalWords(
      MockResponse.conflict(
        'An open stocktake already exists for this branch. Finalize or '
        'cancel it first.',
      ),
    );
    await h.expectToast(words);
    expect(scopeDialog, findsOneWidget);
    expect(tester.widget<DashButton>(_start).loading, isFalse);
  });

  testWidgets('INV-CNT-059 a refusal (no inventory.counts.create) is the '
      'server\'s words', (tester) async {
    final s = countsServer();
    final denied = MockResponse.denied('inventory.counts.create');
    s.server.fail('POST', listRoute, denied);
    final h = await pumpCounts(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    await h.tap(inPage(byKey('counts-start')));
    await h.tap(_start);
    await h.expectToast(h.refusalWords(denied));
    expect(scopeDialog, findsOneWidget);
  });

  testWidgets('INV-CNT-061 opening it again starts over', (tester) async {
    final h = await pumpCounts(tester, branch: SeedIds.zamalek);
    await h.tap(inPage(byKey('counts-start')));
    await _scope(h, 'Specific ingredients');
    await pickSearch(h, inScope(byKey('count-scope-add')), 'Oat Milk');
    await h.tap(inScope(find.text('Cancel')));
    await h.tap(inPage(byKey('counts-start')));
    expect(
      inScope(find.text('Whole branch — every ingredient')),
      findsOneWidget,
    );
    expect(inScope(byKey('count-scope-add')), findsNothing);
    await _scope(h, 'Specific ingredients');
    expect(inScope(byKey('count-scope-items')), findsNothing);
    // Still read once: the cache serves the second opening.
    expect(h.server.callsTo(catalogRoute), hasLength(1));
  });

  testWidgets('INV-CNT-057 phone: the dialog is full screen and starts a '
      'count', (tester) async {
    final h = await pumpCounts(
      tester,
      branch: SeedIds.zamalek,
      size: DashSize.phone,
    );
    await h.tap(inPage(byKey('counts-start')));
    expect(scopeDialog, findsOneWidget);
    expect(tester.getSize(scopeDialog).width, closeTo(390, 1));
    await _scope(h, 'One category');
    await pick(h, inScope(byKey('count-scope-category')), 'Bakery (2)');
    await h.tap(_start);
    await h.expectToast('Started');
    expect(editor, findsOneWidget);
    await h.flushTimers();
  });
}
