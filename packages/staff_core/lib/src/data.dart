// Dawam's whole world, in memory. No madar-core, no MadarRust: every figure
// below is computed here from the mock seed so each workflow in the Dawam
// Target Spec can be walked end to end. The IDs in comments (PAY-12, CV-5…)
// point at that spec.
//
// This class stands where the staff bridge (`rust_bridge_staff`) will: each
// method below becomes a core call once the staff API is wired. Screens reach
// it through `dawamProvider` and never keep its data themselves.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Templates by id, outside the store so a [Shift] can resolve its own while
/// the store is still seeding.
final tplIndex = <String, Tpl>{};

enum Role { employee, manager, owner }

enum Method { app, offline, manager, till, kiosk, auto, correction, cover }

enum FlagKind {
  leftMidShift,
  suspicious,
  trackingOff,
  timeUnverified,
  newPhone,
  cover,
}

enum ReqKind {
  leave,
  lateArrival,
  earlyDeparture,
  excuse,
  mission,
  correction,
  salaryAdvance,
  cover,
  swap,
  openShift,
  overtime,
}

enum ReqStatus { awaitingPeer, pending, approved, rejected, cancelled }

enum PeriodStatus { open, approved, paid }

enum PayMethod { cash, bank, wallet }

enum OvertimeMode { off, automatic, approval }

enum RungKind { minutesPay, flat, dayFraction }

