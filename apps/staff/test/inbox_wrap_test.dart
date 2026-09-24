// E2E posnotif L-09: the inbox is the only place a notification can be read
// again, so a long line must show in full — not "The pay line for Omar
// Khaled was dec…", where approved and declined look the same.
import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

Future<void> _loadFonts() async {
  const cuts = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  for (final family in [MadarType.fontFamily, MadarType.monoFamily]) {
    final loader = FontLoader('packages/${MadarType.fontPackage}/$family');
    for (final cut in cuts) {
      final file = File(
        '../../packages/design_system/assets/fonts/$family-$cut.ttf',
      );
      if (file.existsSync()) {
        loader.addFont(file.readAsBytes().then(ByteData.sublistView));
      }
    }
    await loader.load();
  }
}

void main() {
  useCoreWords();
  setUpAll(() async {
    await _loadFonts();
    await initializeDateFormatting();
  });

  const lines = {
    'en': "Youssef Tarek is covering Karim Mostafa's shift — confirm to pay it",
    'ar': 'Youssef Tarek بيغطي وردية Karim Mostafa — أكّد عشان تتدفع',
  };
  for (final lang in ['en', 'ar']) {
    testWidgets('a long notice shows in full in the inbox · $lang', (t) async {
      final long = lines[lang]!;
      await pumpApp(
        t,
        lang: lang,
        who: 'e1',
        core: (c) => c.edit = (v) {
          (v['notices'] as List<dynamic>).insert(0, {
            'id': 'n-long',
            'at': '2026-09-24T15:52:00+03:00',
            'read': false,
            'text': long,
          });
        },
      );
      await t.tap(find.byTooltip(tr('staff.inbox')).first);
      await frames(t, 30);
      expect(find.text(long), findsOneWidget);
      final p = t.renderObject<RenderParagraph>(find.text(long));
      expect(p.didExceedMaxLines, isFalse, reason: 'the inbox cut the notice');
      expect(t.takeException(), isNull);
      final nav = Navigator.of(t.element(find.byType(MadarShellScaffold)));
      if (nav.canPop()) nav.pop();
      await frames(t);
      await finish(t);
    });
  }
}
