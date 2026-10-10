// The choice groups' screenshot matrix: the list at {phone, tablet, desktop}
// x {en light, ar dark}, scrolled through; the editor (new, a swap group, a
// per-size adds group, errors), the usage dialog and the delete confirm at
// desktop-en-light and phone-ar-light. Written only with FDASH_SHOTS set;
// the screens still render (and must not overflow) without.
import 'package:dashboard_catalog_menu/src/groups/group_editor_dialog.dart';
import 'package:dashboard_catalog_menu/src/groups/groups_page.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Shoots [scope]'s first scrollable top to bottom: `<name>-1`, `<name>-2`…
Future<void> shootScroll(DashHarness h, Finder scope, String name) async {
  final scroll = find
      .descendant(of: scope, matching: find.byType(Scrollable))
      .first;
  final position = h.tester.state<ScrollableState>(scroll).position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('groups/$name-$i');
    if (y >= position.maxScrollExtent || i == 6) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

const _modes = [('en', false), ('ar', true)];
const _states = [(DashSize.desktop, 'en'), (DashSize.phone, 'ar')];

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      testWidgets('default, ${size.name} $lang ${dark ? 'dark' : 'light'}', (
        tester,
      ) async {
        final h = await pumpGroups(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootScroll(h, find.byType(GroupsPage), 'default');
      });
    }
  }

  for (final (size, lang) in _states) {
    final tag = '${size.name} $lang';
    Future<DashHarness> open(WidgetTester tester, String path) =>
        pumpGroups(tester, path: path, size: size, locale: lang);

    testWidgets('editor, new, $tag', (tester) async {
      final h = await open(tester, '$groupsPath?edit=new');
      await shootScroll(h, find.byType(GroupEditorDialog), 'editor-new');
      await h.tap(
        find.descendant(
          of: find.byType(GroupEditorDialog),
          matching: find.widgetWithText(DashButton, h.t('common.save')),
        ),
      );
      await shootScroll(h, find.byType(GroupEditorDialog), 'editor-errors');
    });

    testWidgets('editor, a swap group, $tag', (tester) async {
      final h = await open(tester, '$groupsPath?edit=$milkId');
      await shootScroll(h, find.byType(GroupEditorDialog), 'editor-milk');
    });

    testWidgets('editor, per-size amounts, $tag', (tester) async {
      final h = await open(tester, '$groupsPath?edit=$toppingsId');
      await shootScroll(h, find.byType(GroupEditorDialog), 'editor-toppings');
    });

    testWidgets('editor, plain lines, $tag', (tester) async {
      final h = await open(tester, '$groupsPath?edit=$extrasId');
      await shootScroll(h, find.byType(GroupEditorDialog), 'editor-extras');
    });

    testWidgets('usage dialog, $tag', (tester) async {
      final h = await open(tester, groupsPath);
      await h.tap(textIn(rowOf(beansId), h.t('menu.groups.usedOn', count: 3)));
      await h.shot('groups/usage-dialog');
    });

    testWidgets('delete confirm, $tag', (tester) async {
      final h = await open(tester, groupsPath);
      await h.tap(labelIn(rowOf(servingId), h.t('common.delete')));
      await h.shot('groups/delete-confirm');
    });
  }
}
