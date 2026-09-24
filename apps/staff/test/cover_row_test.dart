// E2E clocking / requests (CV-7): a cover is the coverer's own row, naming
// whose shift it covered. Home shows "Covering · <name>" and the Timesheet
// lists it, in both languages.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

void main() {
  useCoreWords();
  setUpAll(initializeDateFormatting);

  void coverRow(Map<String, dynamic> v) {
    final shifts = v['shifts'] as List<dynamic>;
    final base = Map<String, dynamic>.from(
      (shifts.first as Map).cast<String, dynamic>(),
    );
    shifts.add({
      ...base,
      'id': 'cover|r9',
      'emp': 'e1',
      'cover_of': 'e4',
      'cover_by': null,
      'date': '2026-09-23',
      'absent': false,
      'in_at': '2026-09-23T08:40:00+03:00',
      'out_at': null,
      'in_method': 'cover',
    });
    v['my_now'] = [...(v['my_now'] as List<dynamic>), 'cover|r9'];
    v['active_shift'] = 'cover|r9';
  }

  for (final lang in ['en', 'ar']) {
    testWidgets('a cover is my own row on Home and in the Timesheet · $lang', (
      t,
    ) async {
      final c = await pumpApp(
        t,
        lang: lang,
        who: 'e1',
        core: (f) => f.edit = coverRow,
      );
      await frames(t);
      final covering = tr('staff.covering', {'name': 'Youssef Adel'});
      expect(find.text(covering), findsOneWidget, reason: 'Home card');
      expect(c.read(dawamProvider).activeShift?.coverOf, 'e4');
      await finish(t);
      await pumpApp(
        t,
        lang: lang,
        who: 'e1',
        tab: 1,
        core: (f) => f.edit = coverRow,
      );
      await frames(t);
      expect(
        find.textContaining(covering),
        findsOneWidget,
        reason: 'Timesheet row',
      );
      await finish(t);
    });
  }
}
