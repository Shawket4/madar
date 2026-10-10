/// The team (Dawam) area's own domain data, shared by every team unit so
/// their numbers agree: the Team board's "In" count, the Attendance table,
/// the Approvals lists, Payroll and the Reports all read the same records.
///
/// Built from the core seed (`package:dashboard_api/mock.dart`): its two orgs
/// (Sabah Coffee with POS + Dawam, Nakhla Bakery with Dawam only), branches,
/// employees, the Morning (07:00–15:00) and Evening (15:00–23:00) work shifts
/// and the attendance rules, around the mock clock's "now" (Thursday
/// 8 October 2026, 10:00 in Cairo). Deterministic: the same rows on every
/// run, no lorem ipsum.
///
/// [TeamSeed.loadInto] adds these tables to a [MockDb] (each row a model's
/// `toJson()`, so it has the spec's exact shape) and files each employee
/// under a department. Units read them through [TeamTables] and may add
/// their own rows in their mock files.
///
/// | table ([TeamTables]) | rows |
/// |---|---|
/// | `departments` | [Department] (4 at Sabah, 2 at Nakhla) |
/// | `schedule_assignments` | [ScheduleAssignment]: the standing roster, one per working weekday |
/// | `attendance_records` | [AttendanceRecord]: the last 14 days + this morning |
/// | `attendance_flags` | [AttendanceFlag]: 2 open today, 1 handled |
/// | `leave_types` | `{id, org_id, name, annual_days, is_paid, is_active}`: the leave types requests and balances name (no endpoint lists them) |
/// | `staff_requests` | [StaffRequest]: pending, approved, rejected, cancelled |
/// | `salary_advances` | [SalaryAdvance] |
/// | `adjustments` | [Adjustment]: bonuses and deductions |
/// | `expense_advances` | [ExpenseAdvance] |
/// | `swaps` | [Swap] |
/// | `open_shifts` | [OpenShift] |
/// | `payroll_periods` | [PayrollPeriod]: August (closed) and September (paid) |
///
/// Rows of models that carry no `org_id` (flags, adjustments, expense
/// advances, swaps, open shifts) belong to their employee's (or branch's)
/// org: [TeamSeed.orgOfEmployee], [TeamSeed.orgOfBranch].
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';

/// The table names the team units share.
abstract final class TeamTables {
  static const String departments = 'departments';
  static const String assignments = 'schedule_assignments';
  static const String attendance = 'attendance_records';
  static const String flags = 'attendance_flags';
  static const String leaveTypes = 'leave_types';
  static const String requests = 'staff_requests';
  static const String advances = 'salary_advances';
  static const String adjustments = 'adjustments';
  static const String expenseAdvances = 'expense_advances';
  static const String swaps = 'swaps';
  static const String openShifts = 'open_shifts';
  static const String payrollPeriods = 'payroll_periods';

  /// Marks a [MockDb] the team seed was loaded into.
  static const String loaded = '_team_seed';
}

/// Stable ids of the team seed's rows.
abstract final class TeamSeedIds {
  static String department(String org, String key) =>
      mockUuid('department:$org:$key');

  static String workShift(String org, String key) =>
      mockUuid('work-shift:$org:$key');

  static String leaveType(String org, String key) =>
      mockUuid('leave-type:$org:$key');

  static String attendance(String employeeId, String date) =>
      mockUuid('attendance:$employeeId:$date');

  static String request(String key) => mockUuid('staff-request:$key');
  static String advance(String key) => mockUuid('salary-advance:$key');
  static String adjustment(String key) => mockUuid('adjustment:$key');
  static String expenseAdvance(String key) => mockUuid('expense-advance:$key');
  static String flag(String key) => mockUuid('attendance-flag:$key');
  static String swap(String key) => mockUuid('swap:$key');
  static String openShift(String key) => mockUuid('open-shift:$key');
  static String period(String org, String month) =>
      mockUuid('payroll-period:$org:$month');
}

/// One person's place on the standing roster.
class TeamRosterSlot {
  const TeamRosterSlot({
    required this.employee,
    required this.shiftKey,
    required this.dayOff,
  });

  final Employee employee;

  /// `morning` or `evening`.
  final String shiftKey;

  /// The weekly day off (DOW, 0 = Sunday … 6 = Saturday).
  final int dayOff;

  String get orgKey => employee.orgId == SeedIds.sabahOrg ? 'sabah' : 'nakhla';
  String get workShiftId => TeamSeedIds.workShift(orgKey, shiftKey);
  String get shiftName => shiftKey == 'morning' ? 'Morning' : 'Evening';
  String get branchId => employee.branchIds.first;

  /// `07:00` / `15:00`.
  String get start => shiftKey == 'morning' ? '07:00' : '15:00';
  String get end => shiftKey == 'morning' ? '15:00' : '23:00';
}

class TeamSeed {
  TeamSeed._();

  static final TeamSeed instance = TeamSeed._();

  final MockSeed core = MockSeed.instance;

  /// Thursday 8 October 2026, 07:00 UTC (10:00 in Cairo).
  static final DateTime now = MockSeed.now;

  /// `2026-10-08`.
  static final String today = MockClock.cairoDate(MockSeed.now);