/// Content that arrives in both languages — people's and branches' names,
/// and what the server words itself. UI chrome is NOT this: it comes from the
/// core's i18n table (`tr`).
abstract interface class Bilingual {
  String get en;
  String get ar;
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime weekStart(DateTime d) {
  final x = dateOnly(d);
  return x.subtract(Duration(days: (x.weekday - DateTime.saturday) % 7));
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Suggested amounts round to the nearest 5 EGP (RU-12). Stored amounts stay exact.
int round5(int minor) => (minor / 500).round() * 500;

/// Multiply before dividing; round half away from zero (RU-6).
int mulDiv(int a, int b, int c) => c == 0 ? 0 : (a * b / c).round();

class Branch implements Bilingual {
  Branch(this.id, this.en, this.ar, this.radius);
  final String id;
  @override
  final String en;
  @override
  final String ar;
  int radius;
}

class Tpl implements Bilingual {
  Tpl(
    this.id,
    this.branch,
    this.en,
    this.ar,
    this.start,
    this.end, {
    this.grace = 10,
    this.window = 30,
  });
  final String id;
  final String branch;
  @override
  final String en;
  @override
  final String ar;
  final int start;
  final int end; // minutes of the day; end < start crosses midnight
  int grace;
  int window;
  int get length {
    final l = (end - start) % 1440;
    return l == 0 ? 1440 : l;
  }

  bool get night => end <= start || start >= 22 * 60;
}

class Emp implements Bilingual {
  Emp(
    this.id,
    this.en,
    this.ar,
    this.phone,
    this.role,
    this.branches,
    this.salary,
    this.gender,
    this.hired,
    this.pay, {
    this.account = '',
    this.device = 'iPhone 14',
  });
  final String id;
  @override
  final String en;
  @override
  final String ar;
  final String phone;
  Role role;
  List<String> branches;
  int salary; // piastres per month
  String gender;
  DateTime hired;
  PayMethod pay;
  String account;
  String device;
  DateTime deviceSince = DateTime(2026, 3, 2);
  String? prefTime; // 'morning' | 'evening'
  Set<int> cantWork = {};
  Map<int, List<String>> pattern = {}; // weekday -> template ids (SC-2)
}

class Shift {
  Shift(this.id, this.emp, this.tpl, this.date);
  final String id;
  String? emp; // null = an open shift (SC-9)
  String tpl;
  final DateTime date; // the day it STARTS (SC-10)
  bool changed = false;
  String? coverBy;
  DateTime? inAt;
  DateTime? outAt;
  Method? inMethod;
  Method? outMethod;
  String? punchReason;
  String? leave; // 'paid' | 'unpaid'
  bool halfLeave = false;
  bool mission = false;
  int? lateUntil; // minute of day agreed by an approved late arrival
  int? earlyFrom;
  int excuseMin = 0;
  bool excusePaid = false;
  bool trackingOff = false;
  bool timeUnverified = false;

  Tpl get template => tplIndex[tpl]!;
  DateTime get startAt => date.add(Duration(minutes: template.start));
  DateTime get endAt => startAt.add(Duration(minutes: template.length));
  bool get covered => coverBy != null;
}

class Flag {
  Flag(
    this.id,
    this.kind,
    this.emp,
    this.at, {
    this.shift,
    this.minutesAway = 0,
  });
  final String id;
  final FlagKind kind;
  final String emp;
  final String? shift;
  final DateTime at;
  final int minutesAway;
  String? resolution; // text shown once handled
  int deducted = 0;
  bool get open => resolution == null;
}

class Req {
  Req(
    this.id,
    this.kind,
    this.emp,
    this.created, {
    this.status = ReqStatus.pending,
  });
  final String id;
  final ReqKind kind;
  final String emp;
  final DateTime created;
  ReqStatus status;
  DateTime? from;
  DateTime? to;
  bool half = false;
  int? time;
  int? time2; // minutes of day
  String note = '';
  int amount = 0;
  bool? paid;
  String? shift;
  String? shift2;
  String? peer;
  int installments = 1;
  int minutes = 0;
  bool toOwner = false;
  String? decidedBy;
  String? decisionNote;
}

class Adj {
  Adj(
    this.id,
    this.emp,
    this.amount,
    this.reason,
    this.by,
    this.at,
    this.period, {
    required this.bonus,
    this.pct,
    this.recurring = false,
    this.status = 'active',
  });
  final String id;
  final String emp;
  final String reason;
  final String by;
  final bool bonus;
  final bool recurring;
  final int amount;
  final double? pct;
  final DateTime at;
  final DateTime period; // period start it lands in (or starts from)
  String status; // active | pendingOwner | rejected | deleted | stopped
  int value(Emp e) =>
      pct != null ? mulDiv(e.salary, (pct! * 100).round(), 10000) : amount;
}

class Advance {
  Advance(
    this.id,
    this.emp,
    this.amount,
    this.installments,
    this.date,
    this.by,
  );
  final String id;
  final String emp;
  final String by;
  final int amount;
  final int installments;
  final DateTime date;
  int collected = 0;
  int get outstanding => amount - collected;
  int get installment => (amount / installments).ceil();
}

class Expense {
  Expense(
    this.id,
    this.emp,
    this.amount,
    this.date,
    this.branch,
    this.purpose,
    this.by,
    this.via,
  );
  final String id;
  final String emp;
  final String branch;
  final String purpose;
  final String by;
  final String via;
  final int amount;
  final DateTime date;
}

class Notice implements Bilingual {
  Notice(this.to, this.en, this.ar, this.at);
  final String to;
  @override
  final String en;
  @override
  final String ar;
  final DateTime at;
  bool read = false;
}

class Line implements Bilingual {
  Line(
    this.key,
    this.en,
    this.ar,
    this.amount, {
    this.rule = false,
    this.manual,
    this.note,
  });
  final String key;
  @override
  final String en;
  @override
  final String ar;
  int amount; // signed piastres: + earning, - deduction
  final bool rule; // rule-made: waivable, never deletable (AD-7)
  final String? manual; // adjustment id: deletable until approval
  String? note;
  bool waived = false;
}

class Slip {
  Slip(
    this.emp,
    this.start,
    this.end,
    this.lines,
    this.net,
    this.carryOut,
    this.collected,
  );
  final String emp;
  final DateTime start;
  final DateTime end;
  final List<Line> lines;
  final int net;
  final int carryOut;
  final Map<String, int> collected; // advance id -> taken this slip
  int get earned =>
      lines.where((l) => l.amount > 0).fold(0, (s, l) => s + l.amount);
  int get deducted =>
      lines.where((l) => l.amount < 0).fold(0, (s, l) => s - l.amount);
  int get carryIn =>
      -lines.where((l) => l.key == 'carry').fold(0, (s, l) => s + l.amount);
}

class Period {
  Period(this.start, this.end);
  final DateTime start;
  final DateTime end;
  PeriodStatus status = PeriodStatus.open;
  final Map<String, PayMethod> paidBy = {};
  final Map<String, Slip> frozen = {};
}

class Rung {
  Rung(this.from, this.to, this.kind, this.value);
  final int from;
  final int? to;
  final RungKind kind;
  final num value;
}

class Suggestion implements Bilingual {
  Suggestion(
    this.id,
    this.branch,
    this.date,
    this.en,
    this.ar,
    this.confidence, {
    this.shift,
    this.emp,
    this.tpl,
    this.byDefault = false,
  });
  final String id;
  final String branch;
  @override
  final String en;
  @override
  final String ar;
  final DateTime date;
  final String? shift;
  final String? emp;
  final String? tpl; // reassign [shift] to [emp], or add [emp] on [tpl]
  final int confidence;
  final bool byDefault;
}

class Holiday implements Bilingual {
  Holiday(this.date, this.en, this.ar);
  final DateTime date;
  @override
  final String en;
  @override
  final String ar;
  String? decision; // 'holiday' | 'dismissed'
}

class DawamError implements Exception, Bilingual {
  DawamError(this.en, this.ar);
  @override
  final String en;
  @override
  final String ar;
}

class DawamStore extends ChangeNotifier {
  DawamStore() {
    reset();
  }

  // ── session ──
  String? me;
  final Set<String> privacyAccepted = {};

  // Demo controls: what a real phone would tell us.
  int _offset = 0;
  bool inside = true;
  bool alwaysLocation = true;
  int battery = 78;
  bool offline = false;
  int queued = 0;

  DateTime get now => DateTime.now().add(Duration(minutes: _offset));
  DateTime get today => dateOnly(now);

  // ── data ─────────────────────────────────────────────────────────────────
  final branches = <String, Branch>{};
  Map<String, Tpl> get tpls => tplIndex;
  final emps = <String, Emp>{};
  final shifts = <Shift>[];
  final flags = <Flag>[];
  final reqs = <Req>[];
  final adjs = <Adj>[];
  final advances = <Advance>[];
  final expenses = <Expense>[];
  final notices = <Notice>[];
  final suggestions = <Suggestion>[];
  final holidays = <Holiday>[];
  final published = <String>{};
  final waives = <String, String>{}; // line key -> reason (AD-8: final)
  final history = <Period>[];
  late Period period;
  List<Rung> ladder = <Rung>[];
  double absenceDays = 1;
  OvertimeMode overtime = OvertimeMode.approval;
  double otDay = 1.35;
  double otNight = 1.70;
  double holidayMult = 2;
  int advanceCapPct = 50;
  int managerBonusLimit = 100000;
  int managerDeductLimit = 50000;
  int periodStartDay = 26;
  int _seq = 0;
  Timer? _timer;

  String id(String p) => '$p${++_seq}';
  Emp get user => emps[me]!;
  String get ownerId => emps.values.firstWhere((e) => e.role == Role.owner).id;
  Emp emp(String id) => emps[id]!;
  bool get canManage => me != null && user.role != Role.employee;
  bool get canPayroll =>
      me != null &&
      user.role == Role.owner; // hr.payroll.run, all branches (RO-9)

  void set(VoidCallback f) {
    f();
    notifyListeners();
  }

  // ── demo clock ───────────────────────────────────────────────────────────
  void shiftClock(int minutes) => set(() {
    _offset += minutes;
    sweep();
  });

  void setClock(int minuteOfDay) => set(() {
    final target = dateOnly(DateTime.now()).add(Duration(minutes: minuteOfDay));
    _offset = target.difference(DateTime.now()).inMinutes;
    sweep();
  });

  // ── seed ─────────────────────────────────────────────────────────────────
  void reset() {
    _timer?.cancel();
    for (final l in [
      shifts,
      flags,
      reqs,
      adjs,
      advances,
      expenses,
      notices,
      suggestions,
      holidays,
      history,
    ]) {
      l.clear();
    }
    for (final m in [branches, tpls, emps, waives]) {
      m.clear();
    }
    published.clear();
    me = null;
    privacyAccepted.clear();
    inside = true;
    alwaysLocation = true;
    battery = 78;
    offline = false;
    queued = 0;
    setClock(8 * 60 + 52);
    _seed();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => set(sweep));
  }

  void stop() => _timer?.cancel();

  void _seed() {
    final t0 = today;
    branches['z'] = Branch('z', 'Zamalek', 'الزمالك', 200);
    branches['m'] = Branch('m', 'Maadi', 'المعادي', 150);
    for (final t in [
      Tpl('zM', 'z', 'Morning', 'صباحي', 9 * 60, 17 * 60),
      Tpl('zE', 'z', 'Evening', 'مسائي', 16 * 60, 0),
      Tpl('zA', 'z', 'Split · noon', 'مقسّم · ظهر', 10 * 60, 14 * 60, grace: 5),
      Tpl(
        'zB',
        'z',
        'Split · night',
        'مقسّم · ليل',
        18 * 60,
        22 * 60,
        grace: 5,
      ),
      Tpl('mM', 'm', 'Morning', 'صباحي', 8 * 60, 16 * 60),
      Tpl('mE', 'm', 'Evening', 'مسائي', 15 * 60, 23 * 60),
    ]) {
      tpls[t.id] = t;
    }
    Emp e(
      String id,
      String en,
      String ar,
      String ph,
      Role r,
      List<String> b,
      int egp,
      String g,
      PayMethod p,
      Map<int, List<String>> pat,
    ) => emps[id] = Emp(
      id,
      en,
      ar,
      ph,
      r,
      b,
      egp * 100,
      g,
      DateTime(2025, 1, 5),
      p,
      account: p == PayMethod.bank ? 'EG38 0019 0005 ${ph.substring(7)}' : ph,
    )..pattern = pat;
    Map<int, List<String>> days(List<int> d, List<String> tl) => {
      for (final x in d) x: tl,
    };
    const satThu = [6, 7, 1, 2, 3, 4];
    e(
      'e1',
      'Sara Ahmed',
      'سارة أحمد',
      '01001234567',
      Role.employee,
      ['z'],
      9000,
      'f',
      PayMethod.bank,
      days(satThu, ['zM']),
    ).prefTime = 'morning';
    e(
      'e2',
      'Omar Khaled',
      'عمر خالد',
      '01002345678',
      Role.manager,
      ['z'],
      14000,
      'm',
      PayMethod.bank,
      days([6, 7, 1, 2, 3], ['zM']),
    );
    e(
      'e3',
      'Mona Hassan',
      'منى حسن',
      '01003456789',
      Role.owner,
      ['z', 'm'],
      25000,
      'f',
      PayMethod.bank,
      {},
    );
    e(
      'e4',
      'Youssef Adel',
      'يوسف عادل',
      '01004567890',
      Role.employee,
      ['z'],
      8000,
      'm',
      PayMethod.wallet,
      days([6, 7, 1, 3, 4, 5], ['zE']),
    );
    e(
      'e5',
      'Karim Samir',
      'كريم سمير',
      '01005678901',
      Role.employee,
      ['z'],
      7500,
      'm',
      PayMethod.cash,
      days(satThu, ['zA', 'zB']),
    );
    e(
        'e6',
        'Laila Mahmoud',
        'ليلى محمود',
        '01006789012',
        Role.employee,
        ['z'],
        8500,
        'f',
        PayMethod.wallet,
        days([6, 7, 2, 3, 4], ['zM']),
      )
      ..cantWork = {5}
      ..prefTime = 'morning';
    e(
      'e7',
      'Nour Ali',
      'نور علي',
      '01007890123',
      Role.employee,
      ['m'],
      8500,
      'f',
      PayMethod.bank,
      days(satThu, ['mM']),
    );
    e(
      'e8',
      'Hany Fathy',
      'هاني فتحي',
      '01008901234',
      Role.employee,
      ['m'],
      3000,
      'm',
      PayMethod.cash,
      days([6, 7, 1, 2, 3, 4], ['mE']),
    );
    e(
      'e9',
      'Tarek Nabil',
      'طارق نبيل',
      '01009012345',
      Role.manager,
      ['m'],
      13000,
      'm',
      PayMethod.bank,
      days([7, 1, 2, 3, 4], ['mM']),
    );
    emps['e5']!.hired = t0.subtract(
      const Duration(days: 12),
    ); // joined mid-period (PAY-13)

    ladder = [
      Rung(1, 15, RungKind.minutesPay, 30),
      Rung(16, 60, RungKind.dayFraction, 0.25),
      Rung(61, null, RungKind.dayFraction, 0.5),
    ];

    period = _periodFor(t0);
    final prev = _periodFor(period.start.subtract(const Duration(days: 1)));

    // Rosters from the previous period through next week.
    final from = prev.start;
    final to = weekStart(t0).add(const Duration(days: 13));
    for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
      for (final em in emps.values.where((e) => !d.isBefore(e.hired))) {
        for (final tp in em.pattern[d.weekday] ?? const <String>[]) {
          shifts.add(Shift(id('s'), em.id, tp, d));
        }
      }
    }
    for (
      var w = weekStart(from);
      !w.isAfter(weekStart(t0));
      w = w.add(const Duration(days: 7))
    ) {
      published
        ..add('z|$w')
        ..add('m|$w');
    }

    // Past attendance, deterministic.
    for (final s in shifts.where((s) => s.date.isBefore(t0))) {
      final r = (s.emp.hashCode ^ s.date.day * 31 ^ s.tpl.hashCode) % 23;
      if (r == 0 && s.date.isAfter(prev.end)) continue; // an absence
      final lt = switch (r) {
        1 => 25,
        2 => 72,
        3 || 4 => 14,
        _ => -(r % 7),
      };
      s.inAt = s.startAt.add(
        Duration(minutes: lt + (lt > 0 ? s.template.grace : 0)),
      );
      s.outAt = s.endAt.add(Duration(minutes: r % 9));
      s.inMethod = s.outMethod = Method.app;
    }
    Shift? find(String e, int daysAgo) {
      final d = t0.subtract(Duration(days: daysAgo));
      return shifts.where((s) => s.emp == e && sameDay(s.date, d)).firstOrNull;
    }

    // Nour on paid leave 3 days ago; Youssef forgot to check out (CL-15).
    find('e7', 3)
      ?..leave = 'paid'
      ..inAt = null
      ..outAt = null;
    for (final ago in [1, 2, 3, 4]) {
      final y = find('e4', ago);
      if (y == null || y.inAt == null) continue;
      y
        ..outAt = y.endAt
        ..outMethod = Method.auto;
      break;
    }
    // Today: the manager and Nour are in; Laila is a no-show (cover candidate).
    find('e2', 0)
      ?..inAt = t0.add(const Duration(hours: 8, minutes: 45))
      ..inMethod = Method.app;
    find('e7', 0)
      ?..inAt = t0.add(const Duration(hours: 7, minutes: 55))
      ..inMethod = Method.app;
    find('e9', 0)
      ?..inAt = t0.add(const Duration(hours: 7, minutes: 58))
      ..inMethod = Method.app;

    // Flags waiting for managers.
    final hy = shifts.lastWhere(
      (s) => s.emp == 'e8' && s.inAt != null && s.date.isBefore(t0),
    );
    flags.add(
      Flag(
        id('f'),
        FlagKind.suspicious,
        'e8',
        hy.startAt.add(const Duration(hours: 2)),
        shift: hy.id,
      ),
    );
    final yy = shifts.lastWhere(
      (s) => s.emp == 'e4' && s.inAt != null && s.date.isBefore(t0),
    )..trackingOff = true;
    flags
      ..add(Flag(id('f'), FlagKind.trackingOff, 'e4', yy.inAt!, shift: yy.id))
      ..add(
        Flag(
          id('f'),
          FlagKind.leftMidShift,
          'e4',
          yy.startAt.add(const Duration(hours: 3)),
          shift: yy.id,
          minutesAway: 40,
        ),
      );
    flags.add(
      Flag(
        id('f'),
        FlagKind.newPhone,
        'e6',
        now.subtract(const Duration(hours: 14)),
      ),
    );
    emps['e6']!
      ..device = 'Samsung A54'
      ..deviceSince = now.subtract(const Duration(hours: 14));

    // Requests waiting.
    final nextWeek = weekStart(t0).add(const Duration(days: 7));
    reqs.add(
      Req(id('r'), ReqKind.leave, 'e4', now.subtract(const Duration(hours: 5)))
        ..from = nextWeek.add(const Duration(days: 4))
        ..to = nextWeek.add(const Duration(days: 4))
        ..note = 'Family wedding · فرح في العيلة',
    );
    reqs.add(
      Req(
          id('r'),
          ReqKind.lateArrival,
          'e5',
          now.subtract(const Duration(hours: 2)),
        )
        ..from = t0.add(const Duration(days: 1))
        ..time = 10 * 60 + 30
        ..note = 'University exam · امتحان في الجامعة',
    );
    reqs.add(
      Req(
          id('r'),
          ReqKind.salaryAdvance,
          'e8',
          now.subtract(const Duration(hours: 20)),
        )
        ..amount = 200000
        ..installments = 2
        ..note = 'Rent · الإيجار',
    );
    reqs.add(
      Req(id('r'), ReqKind.leave, 'e2', now.subtract(const Duration(hours: 1)))
        ..from = nextWeek.add(const Duration(days: 2))
        ..to = nextWeek.add(const Duration(days: 2))
        ..toOwner =
            true // a manager without hr.requests.self_approve (RQ-5)
        ..note = 'Doctor · دكتور',
    );
    reqs.add(
      Req(id('r'), ReqKind.overtime, 'e4', yy.endAt)
        ..from = yy.date
        ..shift = yy.id
        ..minutes = 45
        ..note = 'Closing inventory · جرد آخر اليوم',
    );

    // Money.
    adjs.add(
      Adj(
        id('a'),
        'e5',
        bonus: true,
        30000,
        'Meal allowance · بدل وجبة',
        'e3',
        prev.start,
        period.start,
        recurring: true,
      ),
    );
    adjs.add(
      Adj(
        id('a'),
        'e4',
        bonus: false,
        10000,
        'Broken glass · كسر كوبايات',
        'e2',
        now.subtract(const Duration(days: 4)),
        period.start,
      ),
    );
    adjs.add(
      Adj(
        id('a'),
        'e1',
        bonus: true,
        150000,
        'Top seller of the month · الأعلى مبيعاً',
        'e2',
        now.subtract(const Duration(hours: 3)),
        period.start,
        status: 'pendingOwner',
      ),
    );
    adjs.add(
      Adj(
        id('a'),
        'e8',
        bonus: false,
        150000,
        'Cash shortage · عجز في الدرج',
        'e9',
        now.subtract(const Duration(days: 6)),
        period.start,
      ),
    );
    advances.add(
      Advance(
        id('v'),
        'e1',
        150000,
        3,
        prev.start.add(const Duration(days: 5)),
        'e2',
      )..collected = 50000,
    );
    advances.add(
      Advance(
        id('v'),
        'e8',
        100000,
        1,
        prev.start.add(const Duration(days: 9)),
        'e9',
      ),
    );
    expenses.add(
      Expense(
        id('x'),
        'e5',
        45000,
        now.subtract(const Duration(days: 2)),
        'z',
        'Cleaning supplies · أدوات نظافة',
        'e2',
        'till',
      ),
    );
    expenses.add(
      Expense(
        id('x'),
        'e7',
        120000,
        now.subtract(const Duration(days: 8)),
        'm',
        'Milk and sugar · لبن وسكر',
        'e9',
        'safe',
      ),
    );

    // Next week: a draft with an open shift and suggestions (SC-9, SC-13).
    shifts.add(
      Shift(id('s'), null, 'zM', nextWeek.add(const Duration(days: 6))),
    );
    final laThu = shifts
        .where(
          (s) =>
              s.emp == 'e6' &&
              sameDay(s.date, nextWeek.add(const Duration(days: 5))),
        )
        .firstOrNull;
    if (laThu != null) {
      suggestions.add(
        Suggestion(
          id('g'),
          'z',
          laThu.date,
          "Give Laila's Thursday morning to Sara — Laila marked Thursdays hard; Sara accepted 4 of 5 like this",
          'إدي صباحية الخميس بتاعة ليلى لسارة — ليلى قالت الخميس صعب، وسارة وافقت على 4 من 5 زيها',
          82,
          shift: laThu.id,
          emp: 'e1',
        ),
      );
    }
    suggestions.add(
      Suggestion(
        id('g'),
        'z',
        nextWeek.add(const Duration(days: 6)),
        'Add Karim to Friday noon — 1 short 12:00–14:00 (POS: 38 orders/h)',
        'ضيف كريم ظهر الجمعة — ناقص واحد من 12 لـ 2 (الكاشير: 38 طلب/ساعة)',
        71,
        emp: 'e5',
        tpl: 'zA',
      ),
    );
    final saraSat = shifts
        .where((s) => s.emp == 'e1' && sameDay(s.date, nextWeek))
        .firstOrNull;
    if (saraSat != null) {
      suggestions.add(
        Suggestion(
          id('g'),
          'z',
          nextWeek,
          'Put Youssef on Saturday evening cover instead of adding Sara — late shifts go to men by default',
          'يوسف ياخد مسائي السبت بدل سارة — الورديات المتأخرة للرجالة افتراضياً',
          58,
          emp: 'e4',
          tpl: 'zE',
          byDefault: true,
        ),
      );
    }

    // A public holiday to set up (RU-10): 6 October.
    var oct6 = DateTime(t0.year, 10, 6);
    if (oct6.isBefore(t0)) oct6 = DateTime(t0.year + 1, 10, 6);
    holidays.add(Holiday(oct6, 'Armed Forces Day', 'عيد القوات المسلحة'));

    // The previous period, approved and paid: payslips to look at.
    for (final em in emps.values) {
      prev.frozen[em.id] = slip(em.id, prev);
      prev.paidBy[em.id] = em.pay;
    }
    prev.status = PeriodStatus.paid;
    history.add(prev);

    for (final em in emps.values) {
      notify(
        em.id,
        "This week's roster is published",
        'جدول الأسبوع ده اتنشر',
        weekStart(t0).subtract(const Duration(days: 2)),
      );
    }
    notify(
      'e3',
      'Omar asked for a day off — waiting for you',
      'عمر طلب إجازة يوم — مستني موافقتك',
      now.subtract(const Duration(hours: 1)),
    );
    notify(
      'e2',
      'Laila signed in on a new phone (Samsung A54)',
      'ليلى سجلت دخول من موبايل جديد (Samsung A54)',
      now.subtract(const Duration(hours: 14)),
    );
  }

