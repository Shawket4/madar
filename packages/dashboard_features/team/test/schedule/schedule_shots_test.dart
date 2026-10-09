// The Schedule's screenshot matrix: the default page at every size in
// English light and Arabic dark, then each state, dialog and card at
// desktop-en-light and phone-ar-light. Shots are written only with
// FDASH_SHOTS set.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'schedule_support.dart';

const List<(DashSize, String, bool)> _states = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
];

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpSchedule(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang, dark) in _states) {
    final at = '${size.name} $lang';

    testWidgets('loading, $at', (tester) async {
      final s = scheduleServer();
      final gate = s.server.hold('GET', rosterT);
      final h = await pumpSchedule(
        tester,
        s: s,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('schedule/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, $at', (tester) async {
      final s = scheduleServer();
      s.server.fail('GET', rosterT, MockResponse.error(500, 'boom'), times: 2);
      final h = await pumpSchedule(
        tester,
        s: s,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('schedule/failed');
    });

    testWidgets('no staff and rules banner, $at', (tester) async {
      final h = await pumpSchedule(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        edit: (db) {
          for (final s in db['attendance_settings'].rows) {
            s['rules_saved_at'] = null;
          }
          for (final e in db['employees'].rows) {
            if ((e['branch_ids'] as List?)?.contains(SeedIds.zamalek) ??
                false) {
              e['employment_status'] = 'terminated';
            }
          }
        },
      );
      await h.shot('schedule/empty');
    });

    testWidgets('draft week, no work shifts, $at', (tester) async {
      final h = await pumpSchedule(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        edit: (db) => db['work_shifts'].removeWhere(
          (w) => w['org_id'] == SeedIds.sabahOrg,
        ),
      );
      await h.tap(pressable(h.t('dawam.nextWeek')));
      await h.shot('schedule/draft-no-blocks');
    });

    testWidgets('day editor, $at', (tester) async {
      final h = await pumpSchedule(
        tester,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(dayCellOf(h, 'Laila Ehab', 4));
      await h.tap(
        inSurface(pressable(h.t('dawam.editTimesOf', args: {'shift': 'Evening'}))),
      );
      await h.shot('schedule/day-editor');
      await h.tap(
        inSurface(
          pressable(h.t('dawam.moveShiftOf', args: {'shift': 'Evening'})),
        ),
      );
      await h.tap(find.byKey(const Key('day-give-to')));
      await h.tap(find.text('Karim Adel').hitTestable().last);
      await h.shot('schedule/day-editor-move');
    });

    testWidgets('day off confirm, $at', (tester) async {
      final h = await pumpSchedule(
        tester,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(dayCellOf(h, 'Adham Reda', 0));
      await h.tap(inSurface(find.widgetWithText(DashButton, h.t('dawam.dayOff'))));
      await h.shot('schedule/day-off-confirm');
    });

    testWidgets('preferences, $at', (tester) async {
      final h = await pumpSchedule(
        tester,
        size: size,
        locale: lang,
        dark: dark,
      );
      await tapCentered(
        h,
        inGrid(
          pressable(h.t('dawam.prefsOf', args: {'name': 'Hassan Ibrahim'})),
        ),
      );
      await h.shot('schedule/preferences');
    });

    testWidgets('coverage, suggestions, holidays and fairness, $at', (
      tester,
    ) async {
      final h = await pumpSchedule(
        tester,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(
        inPage(find.widgetWithText(DashButton, h.t('dawam.coverageTitle'))),
      );
      await shootPage(h, 'cards');
    });

    testWidgets('post an open shift, $at', (tester) async {
      final h = await pumpSchedule(
        tester,
        size: size,
        locale: lang,
        dark: dark,
      );
      final post = inGrid(
        find.byWidgetPredicate(
          (w) => w is DashIconButton && w.icon == 'calendar-plus',
        ),
      ).first;
      await h.tap(post);
      await h.shot('schedule/post-open');
    });

    testWidgets('publish confirm, $at', (tester) async {
      final h = await pumpSchedule(
        tester,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(pressable(h.t('dawam.nextWeek')));
      await h.tap(
        inPage(find.widgetWithText(DashButton, h.t('dawamOps.publishWeek'))),
      );
      await h.shot('schedule/publish-confirm');
    });
  }
}