  /// Days of attendance history before today.
  static const int historyDays = 14;

  /// The grace minutes of the seeded shifts (lateness counts after them).
  static const int graceMinutes = 10;

  static final DateTime _rosterSince = DateTime.utc(2026, 9, 1, 9);
  static final String _owner = SeedIds.owner;

  // ── people ────────────────────────────────────────────────────────────

  /// Everyone on payroll (the owners are not), both orgs.
  late final List<Employee> staff = [
    for (final e in core.employees)
      if (e.onPayroll) e,
  ];

  Employee employee(String key) =>
      core.employees.firstWhere((e) => e.id == SeedIds.employee(key));

  String orgOfEmployee(String employeeId) =>
      core.employees.firstWhere((e) => e.id == employeeId).orgId;

  String orgOfBranch(String branchId) => core.branchById(branchId).orgId;

  /// Managers and morning people open; the rest close. Day off: a person's
  /// "can't work" day, else spread over the week by their place in the list.
  late final List<TeamRosterSlot> roster = [
    for (final (i, e) in staff.indexed)
      TeamRosterSlot(
        employee: e,
        shiftKey: e.role == 'branch_manager' || e.prefTime == 'morning'
            ? 'morning'
            : 'evening',
        dayOff: e.cantWorkDays.isNotEmpty
            ? e.cantWorkDays.first
            : const [5, 1, 3, 0, 2, 4][i % 6],
      ),
  ];

  TeamRosterSlot slotOf(String employeeId) =>
      roster.firstWhere((s) => s.employee.id == employeeId);

  // ── departments ───────────────────────────────────────────────────────

  static String _departmentKey(Employee e) => switch (e.jobTitle) {
    'Branch manager' || 'Shift lead' => 'management',
    'Barista' => 'bar',
    'Cashier' || 'Waiter' => 'front',
    'Chef' => 'kitchen',
    'Head baker' || 'Baker' => 'bakery',
    _ => 'front',
  };

  static const Map<String, String> _departmentNames = {
    'management': 'Management',
    'bar': 'Bar',
    'front': 'Front of house',
    'kitchen': 'Kitchen',
    'bakery': 'Bakery',
  };

  /// Employee id → department id.
  late final Map<String, String> departmentOf = {
    for (final s in roster)
      s.employee.id: TeamSeedIds.department(
        s.orgKey,
        _departmentKey(s.employee),
      ),
  };

  late final List<Department> departments = [
    for (final (org, orgKey, keys, manager) in [
      (
        SeedIds.sabahOrg,
        'sabah',
        const ['management', 'bar', 'front', 'kitchen'],
        ('Nour El-Sayed', SeedIds.owner),
      ),
      (
        SeedIds.nakhlaOrg,
        'nakhla',
        const ['management', 'bakery', 'front'],
        ('Yasmin Ghali', SeedIds.dawamOwner),
      ),
    ])
      for (final key in keys)
        Department(
          id: TeamSeedIds.department(orgKey, key),
          orgId: org,
          name: orgKey == 'nakhla' && key == 'front'
              ? 'Counter'
              : _departmentNames[key]!,
          managerName: manager.$1,
          managerUserId: manager.$2,
          employeeCount: departmentOf.values
              .where((d) => d == TeamSeedIds.department(orgKey, key))
              .length,
          createdAt: _rosterSince,
          updatedAt: _rosterSince,
        ),
  ];

  // ── the standing roster ───────────────────────────────────────────────

  late final List<ScheduleAssignment> assignments = [
    for (final s in roster)
      for (final dow in const [6, 0, 1, 2, 3, 4, 5])
        if (dow != s.dayOff)
          ScheduleAssignment(
            id: mockUuid('assignment:${s.employee.id}:$dow'),
            orgId: s.employee.orgId,
            employeeId: s.employee.id,
            branchId: s.branchId,
            workShiftId: s.workShiftId,
            workShiftName: s.shiftName,
            dayOfWeek: dow,
            effectiveFrom: '2026-09-01',
            createdAt: _rosterSince,
          ),
  ];

  /// Whether [employeeId] is rostered on [date] (`yyyy-mm-dd`).
  bool works(String employeeId, String date) =>
      slotOf(employeeId).dayOff != _dow(date);

  // ── leave and requests ────────────────────────────────────────────────

  late final List<Map<String, Object?>> leaveTypes = [
    for (final (org, orgKey) in [
      (SeedIds.sabahOrg, 'sabah'),
      (SeedIds.nakhlaOrg, 'nakhla'),
    ])
      for (final (key, name, days, paid) in const [
        ('annual', 'Annual leave', 21, true),
        ('sick', 'Sick leave', 15, true),
        ('casual', 'Casual leave', 6, true),
      ])
        {
          'id': TeamSeedIds.leaveType(orgKey, key),
          'org_id': org,
          'name': name,
          'annual_days': days,
          'is_paid': paid,
          'is_active': true,
        },
  ];

  /// The first day from [from] on which [key] is rostered.
  String _workingDayFrom(String key, String from) {
    var d = from;
    while (!works(SeedIds.employee(key), d)) {
      d = _addDays(d, 1);
    }
    return d;
  }

