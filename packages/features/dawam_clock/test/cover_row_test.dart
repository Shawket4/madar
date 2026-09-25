// The cover proof (M-CV-1, M-CV-2): on the coverer's Timesheet a rejected
// cover looked exactly like a confirmed one, and Home's progress measured a
// 20-minute cover against the block's whole day ("8h 00m").
import 'package:design_system/design_system.dart';
import 'package:feature_dawam_clock/feature_dawam_clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

void main() {
  setUp(() {
    words = coreWord;
    tplIndex
      ..clear()
      ..['am'] = Tpl('am', 'b1', 'Morning', 'Morning', 8 * 60, 16 * 60);
  });

  Shift cover(String? status) =>
      Shift('cover|c1', 'me', 'am', DateTime(2026, 9, 25))
        ..coverOf = 'e4'
        ..coverStatus = status
        // The core gives a cover its own window: 10:40–11:00.
        ..start = 640
        ..end = 660;

  test('a rejected cover reads "Not confirmed", a pending one waits', () {
    final rejected = coverStatus(cover('rejected'))!;
    expect(rejected.label, coreWord('staff.cover_not_confirmed'));
    expect(rejected.tone, MadarTone.danger);
    expect(
      coverStatus(cover('pending'))!.label,
      coreWord('staff.cover_waiting'),
    );
    expect(coverStatus(cover('confirmed')), isNull, reason: 'the usual row');
    expect(
      coverStatus(Shift('me|2026-09-25|am', 'me', 'am', DateTime(2026, 9, 25))),
      isNull,
      reason: 'not a cover',
    );
  });
}
