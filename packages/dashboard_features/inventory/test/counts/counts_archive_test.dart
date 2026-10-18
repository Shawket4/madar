// Archived ingredients in Stock counts: the start dialog's "Specific
// ingredients" picker and the editor's "Add item" never offer one, and an
// archived ingredient still on an open count's sheet carries the badge.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('the start dialog does not offer an archived ingredient', (
    tester,
  ) async {
    final s = countsServer();
    s.db[InvTables.ingredients].update(InvIds.ingredient('cocoa'), {
      'archived_at': '2026-10-01T09:00:00Z',
    });
    final h = await pumpCounts(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    await h.tap(inPage(byKey('counts-start')));
    await pick(h, inScope(byKey('count-scope')), 'Specific ingredients');
    final labels = tester
        .widget<DashSelect<String>>(inScope(byKey('count-scope-add')))
        .options
        .map((o) => o.label);
    expect(labels, contains('Oat Milk'));
    expect(labels, isNot(contains('Cocoa Powder')));
    expect(labels, isNot(contains('Soy Milk')));
  });

  testWidgets('"Add item" skips archived ones; an archived row on the sheet '
      'shows the badge', (tester) async {
    final s = countsServer();
    final st = s.db[InvTables.stocktakes].find(openNewCairo)!;
    st['scope'] = {'kind': 'category', 'category_id': InvIds.category('milk')};
    s.db[InvTables.stocktakeItems].removeWhere(
      (i) =>
          i['stocktake_id'] == openNewCairo &&
          i['category_id'] != InvIds.category('milk'),
    );
    // Oat Milk is on the sheet and archived since; Cocoa is archived too.
    for (final k in ['oat', 'cocoa']) {
      s.db[InvTables.ingredients].update(InvIds.ingredient(k), {
        'archived_at': '2026-10-01T09:00:00Z',
      });
    }
    final h = await pumpCounts(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.newCairo,
    );
    await waitAutosave(h);
    final labels = tester
        .widget<DashSelect<String>>(inEditor(byKey('count-add')))
        .options
        .map((o) => o.label);
    expect(labels, contains('Sugar'));
    expect(labels, isNot(contains('Cocoa Powder')));
    expect(labels, isNot(contains('Soy Milk')));
    expect(inRow('oat', byKey('archived-badge')), findsOneWidget);
    expect(inRow('almond', byKey('archived-badge')), findsNothing);
  });
}
