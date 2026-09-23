// APP-9: every sheet and form, not just each tab's first screen, in Arabic
// and English on a phone: it lays out without an overflow and shows no raw
// i18n key. Plus the sign-in steps (code, business, privacy), and the rule
// behind 06 B1: a refused form stays open with the server's words, and no
// success is said.
import 'dart:async';
import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:feature_dawam_clock/feature_dawam_clock.dart';
import 'package:feature_dawam_pay/feature_dawam_pay.dart';
import 'package:feature_dawam_requests/feature_dawam_requests.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:madar_staff/shell.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

/// The real Plex faces, as on a phone: the test font's square glyphs are far
/// wider than any real text and would fail rows that fit.
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

/// No raw key and no layout error on what is on screen now.
Future<void> check(WidgetTester t, String what) async {
  await frames(t);
  expect(t.takeException(), isNull, reason: what);
  expect(
    find.textContaining(RegExp(r'\b(staff|settings|common)\.[a-z_]+')),
    findsNothing,
    reason: '$what shows a raw key',
  );
}

/// A context inside the app (under its Navigator and ProviderScope).
BuildContext inApp(WidgetTester t) =>
    t.element(find.byType(MadarShellScaffold));

Future<void> closeSheet(WidgetTester t) async {
  final nav = Navigator.of(inApp(t));
  if (nav.canPop()) nav.pop();
  await frames(t);
}