  /// The day Hana Mostafa took off (approved annual leave): her attendance
  /// that day is "On leave".
  late final String hanaLeaveDay = _workingDayFrom('hana', '2026-10-01');

  late final List<StaffRequest> requests = () {
    StaffRequest req(
      String key,
      String person,
      String kind, {
      required String onDate,
      required String status,
      String? endDate,
      String? fromTime,
      String? toTime,
      String? leaveType,
      String? title,
      String? location,
      String? reason,
      bool isHalfDay = false,
      String? decisionNote,
      int askedDaysAgo = 2,
    }) {
      final e = employee(person);
      final orgKey = e.orgId == SeedIds.sabahOrg ? 'sabah' : 'nakhla';
      final asked = now.subtract(Duration(days: askedDaysAgo, hours: 3));
      final decided = status == 'approved' || status == 'rejected';
      final cancelled = status == 'cancelled';
      return StaffRequest(
        id: TeamSeedIds.request(key),
        orgId: e.orgId,
        employeeId: e.id,
        employeeName: e.name,
        kind: kind,
        status: status,
        onDate: onDate,
        endDate: endDate,
        fromTime: fromTime,
        toTime: toTime,
        isHalfDay: isHalfDay,
        leaveTypeId: leaveType == null
            ? null
            : TeamSeedIds.leaveType(orgKey, leaveType),
        leaveTypeName: switch (leaveType) {
          'annual' => 'Annual leave',
          'sick' => 'Sick leave',
          'casual' => 'Casual leave',
          _ => null,
        },
        isPaid: kind == 'leave' ? true : null,
        paidDefault: kind == 'leave' ? true : null,
        title: title,
        location: location,
        reason: reason,
        decidedAt: decided ? asked.add(const Duration(hours: 5)) : null,
        decidedBy: decided ? _owner : null,
        decidedByName: decided ? 'Nour El-Sayed' : null,
        decisionNote: decisionNote,
        cancelledAt: cancelled ? asked.add(const Duration(hours: 20)) : null,
        cancelledBy: cancelled ? e.userId : null,
        cancelledByName: cancelled ? e.name : null,
        monthClosed: onDate.compareTo('2026-10-01') < 0,
        createdAt: asked,
        updatedAt: asked,
      );
    }

    final omarOff = _workingDayFrom('omar', '2026-09-29');
    return [
      req(
        'salma-leave',
        'salma',
        'leave',
        onDate: '2026-10-12',
        endDate: '2026-10-13',
        leaveType: 'annual',
        status: 'pending',
        reason: "My sister's wedding in Alexandria.",
        askedDaysAgo: 1,
      ),
      req(
        'youssef-late',
        'youssef',
        'late_arrival',
        onDate: '2026-10-09',
        toTime: '08:30',
        status: 'pending',
        reason: 'Renewing my national ID at the civil registry first thing.',
        askedDaysAgo: 0,
      ),
      req(
        'tarek-mission',
        'tarek',
        'mission',
        onDate: today,
        endDate: today,
        fromTime: '10:00',
        toTime: '13:00',
        title: 'Supplier visit',
        location: 'El Obour wholesale market',
        status: 'pending',
        reason: 'Choosing next month’s coffee beans with the roaster.',
        askedDaysAgo: 1,
      ),
      req(
        'farida-excuse',
        'farida',
        'excuse',
        onDate: _addDays(today, -1),
        fromTime: '12:00',
        toTime: '13:00',
        status: 'pending',
        reason: "Doctor's appointment.",
        askedDaysAgo: 2,
      ),
      req(
        'hana-leave',
        'hana',
        'leave',
        onDate: hanaLeaveDay,
        endDate: hanaLeaveDay,
        leaveType: 'annual',
        status: 'approved',
        reason: 'Family visit in Tanta.',
        askedDaysAgo: 12,
      ),
      req(
        'omar-early',
        'omar',
        'early_departure',
        onDate: omarOff,
        fromTime: '13:00',
        status: 'rejected',
        reason: 'Football match.',
        decisionNote: 'Two of us are already off that afternoon.',
        askedDaysAgo: 10,
      ),
      req(
        'ziad-leave',
        'ziad',
        'leave',
        onDate: '2026-10-15',
        endDate: '2026-10-15',
        leaveType: 'casual',
        status: 'cancelled',
        reason: 'Moving flats.',
        askedDaysAgo: 4,
      ),
      req(
        'malak-sick',
        'malak',
        'leave',
        onDate: '2026-10-11',
        endDate: '2026-10-11',
        leaveType: 'sick',
        status: 'pending',
        reason: 'Dentist: a wisdom tooth out.',
        askedDaysAgo: 0,
      ),
    ];
  }();

  // ── attendance ────────────────────────────────────────────────────────

  /// Yesterday Youssef covered Mariam's morning (the cover waits for a
  /// manager); Mariam has no record that day.
  late final String _yesterday = _addDays(today, -1);

