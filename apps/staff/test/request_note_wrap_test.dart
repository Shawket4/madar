// POLISH (FINAL device checks, iPhone): a pending Late arrival's row read
// "Thu 24 Sep · until 9:30 AM …": its note, the one thing the person wrote,
// was cut in the row's single line. A request row that carries words (my
// note, a reason) wraps; every pending kind is checked, in both languages,
// at the narrowest phone with the real faces.
import 'package:design_system/design_system.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support.dart';

/// The owner-free side: Home, Timesheet, Shifts, Requests, Pay.
const _requests = 3;

const _note = 'University exam in the morning, then the bank for my papers';

Map<String, dynamic> _pending(String id, String kind) => {
  'amount': kind == 'salaryAdvance' ? 400000 : 0,
  'can_decide': null,
  'cancel_note': null,
  'cancelled_by': null,
  'cancelled_by_name': null,
  'created': '2026-09-25T09:00:00+03:00',
  'decided_by': null,
  'decision_note': null,
  'emp': 'e1',
  'from': '2026-09-29',
  'half': false,
  'id': id,
  'installments': kind == 'salaryAdvance' ? 3 : 1,
  'kind': kind,
  'leave_half': null,
  'minutes': 0,
  'month_open': true,
  'note': _note,
  'paid': null,
  'paid_default': null,
  'peer': null,
  'shift': null,
  'shift2': null,
  'status': 'pending',
  'time': switch (kind) {
    'lateArrival' => 570,
    'earlyDeparture' => 900,
    'excuse' => 720,
    'correction' => 600,
    _ => null,
  },
  'time2': switch (kind) {
    'excuse' => 780,
    'correction' => 1020,
    _ => null,
  },
  'to': kind == 'leave' ? '2026-10-01' : null,
  'to_owner': false,
  'tpl': null,
  'within_cap': null,
  'worked': <String>[],
};

const _kinds = [
  'leave',
  'lateArrival',
  'earlyDeparture',
  'excuse',
  'mission',
  'correction',
  'salaryAdvance',
];

void main() {
  useCoreWords();
  setUpAll(() async {
    await loadFonts();
    await initializeDateFormatting();
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('a pending row reads its note in full on a phone · $lang', (
      t,
    ) async {
      await pumpApp(
        t,
        lang: lang,
        who: 'e1',
        tab: _requests,
        size: const Size(375, 812),
        core: (f) => f.edit = (v) {
          final reqs = v['requests'] as List<dynamic>;
          for (final (i, k) in _kinds.indexed) {
            reqs.add(_pending('x|$i', k));
          }
        },
      );
      await frames(t);
      final rows = find.descendant(
        of: find.byType(MadarListRow),
        matching: find.textContaining(_note),
      );
      // Every row built so far, read where it lies (a lazy list builds as
      // it scrolls; each row is checked once it exists).
      final cut = <String>[];
      final checked = <String>{};
      Future<void> check() async {
        for (final e in rows.evaluate()) {
          final text = (e.widget as Text).data!;
          if (!checked.add(text)) continue;
          final p = e.renderObject! as RenderParagraph;
          if (p.didExceedMaxLines) cut.add(text);
        }
      }

      await t.drag(find.byType(Scrollable).first, const Offset(0, 5000));
      await frames(t, 4);
      for (var i = 0; i < 15; i++) {
        await check();
        await t.drag(find.byType(Scrollable).first, const Offset(0, -250));
        await frames(t, 4);
      }
      await check();
      expect(
        checked.length,
        _kinds.length,
        reason: 'every pending kind: $checked',
      );
      expect(cut, isEmpty, reason: 'cut on a phone');
      expect(t.takeException(), isNull);
      await finish(t);
    });
  }
}