void main() {
  useCoreWords();
  setUpAll(() async {
    await _loadFonts();
    await initializeDateFormatting();
  });

  for (final lang in ['ar', 'en']) {
    group(lang, () {
      testWidgets('every request form · $lang', (t) async {
        await pumpApp(t, lang: lang, who: 'e1', tab: 3);
        for (final k in [
          ReqKind.leave,
          ReqKind.lateArrival,
          ReqKind.earlyDeparture,
          ReqKind.excuse,
          ReqKind.mission,
        ]) {
          unawaited(requestSheet(inApp(t), k));
          await check(t, 'request $k');
          expect(find.text(kindLabel(k)), findsWidgets);
          await closeSheet(t);
        }
        await finish(t);
      });

      testWidgets('correction, advance, payslip, inbox, settings · $lang', (
        t,
      ) async {
        final c = await pumpApp(t, lang: lang, who: 'e1', tab: 1);
        final store = c.read(dawamProvider);
        final mine = store.shifts.where((s) => s.emp == 'e1').first;
        unawaited(correctionSheet(inApp(t), mine));
        await check(t, 'correction');
        await closeSheet(t);

        // The Pay tab's advance request.
        c.read(shellProvider.notifier).select(4);
        await frames(t);
        final ask = find.text(tr('staff.request'));
        await t.ensureVisible(ask.first);
        await t.tap(ask.first);
        await check(t, 'advance request');
        expect(find.text(tr('staff.request_a_salary_advance')), findsWidgets);
        await closeSheet(t);

        final slips = store.payslipsOf('e1');
        if (slips.isNotEmpty) {
          unawaited(payslipSheet(inApp(t), slips.first));
          await check(t, 'payslip');
          await closeSheet(t);
        }

        await t.tap(find.byTooltip(tr('staff.inbox')).first);
        await check(t, 'inbox');
        expect(find.text(tr('staff.inbox')), findsWidgets);
        await closeSheet(t);

        final shell = t.widget<MadarShellScaffold>(
          find.byType(MadarShellScaffold),
        );
        shell.onPersonTap!();
        await check(t, 'settings');
        expect(
          find.textContaining(
            RegExp(RegExp.escape(tr('settings.account')), caseSensitive: false),
          ),
          findsWidgets,
        );
        await closeSheet(t);
        await finish(t);
      });

      testWidgets('a manager\'s money sheets and a flag · $lang', (t) async {
        final c = await pumpApp(t, lang: lang, who: 'e2', manage: true);
        final store = c.read(dawamProvider);
        final someone = store.emps.keys.firstWhere((e) => e != 'e2');
        for (final (name, open) in [
          ('adjustment', () => adjustmentSheet(inApp(t))),
          ('expense', () => expenseSheet(inApp(t))),
          ('record advance', () => recordAdvanceSheet(inApp(t), someone)),
        ]) {
          unawaited(open());
          await check(t, name);
          await closeSheet(t);
        }
        final flag = find.textContaining('Youssef Adel ·').first;
        await t.ensureVisible(flag);
        await t.tap(flag);
        await check(t, 'flag');
        expect(find.text(tr('staff.deduct')), findsWidgets);
        await closeSheet(t);
        await finish(t);
      });

      testWidgets('the sign-in steps: code, business, privacy · $lang', (
        t,
      ) async {
        await pumpApp(t, lang: lang);
        testCore.verifyAnswer = (org) => org == null
            ? {
                'needs_org': true,
                'orgs': [
                  {'org_id': 'o1', 'org_name': 'Rue', 'active': true},
                  {
                    'org_id': 'o2',
                    'org_name': 'Zamalek Bakery',
                    'active': false,
                  },
                ],
              }
            : {'employee_id': 'e1', 'token': 't', 'device_token': 'd'};
        await t.enterText(find.byType(EditableText), '01001234567');
        await t.tap(find.text(tr('staff.send_code')));
        await check(t, 'code step');
        await t.enterText(find.byType(EditableText), '123456');
        await t.tap(find.text(tr('staff.verify')));
        await check(t, 'business step');
        expect(find.text('Zamalek Bakery'), findsOneWidget);
        await t.tap(find.text('Rue'));
        await check(t, 'privacy step');
        expect(find.text(tr('staff.i_agree')), findsOneWidget);
        await finish(t);
      });
    });
  }

  testWidgets(
    'a code check that names no one is refused, not a crash (06 B13)',
    (t) async {
      final c = await pumpApp(t, lang: 'en');
      testCore.verifyAnswer = (_) => {'token': 't'};
      await t.enterText(find.byType(EditableText), '01001234567');
      await t.tap(find.text(tr('staff.send_code')));
      await frames(t);
      await t.enterText(find.byType(EditableText), '123456');
      await t.tap(find.text(tr('staff.verify')));
      await check(t, 'no person');
      expect(find.textContaining("didn't sign anyone in"), findsOneWidget);
      expect(find.text(tr('staff.i_agree')), findsNothing);
      expect(c.read(dawamProvider).pendingUser, isNull);
      await finish(t);
    },
  );

  testWidgets('Team shows who is in or late as the server said (AT-3)', (
    t,
  ) async {
    final c = await pumpApp(t, lang: 'en', who: 'e2', manage: true);
    final store = c.read(dawamProvider);
    expect(store.presence['e1']?.state, PresenceState.late);
    await frames(t);
    expect(find.textContaining('12m late'), findsOneWidget);
    await finish(t);
  });

  group('a refused form stays open (06 B1, APP-8)', () {
    for (final lang in ['ar', 'en']) {
      testWidgets('request · $lang', (t) async {
        await pumpApp(t, lang: lang, who: 'e1', tab: 3);
        final refusal = DawamError(
          'This needs a connection.',
          'ده محتاج اتصال.',
        );
        testCore.refuse = refusal;
        unawaited(requestSheet(inApp(t), ReqKind.leave));
        await frames(t);
        final send = find.text(tr('staff.send'));
        await t.ensureVisible(send.last);
        await t.tap(send.last);
        await frames(t);
        expect(testCore.acts, isNotEmpty, reason: 'it did ask the core');
        expect(find.text(loc(refusal)), findsOneWidget);
        expect(find.text(tr('staff.sent_to_your_manager')), findsNothing);
        expect(
          find.text(kindLabel(ReqKind.leave)),
          findsWidgets,
          reason: 'the sheet is still open with what was typed',
        );
        // Accepted next time: the success is said and the sheet closes.
        testCore.refuse = null;
        await t.tap(send.last);
        await frames(t);
        expect(find.text(tr('staff.sent_to_your_manager')), findsOneWidget);
        await finish(t);
      });
    }
  });
}