  late final List<AttendanceRecord> attendance = () {
    final out = <AttendanceRecord>[];
    final mariam = SeedIds.employee('mariam');
    final youssef = SeedIds.employee('youssef');
    for (final s in roster) {
      final e = s.employee;
      for (var back = historyDays; back >= 0; back--) {
        final date = _addDays(today, -back);
        if (!works(e.id, date)) continue;
        final isToday = back == 0;
        // This morning only the morning shift has started.
        if (isToday && s.shiftKey != 'morning') continue;
        if (e.id == mariam && date == _yesterday) continue;
        final rec = _record(
          s,
          date,
          isToday: isToday,
          onLeave: e.id == SeedIds.employee('hana') && date == hanaLeaveDay,
        );
        if (rec != null) out.add(rec);
      }
    }
    // Youssef's cover of Mariam's morning, yesterday.
    final y = slotOf(youssef);
    final start = _at(_yesterday, '07:00');
    out.add(
      AttendanceRecord(
        id: TeamSeedIds.attendance(youssef, '$_yesterday:cover'),
        orgId: SeedIds.sabahOrg,
        branchId: y.branchId,
        employeeId: youssef,
        employeeName: y.employee.name,
        businessDate: _yesterday,
        workShiftId: TeamSeedIds.workShift('sabah', 'morning'),
        workShiftName: 'Morning',
        scheduledStartAt: start,
        scheduledEndAt: _at(_yesterday, '15:00'),
        checkInAt: start.subtract(const Duration(minutes: 4)),
        checkOutAt: _at(_yesterday, '15:02'),
        checkInMethod: 'mobile_gps',
        checkOutMethod: 'mobile_gps',
        checkInDistanceMeters: 12,
        checkOutDistanceMeters: 18,
        status: 'present',
        lateMinutes: 0,
        earlyLeaveMinutes: 0,
        overtimeMinutes: 0,
        workedMinutes: 486,
        isManual: false,
        trackingOff: false,
        monthClosed: false,
        coveredEmployeeId: mariam,
        coverStatus: 'pending',
        createdAt: start,
        updatedAt: _at(_yesterday, '15:02'),
      ),
    );
    return out;
  }();

  AttendanceRecord? _record(
    TeamRosterSlot s,
    String date, {
    required bool isToday,
    required bool onLeave,
  }) {
    final e = s.employee;
    final r = MockRandom('team:attendance:${e.id}:$date');
    final roll = r.nextDouble();
    final branch = core.branchById(s.branchId);
    final start = _at(date, s.start);
    final end = _at(date, s.end);
    final base = AttendanceRecord(
      id: TeamSeedIds.attendance(e.id, date),
      orgId: e.orgId,
      branchId: s.branchId,
      employeeId: e.id,
      employeeName: e.name,
      businessDate: date,
      workShiftId: s.workShiftId,
      workShiftName: s.shiftName,
      scheduledStartAt: start,
      scheduledEndAt: end,
      status: 'present',
      lateMinutes: 0,
      earlyLeaveMinutes: 0,
      overtimeMinutes: 0,
      workedMinutes: 0,
      isManual: false,
      trackingOff: false,
      monthClosed: date.compareTo('2026-10-01') < 0,
      createdAt: start,
      updatedAt: start,
    );
    if (onLeave) {
      return _copy(base, status: 'on_leave', updatedAt: start);
    }
    if (isToday) {
      // Not in yet: nothing is recorded until a punch.
      if (roll < 0.12) return null;
      final late = roll < 0.3;
      final inAt = start.add(
        Duration(minutes: late ? r.range(16, 42) : r.range(-12, 6)),
      );
      final lateBy = inAt.difference(start).inMinutes;
      return _copy(
        base,
        status: late ? 'late' : 'present',
        lateMinutes: late ? lateBy : 0,
        checkInAt: inAt,
        checkInMethod: 'mobile_gps',
        checkInDistanceMeters: r.range(4, 60).toDouble(),
        checkInLatitude: _jitter(branch.latitude, r),
        checkInLongitude: _jitter(branch.longitude, r),
        updatedAt: inAt,
      );
    }
    if (roll < 0.05) {
      return _copy(base, status: 'absent', updatedAt: end);
    }
    final late = roll < 0.17;
    final manual = !late && roll > 0.96;
    final inAt = start.add(
      Duration(minutes: late ? r.range(16, 48) : r.range(-12, 6)),
    );
    final lateBy = inAt.difference(start).inMinutes;
    final shape = r.nextDouble();
    final overtime = shape < 0.12;
    final early = !overtime && shape > 0.95;
    final outAt = end.add(
      Duration(
        minutes: overtime
            ? r.range(35, 75)
            : early
            ? -r.range(20, 50)
            : r.range(-3, 12),
      ),
    );
    final worked = outAt.difference(inAt).inMinutes;
    final pastEnd = outAt.difference(end).inMinutes;
    final daysAgo = _date(today).difference(_date(date)).inDays;
    return _copy(
      base,
      status: late ? 'late' : 'present',
      lateMinutes: late ? lateBy : 0,
      earlyLeaveMinutes: early ? -pastEnd : 0,
      overtimeMinutes: overtime ? pastEnd : 0,
      overtimeStatus: overtime ? (daysAgo <= 3 ? 'pending' : 'approved') : null,
      workedMinutes: worked,
      checkInAt: inAt,
      checkOutAt: outAt,
      checkInMethod: manual ? 'manual' : 'mobile_gps',
      checkOutMethod: manual ? 'manual' : 'mobile_gps',
      checkInDistanceMeters: manual ? null : r.range(4, 85).toDouble(),
      checkOutDistanceMeters: manual ? null : r.range(4, 85).toDouble(),
      checkInLatitude: manual ? null : _jitter(branch.latitude, r),
      checkInLongitude: manual ? null : _jitter(branch.longitude, r),
      isManual: manual,
      notes: manual ? 'Phone battery died; the manager punched them in.' : null,
      createdBy: manual ? _owner : null,
      updatedAt: outAt,
    );
  }

