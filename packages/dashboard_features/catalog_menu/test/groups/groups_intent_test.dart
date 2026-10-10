// Intent warming on Modifier groups: resting on a group's Edit, its
// "Used on" link, "New group" or the editor's "Manage" warms the reads the
// press makes, so the press asks the server nothing more. Also: a save
// refreshes the page's list even when the editor closed while it ran.
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dashboard_core/testing.dart';

import 'support.dart';

/// The editor's reads: catalog, categories, the active groups list and the
/// items the group is used on.
({int catalog, int categories, int active, int items}) _editorReads(
  DashHarness h,
) => (
  catalog: callsTo(h, 'GET', catalogT).length,
  categories: callsTo(h, 'GET', categoriesT).length,
  active: [
    for (final c in callsTo(h, 'GET', listT))
      if (c.query['include_inactive'] == null) c,
  ].length,
  items: callsTo(h, 'GET', itemT).length,
);

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

void main() {
  testWidgets('MENU-GRP-011 resting on Edit warms the editor reads; the press '
      'asks the server nothing more', (tester) async {
    final h = await pumpGroups(tester);
    final mouse = await _mouse(tester);
    final before = _editorReads(h);
    final edit = labelIn(rowOf(beansId), h.t('common.edit'));

    await mouse.moveTo(tester.getCenter(edit));
    await h.settle();
    final warm = _editorReads(h);
    expect(warm.catalog, before.catalog + 1);
    expect(warm.categories, before.categories + 1);
    expect(warm.active, before.active + 1);
    expect(warm.items, before.items + 3, reason: 'its three items');

    await h.tap(edit);
    expect(surface(h.t('menu.groups.editor.editTitle')), findsOneWidget);
    expect(_editorReads(h), warm, reason: 'the editor opened from the cache');

    // The editor's "Manage" warms the usage dialog's item list.
    final items = callsTo(h, 'GET', itemsT).length;
    final manage = find.text(h.t('menu.groups.manage'));
    await tester.ensureVisible(manage);
    await h.settle();
    await mouse.moveTo(tester.getCenter(manage));
    await h.settle();
    expect(callsTo(h, 'GET', itemsT), hasLength(items + 1));
    await h.tap(manage);
    expect(callsTo(h, 'GET', itemsT), hasLength(items + 1));
  });

  testWidgets('MENU-GRP-010 resting on "Used on" warms the item list; the '
      'press asks the server nothing more', (tester) async {
    final h = await pumpGroups(tester);
    final mouse = await _mouse(tester);
    final used = textIn(rowOf(beansId), h.t('menu.groups.usedOn', count: 3));
    final before = callsTo(h, 'GET', itemsT).length;

    await mouse.moveTo(tester.getCenter(used));
    await h.settle();
    expect(callsTo(h, 'GET', itemsT), hasLength(before + 1));
    await h.tap(used);
    expect(callsTo(h, 'GET', itemsT), hasLength(before + 1));
  });

  testWidgets('MENU-GRP-001 resting on "New group" warms the editor reads; '
      'the press asks the server nothing more', (tester) async {
    final h = await pumpGroups(tester);
    final mouse = await _mouse(tester);
    final before = _editorReads(h);
    final button = find.text(h.t('menu.groups.new'));

    await mouse.moveTo(tester.getCenter(button));
    await h.settle();
    final warm = _editorReads(h);
    expect(warm.catalog, before.catalog + 1);
    expect(warm.categories, before.categories + 1);
    expect(warm.active, before.active + 1);

    await h.tap(button);
    expect(surface(h.t('menu.groups.editor.newTitle')), findsOneWidget);
    expect(_editorReads(h), warm, reason: 'the editor opened from the cache');
  });

  testWidgets('MENU-GRP-017 a save refetches the list even when the editor '
      'closed while it ran (the web\'s onSaved)', (tester) async {
    final s = groupsServer();
    final h = await pumpGroups(tester, seeded: s);
    int listed() => [
      for (final c in callsTo(h, 'GET', listT))
        if (c.query['include_inactive']?.single == 'true') c,
    ].length;
    await h.tap(labelIn(rowOf(beansId), h.t('common.edit')));
    final gate = s.server.hold('PATCH', groupT);
    await h.tap(find.text(h.t('common.save')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(find.text(h.t('menu.groups.editor.editTitle')), findsNothing);
    final before = listed();
    gate.release();
    await h.settle();
    expect(listed(), greaterThan(before));
  });
}
