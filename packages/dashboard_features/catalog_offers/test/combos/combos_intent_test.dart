// Intent warming on Combos: a row, its pencil and New combo warm the
// editor's reads; a filter option and the pager warm that list page. After
// the mouse rests, the press asks the server nothing more.
import 'package:dashboard_catalog_offers/src/combo_editor/combo_editor_page.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder _option(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is DashOptionList),
  matching: find.text(label),
);

void main() {
  Finder editor() => find.byType(ComboEditorPage);
  for (final (kind, open, target, warms, opened)
      in <(String, String?, Finder Function(), String, Finder Function())>[
        ('a row', null, () => rowOf('Coffee & Cookie'), '/combos/{id}', editor),
        (
          'a row\'s pencil',
          null,
          () => rowButton('Coffee & Cookie', 'Edit'),
          '/combos/{id}',
          editor,
        ),
        (
          'New combo',
          null,
          () => pageButton('New combo'),
          '/menu-items',
          editor,
        ),
        (
          'a Status option',
          'Status',
          () => _option('Active'),
          combosApi,
          () => find.bySemanticsLabel('Status: Active'),
        ),
        (
          'Next',
          null,
          () => inPage(find.bySemanticsLabel('Next')),
          combosApi,
          () => pageText('Page 2 of 2'),
        ),
      ]) {
    testWidgets('intent: resting on $kind warms its read; the press asks '
        'nothing more', (tester) async {
      final s = combosServer();
      addCombos(s.db, 30);
      final h = await pumpCombos(tester, seeded: s);
      if (open != null) await h.tap(filterSelect(open));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      int asked() => h.server.calls.where((c) => c.method == 'GET').length;
      // Older than 30 s: a press adding a reader would refetch.
      h.db!.clock.advance(const Duration(seconds: 31));
      final f = target();
      await tester.ensureVisible(f.first);
      await h.settle();
      final before = callsTo(h, warms).length;
      await mouse.moveTo(tester.getCenter(f.first));
      await tester.pump(const Duration(milliseconds: 90));
      await h.settle();
      expect(callsTo(h, warms), hasLength(before + 1), reason: 'warmed');
      final warmed = asked();
      await h.tap(f.first);
      expect(opened(), findsWidgets);
      expect(asked(), warmed);
    });
  }
}