  Period _periodFor(DateTime d) {
    final start = d.day >= periodStartDay
        ? DateTime(d.year, d.month, periodStartDay)
        : DateTime(d.year, d.month - 1, periodStartDay);
    return Period(
      start,
      DateTime(start.year, start.month + 1, periodStartDay - 1),
    );
  }

  // ── lookups ──────────────────────────────────────────────────────────────
  Iterable<Emp> get visibleEmps {
    final u = user;
    return emps.values.where(
      (e) =>
          e.id == u.id ||
          u.role == Role.owner ||
          (e.role != Role.owner && e.branches.any(u.branches.contains)),
    );
  }

  List<String> get myBranches =>
      user.role == Role.owner ? branches.keys.toList() : user.branches;

  Iterable<Emp> managersOf(String branch) => emps.values.where(
    (e) =>
        e.role == Role.owner ||
        (e.role == Role.manager && e.branches.contains(branch)),
  );

  bool isPublished(Shift s) =>
      published.contains('${s.template.branch}|${weekStart(s.date)}');

  List<Shift> shiftsOn(String emp, DateTime d) =>
      shifts.where((s) => s.emp == emp && sameDay(s.date, d)).toList()
        ..sort((a, b) => a.startAt.compareTo(b.startAt));

  /// The one function that decides who works when (SC-6, AT-9).
  List<Shift> rostered(String emp, DateTime d) =>
      shiftsOn(emp, d).where(isPublished).toList();

