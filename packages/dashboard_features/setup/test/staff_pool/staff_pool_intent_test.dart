// Intent warming on Staff drinks: pointing at the items trigger warms the
// org menu the picker lists, so pressing it asks the server nothing more.
// Resting on the settings rail row warms the page's mount reads through the
// route's `prefetch:` (no `route-prefetch.ts` case on the web), only for a
// person with an org.settings cap. (Save and Revert are writes and warm
// nothing.)
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show routePrefetchesProvider;
import 'package:dashboard_setup/src/brand_appearance/settings_shell.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart' show pumpSetup;
import 'support.dart';

void main() {
  testWidgets('resting on the Staff drinks rail row warms the settings and '
      'the chips\' menu; the press asks nothing more', (tester) async {
    final m = splServer();
    final h = await pumpSetup(
      tester,
      path: '/settings/payment-methods',
      server: m.server,
      db: m.db,
    );
    List<MockCall> reads() => h.server.callsTo(splSettings, method: 'GET');
    expect(reads(), isEmpty);
    expect(h.server.callsTo(splMenu), isEmpty);

    final row = find.descendant(
      of: find.byType(SettingsShell),
      matching: find.text(h.t('nav.staffPool')),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(row.first));
    await h.settle();
    expect(reads(), hasLength(1), reason: 'warmed on rest');
    expect(h.server.callsTo(splMenu), hasLength(1), reason: 'chips named');

    await h.tap(row.first);
    expect(h.location.path, splPath);
    expect(reads(), hasLength(1), reason: 'served from the cache');
    expect(h.server.callsTo(splMenu), hasLength(1));
  });

  testWidgets('the prefetch warms nothing without an org.settings cap', (
    tester,
  ) async {
    final h = await pumpStaffPool(tester, persona: Persona.manager);
    final before = h.server.callsTo(splSettings).length;
    h.container.read(routePrefetchesProvider)[splPath]!(
      DashPrefetcher(h.container),
      h.container.read(currentScopeProvider),
    );
    await h.settle();
    expect(h.server.callsTo(splSettings), hasLength(before));
    expect(h.server.callsTo(splMenu), isEmpty);
  });

  testWidgets('the items trigger warms the menu; the press opens it from '
      'the cache', (tester) async {
    final m = splServer();
    // No items chosen: the menu is not needed to name chips, so only the
    // picker asks for it.
    savedRow(m.db, null)!['eligible_item_ids'] = <String>[];
    final h = await pumpStaffPool(tester, backend: m);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    expect(h.server.callsTo(splMenu), isEmpty);

    final trigger = find.byKey(const ValueKey('spl-items-trigger'));
    await mouse.moveTo(tester.getCenter(trigger));
    await h.settle();
    expect(h.server.callsTo(splMenu), hasLength(1), reason: 'warmed');
    expect(h.server.callsTo(splMenu).single.query['org_id'], [
      SeedIds.sabahOrg,
    ]);

    await h.tap(trigger);
    expect(inPicker(find.text(itemName('latte'))), findsOneWidget);
    expect(h.server.callsTo(splMenu), hasLength(1), reason: 'from the cache');
  });
}
