// Basira's screenshot matrix: the default state at every size in en/light
// and ar/dark, then each other state at desktop-en-light and phone-ar-light.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_reports/src/basira/basira_models.dart';
import 'package:dashboard_reports/src/basira/basira_page.dart';
import 'package:dashboard_reports/src/mock/basira_mock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const String _page = 'basira';

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpBasira(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await h.shot('$_page/default');
      });
    }
  }

  testWidgets('the slide-over rail, tablet en', (tester) async {
    final h = await pumpBasira(tester, size: DashSize.tablet);
    await h.tap(inPage(find.text(h.t('basira.showConversations'))));
    await h.shot('$_page/rail-sheet');
  });

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    final phone = size == DashSize.phone;

    Future<void> openRail(DashHarness h) async {
      if (phone) {
        await h.tap(inPage(find.text(h.t('basira.showConversations'))));
      }
    }

    testWidgets('loading, ${size.name} $lang', (tester) async {
      final s = basiraServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpBasira(
        tester,
        size: size,
        locale: lang,
        server: s.server,
        db: s.db,
      );
      final live = basiraMockOf(s.server).hold();
      await askByTyping(h, 'Top 3 products');
      live.push({
        'event': 'querying',
        'title': 'Top products',
        'dataset': 'sales_items',
      });
      await h.settle();
      await h.shot('$_page/working');
      await openRail(h);
      await h.shot('$_page/rail-loading');
      gate.release();
      await live.close();
      await h.settle();
    });

    testWidgets('states, ${size.name} $lang', (tester) async {
      final s = basiraServer();
      final h = await pumpBasira(
        tester,
        size: size,
        locale: lang,
        server: s.server,
        db: s.db,
      );
      final conv = mockOf(h).conversationsOf(SeedIds.owner).first;
      final title = ownDirection(conv['title']! as String);
      await openRail(h);
      if (phone) await h.shot('$_page/rail-sheet');
      // The ⋯ menu, rename and delete.
      Finder more() => find.descendant(
        of: find
            .ancestor(
              of: inRail(find.text(title)),
              matching: find.byType(Stack),
            )
            .first,
        matching: find.bySemanticsLabel(h.t('common.more')),
      );
      await h.tap(more());
      await h.shot('$_page/item-menu');
      await h.tapText(h.t('common.rename'));
      await h.shot('$_page/rename');
      await h.tapText(h.t('common.cancel'));
      await h.tap(more());
      await h.tapText(h.t('common.delete'));
      await h.shot('$_page/delete-confirm');
      await h.tapText(h.t('common.cancel'));
      // A stored conversation with its charts.
      await h.tap(inRail(find.text(title)));
      await h.shot('$_page/history');
      // A failure.
      mockOf(h).script([
        {'event': 'error', 'message': 'The model took too long. Try again.'},
      ]);
      await askByTyping(h, 'Top 3 products');
      await h.shot('$_page/failure');
      // Every viz the agent draws, and the query behind one.
      for (final (i, q) in [
        'What sold best last month?',
        'Show the daily revenue trend',
        'When are we busiest?',
        'How much did we take today?',
        'Payment mix this month',
        'How long is prep taking?',
        'List orders for today',
        'Revenue at our Alexandria branch',
        'Tell me something',
        'How much payroll did we pay?',
      ].indexed) {
        await askByTyping(h, q);
        await h.shot('$_page/answer-$i');
      }
      await h.tap(inTranscript(find.text(h.t('basira.provenance'))).last);
      final scroll = tester
          .widget<SingleChildScrollView>(find.byKey(BasiraPage.transcriptKey))
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await h.settle();
      await h.shot('$_page/provenance');
    });
  }
}