  /// My shifts that matter now: today's, last night's still running (SC-10), covers I opened.
  List<Shift> myNow() {
    final n = now;
    return shifts
        .where(
          (s) =>
              isPublished(s) &&
              ((s.emp == me && !s.covered) || s.coverBy == me) &&
              (sameDay(s.date, today) ||
                  (s.inAt != null && s.outAt == null) ||
                  (s.startAt.isBefore(n) && s.endAt.isAfter(n))),
        )
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  Shift? get activeShift => shifts
      .where(
        (s) =>
            s.inAt != null &&
            s.outAt == null &&
            ((s.emp == me && !s.covered) || s.coverBy == me),
      )
      .firstOrNull;

  int dayMinutes(String emp, DateTime d) {
    final m = rostered(emp, d).fold(0, (s, x) => s + x.template.length);
    return m == 0 ? 480 : m;
  }

  int minuteCost(String emp, DateTime d, int minutes) =>
      mulDiv(emps[emp]!.salary, minutes, 30 * dayMinutes(emp, d));

  int lateMinutes(Shift s) {
    if (s.inAt == null || s.covered) return 0;
    final allowed = s.lateUntil != null
        ? s.date.add(Duration(minutes: s.lateUntil!))
        : s.startAt.add(Duration(minutes: s.template.grace));
    return math.max(0, s.inAt!.difference(allowed).inMinutes);
  }

  int ladderCost(String emp, DateTime d, int lt) {
    if (lt <= 0) return 0;
    final r = ladder
        .where((r) => lt >= r.from && (r.to == null || lt <= r.to!))
        .firstOrNull;
    if (r == null) return 0;
    final day = mulDiv(emps[emp]!.salary, 1, 30);
    return switch (r.kind) {
      RungKind.minutesPay => minuteCost(emp, d, r.value.toInt()),
      RungKind.flat => r.value.toInt(),
      RungKind.dayFraction => (day * r.value).round(),
    };
  }

  bool isHoliday(DateTime d) =>
      holidays.any((h) => h.decision == 'holiday' && sameDay(h.date, d));

  bool isAbsent(Shift s) =>
      s.emp != null &&
      isPublished(s) &&
      s.endAt.isBefore(now) &&
      (s.inAt == null || s.covered) &&
      s.leave == null &&
      !s.mission &&
      !isHoliday(s.date);

  int shiftShare(Shift s) => mulDiv(
    emps[s.emp]!.salary,
    (absenceDays * s.template.length * 100).round(),
    30 * 100 * dayMinutes(s.emp!, s.date),
  );

  // ── payroll: the preview and approval use this same function (PAY-2) ────────
  Slip slip(String empId, Period p) {
    final frozen = p.frozen[empId];
    if (frozen != null) return frozen;
    final e = emps[empId]!;
    final lines = <Line>[];
    final until = p.end.isBefore(today) ? p.end : today;
    final days = p.end.difference(p.start).inDays + 1;

    // Salary, pro rata by calendar days for a mid-period joiner (PAY-13).
    final hired = e.hired.isAfter(p.start) ? dateOnly(e.hired) : p.start;
    final paidDays = math.max(0, p.end.difference(hired).inDays + 1);
    lines.add(
      Line(
        'salary',
        paidDays < days ? 'Salary ($paidDays of $days days)' : 'Salary',
        paidDays < days ? 'المرتب ($paidDays من $days يوم)' : 'المرتب',
        mulDiv(e.salary, paidDays, days),
      ),
    );

    bool inP(DateTime d) => !d.isBefore(p.start) && !d.isAfter(until);
    final mine = shifts.where((s) => s.emp == empId && inP(s.date)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    for (final s in mine) {
      final dl = _dm(s.date);
      final lt = lateMinutes(s);
      if (lt > 0) {
        lines.add(
          Line(
            'late:${s.id}',
            'Late $lt min · $dl',
            'تأخير $lt د · $dl',
            -ladderCost(empId, s.date, lt),
            rule: true,
          ),
        );
      }
      if (isAbsent(s)) {
        lines.add(
          Line(
            'abs:${s.id}',
            s.covered ? 'Absent (covered) · $dl' : 'Absent · $dl',
            s.covered ? 'غياب (اتغطى) · $dl' : 'غياب · $dl',
            -shiftShare(s),
            rule: true,
          ),
        );
      }
      if (s.leave == 'unpaid') {
        final c = s.halfLeave ? shiftShare(s) ~/ 2 : shiftShare(s);
        lines.add(
          Line(
            'leave:${s.id}',
            'Unpaid leave · $dl',
            'إجازة بدون مرتب · $dl',
            -c,
            rule: true,
          ),
        );
      }
      if (s.excuseMin > 0 && !s.excusePaid) {
        lines.add(
          Line(
            'exc:${s.id}',
            'Unpaid excuse ${s.excuseMin} min · $dl',
            'إذن بدون مرتب ${s.excuseMin} د · $dl',
            -minuteCost(empId, s.date, s.excuseMin),
            rule: true,
          ),
        );
      }
      if (isHoliday(s.date) && s.inAt != null) {
        lines.add(
          Line(
            'hol:${s.id}',
            'Holiday worked · $dl',
            'شغل يوم إجازة رسمية · $dl',
            (shiftShare(s) * (holidayMult - 1)).round(),
          ),
        );
      }
    }
    for (final f in flags.where(
      (f) => f.emp == empId && f.deducted > 0 && inP(dateOnly(f.at)),
    )) {
      lines.add(
        Line(
          'away:${f.id}',
          'Left mid-shift · ${_dm(f.at)}',
          'خرج أثناء الوردية · ${_dm(f.at)}',
          -f.deducted,
          rule: true,
        ),
      );
    }
    for (final r in reqs.where(
      (r) => r.status == ReqStatus.approved && r.from != null && inP(r.from!),
    )) {
      if (r.kind == ReqKind.overtime &&
          r.emp == empId &&
          overtime != OvertimeMode.off) {
        final s = shifts.firstWhere((x) => x.id == r.shift);
        final rate = s.template.night ? otNight : otDay;
        lines.add(
          Line(
            'ot:${r.id}',
            'Overtime ${r.minutes} min × $rate',
            'وقت إضافي ${r.minutes} د × $rate',
            (minuteCost(empId, s.date, r.minutes) * rate).round(),
          ),
        );
      }
      if (r.kind == ReqKind.cover && r.emp == empId) {
        final s = shifts.firstWhere((x) => x.id == r.shift);
        final worked = (s.outAt ?? now).difference(s.inAt!).inMinutes;
        final own = rostered(
          empId,
          s.date,
        ).fold(0, (a, x) => a + x.template.length);
        lines.add(
          Line(
            'cov:${r.id}',
            'Cover · ${emps[s.emp]!.en} · ${_dm(s.date)}',
            'تغطية · ${emps[s.emp]!.ar} · ${_dm(s.date)}',
            mulDiv(e.salary, worked, 30 * (own == 0 ? s.template.length : own)),
          ),
        );
      }
    }
    for (final a in adjs.where(
      (a) =>
          a.emp == empId &&
          a.status == 'active' &&
          (a.recurring
              ? !a.period.isAfter(p.start)
              : sameDay(a.period, p.start)),
    )) {
      final v = a.value(e);
      lines.add(
        Line(
          'adj:${a.id}',
          '${a.recurring ? (a.bonus ? 'Allowance' : 'Recurring deduction') : (a.bonus ? 'Bonus' : 'Deduction')} · ${a.reason}',
          '${a.recurring ? (a.bonus ? 'بدل' : 'خصم ثابت') : (a.bonus ? 'مكافأة' : 'خصم')} · ${a.reason}',
          a.bonus ? v : -v,
          manual: a.recurring ? null : a.id,
        ),
      );
    }
    for (final l in lines) {
      if (waives.containsKey(l.key)) {
        l
          ..waived = true
          ..note = waives[l.key]
          ..amount = 0;
      }
    }

    // Carried shortfall from the last payslip, collected like an advance (PAY-12).
    final last = history
        .where((h) => h.end.isBefore(p.start))
        .lastOrNull
        ?.frozen[empId];
    if (last != null && last.carryOut > 0) {
      lines.add(
        Line(
          'carry',
          'Carried from last payslip',
          'مرحّل من القسيمة اللي فاتت',
          -last.carryOut,
        ),
      );
    }
    var balance = lines.fold(0, (s, l) => s + l.amount);
    final carryOut = balance < 0 ? -balance : 0;
    // Advances take only what's left, oldest first; never below zero (AV-4).
    final collected = <String, int>{};
    final open =
        advances
            .where(
              (a) =>
                  a.emp == empId && a.outstanding > 0 && a.date.isBefore(p.end),
            )
            .toList()
          ..sort((x, y) => x.date.compareTo(y.date));
    for (final a in open) {
      final take = math.min(
        math.min(a.installment, a.outstanding),
        math.max(0, balance),
      );
      if (take <= 0) continue;
      collected[a.id] = take;
      balance -= take;
      lines.add(
        Line('adv:${a.id}', 'Salary advance repayment', 'قسط سلفة', -take),
      );
    }
    return Slip(
      empId,
      p.start,
      p.end,
      lines,
      math.max(0, balance),
      carryOut,
      collected,
    );
  }

  // ── notifications ────────────────────────────────────────────────────────
  void notify(String to, String en, String ar, [DateTime? at]) =>
      notices.add(Notice(to, en, ar, at ?? now));
  void notifyManagers(String branch, String en, String ar) {
    for (final m in managersOf(branch)) {
      if (m.id != me) notify(m.id, en, ar);
    }
  }

  Iterable<Notice> get myNotices =>
      notices.where((n) => n.to == me).toList().reversed;
  int get unread => myNotices.where((n) => !n.read).length;
  void readAll() => set(() {
    for (final n in myNotices) {
      n.read = true;
    }
  });

  // ── sign-in (RO-1..RO-5, AT-5) ────────────────────────────────────────────
  Emp? byPhone(String phone) => emps.values
      .where((e) => e.phone == phone.replaceAll(' ', ''))
      .firstOrNull;

  List<(String, String, bool)> orgsFor(Emp e) => [
    ('Nile Café', 'كافيه النيل', true),
    if (e.id == 'e2')
      (
        'Sun Bakery',
        'مخبز الشمس',
        false,
      ), // a second employer, suspended (SA-3)
  ];

  void signIn(String emp, {bool newPhone = false}) => set(() {
    me = emp;
    if (newPhone) {
      final e = emps[emp]!
        ..device = 'Pixel 9'
        ..deviceSince = now;
      flags.add(Flag(id('f'), FlagKind.newPhone, emp, now));
      for (final b in e.branches) {
        notifyManagers(
          b,
          '${e.en} moved to a new phone; the old one is signed out',
          '${e.ar} نقل على موبايل جديد؛ القديم اتقفل',
        );
      }
    }
  });

  void signOut() => set(() => me = null);

  void _online() {
    if (offline) {
      throw DawamError(
        "This needs a connection. Try again when you're online.",
        'ده محتاج إنترنت. جرّب تاني لما تتصل.',
      );
    }
  }

  // ── clocking in (CL-*) ────────────────────────────────────────────────────
  void clockIn(Shift s) {
    final tp = s.template;
    final b = branches[tp.branch]!;
    if (!inside) {
      throw DawamError(
        "You're 340 m from ${b.en}. Clock in from inside ${b.radius} m.",
        'إنت على بُعد 340 م من ${b.ar}. سجّل حضورك من جوه ${b.radius} م.',
      );
    }
    final opens = s.startAt.subtract(Duration(minutes: tp.window));
    if (now.isBefore(opens)) {
      throw DawamError(
        'Check-in opens at ${_hm(opens)}.',
        'الحضور بيفتح الساعة ${_hm(opens)}.',
      );
    }
    if (!now.isBefore(s.endAt)) {
      throw DawamError('This shift has ended.', 'الوردية دي خلصت.');
    }
    set(() {
      s
        ..inAt = now
        ..inMethod = offline ? Method.offline : Method.app
        ..trackingOff = !alwaysLocation;
      if (offline) queued++;
      if (!alwaysLocation) {
        flags.add(Flag(id('f'), FlagKind.trackingOff, me!, now, shift: s.id));
        notifyManagers(
          tp.branch,
          '${user.en} clocked in with tracking off',
          '${user.ar} سجّل حضور والتتبع مقفول',
        );
      }
    });
  }

  void clockOut(Shift s) => set(() {
    s
      ..outAt = now
      ..outMethod = offline ? Method.offline : Method.app;
    if (offline) queued++;
    _maybeOvertime(s);
  });

  void _maybeOvertime(Shift s) {
    final extra = s.outAt!.difference(s.endAt).inMinutes;
    if (overtime == OvertimeMode.off || extra < 15 || s.covered) return;
    final r =
        Req(
            id('r'),
            ReqKind.overtime,
            s.emp!,
            now,
            status: overtime == OvertimeMode.automatic
                ? ReqStatus.approved
                : ReqStatus.pending,
          )
          ..from = s.date
          ..shift = s.id
          ..minutes = extra;
    reqs.add(r);
    if (r.status == ReqStatus.pending) {
      notifyManagers(
        s.template.branch,
        '${emps[s.emp]!.en} worked $extra min overtime',
        '${emps[s.emp]!.ar} اشتغل $extra د إضافي',
      );
    }
  }

  void sync() => set(() {
    offline = false;
    queued = 0;
  });

  /// Shifts a colleague missed that I can open as a cover (CV-1, CV-2).
  List<Shift> coverable() {
    if (me == null || activeShift != null) return [];
    return shifts
        .where(
          (s) =>
              s.emp != null &&
              s.emp != me &&
              !s.covered &&
              s.inAt == null &&
              s.leave == null &&
              isPublished(s) &&
              user.branches.contains(s.template.branch) &&
              now.isAfter(s.startAt.add(Duration(minutes: s.template.grace))) &&
              now.isBefore(s.endAt),
        )
        .toList();
  }

  void openCover(Shift s) {
    if (!inside) {
      throw DawamError(
        'Covers need you inside the branch too.',
        'التغطية محتاجة تكون جوه الفرع برضه.',
      );
    }
    set(() {
      s
        ..coverBy = me
        ..inAt = now
        ..inMethod = Method.cover;
      flags.add(Flag(id('f'), FlagKind.cover, me!, now, shift: s.id));
      reqs.add(
        Req(id('r'), ReqKind.cover, me!, now)
          ..from = s.date
          ..shift = s.id,
      );
      notifyManagers(
        s.template.branch,
        "${user.en} is covering ${emps[s.emp]!.en}'s shift — confirm to pay it",
        '${user.ar} بيغطي وردية ${emps[s.emp]!.ar} — أكّد عشان تتدفع',
      );
    });
  }

  /// Demo: what the 15-minute pings would reveal (CL-6, CL-8, CL-9).
  void simulate(FlagKind k) => set(() {
    final s = activeShift;
    if (s == null) return;
    flags.add(
      Flag(
        id('f'),
        k,
        me!,
        now,
        shift: s.id,
        minutesAway: k == FlagKind.leftMidShift ? 35 : 0,
      ),
    );
    final what = k == FlagKind.leftMidShift
        ? (
            '${user.en} left the branch mid-shift (2 pings outside)',
            '${user.ar} خرج من الفرع أثناء الوردية (قراءتين برّه)',
          )
        : ("${user.en}'s location looks spoofed", 'موقع ${user.ar} شكله مزيّف');
    notifyManagers(s.template.branch, what.$1, what.$2);
  });

  void punchFor(Shift s, String reason) => set(() {
    if (s.inAt == null) {
      s
        ..inAt = now
        ..inMethod = Method.manager
        ..punchReason = reason;
    } else {
      s
        ..outAt = now
        ..outMethod = Method.manager
        ..punchReason = reason;
      _maybeOvertime(s);
    }
    notify(
      s.emp!,
      '${user.en} punched ${s.outAt == null ? 'in' : 'out'} for you: $reason',
      '${user.ar} سجّل ${s.outAt == null ? 'حضورك' : 'انصرافك'}: $reason',
    );
  });

  /// Forgotten check-outs close at the scheduled end two hours later (CL-15).
  void sweep() {
    for (final s in shifts) {
      if (s.inAt != null &&
          s.outAt == null &&
          now.isAfter(s.endAt.add(const Duration(hours: 2)))) {
        s
          ..outAt = s.endAt
          ..outMethod = Method.auto;
      }
    }
  }

  // ── requests (RQ-*) ───────────────────────────────────────────────────────
  bool monthOpen(DateTime d) =>
      !d.isBefore(period.start) && period.status == PeriodStatus.open;

  Req file(
    ReqKind kind, {
    DateTime? from,
    DateTime? to,
    bool half = false,
    int? time,
    int? time2,
    String note = '',
    int amount = 0,
    int installments = 1,
    String? shift,
    String? shift2,
    String? peer,
  }) {
    _online();
    final d = from ?? today;
    if (!monthOpen(d)) {
      throw DawamError(
        "That month's payroll is approved — it's closed to requests.",
        'مرتبات الشهر ده اتعمدت — مفيش طلبات عليه.',
      );
    }
    final end = to ?? d;
    final clash = reqs.any(
      (r) =>
          r.emp == me &&
          r.kind == kind &&
          (r.status == ReqStatus.pending ||
              r.status == ReqStatus.approved ||
              r.status == ReqStatus.awaitingPeer) &&
          (kind == ReqKind.correction
              ? r.shift == shift
              : r.from != null &&
                    !r.from!.isAfter(end) &&
                    !(r.to ?? r.from!).isBefore(d)),
    );
    if (clash && kind != ReqKind.salaryAdvance) {
      throw DawamError(
        'You already have a request like this for that time.',
        'عندك طلب زي ده لنفس الوقت.',
      );
    }
    final r =
        Req(
            id('r'),
            kind,
            me!,
            now,
            status: kind == ReqKind.swap
                ? ReqStatus.awaitingPeer
                : ReqStatus.pending,
          )
          ..from = d
          ..to = to
          ..half = half
          ..time = time
          ..time2 = time2
          ..note = note
          ..amount = amount
          ..installments = installments
          ..shift = shift
          ..shift2 = shift2
          ..peer = peer;
    set(() {
      reqs.add(r);
      if (kind == ReqKind.swap) {
        notify(
          peer!,
          '${user.en} wants to swap a shift with you',
          '${user.ar} عايز يبدّل وردية معاك',
        );
      } else if (user.role == Role.owner) {
        _apply(r, approve: true); // the owner holds hr.requests.self_approve
      } else if (user.role == Role.manager) {
        r.toOwner = true;
        notify(
          ownerId,
          '${user.en} filed a request — it waits for you',
          '${user.ar} قدّم طلب — مستني موافقتك',
        );
      } else {
        for (final b in user.branches) {
          notifyManagers(
            b,
            '${user.en}: new ${kindEn(kind)} request',
            '${user.ar}: طلب ${kindAr(kind)} جديد',
          );
        }
      }
    });
    return r;
  }

  void peerAnswer(Req r, {required bool yes}) {
    _online();
    set(() {
      r.status = yes ? ReqStatus.pending : ReqStatus.rejected;
      notify(
        r.emp,
        yes
            ? '${user.en} agreed to swap — waiting for the manager'
            : '${user.en} declined the swap',
        yes
            ? '${user.ar} وافق على التبديل — مستني المدير'
            : '${user.ar} رفض التبديل',
      );
      if (yes) {
        for (final b in emps[r.emp]!.branches) {
          notifyManagers(
            b,
            'A shift swap waits for approval',
            'تبديل وردية مستني موافقة',
          );
        }
      }
    });
  }

  void cancel(Req r) {
    _online();
    if (r.status == ReqStatus.approved && !monthOpen(r.from!)) {
      throw DawamError(
        'Payroll is approved for that month.',
        'مرتبات الشهر ده اتعمدت.',
      );
    }
    set(() {
      if (r.status == ReqStatus.approved &&
          (r.kind == ReqKind.leave || r.kind == ReqKind.mission)) {
        for (final s in _range(r)) {
          s
            ..leave = null
            ..halfLeave = false
            ..mission = false; // reprices those days (RQ-12)
        }
      }
      r.status = ReqStatus.cancelled;
    });
  }

  Iterable<Shift> _range(Req r) => shifts.where(
    (s) =>
        s.emp == r.emp &&
        !s.date.isBefore(r.from!) &&
        !s.date.isAfter(r.to ?? r.from!),
  );

  /// Requests waiting on the signed-in person.
  List<Req> get inbox => reqs.where((r) {
    if (r.status != ReqStatus.pending || r.emp == me || !canManage) {
      return false;
    }
    if (r.toOwner) return user.role == Role.owner;
    return visibleEmps.any((e) => e.id == r.emp);
  }).toList()..sort((a, b) => b.created.compareTo(a.created));

  List<Adj> get adjInbox => user.role == Role.owner
      ? adjs.where((a) => a.status == 'pendingOwner').toList()
      : [];

  int outstandingAdvances(String emp) =>
      advances.where((a) => a.emp == emp).fold(0, (s, a) => s + a.outstanding);
  int advanceCap(String emp) => mulDiv(emps[emp]!.salary, advanceCapPct, 100);

  void decide(
    Req r, {
    required bool approve,
    bool? paid,
    int? amount,
    int? installments,
    String? note,
  }) {
    _online();
    if (approve && r.kind == ReqKind.salaryAdvance) {
      final a = amount ?? r.amount;
      if (outstandingAdvances(r.emp) + a > advanceCap(r.emp) &&
          user.role != Role.owner) {
        set(() {
          r.toOwner = true;
          notify(
            ownerId,
            'An advance above the cap needs you: ${emps[r.emp]!.en}',
            'سلفة فوق الحد محتاجاك: ${emps[r.emp]!.ar}',
          );
        });
        throw DawamError(
          'Above the $advanceCapPct% cap — sent to the owner.',
          'فوق حد $advanceCapPct% — اتبعتت للمالك.',
        );
      }
    }
    set(
      () => _apply(
        r,
        approve: approve,
        paid: paid,
        amount: amount,
        installments: installments,
        note: note,
      ),
    );
  }

  void _apply(
    Req r, {
    required bool approve,
    bool? paid,
    int? amount,
    int? installments,
    String? note,
  }) {
    r
      ..status = approve ? ReqStatus.approved : ReqStatus.rejected
      ..decidedBy = me
      ..decisionNote = note
      ..paid = paid ?? r.paid;
    if (amount != null) r.amount = amount;
    if (installments != null) r.installments = installments;
    final e = emps[r.emp]!;
    if (approve) {
      switch (r.kind) {
        case ReqKind.leave:
          for (final s in _range(r)) {
            s
              ..leave = (paid ?? true) ? 'paid' : 'unpaid'
              ..halfLeave = r.half;
          }
        case ReqKind.mission:
          for (final s in _range(r)) {
            s.mission = true;
          }
        case ReqKind.lateArrival:
          for (final s in _range(r).take(1)) {
            s.lateUntil = r.time;
          }
        case ReqKind.earlyDeparture:
          for (final s in _range(r).take(1)) {
            s.earlyFrom = r.time;
          }
        case ReqKind.excuse:
          for (final s in _range(r).take(1)) {
            s
              ..excuseMin = (r.time2! - r.time!)
              ..excusePaid = paid ?? false;
            for (final f in flags.where(
              (f) =>
                  f.shift == s.id && f.kind == FlagKind.leftMidShift && f.open,
            )) {
              f.resolution = 'excused';
            }
          }
        case ReqKind.correction:
          final s = shifts.firstWhere((x) => x.id == r.shift);
          if (r.time != null) s.inAt = s.date.add(Duration(minutes: r.time!));
          if (r.time2 != null) {
            var out = s.date.add(Duration(minutes: r.time2!));
            if (out.isBefore(s.inAt ?? s.startAt)) {
              out = out.add(const Duration(days: 1));
            }
            s.outAt = out;
          }
          s
            ..inMethod = r.time != null ? Method.correction : s.inMethod
            ..outMethod = r.time2 != null ? Method.correction : s.outMethod;
        case ReqKind.salaryAdvance:
          advances.add(
            Advance(id('v'), r.emp, r.amount, r.installments, now, me!),
          );
        case ReqKind.swap:
          final a = shifts.firstWhere((x) => x.id == r.shift);
          final b = shifts.firstWhere((x) => x.id == r.shift2);
          final ea = a.emp;
          a
            ..emp = b.emp
            ..changed = true;
          b
            ..emp = ea
            ..changed = true;
          notify(
            r.peer!,
            'Your shift swap with ${e.en} is approved',
            'تبديل ورديتك مع ${e.ar} اتوافق عليه',
          );
        case ReqKind.openShift:
          shifts.firstWhere((x) => x.id == r.shift)
            ..emp = r.emp
            ..changed = true;
        case ReqKind.cover:
          for (final f in flags.where(
            (f) => f.shift == r.shift && f.kind == FlagKind.cover,
          )) {
            f.resolution = 'confirmed';
          }
        case ReqKind.overtime:
          break;
      }
    }
    if (r.emp != me) {
      notify(
        r.emp,
        'Your ${kindEn(r.kind)} request was ${approve ? 'approved' : 'declined'}',
        'طلب ${kindAr(r.kind)} بتاعك ${approve ? 'اتوافق عليه' : 'اترفض'}',
      );
    }
  }

  // ── flags ────────────────────────────────────────────────────────────────
  List<Flag> get openFlags =>
      flags
          .where(
            (f) =>
                f.open && visibleEmps.any((e) => e.id == f.emp) && f.emp != me,
          )
          .toList()
        ..sort((a, b) => b.at.compareTo(a.at));

  int suggestedAway(Flag f) =>
      round5(minuteCost(f.emp, dateOnly(f.at), f.minutesAway));

  void resolve(Flag f, String how, {int deduct = 0}) => set(() {
    f
      ..resolution = how
      ..deducted = deduct;
    if (deduct > 0) {
      notify(
        f.emp,
        'A deduction was added: left mid-shift (${deduct ~/ 100} EGP)',
        'اتضاف خصم: خروج أثناء الوردية (${deduct ~/ 100} ج.م)',
      );
    }
  });

  // ── adjustments (AD-*) ────────────────────────────────────────────────────
  void addAdjustment(
    String emp, {
    required bool bonus,
    required int amount,
    required String reason,
    double? pct,
    bool recurring = false,
  }) {
    _online();
    if (period.status != PeriodStatus.open) {
      throw DawamError(
        'Payroll is approved; this goes into next month.',
        'المرتبات اتعمدت؛ ده هيروح الشهر الجاي.',
      );
    }
    final value = pct != null
        ? mulDiv(emps[emp]!.salary, (pct * 100).round(), 10000)
        : amount;
    final limit = bonus ? managerBonusLimit : managerDeductLimit;
    final over = user.role != Role.owner && value > limit;
    set(() {
      adjs.add(
        Adj(
          id('a'),
          emp,
          bonus: bonus,
          amount,
          reason,
          me!,
          now,
          period.start,
          pct: pct,
          recurring: recurring,
          status: over ? 'pendingOwner' : 'active',
        ),
      );
      if (over) {
        notify(
          ownerId,
          '${user.en} added a ${bonus ? 'bonus' : 'deduction'} over the limit — approve it',
          '${user.ar} ضاف ${bonus ? 'مكافأة' : 'خصم'} فوق الحد — وافق عليه',
        );
      } else {
        notify(
          emp,
          '${bonus ? 'Bonus' : 'Deduction'}: $reason',
          '${bonus ? 'مكافأة' : 'خصم'}: $reason',
        );
      }
    });
  }

  void decideAdj(Adj a, {required bool yes}) => set(() {
    a.status = yes ? 'active' : 'rejected';
    if (yes) {
      notify(
        a.emp,
        '${a.bonus ? 'Bonus' : 'Deduction'}: ${a.reason}',
        '${a.bonus ? 'مكافأة' : 'خصم'}: ${a.reason}',
      );
    }
  });

  void deleteAdj(String adjId) =>
      set(() => adjs.firstWhere((a) => a.id == adjId).status = 'deleted');
  void stopAdj(Adj a) => set(() => a.status = 'stopped');

  void waive(String key, String reason) => set(() => waives[key] = reason);
  void unwaive(String key) => set(() => waives.remove(key));

  // ── advances ─────────────────────────────────────────────────────────────
  void recordAdvance(String emp, int amount, int installments) {
    _online();
    if (outstandingAdvances(emp) + amount > advanceCap(emp) &&
        user.role != Role.owner) {
      throw DawamError(
        'Above the $advanceCapPct% cap — only the owner can.',
        'فوق حد $advanceCapPct% — المالك بس.',
      );
    }
    set(() {
      advances.add(Advance(id('v'), emp, amount, installments, now, me!));
      notify(
        emp,
        'Salary advance recorded: ${amount ~/ 100} EGP',
        'اتسجلت سلفة: ${amount ~/ 100} ج.م',
      );
    });
  }

  void logExpense(String emp, int amount, String purpose, String via) {
    _online();
    set(
      () => expenses.add(
        Expense(
          id('x'),
          emp,
          amount,
          now,
          emps[emp]!.branches.first,
          purpose,
          me!,
          via,
        ),
      ),
    );
  }

  // ── schedule (SC-*) ───────────────────────────────────────────────────────
  void setDay(String emp, DateTime d, String? tpl, String branch) => set(() {
    final existing = shiftsOn(
      emp,
      d,
    ).where((s) => s.template.branch == branch).toList();
    final wasPublished = published.contains('$branch|${weekStart(d)}');
    shifts.removeWhere(existing.contains);
    if (tpl != null) {
      shifts.add(Shift(id('s'), emp, tpl, d)..changed = wasPublished);
    }
    if (wasPublished) {
      notify(
        emp,
        'Your shift on ${d.day}/${d.month} changed',
        'ورديتك يوم ${d.day}/${d.month} اتغيرت',
      ); // SC-4
    }
  });

  /// A drag in the roster: the shift moves to [day] on template [tpl], for
  /// that date only (SC-5). A published week tells the person (SC-4).
  void moveShift(Shift s, DateTime day, String tpl) => set(() {
    final branch = s.template.branch;
    final pub =
        published.contains('$branch|${weekStart(s.date)}') ||
        published.contains('$branch|${weekStart(day)}');
    shifts
      ..remove(s)
      ..add(Shift(id('s'), s.emp, tpl, dateOnly(day))..changed = pub);
    if (pub && s.emp != null) {
      notify(
        s.emp!,
        'Your shift moved to ${day.day}/${day.month}',
        'ورديتك اتنقلت ليوم ${day.day}/${day.month}',
      );
    }
  });

  /// Gives a shift to someone else, or opens it (null) for anyone to claim.
  void assign(Shift s, String? emp) => set(() {
    final pub = isPublished(s);
    s
      ..emp = emp
      ..changed = pub;
    if (pub && emp != null) {
      notify(
        emp,
        'You were given a shift on ${s.date.day}/${s.date.month}',
        'اتضافتلك وردية يوم ${s.date.day}/${s.date.month}',
      );
    }
  });

  void postOpen(String branch, DateTime d, String tpl) => set(() {
    shifts.add(Shift(id('s'), null, tpl, d));
    if (published.contains('$branch|${weekStart(d)}')) {
      for (final e in emps.values.where(
        (e) => e.branches.contains(branch) && e.role == Role.employee,
      )) {
        notify(
          e.id,
          'An open shift was posted — claim it in Shifts',
          'في وردية متاحة — احجزها من الورديات',
        );
      }
    }
  });

  void claim(Shift s) => file(ReqKind.openShift, from: s.date, shift: s.id);

  void publish(String branch, DateTime ws) => set(() {
    published.add('$branch|$ws');
    final people = shifts
        .where(
          (s) =>
              s.emp != null &&
              s.template.branch == branch &&
              sameDay(weekStart(s.date), ws),
        )
        .map((s) => s.emp!)
        .toSet();
    for (final e in people) {
      notify(e, "Next week's roster is published", 'جدول الأسبوع الجاي اتنشر');
    }
    for (final e in emps.values.where(
      (e) => e.branches.contains(branch) && e.role == Role.employee,
    )) {
      if (shifts.any(
        (s) =>
            s.emp == null &&
            sameDay(weekStart(s.date), ws) &&
            s.template.branch == branch,
      )) {
        notify(
          e.id,
          'Open shifts are waiting to be claimed',
          'في ورديات متاحة مستنية حد يحجزها',
        );
      }
    }
  });

  void acceptSuggestion(Suggestion g) => set(() {
    if (g.shift != null) {
      shifts.firstWhere((x) => x.id == g.shift).emp = g.emp;
    } else {
      shifts.add(Shift(id('s'), g.emp, g.tpl!, g.date));
    }
    suggestions.remove(g);
  });

  void rejectSuggestion(Suggestion g) => set(() => suggestions.remove(g));

  void decideHoliday(Holiday h, String d) => set(() => h.decision = d);

  /// Labour limits warn, never block (RU-13). Each is a core i18n key and
  /// its arguments; the screen words it.
  List<(String, Map<String, Object>)> warnings(String emp, DateTime ws) {
    final week =
        shifts
            .where((s) => s.emp == emp && sameDay(weekStart(s.date), ws))
            .toList()
          ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final out = <(String, Map<String, Object>)>[];
    final hours = week.fold(0, (s, x) => s + x.template.length) / 60;
    if (hours > 48) out.add(('staff.warn_week_hours', {'hours': 48}));
    for (var i = 1; i < week.length; i++) {
      final rest = week[i].startAt.difference(week[i - 1].endAt).inHours;
      if (rest >= 0 && rest < 12 && !sameDay(week[i].date, week[i - 1].date)) {
        out.add(('staff.warn_rest', {'date': week[i].date}));
      }
    }
    return out;
  }

  void setPrefs(String emp, String? time, Set<int> cant) => set(() {
    emps[emp]!
      ..prefTime = time
      ..cantWork = cant;
  });

  // ── payroll run (PAY-*) ───────────────────────────────────────────────────
  void approvePayroll() => set(() {
    for (final e in emps.values) {
      final s = slip(e.id, period);
      period.frozen[e.id] = s;
      for (final c in s.collected.entries) {
        advances.firstWhere((a) => a.id == c.key).collected += c.value;
      }
      notify(e.id, 'Your payslip is ready', 'قسيمة مرتبك جاهزة');
    }
    period.status = PeriodStatus.approved;
  });

  void reopenPayroll() {
    if (period.paidBy.isNotEmpty) {
      throw DawamError(
        'Someone is already marked paid.',
        'في حد اتعلّم إنه اتقبض خلاص.',
      );
    }
    set(() {
      for (final s in period.frozen.values) {
        for (final c in s.collected.entries) {
          advances.firstWhere((a) => a.id == c.key).collected -=
              c.value; // never twice (AV-6)
        }
      }
      period.frozen.clear();
      period.status = PeriodStatus.open;
    });
  }

  void markPaid(String emp, PayMethod m) => set(() {
    period.paidBy[emp] = m;
    if (period.paidBy.length == emps.length) period.status = PeriodStatus.paid;
  });

  List<Slip> payslipsOf(String emp) => [
    if (period.status != PeriodStatus.open) period.frozen[emp]!,
    for (final h in history.reversed) h.frozen[emp]!,
  ];

  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String _dm(DateTime d) => '${d.day}/${d.month}';

String kindEn(ReqKind k) => switch (k) {
  ReqKind.leave => 'leave',
  ReqKind.lateArrival => 'late arrival',
  ReqKind.earlyDeparture => 'early departure',
  ReqKind.excuse => 'excuse',
  ReqKind.mission => 'mission',
  ReqKind.correction => 'correction',
  ReqKind.salaryAdvance => 'salary advance',
  ReqKind.cover => 'cover',
  ReqKind.swap => 'swap',
  ReqKind.openShift => 'open shift',
  ReqKind.overtime => 'overtime',
};

String kindAr(ReqKind k) => switch (k) {
  ReqKind.leave => 'إجازة',
  ReqKind.lateArrival => 'تأخير',
  ReqKind.earlyDeparture => 'انصراف بدري',
  ReqKind.excuse => 'إذن',
  ReqKind.mission => 'مأمورية',
  ReqKind.correction => 'تصحيح',
  ReqKind.salaryAdvance => 'سلفة',
  ReqKind.cover => 'تغطية',
  ReqKind.swap => 'تبديل',
  ReqKind.openShift => 'وردية متاحة',
  ReqKind.overtime => 'وقت إضافي',
};
