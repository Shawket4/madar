// H2-P1: after the month rolled over, an older month still a draft (or
// approved with someone unpaid) could not be approved or paid from the app:
// every action named the current month. The owner's Payroll tab says which
// older month isn't fully paid yet and opens it with its own actions.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

const _payrollTab = 3;

Future<void> _tapText(WidgetTester t, String text) async {
  final f = find.text(text).last;
  await t.ensureVisible(f);
  await t.tap(f);
  await frames(t);
}

void main() {
  useCoreWords();
  setUpAll(() async {
    // The real faces, so a line is measured as the phone measures it.
    await loadFonts();
    await initializeDateFormatting();
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('an older unpaid month opens with its actions · $lang', (
      t,
    ) async {
      await pumpApp(
        t,
        lang: lang,
        who: 'e3',
        manage: true,
        tab: _payrollTab,
        size: const Size(1180, 820),
        core: (f) => f.edit = (v) {
          (v['history'] as List<dynamic>).add({
            'end': '2026-07-25',
            'id': 'p0',
            'paid_by': <String, dynamic>{},
            'start': '2026-06-26',
            'status': 'open',
          });
          final slip = Map<String, dynamic>.of(
            (v['slips'] as List<dynamic>).first as Map<String, dynamic>,
          );
          (v['slips'] as List<dynamic>).add({
            ...slip,
            'start': '2026-06-26',
            'end': '2026-07-25',
            'frozen': false,
            'net': 777700,
          });
          v['unsettled'] = [
            {
              'id': 'p0',
              'start': '2026-06-26',
              'end': '2026-07-25',
              'status': 'open',
              'net': 777700,
              'paid_count': 0,
              'people': 1,
            },
          ];
        },
      );
      await frames(t);
      final older =
          '${dayMonth(DateTime(2026, 6, 26))} – ${dayMonth(DateTime(2026, 7, 25))}';
      final banner = tr('staff.unsettled_title', {'period': older});
      expect(find.text(banner), findsOneWidget);
      await _tapText(t, banner);
      expect(find.text(older), findsWidgets, reason: 'that month is open');
      await _tapText(t, tr('staff.pay_out'));
      await _tapText(t, tr('staff.approve_payroll'));
      await _tapText(t, tr('staff.approve_payroll_confirm'));
      expect(lastAct(), {'action': 'approve_payroll', 'period': 'p0'});
      await _tapText(t, tr('staff.back_to_this_month'));
      expect(find.text(banner), findsOneWidget, reason: 'back on this month');
      await finish(t);
    });
  }

  // FINAL device check (run C, shot 03-H1-banner): on the iPhone the
  // banner's title and meta were cut ("isn't fully paid …", "EGP 87…"), so
  // the owner could not read which month or how much. Both wrap, in full, at
  // the narrowest phone (375 wide) with the long Arabic words and a
  // five-figure amount.
  for (final lang in ['en', 'ar']) {
    testWidgets('the banner reads in full on a phone · $lang', (t) async {
      await pumpApp(
        t,
        lang: lang,
        who: 'e3',
        manage: true,
        tab: _payrollTab,
        size: const Size(375, 812),
        core: (f) => f.edit = (v) {
          v['unsettled'] = [
            {
              'id': 'p0',
              'start': '2026-07-26',
              'end': '2026-08-25',
              'status': 'open',
              'net': 8701046,
              'paid_count': 0,
              'people': 13,
            },
            {
              'id': 'p00',
              'start': '2026-06-26',
              'end': '2026-07-25',
              'status': 'approved',
              'net': 7777700,
              'paid_count': 0,
              'people': 1,
            },
          ];
        },
      );
      await frames(t);
      final big = tr('staff.unsettled_title', {
        'period':
            '${dayMonth(DateTime(2026, 7, 26))} – ${dayMonth(DateTime(2026, 8, 25))}',
      });
      final small = tr('staff.unsettled_title', {
        'period':
            '${dayMonth(DateTime(2026, 6, 26))} – ${dayMonth(DateTime(2026, 7, 25))}',
      });
      for (final text in [big, small]) {
        expect(find.text(text), findsOneWidget);
      }
      final bigMeta = find.textContaining(egp(8701046));
      final smallMeta = find.textContaining(egp(7777700));
      expect(bigMeta, findsOneWidget);
      expect(smallMeta, findsOneWidget);
      for (final f in [find.text(big), find.text(small), bigMeta, smallMeta]) {
        final p = t.renderObject<RenderParagraph>(f);
        expect(
          p.didExceedMaxLines,
          isFalse,
          reason: 'cut on a phone: ${(t.widget<Text>(f)).data}',
        );
      }
      expect(t.takeException(), isNull);
      if (lang == 'en') {
        final meta = t.widget<Text>(smallMeta).data!;
        expect(meta, contains('of 1 paid'));
        expect(
          t.widget<Text>(bigMeta).data,
          'Not approved yet · 13 people · ${egp(8701046)}',
        );
      }
      await finish(t);
    });

    // FINAL device check (C2): a count reads in its own form, "1 person"
    // and "شخص واحد", never "1 people" / "1 أشخاص".
    testWidgets('a one-person month says one person · $lang', (t) async {
      await pumpApp(
        t,
        lang: lang,
        who: 'e3',
        manage: true,
        tab: _payrollTab,
        core: (f) => f.edit = (v) {
          v['unsettled'] = [
            {
              'id': 'p0',
              'start': '2026-07-26',
              'end': '2026-08-25',
              'status': 'open',
              'net': 650000,
              'paid_count': 0,
              'people': 1,
            },
          ];
        },
      );
      await frames(t);
      final meta = t.widget<Text>(find.textContaining(egp(650000))).data!;
      expect(
        meta,
        lang == 'en'
            ? 'Not approved yet · 1 person · ${egp(650000)}'
            : 'لسه ما اتعتمدش · شخص واحد · ${egp(650000)}',
      );
      await finish(t);
    });
  }

  testWidgets('no older month to settle: no banner', (t) async {
    await pumpApp(
      t,
      lang: 'en',
      who: 'e3',
      manage: true,
      tab: _payrollTab,
      size: const Size(1180, 820),
    );
    await frames(t);
    expect(find.textContaining("isn't fully paid yet"), findsNothing);
    await finish(t);
  });
}