  AttendanceRecord _copy(
    AttendanceRecord b, {
    String? status,
    int? lateMinutes,
    int? earlyLeaveMinutes,
    int? overtimeMinutes,
    String? overtimeStatus,
    int? workedMinutes,
    DateTime? checkInAt,
    DateTime? checkOutAt,
    String? checkInMethod,
    String? checkOutMethod,
    double? checkInDistanceMeters,
    double? checkOutDistanceMeters,
    double? checkInLatitude,
    double? checkInLongitude,
    bool? isManual,
    String? notes,
    String? createdBy,
    required DateTime updatedAt,
  }) => AttendanceRecord(
    id: b.id,
    orgId: b.orgId,
    branchId: b.branchId,
    employeeId: b.employeeId,
    employeeName: b.employeeName,
    businessDate: b.businessDate,
    workShiftId: b.workShiftId,
    workShiftName: b.workShiftName,
    scheduledStartAt: b.scheduledStartAt,
    scheduledEndAt: b.scheduledEndAt,
    status: status ?? b.status,
    lateMinutes: lateMinutes ?? b.lateMinutes,
    earlyLeaveMinutes: earlyLeaveMinutes ?? b.earlyLeaveMinutes,
    overtimeMinutes: overtimeMinutes ?? b.overtimeMinutes,
    overtimeStatus: overtimeStatus,
    workedMinutes: workedMinutes ?? b.workedMinutes,
    checkInAt: checkInAt,
    checkOutAt: checkOutAt,
    checkInMethod: checkInMethod,
    checkOutMethod: checkOutMethod,
    checkInDistanceMeters: checkInDistanceMeters,
    checkOutDistanceMeters: checkOutDistanceMeters,
    checkInLatitude: checkInLatitude,
    checkInLongitude: checkInLongitude,
    isManual: isManual ?? b.isManual,
    notes: notes,
    createdBy: createdBy,
    trackingOff: b.trackingOff,
    monthClosed: b.monthClosed,
    createdAt: b.createdAt,
    updatedAt: updatedAt,
  );

  /// Today's records (the morning shift so far).
  late final List<AttendanceRecord> todayRecords = [
    for (final a in attendance)
      if (a.businessDate == today) a,
  ];

  // ── flags ─────────────────────────────────────────────────────────────

  late final List<AttendanceFlag> flags = () {
    // Two open flags on this morning's Sabah records; one handled last week.
    final open = [
      for (final a in todayRecords)
        if (a.orgId == SeedIds.sabahOrg && a.checkInAt != null) a,
    ];
    final out = <AttendanceFlag>[];
    if (open.isNotEmpty) {
      final a = open.first;
      final salary = core.employees
          .firstWhere((e) => e.id == a.employeeId)
          .baseSalaryPiastres;
      // 25 minutes of pay: salary / (26 working days × 480 minutes) × 25.
      final suggested = salary == null ? 0 : (salary * 25 / (26 * 480)).round();
      out.add(
        AttendanceFlag(
          id: TeamSeedIds.flag('left-mid-shift'),
          employeeId: a.employeeId,
          employeeName: a.employeeName ?? '',
          branchId: a.branchId,
          attendanceRecordId: a.id,
          kind: 'left_mid_shift',
          minutesAway: 25,
          detectedAt: now.subtract(const Duration(minutes: 40)),
          suggestedDeductionPiastres: suggested,
        ),
      );
    }
    if (open.length > 1) {
      final a = open[1];
      out.add(
        AttendanceFlag(
          id: TeamSeedIds.flag('new-phone'),
          employeeId: a.employeeId,
          employeeName: a.employeeName ?? '',
          branchId: a.branchId,
          attendanceRecordId: a.id,
          kind: 'new_phone',
          minutesAway: 0,
          detectedAt: a.checkInAt!,
          suggestedDeductionPiastres: 0,
        ),
      );
    }
    final hana = SeedIds.employee('hana');
    out.add(
      AttendanceFlag(
        id: TeamSeedIds.flag('tracking-off'),
        employeeId: hana,
        employeeName: 'Hana Mostafa',
        branchId: SeedIds.maadi,
        kind: 'tracking_off',
        minutesAway: 0,
        detectedAt: now.subtract(const Duration(days: 2, hours: 2)),
        resolution: 'ignored',
        resolvedAt: now.subtract(const Duration(days: 2)),
        suggestedDeductionPiastres: 0,
      ),
    );
    return out;
  }();

  // ── money ─────────────────────────────────────────────────────────────

  int _salary(String key) => employee(key).baseSalaryPiastres ?? 0;

