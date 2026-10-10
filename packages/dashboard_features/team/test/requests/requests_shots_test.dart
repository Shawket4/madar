// The Requests inbox's screenshot matrix: the default page at every size in
// English light and Arabic dark, then each state and form at desktop
// English light and phone Arabic light. Run with FDASH_SHOTS set.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:flutter/widgets.dart' show Scrollable;
import 'package:flutter_test/flutter_test.dart';

import 'requests_support.dart';

const String _salma = "My sister's wedding";
const String _youssef = 'Renewing my national ID';

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpRequests(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'default');
        await h.tap(pageText(h.t('dawam.all')));
        await shootPage(h, 'all');
      });
    }
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    testWidgets('states and forms, ${size.name} $lang', (tester) async {
      Future<DashHarness> open([Srv? s]) =>
          pumpRequests(tester, size: size, locale: lang, s: s);

      final loading = requestsServer();
      final gate = loading.server.hold('GET', listT);
      var h = await open(loading);
      await h.shot('requests/loading');
      gate.release();
      await h.settle();

      final failing = requestsServer();
      failing.server.fail(
        'GET',
        listT,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      h = await open(failing);
      await h.shot('requests/error');

      h = await open(
        requestsServer(
          edit: (db) => db[TeamTables.requests].removeWhere(
            (r) => r['status'] == 'pending',
          ),
        ),
      );
      await h.shot('requests/empty-pending');
      await h.tap(pageText(h.t('staff.req_rejected')));
      await h.tap(pageText(h.t('staff.allKinds')));
      await h.tap(find.text(h.t('dawam.kindCorrection')).last);
      await h.shot('requests/empty-filtered');

      h = await open(
        requestsServer(
          edit: (db) => db[TeamTables.requests].insert(
            requestRow(
              id: 'rq-w',
              employeeKey: 'laila',
              kind: 'leave',
              onDate: day(-2),
              endDate: day(-1),
              reason: 'Was sick',
              workedDates: [day(-2)],
            ),
          ),
        ),
      );
      await h.tap(approveIn('Was sick'));
      await h.shot('requests/approve-pay');
      await h.tap(inSurface(find.text(h.t('common.cancel'))));
      await h.tap(rejectIn(_salma));
      await h.shot('requests/reject');
      await h.tap(inSurface(find.text(h.t('common.cancel'))));
      await h.tap(cancelIn(_youssef));
      await h.tap(inSurface(find.text(h.t('staff.cancelRequest'))).last);
      await h.shot('requests/cancel-required');
      await h.tap(inSurface(find.text(h.t('common.back'))));
      await h.tap(pageText(h.t('staff.newRequest')));
      await h.shot('requests/new-request');
      await h.tap(surfaceText(h.t('staff.kindLateArrival')));
      await h.tap(find.text(h.t('staff.kindLeave')).last);
      await h.tap(surfaceText(h.t('staff.pickEmployee')));
      final list = find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('DashOptionList'),
      );
      final nour = find.descendant(
        of: list,
        matching: find.text('Nour El-Sayed'),
      );
      await tester.scrollUntilVisible(
        nour,
        100,
        scrollable: find
            .descendant(of: list, matching: find.byType(Scrollable))
            .last,
      );
      await h.tap(nour.last);
      await h.tap(surfaceText(h.t('common.save')));
      await h.shot('requests/new-leave-own');
    });
  }
}
