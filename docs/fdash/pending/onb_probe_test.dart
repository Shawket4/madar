// Verifier probe (read-only, lives in the scratchpad).
import 'package:dashboard_admin/src/mock/onboarding_mock.dart';
import 'package:dashboard_admin/src/onboarding/celebration.dart';
import 'package:dashboard_admin/src/onboarding/step_navigator.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file:///Users/shawket/Desktop/Madar/wt-fdash-pos/packages/dashboard_features/admin/test/onboarding/support.dart';

Finder _navStep(String t) => find.descendant(
  of: find.byType(OnbStepNavigator),
  matching: find.bySemanticsLabel(RegExp(t)),
);

void main() {
  testWidgets('PROBE-A slow gate read after Open my cafe', (tester) async {
    final s = onboardingServer();
    readyCafe(s.db);
    final h = await pumpOnboarding(tester, server: s.server, db: s.db);
    h.allowUnmatched = true;
    await h.tap(_navStep('Open your café'));
    final gate = s.server.hold('GET', statusRoute);
    await h.tap(buttonOf('Open my café'));
    await tester.pump(const Duration(milliseconds: 1600));
    await h.settle();
    // ignore: avoid_print
    print('PROBE-A at 2s (gate read held): location=${h.location} '
        'celebration=${find.byType(OnbCelebration).evaluate().length}');
    gate.release();
    await h.settle();
    await tester.pump(const Duration(seconds: 5));
    await h.settle();
    // ignore: avoid_print
    print('PROBE-A after release: location=${h.location} '
        'celebration=${find.byType(OnbCelebration).evaluate().length}');
  });

  testWidgets('PROBE-B team step opens the user dialog', (tester) async {
    final s = onboardingServer();
    freshCafe(s.db);
    final h = await pumpOnboarding(tester, server: s.server, db: s.db);
    await h.tap(_navStep('Invite your team'));
    await h.tap(buttonOf('Add a team member'));
    final surfaces = find.byType(DashSurface).evaluate().length;
    // ignore: avoid_print
    print('PROBE-B surfaces=$surfaces newTitle='
        '${find.text(h.t('users.newTitle')).evaluate().length}');
    if (surfaces > 0) await h.tap(buttonOf('Cancel', within: surface));
  });

  testWidgets('PROBE-C a refresh landing re-seeds an unedited item editor', (
    tester,
  ) async {
    final s = onboardingServer();
    freshCafe(s.db);
    addItem(s.db, addCategory(s.db));
    final h = await pumpOnboarding(tester, server: s.server, db: s.db);
    await h.tap(_navStep('Recipes & costs'));
    await h.tap(buttonOf('Add recipe'));
    String price() => tester
        .widget<EditableText>(
          find.descendant(
            of: field('item-price'),
            matching: find.byType(EditableText),
          ),
        )
        .controller
        .text;
    final before = price();
    final item = s.db[OnbTables.menuItems].rows.single;
    item['base_price'] = 7000;
    for (final r in s.db[OnbTables.sizes].rows) {
      if (r['menu_item_id'] == item['id']) r['price_override'] = 7000;
    }
    final gets = h.server.callsTo('/menu-items/{id}', method: 'GET').length;
    h.container.read(realtimeBusProvider).invalidate(['/menu-items/${item['id']}']);
    await h.settle();
    // ignore: avoid_print
    print('PROBE-C before=$before after=${price()} '
        'refetched=${h.server.callsTo('/menu-items/{id}', method: 'GET').length - gets}');
    await h.tap(buttonOf('Cancel', within: surface));
  });
}