  /// Half a month's salary (the rules' `advance_cap_percent` is 50).
  int capOf(String key) => _salary(key) * 50 ~/ 100;

  late final List<SalaryAdvance> advances = () {
    SalaryAdvance adv(
      String key,
      String person, {
      required int egp,
      required int installments,
      required String status,
      int paidInstallments = 0,
      String? reason,
      String? note,
      int daysAgo = 3,
    }) {
      final e = employee(person);
      final amount = egp * 100;
      final monthly = amount ~/ installments;
      final remaining = status == 'approved'
          ? amount - monthly * paidInstallments
          : status == 'settled'
          ? 0
          : amount;
      final at = now.subtract(Duration(days: daysAgo, hours: 2));
      final decided = status != 'pending';
      final outstanding = status == 'approved' ? remaining : 0;
      return SalaryAdvance(
        id: TeamSeedIds.advance(key),
        orgId: e.orgId,
        employeeId: e.id,
        employeeName: e.name,
        amountPiastres: amount,
        installments: installments,
        monthlyInstallmentPiastres: monthly,
        remainingPiastres: remaining,
        outstandingPiastres: outstanding,
        capPiastres: capOf(person),
        withinCap: outstanding + (decided ? 0 : amount) <= capOf(person),
        status: status,
        reason: reason,
        decisionNote: note,
        decidedAt: decided ? at.add(const Duration(hours: 4)) : null,
        decidedBy: decided ? _owner : null,
        createdAt: at,
        updatedAt: at,
      );
    }

    return [
      adv(
        'omar',
        'omar',
        egp: 3000,
        installments: 3,
        status: 'pending',
        reason: "My mother's eye operation.",
        daysAgo: 1,
      ),
      adv(
        'ziad',
        'ziad',
        egp: 6000,
        installments: 6,
        status: 'pending',
        reason: 'Deposit on a new flat.',
        daysAgo: 2,
      ),
      adv(
        'mariam',
        'mariam',
        egp: 4000,
        installments: 4,
        status: 'approved',
        paidInstallments: 1,
        reason: 'School fees.',
        daysAgo: 40,
      ),
      adv(
        'ali',
        'ali',
        egp: 2000,
        installments: 2,
        status: 'settled',
        reason: 'Laptop repair.',
        daysAgo: 75,
      ),
      adv(
        'seif',
        'seif',
        egp: 1500,
        installments: 3,
        status: 'pending',
        reason: 'Wedding gift for my brother.',
        daysAgo: 1,
      ),
    ];
  }();

  /// [tierPiastres] for a "minutes of pay" rung: salary × minutes /
  /// (26 working days × a 480-minute shift).
  static int minutesOfPay(int salaryPiastres, int minutes) =>
      (salaryPiastres * minutes / (26 * 480)).round();

  /// A day-fraction rung: salary × fraction / 26.
  static int dayFractionOfPay(int salaryPiastres, double fraction) =>
      (salaryPiastres * fraction / 26).round();

  /// The late-arrival deduction the seeded ladder charges for [lateMinutes]
  /// (15–30 → 30 minutes of pay, 30–60 → a quarter day, 60+ → half a day);
  /// 0 under 15.
  static int lateDeduction(int salaryPiastres, int lateMinutes) {
    if (lateMinutes < 15) return 0;
    if (lateMinutes <= 30) return minutesOfPay(salaryPiastres, 30);
    if (lateMinutes <= 60) return dayFractionOfPay(salaryPiastres, 0.25);
    return dayFractionOfPay(salaryPiastres, 0.5);
  }

  late final List<Adjustment> adjustments = () {
    final out = <Adjustment>[];
    // The rules' late penalties for this month's late arrivals (Sabah).
    for (final a in attendance) {
      if (a.status != 'late' || a.orgId != SeedIds.sabahOrg) continue;
      if (a.businessDate.compareTo('2026-10-01') < 0) continue;
      if (a.businessDate == today) continue;
      final salary = core.employees
          .firstWhere((e) => e.id == a.employeeId)
          .baseSalaryPiastres;
      if (salary == null) continue;
      final value = lateDeduction(salary, a.lateMinutes);
      if (value == 0) continue;
      out.add(
        Adjustment(
          id: TeamSeedIds.adjustment('late:${a.id}'),
          kind: 'deduction',
          source: 'late_penalty',
          status: 'approved',
          employeeId: a.employeeId,
          employeeName: a.employeeName ?? '',
          effectiveDate: a.businessDate,
          valuePiastres: value,
          amountPiastres: value,
          reason: 'Late by ${a.lateMinutes} minutes',
          reasonCode: 'late',
          reasonVars: {'minutes': a.lateMinutes},
          recurring: false,
          createdAt: a.checkOutAt ?? a.updatedAt,
        ),
      );
    }
    Adjustment line(
      String key,
      String person,
      String kind, {
      required int egp,
      required String status,
      required String source,
      required String reason,
      String effective = '2026-10-01',
      int daysAgo = 2,
    }) {
      final e = employee(person);
      final at = now.subtract(Duration(days: daysAgo, hours: 1));
      final decided = status != 'pending';
      return Adjustment(
        id: TeamSeedIds.adjustment(key),
        kind: kind,
        source: source,
        status: status,
        employeeId: e.id,
        employeeName: e.name,
        effectiveDate: effective,
        valuePiastres: egp * 100,
        amountPiastres: egp * 100,
        reason: reason,
        recurring: false,
        createdBy: SeedIds.manager,
        decidedAt: decided ? at.add(const Duration(hours: 3)) : null,
        decidedBy: decided ? _owner : null,
        createdAt: at,
      );
    }

    out.addAll([
      line(
        'hassan-bonus',
        'hassan',
        'bonus',
        egp: 1500,
        status: 'pending',
        source: 'manual',
        reason: 'Kept the kitchen running through the AC repair week.',
        daysAgo: 1,
      ),
      line(
        'salma-bonus',
        'salma',
        'bonus',
        egp: 500,
        status: 'approved',
        source: 'performance',
        reason: 'Best mystery-shopper score in September.',
        daysAgo: 6,
      ),
      line(
        'laila-cups',
        'laila',
        'deduction',
        egp: 250,
        status: 'approved',
        source: 'manual',
        reason: 'Two broken espresso cups.',
        daysAgo: 4,
      ),
      line(
        'reem-bonus',
        'reem',
        'bonus',
        egp: 800,
        status: 'pending',
        source: 'manual',
        reason: 'Trained the two new bakers.',
        daysAgo: 0,
      ),
    ]);
    return out;
  }();

