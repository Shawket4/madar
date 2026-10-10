// Tills screenshot matrix: the default page at every size in EN light and
// AR dark, and each dialog / panel / state at desktop-en-light and
// phone-ar-light. Run with FDASH_SHOTS set, then look at the PNGs.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/tills/till_report_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tills_support.dart';

const _modes = [('en', false), ('ar', true)];
const _overlayModes = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
];

/// One PNG per screen of [scrollable] (the page's own by default).
Future<void> shootScroll(DashHarness h, String name, {Finder? of}) async {
  final scroll = find
      .descendant(of: of ?? tillsPage, matching: find.byType(Scrollable))
      .first;
  final position = h.tester.state<ScrollableState>(scroll).position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('tills/$name-$i');
    if (y >= position.maxScrollExtent || i >= 6) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

/// Makes Ali's open Heliopolis till the owner's (the cash and close
/// dialogs need MY open till).
({MockServer server, MockDb db}) _ownerServer() {
  final s = tillsServer();
  s.db['tills'].get(TillIds.helioMorning)
    ..['teller_id'] = SeedIds.owner
    ..['teller_name'] = 'Nour El-Sayed';
  return s;
}

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      final tag = '${size.name} $lang ${dark ? 'dark' : 'light'}';
      testWidgets('default, $tag', (tester) async {
        final h = await pumpTills(tester, size: size, locale: lang, dark: dark);
        await shootScroll(h, 'default');
      });
    }
  }

  for (final (size, lang, dark) in _overlayModes) {
    final tag = '${size.name} $lang';
    testWidgets('all branches, $tag', (tester) async {
      final h = await pumpTills(
        tester,
        allBranches: true,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('tills/all-branches');
    });

    testWidgets('loading, $tag', (tester) async {
      final s = tillsServer();
      s.server
        ..hold('GET', tillsList)
        ..hold('GET', tillsOpen)
        ..hold('GET', tillsNotice);
      final h = await pumpTills(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('tills/loading');
    });

    testWidgets('failed, $tag', (tester) async {
      final s = tillsServer();
      for (final t in [tillsList, tillsOpen]) {
        s.server.fail(
          'GET',
          t,
          MockResponse.error(500, 'Database error: connection reset'),
          times: null,
        );
      }
      final h = await pumpTills(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('tills/failed');
    });

    testWidgets('empty, $tag', (tester) async {
      final s = tillsServer();
      s.db['tills'].removeWhere((t) => t['branch_id'] == SeedIds.heliopolis);
      final h = await pumpTills(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('tills/empty');
    });

    testWidgets('row menu, $tag', (tester) async {
      final s = _ownerServer();
      final h = await pumpTills(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
      );
      await openRowMenu(h, TillIds.helioMorning);
      await h.shot('tills/row-menu');
    });

    testWidgets('status filter, $tag', (tester) async {
      final h = await pumpTills(tester, size: size, locale: lang, dark: dark);
      await h.tap(inKey('filter-status', find.byType(DashSelectTrigger)));
      await h.shot('tills/status-filter');
    });

    testWidgets('open till dialog, $tag', (tester) async {
      final h = await pumpTills(tester, size: size, locale: lang, dark: dark);
      await h.tap(inPage(find.text(h.t('tills.openTill'))));
      await h.shot('tills/open-till');
    });

    testWidgets('cash movement dialog, $tag', (tester) async {
      final s = _ownerServer();
      final h = await pumpTills(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
      );
      await openRowMenu(h, TillIds.helioMorning);
      await pickMenu(h, h.t('tills.cashMovement'));
      await h.tap(inSurface(find.text(h.t('tills.cashOut'))));
      await h.shot('tills/cash-movement');
    });

    testWidgets('close till dialog, $tag', (tester) async {
      final s = _ownerServer();
      closeOthers(s.db, SeedIds.heliopolis, TillIds.helioMorning);
      final h = await pumpTills(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
      );
      await openRowMenu(h, TillIds.helioMorning);
      await pickMenu(h, h.t('tills.closeTill'));
      await h.tap(find.byKey(const ValueKey('close-till-submit')));
      final rows = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('reconcile-row-'),
      );
      if (rows.evaluate().isNotEmpty) {
        await h.tap(
          find.descendant(
            of: rows.first,
            matching: find.text(h.t('tills.reconciliation.disagreed')),
          ),
        );
      }
      await h.shot('tills/close-till');
      await h.enterText(find.byKey(const ValueKey('closing-cash')), '1000');
      if (rows.evaluate().isNotEmpty) {
        await h.tap(
          find.descendant(
            of: rows.first,
            matching: find.text(h.t('tills.reconciliation.checked')),
          ),
        );
      }
      await h.tap(find.byKey(const ValueKey('close-till-submit')));
      await h.shot('tills/last-till-warning');
      await h.flushTimers();
    });

    testWidgets('force close and delete confirms, $tag', (tester) async {
      final h = await pumpTills(tester, size: size, locale: lang, dark: dark);
      await openRowMenu(h, TillIds.helioSecond);
      await pickMenu(h, h.t('tills.forceClose'));
      await h.shot('tills/force-close');
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text(h.t('common.cancel')),
        ),
      );
      await openRowMenu(h, TillIds.helioSecond);
      await pickMenu(h, h.t('common.delete'));
      await h.shot('tills/delete');
    });

    for (final (name, id, branch) in [
      ('report-open', TillIds.helioMorning, SeedIds.heliopolis),
      ('report-closed', TillIds.zamalekLastEvening, SeedIds.zamalek),
    ]) {
      testWidgets('$name, $tag', (tester) async {
        final h = await pumpTills(
          tester,
          query: 'report=$id',
          branchId: branch,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootScroll(h, name, of: find.byType(TillReportView));
      });
    }
  }
}
