// The Attendance page's screenshot matrix: the default state at every size
// in English light and Arabic dark, and every other state (loading, error,
// empty, the words opened, the picker, both dialogs) at desktop-en-light and
// phone-ar-light. Run with FDASH_SHOTS set to write the PNGs.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_kit/testing.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'attendance_support.dart';

/// Records with every kind of cell: badges, reasons, cover, late/early.
List<MockRow> richRows() => [
  recordRow(
    id: 'r-laila',
    employeeKey: 'laila',
    date: day(-1),
    status: 'late',
    workShiftName: 'Morning',
    inAt: cairo(day(-1), '07:22'),
    outAt: cairo(day(-1), '14:30'),
    inMethod: 'mobile_gps',
    outMethod: 'mobile_gps',
    late: 12,
    early: 30,
    worked: 428,
    scheduledStart: cairo(day(-1), '07:00'),
    scheduledEnd: cairo(day(-1), '15:00'),
    distance: 14,
  ),
  recordRow(
    id: 'r-omar',
    employeeKey: 'omar',
    date: day(-1),
    branchId: SeedIds.newCairo,
    workShiftName: 'Evening',
    inAt: cairo(day(-1), '15:00'),
    outAt: cairo(day(-1), '23:45'),
    inMethod: 'manager',
    outMethod: 'manager',
    worked: 525,
    overtime: 15,
    punchReason: 'Phone died on the way in, so the manager punched him in',
    outReason: 'Forgot to clock out',
  ),
  recordRow(
    id: 'r-mariam',
    employeeKey: 'mariam',
    date: day(-1),
    status: 'absent',
    workShiftId: TeamSeedIds.workShift('sabah', 'morning'),
    workShiftName: 'Morning',
  ),
  recordRow(
    id: 'r-youssef',
    employeeKey: 'youssef',
    date: day(-1),
    workShiftId: TeamSeedIds.workShift('sabah', 'morning'),
    workShiftName: 'Morning',
    inAt: cairo(day(-1), '06:56'),
    outAt: cairo(day(-1), '15:02'),
    inMethod: 'cover',
    outMethod: 'auto',
    worked: 486,
    coveredEmployeeId: emp('mariam'),
    coverStatus: 'pending',
  ),
  recordRow(
    id: 'r-hana',
    employeeKey: 'hana',
    date: day(-2),
    branchId: SeedIds.maadi,
    status: 'on_leave',
  ),
  recordRow(
    id: 'r-ali',
    employeeKey: 'ali',
    date: day(-2),
    branchId: SeedIds.heliopolis,
    status: 'half_day',
    workShiftName: 'Morning',
    inAt: cairo(day(-2), '07:01'),
    outAt: cairo(day(-2), '10:30'),
    inMethod: 'till',
    outMethod: 'correction',
    worked: 209,
    early: 270,
    scheduledEnd: cairo(day(-2), '15:00'),
  ),
];

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpAttendance(
          tester,
          size: size,
          locale: lang,
          dark: dark,
          edit: (db) => onlyRecords(db, richRows()),
        );
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    final tag = '${size.name} $lang';

    testWidgets('seeded week, $tag', (tester) async {
      final h = await pumpAttendance(tester, size: size, locale: lang);
      await shootPage(h, 'seeded');
    });

    testWidgets('loading, $tag', (tester) async {
      final s = attendanceServer();
      final list = s.server.hold('GET', listT);
      final summary = s.server.hold('GET', summaryT);
      final h = await pumpAttendance(tester, size: size, locale: lang, s: s);
      await h.shot('attendance/loading');
      list.release();
      summary.release();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final s = attendanceServer();
      s.server
        ..fail('GET', listT, MockResponse.error(500, 'boom'))
        ..fail('GET', summaryT, MockResponse.error(500, 'boom'));
      final h = await pumpAttendance(tester, size: size, locale: lang, s: s);
      await shootPage(h, 'failed');
    });

    testWidgets('empty, $tag', (tester) async {
      final h = await pumpAttendance(
        tester,
        size: size,
        locale: lang,
        edit: (db) => onlyRecords(db, []),
      );
      await shootPage(h, 'empty');
    });

    testWidgets('words open, $tag', (tester) async {
      final h = await pumpAttendance(tester, size: size, locale: lang);
      await h.tap(pageText(h.t('dawamOps.wordsTitle')));
      await h.shot('attendance/words');
    });

    testWidgets('employee picker, $tag', (tester) async {
      final h = await pumpAttendance(tester, size: size, locale: lang);
      await h.tap(pageText(h.t('dawamOps.everyone')));
      await h.shot('attendance/picker');
    });

    testWidgets('add record, $tag', (tester) async {
      final h = await pumpAttendance(tester, size: size, locale: lang);
      await h.tap(pageText(h.t('staff.addRecord')));
      await h.tap(inSurface(find.text(h.t('common.save'))).last);
      await h.shot('attendance/add');
    });

    testWidgets('add record covered, $tag', (tester) async {
      final h = await pumpAttendance(
        tester,
        size: size,
        locale: lang,
        edit: (db) => db['employees']
            .where(
              (e) =>
                  e['org_id'] == SeedIds.sabahOrg && e['id'] != emp('mariam'),
            )
            .forEach((e) => e['employment_status'] = 'suspended'),
      );
      await h.tap(pageText(h.t('staff.addRecord')));
      await h.tap(inSurface(find.text(h.t('staff.pickEmployee'))).first);
      await h.tap(find.text('Mariam Fathy').last);
      await h.tap(inSurface(find.text(h.t('staff.unscheduled'))).first);
      await h.tap(find.text('Morning').last);
      await h.tap(
        find
            .descendant(of: surface(), matching: find.byType(DashDateField))
            .first,
      );
      await h.tap(find.text('7').last);
      await h.shot('attendance/add-covered');
    });

    testWidgets('correct record, $tag', (tester) async {
      final h = await pumpAttendance(
        tester,
        size: size,
        locale: lang,
        edit: (db) => onlyRecords(db, richRows()),
      );
      await h.tap(inPage(find.bySemanticsLabel(h.t('staff.correct'))).first);
      await h.shot('attendance/correct');
    });
  }
}