  late final List<ExpenseAdvance> expenseAdvances = [
    ExpenseAdvance(
      id: TeamSeedIds.expenseAdvance('karim-milk'),
      employeeId: SeedIds.employee('karim'),
      employeeName: 'Karim Adel',
      branchId: SeedIds.zamalek,
      amountPiastres: 120000,
      purpose: 'Milk and ice from the market (supplier late)',
      via: 'till',
      givenOn: _addDays(today, -2),
      handedBy: _owner,
      handedByName: 'Nour El-Sayed',
      createdAt: now.subtract(const Duration(days: 2, hours: 2)),
    ),
    ExpenseAdvance(
      id: TeamSeedIds.expenseAdvance('dina-plumber'),
      employeeId: SeedIds.employee('dina'),
      employeeName: 'Dina Fouad',
      branchId: SeedIds.newCairo,
      amountPiastres: 65000,
      purpose: 'Plumber for the bar sink',
      via: 'safe',
      givenOn: _addDays(today, -5),
      handedBy: _owner,
      handedByName: 'Nour El-Sayed',
      createdAt: now.subtract(const Duration(days: 5, hours: 1)),
    ),
    ExpenseAdvance(
      id: TeamSeedIds.expenseAdvance('reem-flour'),
      employeeId: SeedIds.employee('reem'),
      employeeName: 'Reem Mostafa',
      branchId: SeedIds.nasrCity,
      amountPiastres: 90000,
      purpose: 'Two sacks of flour when the delivery was short',
      via: 'bank',
      givenOn: _addDays(today, -3),
      handedBy: SeedIds.dawamOwner,
      handedByName: 'Yasmin Ghali',
      createdAt: now.subtract(const Duration(days: 3, hours: 4)),
    ),
  ];

  // ── swaps and open shifts ─────────────────────────────────────────────

  late final List<Swap> swaps = () {
    Swap swap(String key, String a, String b, String date, String status) {
      final sa = slotOf(SeedIds.employee(a));
      final sb = slotOf(SeedIds.employee(b));
      return Swap(
        id: TeamSeedIds.swap(key),
        requesterId: sa.employee.id,
        requesterName: sa.employee.name,
        requesterDate: date,
        requesterShiftId: sa.workShiftId,
        requesterShiftName: sa.shiftName,
        peerId: sb.employee.id,
        peerName: sb.employee.name,
        peerDate: date,
        peerShiftId: sb.workShiftId,
        peerShiftName: sb.shiftName,
        status: status,
        createdAt: now.subtract(const Duration(hours: 20)),
      );
    }

    return [
      swap(
        'salma-omar',
        'salma',
        'omar',
        _workingDayFrom('salma', '2026-10-10'),
        'pending',
      ),
      swap(
        'hana-ziad',
        'hana',
        'ziad',
        _workingDayFrom('hana', '2026-10-11'),
        'awaiting_peer',
      ),
    ];
  }();

  late final List<OpenShift> openShifts = [
    OpenShift(
      id: TeamSeedIds.openShift('zamalek-evening'),
      branchId: SeedIds.zamalek,
      workShiftId: TeamSeedIds.workShift('sabah', 'evening'),
      shiftName: 'Evening',
      onDate: '2026-10-10',
      startAt: _at('2026-10-10', '15:00'),
      endAt: _at('2026-10-10', '23:00'),
      status: 'open',
    ),
    OpenShift(
      id: TeamSeedIds.openShift('zamalek-morning'),
      branchId: SeedIds.zamalek,
      workShiftId: TeamSeedIds.workShift('sabah', 'morning'),
      shiftName: 'Morning',
      onDate: '2026-10-11',
      startAt: _at('2026-10-11', '07:00'),
      endAt: _at('2026-10-11', '15:00'),
      status: 'claimed',
      claimedBy: SeedIds.employee('laila'),
      claimedByName: 'Laila Ehab',
      claimedAt: now.subtract(const Duration(hours: 5)),
    ),
  ];

