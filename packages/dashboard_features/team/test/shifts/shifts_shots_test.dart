// The Work shifts screenshot matrix: the page at every size in EN light and
// AR dark, then each state, dialog and menu at desktop-en-light and
// phone-ar-light. Writes PNGs only with FDASH_SHOTS set.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shifts_support.dart';

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpShifts(
          tester,
          size: size,
          locale: lang,
          dark: dark,
          edit: addDemoShifts,
        );
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    testWidgets('loading, ${size.name} $lang', (tester) async {
      final s = shiftsServer();
      final a = s.server.hold('GET', shiftsT);
      final b = s.server.hold('GET', rosterT);
      final h = await pumpShifts(tester, s: s, size: size, locale: lang);
      await h.shot('shifts/loading');
      a.release();
      b.release();
      await h.settle();
    });

    testWidgets('failed, ${size.name} $lang', (tester) async {
      final s = shiftsServer();
      for (final t in [shiftsT, rosterT]) {
        s.server.fail(
          'GET',
          t,
          MockResponse.error(500, 'boom'),
          times: null,
        );
      }
      final h = await pumpShifts(tester, s: s, size: size, locale: lang);
      await shootPage(h, 'failed');
    });

    testWidgets('empty, ${size.name} $lang', (tester) async {
      final h = await pumpShifts(
        tester,
        size: size,
        locale: lang,
        edit: (db) {
          noRoster(db);
          db['work_shifts'].removeWhere(
            (r) => r['org_id'] == SeedIds.sabahOrg,
          );
        },
      );
      await shootPage(h, 'empty');
    });

    testWidgets('new dialog, ${size.name} $lang', (tester) async {
      final h = await pumpShifts(tester, size: size, locale: lang);
      await h.tap(inPage(find.byKey(const ValueKey('shifts-new'))));
      await h.shot('shifts/dialog-new');
      await h.tap(inSurface(find.text(h.t('staff.moreShiftSettings'))));
      await tester.ensureVisible(save());
      await h.settle();
      await h.shot('shifts/dialog-new-more');
    });

    testWidgets('edit dialog over the cap, ${size.name} $lang', (
      tester,
    ) async {
      final h = await pumpShifts(
        tester,
        size: size,
        locale: lang,
        edit: (db) {
          addDemoShifts(db);
          noRoster(db);
        },
      );
      await h.tap(inRow(oldNight, find.bySemanticsLabel(h.t('common.edit'))));
      await h.shot('shifts/dialog-edit');
      await h.tap(inSurface(find.text(h.t('common.cancel'))));
      await h.tap(inRow(eveningZ, find.bySemanticsLabel(h.t('common.edit'))));
      await h.shot('shifts/dialog-edit-day-times');
    });

    testWidgets('delete confirm, ${size.name} $lang', (tester) async {
      final h = await pumpShifts(
        tester,
        size: size,
        locale: lang,
        edit: addDemoShifts,
      );
      await h.tap(
        inRow(brunch, find.bySemanticsLabel(h.t('staff.deleteShift'))),
      );
      await h.shot('shifts/delete-confirm');
    });

    testWidgets('cell menu, ${size.name} $lang', (tester) async {
      final h = await pumpShifts(
        tester,
        size: size,
        locale: lang,
        edit: addDemoShifts,
      );
      final first = inGrid(
        find.byWidgetPredicate(
          (w) => w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('roster-') &&
              (w.key! as ValueKey<String>).value.endsWith('-4'),
        ),
      ).first;
      await h.tap(first);
      await h.shot('shifts/cell-menu');
    });
  }
}
