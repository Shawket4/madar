// E2E bug S4 (Omar, EN, Pixel 7): on the Shifts list, a shift marked
// "Changed" (SC-4) lost its times to the wide pill: "08:00 – 16:…". The
// change is still marked (a warning glyph that says "Changed" to a screen
// reader and on long-press), and the times stay whole on a phone, in
// Arabic and English.
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

void main() {
  useCoreWords();
  setUpAll(() async {
    await initializeDateFormatting();
    await loadFonts();
  });

  for (final lang in ['en', 'ar']) {
    testWidgets(
      'a changed shift keeps its times on a phone (390 wide) · $lang',
      (t) async {
        final semantics = t.ensureSemantics();
        await pumpApp(
          t,
          lang: lang,
          who: 'e1',
          tab: 2,
          size: const Size(390, 844),
        );
        await frames(t, 30);
        final changed = testContainer
            .read(dawamProvider)
            .shifts
            .where((s) => s.changed && s.emp != null)
            .toList();
        expect(changed, isNotEmpty, reason: 'the fixture has a changed shift');
        final meta = find.textContaining(' – ');
        expect(meta, findsWidgets);
        for (final e in meta.evaluate()) {
          final p = e.findRenderObject()! as RenderParagraph;
          expect(
            p.didExceedMaxLines,
            isFalse,
            reason: 'cut: ${p.text.toPlainText()}',
          );
        }
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(tr('staff.changed')))),
          findsWidgets,
          reason: 'the change is still marked',
        );
        semantics.dispose();
        await finish(t);
      },
    );
  }
}