  // ── payroll periods ───────────────────────────────────────────────────

  /// The full-month salaries of [org]'s payroll people hired by [end].
  int _monthPayroll(String org, String end) => [
    for (final s in roster)
      if (s.employee.orgId == org &&
          (s.employee.hireDate ?? '').compareTo(end) <= 0)
        s.employee.baseSalaryPiastres ?? 0,
  ].fold(0, (a, b) => a + b);

  int _headcount(String org, String end) => roster
      .where(
        (s) =>
            s.employee.orgId == org &&
            (s.employee.hireDate ?? '').compareTo(end) <= 0,
      )
      .length;

  late final List<PayrollPeriod> payrollPeriods = [
    for (final (org, orgKey) in [
      (SeedIds.sabahOrg, 'sabah'),
      (SeedIds.nakhlaOrg, 'nakhla'),
    ]) ...[
      PayrollPeriod(
        id: TeamSeedIds.period(orgKey, '2026-08'),
        orgId: org,
        name: 'August 2026',
        startDate: '2026-08-01',
        endDate: '2026-08-31',
        status: 'closed',
        employeeCount: _headcount(org, '2026-08-31'),
        totalNetPiastres: _monthPayroll(org, '2026-08-31'),
        generatedAt: DateTime.utc(2026, 9, 1, 8),
        generatedBy: org == SeedIds.sabahOrg ? _owner : SeedIds.dawamOwner,
        paidAt: DateTime.utc(2026, 9, 2, 10),
        closedAt: DateTime.utc(2026, 9, 10, 9),
        createdAt: DateTime.utc(2026, 8, 1, 6),
        updatedAt: DateTime.utc(2026, 9, 10, 9),
      ),
      PayrollPeriod(
        id: TeamSeedIds.period(orgKey, '2026-09'),
        orgId: org,
        name: 'September 2026',
        startDate: '2026-09-01',
        endDate: '2026-09-30',
        status: 'paid',
        employeeCount: _headcount(org, '2026-09-30'),
        totalNetPiastres: _monthPayroll(org, '2026-09-30'),
        generatedAt: DateTime.utc(2026, 10, 1, 8),
        generatedBy: org == SeedIds.sabahOrg ? _owner : SeedIds.dawamOwner,
        paidAt: DateTime.utc(2026, 10, 2, 10),
        createdAt: DateTime.utc(2026, 9, 1, 6),
        updatedAt: DateTime.utc(2026, 10, 2, 10),
      ),
    ],
  ];

  // ── loading ───────────────────────────────────────────────────────────

  /// Copies the team seed into [db] (once per db) and files every employee
  /// row under its department.
  static void loadInto(MockDb db) {
    if (db.hasTable(TeamTables.loaded)) return;
    db.table(TeamTables.loaded);
    final s = instance;
    void put(String table, Iterable<Map<String, Object?>> rows) =>
        db.table(table).insertAll(rows, timestamps: false);
    put(TeamTables.departments, s.departments.map((o) => o.toJson()));
    put(TeamTables.assignments, s.assignments.map((o) => o.toJson()));
    put(TeamTables.attendance, s.attendance.map((o) => o.toJson()));
    put(TeamTables.flags, s.flags.map((o) => o.toJson()));
    put(TeamTables.leaveTypes, s.leaveTypes);
    put(TeamTables.requests, s.requests.map((o) => o.toJson()));
    put(TeamTables.advances, s.advances.map((o) => o.toJson()));
    put(TeamTables.adjustments, s.adjustments.map((o) => o.toJson()));
    put(TeamTables.expenseAdvances, s.expenseAdvances.map((o) => o.toJson()));
    put(TeamTables.swaps, s.swaps.map((o) => o.toJson()));
    put(TeamTables.openShifts, s.openShifts.map((o) => o.toJson()));
    put(TeamTables.payrollPeriods, s.payrollPeriods.map((o) => o.toJson()));
    final names = {for (final d in s.departments) d.id: d.name};
    for (final e in db['employees'].rows) {
      final dep = s.departmentOf[e['id']];
      if (dep == null) continue;
      e['department_id'] = dep;
      e['department_name'] = names[dep];
    }
  }

  // ── dates ─────────────────────────────────────────────────────────────

  /// A calendar date as a UTC midnight (never through a zone).
  static DateTime _date(String iso) {
    final p = iso.split('-').map(int.parse).toList();
    return DateTime.utc(p[0], p[1], p[2]);
  }

  static int _dow(String iso) => _date(iso).weekday % 7;

  static String _addDays(String iso, int n) {
    final d = _date(iso).add(Duration(days: n));
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// [date] at Cairo wall-clock [hhmm], as a UTC instant.
  static DateTime _at(String date, String hhmm) {
    final d = _date(date);
    final t = hhmm.split(':').map(int.parse).toList();
    return MockClock.fromCairo(d.year, d.month, d.day, t[0], t[1]);
  }

  static double? _jitter(double? v, MockRandom r) =>
      v == null ? null : v + (r.nextDouble() - 0.5) * 0.0008;
}
