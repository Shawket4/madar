// Typing into the studio's recipe grid a key at a time (the web's e4170ce).
// Every key rebuilds the grid's rows from the new sizes; the box being typed
// in must keep its value and its focus, also when the edit moves its row
// (rows follow the first size that carries them).
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/typing.dart';
import 'support.dart';

const String _milk = 'Full cream milk';
const String _pistachio = 'Pistachio paste';

Finder _cell(DashHarness h, String ingredient, String size) =>
    studioLabel(_label(h, ingredient, size));

String _label(DashHarness h, String ingredient, String size) => h.t(
  'modeling.grid.cellAria',
  args: {'ingredient': ingredient, 'size': size},
);

void main() {
  testWidgets('typing "18" a key at a time keeps the value and the focus', (
    tester,
  ) async {
    final h = await pumpStudio(tester, key: 'pistachio_latte');
    final typing = await TypingSession.start(
      h,
      _cell(h, _pistachio, 'Regular'),
    );
    // The box selects its 15 on focus: the first key replaces it.
    await typing.type('18');
    expect(typing.text, '18');
    await typing.clear();
    typing.expectFocusHeld();
    await typing.type('18');
    expect(typing.text, '18');
    expect(fieldText(tester, _cell(h, _milk, 'Regular')), '170');
    expect(fieldText(tester, _cell(h, _pistachio, 'Large')), '20');
  });

  testWidgets('an edit that moves the row up keeps typing in that row', (
    tester,
  ) async {
    // Regular has no lines: the rows come from Large (milk, then pistachio).
    // The first key in pistachio's Regular cell gives Regular its first
    // line, so pistachio becomes the first row.
    final s = studioServer();
    final regular = MenuSeedIds.size('pistachio_latte', 'Regular');
    s.db[MenuTables.recipeLines].removeWhere((r) => r['size_id'] == regular);
    final h = await pumpStudio(tester, key: 'pistachio_latte', seeded: s);
    final typing = await TypingSession.start(
      h,
      _cell(h, _pistachio, 'Regular'),
    );
    await typing.type('18');
    expect(typing.text, '18');
    expect(typing.focusedLabel, _label(h, _pistachio, 'Regular'));
    expect(fieldText(tester, _cell(h, _milk, 'Regular')), '');
    expect(fieldText(tester, _cell(h, _milk, 'Large')), '230');
    expect(fieldText(tester, _cell(h, _pistachio, 'Large')), '20');
    // Enter moves down a row from where the person is.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await h.settle(rounds: 2);
    expect(typing.focusedLabel, _label(h, _milk, 'Regular'));
  });
}
