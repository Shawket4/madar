// The Approvals screenshot matrix: the default queue at every size in
// {en light, ar dark}, and every state, dialog and confirm at desktop-en-light
// and phone-ar-light.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'approvals_support.dart';

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpApprovals(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang) in [(DashSize.desktop, 'en'), (DashSize.phone, 'ar')]) {
    final tag = '${size.name} $lang';

    testWidgets('loading, $tag', (tester) async {
      final s = approvalsServer();
      final gate = s.server.hold('GET', swapsT);
      final h = await pumpApprovals(tester, s: s, size: size, locale: lang);
      await h.shot('approvals/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('a list failed, $tag', (tester) async {
      final s = approvalsServer();
      s.server.fail(
        'GET',
        advancesT,
        MockResponse.denied('hr.advances.decide'),
        times: null,
      );
      final h = await pumpApprovals(tester, s: s, size: size, locale: lang);
      await h.shot('approvals/failed');
    });

    testWidgets('empty, $tag', (tester) async {
      final h = await pumpApprovals(
        tester,
        edit: emptyQueue,
        size: size,
        locale: lang,
      );
      await h.shot('approvals/empty');
    });

    testWidgets('refused, $tag', (tester) async {
      final h = await pumpApprovals(
        tester,
        persona: Persona.limited,
        size: size,
        locale: lang,
      );
      await h.shot('approvals/refused');
    });

    testWidgets('closed month and the cap, $tag', (tester) async {
      final s = approvalsServer(persona: Persona.manager);
      final h = await pumpApprovals(tester, s: s, size: size, locale: lang);
      await shootPage(h, 'manager');
    });

    testWidgets('approve with pay, $tag', (tester) async {
      final h = await pumpApprovals(tester, size: size, locale: lang);
      await h.tap(approveIn(h.t('staff.kindLeave')));
      await h.shot('approvals/approve-with-pay');
    });

    testWidgets('review advance, $tag', (tester) async {
      final h = await pumpApprovals(tester, size: size, locale: lang);
      await h.tap(approveIn("My mother's eye operation"));
      await h.shot('approvals/review-advance');
    });

    testWidgets('reject with a reason, $tag', (tester) async {
      final h = await pumpApprovals(tester, size: size, locale: lang);
      await h.tap(rejectIn('Hassan Ibrahim'));
      await h.tap(inSurface(find.text(h.t('common.reject'))).last);
      await h.shot('approvals/reject-reason');
    });

    testWidgets('reject confirm, $tag', (tester) async {
      final h = await pumpApprovals(tester, size: size, locale: lang);
      await h.tap(rejectIn('Laila Ehab'));
      await h.shot('approvals/reject-confirm');
    });

    testWidgets('batch confirm, $tag', (tester) async {
      final h = await pumpApprovals(tester, size: size, locale: lang);
      final n = batchCount(tester);
      await h.tap(inPage(find.bySemanticsLabel(h.t('dawamOps.selectAll', count: n))));
      await h.tap(inPage(find.text(h.t('dawamOps.approveCount', count: n))));
      await h.shot('approvals/batch-confirm');
    });
  }
}
