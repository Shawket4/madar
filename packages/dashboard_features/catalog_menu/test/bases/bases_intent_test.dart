// Intent warming and re-seeding on the bases and packaging pages: resting on
// a base's Edit warms the editor's usage read, so the press asks nothing
// more; an untouched editor follows a refresh, a touched one keeps its edits.
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _usage = '/recipe-bases/{id}/usage';

void main() {
  testWidgets('MENU-BAS-010 resting on Edit warms the base usage; the press '
      'asks the server nothing more', (tester) async {
    final h = await pumpMenu(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final edit = labelIn(rowOf(icedBase), h.t('common.edit'));
    expect(h.server.callsTo(_usage), isEmpty);

    await mouse.moveTo(tester.getCenter(edit));
    await h.settle();
    final warmed = h.server.callsTo(_usage, method: 'GET');
    expect(warmed, hasLength(1), reason: 'the editor read is warmed');
    expect(warmed.single.path, '/recipe-bases/$icedBase/usage');

    await h.tap(edit);
    expect(find.text('Affects 2 items / 4 sizes'), findsOneWidget);
    expect(
      h.server.callsTo(_usage, method: 'GET'),
      hasLength(1),
      reason: 'the editor opened from the cache',
    );
  });

  testWidgets('MENU-BAS-010 a refresh that lands re-seeds the untouched base '
      'editor, never a touched one', (tester) async {
    final s = menuServer();
    final h = await pumpMenu(tester, seeded: s);
    await h.tap(labelIn(rowOf(icedBase), h.t('common.edit')));
    String name() =>
        editable(tester, find.bySemanticsLabel('Name')).controller.text;
    Future<void> refresh(String name) async {
      s.db[MenuTables.bases].update(icedBase, {'name': name});
      h.container.read(realtimeBusProvider).invalidate(const ['/recipe-bases']);
      await h.settle();
    }

    await refresh('Iced prep');
    expect(name(), 'Iced prep');
    await h.enterText(find.bySemanticsLabel('Name'), 'Mine');
    await refresh('Iced later');
    expect(name(), 'Mine');
  });

  testWidgets('MENU-PKG-009 a refresh that lands re-seeds the untouched rule '
      'dialog, never a touched one', (tester) async {
    final s = menuServer();
    final h = await pumpMenu(tester, path: packagingPath, seeded: s);
    final id = MenuSeedIds.rule('hot_large');
    await h.tap(labelIn(rowOf(id), h.t('common.edit')));
    final field = find.bySemanticsLabel(h.t('common.name'));
    String name() => editable(tester, field).controller.text;
    Future<void> refresh(String name) async {
      s.db[MenuTables.rules].update(id, {'name': name});
      h.container.read(realtimeBusProvider).invalidate(const [
        '/packaging-rules',
      ]);
      await h.settle();
    }

    await refresh('Large hot cups');
    expect(name(), 'Large hot cups');
    await h.enterText(field, 'Mine');
    await refresh('Large later');
    expect(name(), 'Mine');
  });
}
