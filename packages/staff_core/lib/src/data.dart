// Dawam as the screens see it: the core's snapshot, decoded. No business
// logic lives here — madar-core's `dawam.rs` builds every figure from the
// server's numbers and its offline mirror, and does every action. This file
// only holds the picture and forwards what the person does. The IDs in
// comments (PAY-12, CV-5…) point at the Dawam Target Spec.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:staff_core/src/format.dart';

/// Templates by id, so a [Shift] can resolve its own.
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
  phoneDied,
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

typedef J = Map<String, dynamic>;

DateTime _date(Object? v) => DateTime.parse(v! as String);
DateTime? _at(Object? v) => v is String && v.isNotEmpty ? branchWall(v) : null;

final _wall = RegExp(r'^\d{4}-\d\d-\d\d[T ]\d\d:\d\d(:\d\d(\.\d+)?)?');

/// An instant from the core, which writes every one in the branch's zone
/// (`2026-09-23T09:02:00+03:00`), read as that wall-clock time (AT-1). The
/// offset is dropped on purpose: the phone's own zone never moves a time.
/// Unparseable text is null, never a crash (one bad field must not blank the
/// screen).
DateTime? branchWall(String v) {
  final m = _wall.firstMatch(v);
  return m == null ? null : DateTime.tryParse(m.group(0)!);
}

List<J> _list(Object? v) => (v as List<dynamic>? ?? const []).cast<J>();
int _int(Object? v) => (v as num?)?.round() ?? 0;
T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.where((e) => e.name == name).firstOrNull ?? fallback;
String _d(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class Branch implements Bilingual {
  Branch(this.id, this.en, this.ar, this.radius);
  final String id;
  @override
  final String en;
  @override
  final String ar;
  final int radius;
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
    this.days = const {1, 2, 3, 4, 5, 6, 7},
    this.dayTimes = const {},
  });
  final String id;
  final String branch;
  @override
  final String en;
  @override
  final String ar;
  final int start;
  final int end; // minutes of the day; end < start crosses midnight
  final int grace;
  final int window;

  /// ISO weekdays (Mon = 1 … Sun = 7) the block may be rostered on, as the
  /// server says: the board offers it only on those.
  final Set<int> days;

  /// The server's own times on some weekdays: ISO weekday → (start, end).
  final Map<int, (int, int)> dayTimes;

  bool validOn(DateTime d) => days.contains(d.weekday);

  /// The block's times on [d]: that weekday's own, else its default.
  (int, int) timesOn(DateTime d) => dayTimes[d.weekday] ?? (start, end);
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
    this.device = '',
  });
  final String id;
  @override
  final String en;
  @override
  final String ar;
  final String phone;
  final Role role;
  final List<String> branches;
  final int salary; // piastres per month
  final String gender;
  final DateTime hired;
  final PayMethod pay;
  final String account;
  final String device;
  DateTime? deviceSince;
  String? prefTime; // 'morning' | 'evening'
  Set<int> cantWork = {};
}

class Shift {
  Shift(this.id, this.emp, this.tpl, this.date);
  final String id;
  final String? emp; // null = an open shift (SC-9)
  final String tpl;
  final DateTime date; // the day it STARTS (SC-10)
  bool published = false;
  bool changed = false;

  /// The server's EFFECTIVE times (minutes of the day): this assignment's
  /// own, else the block's for that weekday, else its default.
  int? start;
  int? end;

  /// Ends the next day; still the day it starts (SC-10).
  bool nextDay = false;

  /// This assignment has its own from/to.
  bool edited = false;

  /// The date holds its own set of shifts, not the usual pattern.
  bool ownDay = false;
  String? coverBy;

  /// A cover's own row (the coverer's): whose shift it covered (CV-7).
  String? coverOf;
  DateTime? inAt;
  DateTime? outAt;
  Method? inMethod;
  Method? outMethod;
  String? punchReason;
  String? leave; // 'paid' | 'unpaid'
  bool halfLeave = false;
  String? leaveHalf; // 'first' | 'second' (RQ-8)
  bool mission = false;
  int? lateUntil; // minute of day agreed by an approved late arrival
  int? earlyFrom;
  int excuseMin = 0;
  bool excusePaid = false;
  bool trackingOff = false;
  bool timeUnverified = false;
  int lateMinutes = 0;
  bool absent = false;
  bool queued = false;

  /// No approved or paid period holds its day: it can still be fixed. The
  /// core decides (RQ-4, B13).
  bool monthOpen = true;

  // A shift can point at a template the snapshot didn't bring (deactivated,
  // or another branch's): show it as an unnamed all-day shift, never crash.
  Tpl get template => tplIndex[tpl] ?? Tpl(tpl, '', '—', '—', 0, 0);
  DateTime get startAt => date.add(Duration(minutes: start ?? template.start));
  DateTime get endAt {
    final s = start ?? template.start;
    final e = end ?? template.end;
    final l = (e - s) % 1440;
    return startAt.add(Duration(minutes: l == 0 ? 1440 : l));
  }

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
    this.suggested = 0,
  });
  final String id;
  final FlagKind kind;
  final String emp;
  final String? shift;
  final DateTime at;
  final int minutesAway;
  final int suggested; // CL-7, the server's figure
  String? resolution;
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

  /// The pay an approver starts from (the rule, RQ-7); null = not asked.
  bool? paidDefault;
  String? leaveHalf; // 'first' | 'second' (RQ-8)
  String? decidedBy;
  String? decisionNote;

  /// Who cancelled it and why (RQ-F6); decided_by stays the approver's.
  String? cancelledBy;
  String? cancelNote;

  /// The canceller's name when the server sends it (someone this phone's
  /// people list doesn't hold, e.g. the owner).
  String? cancelledByName;

  /// Every day it covers can still change (RQ-4, B13), from the core.
  bool monthOpen = true;
}

/// What the server made of a request just filed (RQ-5): approved at once for
/// a filer who approves their own, else waiting — for the owner when
/// `toOwner`.
typedef Filed = ({String id, ReqStatus status, bool toOwner});

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
    this.resolved = 0,
    this.recurring = false,
    this.status = 'active',
    this.waived = false,
  });
  final String id;
  final String emp;
  final String reason;
  final String by;
  final bool bonus;
  final bool recurring;

  /// A waived rule deduction: struck through, charged nothing (AD-6, AD-8).
  final bool waived;
  final int amount;
  final double? pct;
  final DateTime at;
  final DateTime period;
  final String status; // active | pendingOwner | rejected | stopped
  final int resolved; // the core's figure: a % already resolved on the salary
  int value(Emp _) => resolved;
}

class Advance {
  Advance(
    this.id,
    this.emp,
    this.amount,
    this.installments,
    this.date,
    this.by,
    this.collected,
  );
  final String id;
  final String emp;
  final String by;
  final int amount;
  final int installments;
  final DateTime date;
  final int collected;
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
  Notice(this.text, this.at, {this.read = false});
  final String text; // already in the phone's language (the core's words)
  final DateTime at;
  final bool read;
  @override
  String get en => text;
  @override
  String get ar => text;
}

class Line implements Bilingual {
  Line(
    this.key,
    this.en,
    this.ar,
    this.amount, {
    this.rule = false,
    this.manual,
    this.date,
  });
  final String key;
  @override
  final String en;
  @override
  final String ar;
  final int amount; // signed piastres: + earning, - deduction
  final bool rule; // rule-made: waivable, never deletable (AD-7)
  final String? manual; // adjustment id: deletable until approval
  final DateTime? date; // the day a bonus or deduction counts on (AD-6)
  String? note;
  bool waived = false; // a waived line leaves the server's payslip (AD-8)
}

/// The server's presence states (`/staff/team/presence`).
enum PresenceState { in_, late, absent, onLeave, off, done }

/// One colleague right now, as the server decided it.
class Presence {
  const Presence(this.state, {this.since, this.lateMinutes = 0});
  final PresenceState state;
  final DateTime? since;
  final int lateMinutes;
}

class Slip {
  Slip(
    this.emp,
    this.start,
    this.end,
    this.lines,
    this.net,
    this.carryOut,
    this.collected, {
    this.frozen = false,
  });
  final String emp;
  final DateTime start;
  final DateTime end;
  final List<Line> lines;
  final int net;
  final int carryOut;
  final Map<String, int> collected; // advance id -> taken this slip
  final bool frozen;
  int get earned => lines
      .where((l) => l.amount > 0 && !l.waived)
      .fold(0, (s, l) => s + l.amount);
  int get deducted => lines
      .where((l) => l.amount < 0 && !l.waived)
      .fold(0, (s, l) => s - l.amount);
  int get carryIn =>
      -lines.where((l) => l.key == 'carry').fold(0, (s, l) => s + l.amount);
}

class Period {
  Period(this.start, this.end, {this.id});
  final String? id;
  final DateTime start;
  final DateTime end;
  PeriodStatus status = PeriodStatus.open;
  final Map<String, PayMethod> paidBy = {};

  /// 0-net payslips the server settled itself at approval (`paid_method`
  /// 'none', PAY-7): nothing was paid, so they never read "Paid · Cash" and
  /// never block a reopen (PAY-6, D16).
  final Set<String> settled = {};
  final Map<String, Slip> frozen = {};
}

class Suggestion implements Bilingual {
  Suggestion(
    this.id,
    this.branch,
    this.date,
    this.text,
    this.confidence, {
    this.shift,
    this.emp,
    this.tpl,
    this.byDefault = false,
  });
  final String id;
  final String branch;
  final String text;
  final DateTime date;
  final String? shift;
  final String? emp;
  final String? tpl;
  final int confidence;
  final bool byDefault;
  @override
  String get en => text;
  @override
  String get ar => text;
}

class Holiday implements Bilingual {
  Holiday(this.date, this.en, this.ar, this.decision);
  final DateTime date;
  @override
  final String en;
  @override
  final String ar;
  final String? decision; // 'holiday' | 'dismissed'
}

class DawamError implements Exception, Bilingual {
  DawamError(this.en, this.ar);
  @override
  final String en;
  @override
  final String ar;

  @override
  String toString() => 'DawamError: $en';
}

/// The server no longer accepts this sign-in (a revoked phone, RO-4, or an
/// expired session): back to the sign-in screen.
class DawamSignedOut extends DawamError {
  DawamSignedOut(super.en, super.ar);
}

/// Where the phone is against a branch's fence (06 B4), as the core read it
/// from a FRESH reading. [FenceState.unknown] is never "inside".
enum FenceState { inside, outside, unknown }

class Fence {
  const Fence(this.state, this.distance, this.radius);
  final FenceState state;

  /// Metres from the branch; null when unknown.
  final int? distance;
  final int radius;

  static const unknown = Fence(FenceState.unknown, null, 200);
}

/// A position reading the host takes; the core decides what it means.
typedef DawamFix = ({
  double lat,
  double lng,
  double? accuracy,
  bool mock,
  DateTime? gpsTime,
  int? battery,
});

/// The host's side: the core through the staff bridge, and the phone's GPS.
/// Every method that returns a snapshot returns the core's JSON.
abstract interface class DawamBackend {
  Future<void> otpRequest(String phone);

  /// The server's session JSON (`needs_org` + `orgs`, or a live session).
  Future<J> otpVerify(String phone, String code, {String? orgId});

  Future<String> snapshot({required bool refresh});

  /// One action (`dawam::Act`); throws [DawamError] in the server's words.
  Future<String> act(J action);

  Future<String> ping(DawamFix fix);

  /// Send what is queued, then refresh.
  Future<String> sync();

  Future<DawamFix?> locate();

  /// Positions while on shift, in the background too (CL-4): the host keeps
  /// the OS's location indicator up while this is listened to.
  Stream<DawamFix> track();

  /// Ask for "Always" location; false when refused (CL-5).
  Future<bool> alwaysLocation();

  /// On shift or not (CL-4, CL-17): the host keeps the background pings
  /// going when [on] — on Android a native location service that survives
  /// the app being closed and the phone restarting, on iOS significant-change
  /// monitoring that relaunches the app — and stops them when not.
  Future<void> tracking({required bool on});

  /// The signed-in user from the core's saved session, if any.
  String? restoredUser();

  Future<void> signOut();
}

/// The picture every screen reads. Decoded from the core; every action goes
/// back to it, and a refusal the screen has already moved past arrives on
/// [failures].
class DawamStore extends ChangeNotifier {
  DawamStore(this.backend);

  final DawamBackend backend;

  final failures = StreamController<String>.broadcast();

  // ── session ──
  String? me;
  String? pendingUser;

  /// This phone accepted the location notice, as the server recorded it
  /// (AT-5). Until then the app shows the notice, never the tabs; a
  /// restored session does not accept it by itself.
  bool privacyAccepted = false;

  /// "Always" location was granted (CL-5), and the battery level (CL-12):
  /// the host keeps both current.
  bool alwaysLocation = true;
  int battery = 100;
  bool loading = false;

  /// On shift with a low battery: the core says charge (CL-12).
  bool chargePhone = false;

  /// The owner saved the rules; until then nobody clocks in (RU-1).
  bool rulesSaved = true;

  /// The org's modules (`pos`, `dawam`).
  List<String> modules = const ['pos', 'dawam'];

  /// Coverage needs per branch (SC-13), as the server sent them.
  Map<String, J> coverage = const {};

  /// `emp|yyyy-mm-dd` of the dates that hold their own set (a date change):
  /// those can go back to the usual pattern.
  Set<String> ownDays = const {};

  /// `emp|yyyy-mm-dd` of the dates changed to a day off.
  Set<String> daysOff = const {};

  bool isOwnDay(String emp, DateTime d) => ownDays.contains('$emp|${_d(d)}');
  bool isDayOff(String emp, DateTime d) => daysOff.contains('$emp|${_d(d)}');

  /// Each colleague's state right now, as the SERVER decided it (AT-3):
  /// employee id → presence. Empty for someone who manages no one, and until
  /// the first answer.
  Map<String, Presence> presence = const {};

  // ── the picture ──
  Duration _skew = Duration.zero;
  DateTime get now => DateTime.now().add(_skew);
  DateTime get today => dateOnly(now);
  bool offline = false;
  int queued = 0;
  List<String> stuck = const [];
  Role role = Role.employee;
  String orgName = '';
  bool canManage = false;
  bool canPayroll = false;

  /// My own requests are approved as I file them (RQ-5): a leave then needs
  /// its paid/unpaid choice at filing (RQ-2), as the server says.
  bool selfApproves = false;

  /// The manager tabs, from the capabilities the server says I hold (PM-4).
  bool canTeam = false;
  bool canApprove = false;
  bool canSchedule = false;
  bool? insideNow;
  double? distance;

  /// Where I am against each branch's fence, from a fresh reading (06 B4).
  Map<String, Fence> fences = const {};
  Fence fenceAt(String branch) => fences[branch] ?? Fence.unknown;
  List<String> myBranches = const [];

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

  /// The dates the picture holds in full, from–to (H2-01): this week, four
  /// back and three ahead, and what a screen asked for. Null from a core
  /// that doesn't say: it holds whatever it shows.
  List<(DateTime, DateTime)>? loaded;

  /// A screen is fetching the dates it shows ([viewRange]).
  bool viewing = false;
  String? _viewingKey;
  final history = <Period>[];
  Period period = Period(DateTime(2000), DateTime(2000));
  final _slips = <String, Slip>{};
  final _cap = <String, int>{};
  final _outstanding = <String, int>{};
  final _warnings = <String, List<(String, Map<String, Object>)>>{};
  List<String> _myNow = const [];
  String? _active;
  List<String> _coverable = const [];
  List<String> _inbox = const [];

  /// The server's answer to the last filing, from the picture it came with.
  Filed? lastFiled;
  List<String> _adjInbox = const [];
  List<String> _openFlags = const [];

  double holidayMult = 2;
  double advanceCapPct = 50;
  int managerBonusLimit = 1 << 40;
  int managerDeductLimit = 1 << 40;

  /// Paid through Dawam (the server says). Off: no estimate on the Pay tab.
  bool onPayroll = true;

  /// When the core last fetched the picture from the server (its
  /// `fetched_at`, ms): a pull that did not move it never reached the server.
  int fetchedAt = 0;

  /// When the phone last ASKED the server for the whole picture (sign-in,
  /// the poll, a push, the pill, a pull, a resume) — reached or not. A
  /// resume soon after one skips its own.
  DateTime? lastFetch;

  /// The clock [lastFetch] is stamped and read with; a test sets it.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  /// A resume within this long of the last fetch does not fetch again: a
  /// quick app switch is not a refresh storm.
  static const resumeQuiet = Duration(seconds: 15);

  Future<bool>? _fetching;
  Timer? _poll;
  StreamSubscription<DawamFix>? _track;
  DateTime? _lastPing;
  String? _lastGood;
  bool? _trackingOn;

  Emp get user => emp(me ?? '');
  // Requests, flags and shifts can name someone the snapshot doesn't carry — a
  // terminated employee, or a branch this manager doesn't see. Show a blank
  // person rather than crash the whole screen.
  Emp emp(String id) =>
      emps[id] ??
      Emp(
        id,
        '—',
        '—',
        '',
        Role.employee,
        const [],
        0,
        '',
        DateTime(2000),
        PayMethod.cash,
      );

  // ── reading the core ──
  void _apply(String json) {
    final v = jsonDecode(json) as J;
    tplIndex.clear();
    branches.clear();
    emps.clear();
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
    published.clear();
    _slips.clear();

    me = v['me'] as String;
    _skew = (_at(v['now']) ?? DateTime.now()).difference(DateTime.now());
    offline = v['online'] != true;
    fetchedAt = _int(v['fetched_at']);
    queued = _int(v['queued']);
    stuck = (v['stuck'] as List<dynamic>).cast<String>();
    role = _enum(Role.values, v['role'], Role.employee);
    orgName = v['org_name'] as String;
    canManage = v['can_manage'] == true;
    canPayroll = v['can_payroll'] == true;
    selfApproves = v['self_approves'] == true;
    final tabs = (v['tabs'] as J?) ?? const {};
    canTeam = tabs['team'] == true;
    canApprove = tabs['approvals'] == true;
    canSchedule = tabs['schedule'] == true;
    myBranches = (v['my_branches'] as List<dynamic>).cast<String>();
    insideNow = v['inside'] as bool?;
    distance = (v['distance_m'] as num?)?.toDouble();
    privacyAccepted = v['privacy_accepted'] == true;
    fences = ((v['fences'] as J?) ?? const {}).map((k, f) {
      final x = f as J;
      return MapEntry(
        k,
        Fence(
          _enum(FenceState.values, x['state'], FenceState.unknown),
          (x['distance_m'] as num?)?.round(),
          _int(x['radius']),
        ),
      );
    });
    chargePhone = v['charge_phone'] == true;
    modules = ((v['modules'] as List<dynamic>?) ?? const ['pos', 'dawam'])
        .cast<String>();
    coverage = ((v['coverage'] as J?) ?? const {}).map(
      (k, x) => MapEntry(k, x is J ? x : const <String, dynamic>{}),
    );
    ownDays = ((v['own_days'] as List<dynamic>?) ?? const [])
        .cast<String>()
        .toSet();
    daysOff = ((v['days_off'] as List<dynamic>?) ?? const [])
        .cast<String>()
        .toSet();

    presence = {
      for (final MapEntry(key: id, value: p)
          in ((v['presence'] as J?) ?? const {}).entries)
        if (p is J)
          id: Presence(
            switch (p['state']) {
              'in' => PresenceState.in_,
              'late' => PresenceState.late,
              'absent' => PresenceState.absent,
              'on_leave' => PresenceState.onLeave,
              'done' => PresenceState.done,
              _ => PresenceState.off,
            },
            since: _at(p['since']),
            lateMinutes: _int(p['late_minutes']),
          ),
    };

    for (final b in _list(v['branches'])) {
      final name = b['name'] as String;
      branches[b['id'] as String] = Branch(
        b['id'] as String,
        name,
        name,
        _int(b['radius']),
      );
    }
    for (final t in _list(v['templates'])) {
      final name = t['name'] as String;
      tplIndex[t['id'] as String] = Tpl(
        t['id'] as String,
        t['branch'] as String,
        name,
        name,
        _int(t['start']),
        _int(t['end']),
        grace: _int(t['grace']),
        window: _int(t['window']),
        days: t['days'] == null
            ? const {1, 2, 3, 4, 5, 6, 7}
            : (t['days'] as List<dynamic>).cast<int>().toSet(),
        dayTimes: {
          for (final x in _list(t['day_times']))
            _int(x['day']): (_int(x['start']), _int(x['end'])),
        },
      );
    }
    for (final p in _list(v['people'])) {
      final name = p['name'] as String;
      emps[p['id'] as String] =
          Emp(
              p['id'] as String,
              name,
              name,
              p['phone'] as String,
              _enum(Role.values, p['role'], Role.employee),
              (p['branches'] as List<dynamic>).cast<String>(),
              _int(p['salary']),
              p['gender'] as String,
              _date(p['hired']),
              _enum(PayMethod.values, p['pay'], PayMethod.cash),
              account: p['account'] as String,
              device: p['device'] as String,
            )
            ..deviceSince = _at(p['device_since'])
            ..prefTime = p['pref_time'] as String?
            ..cantWork = (p['cant_work'] as List<dynamic>).cast<int>().toSet();
    }
    for (final s in _list(v['shifts'])) {
      if (!tplIndex.containsKey(s['tpl'])) continue;
      final sh =
          Shift(
              s['id'] as String,
              s['emp'] as String?,
              s['tpl'] as String,
              _date(s['date']),
            )
            ..published = s['published'] == true
            ..changed = s['changed'] == true
            ..start = s['start'] as int?
            ..end = s['end'] as int?
            ..nextDay = s['next_day'] == true
            ..edited = s['edited'] == true
            ..ownDay = s['own_day'] == true
            ..coverBy = s['cover_by'] as String?
            ..coverOf = s['cover_of'] as String?
            ..inAt = _at(s['in_at'])
            ..outAt = _at(s['out_at'])
            ..inMethod = s['in_method'] == null
                ? null
                : _enum(Method.values, s['in_method'], Method.app)
            ..outMethod = s['out_method'] == null
                ? null
                : _enum(Method.values, s['out_method'], Method.app)
            ..punchReason = s['punch_reason'] as String?
            ..leave = s['leave'] as String?
            ..halfLeave = s['half_leave'] == true
            ..mission = s['mission'] == true
            ..lateUntil = s['late_until'] as int?
            ..earlyFrom = s['early_from'] as int?
            ..excuseMin = _int(s['excuse_min'])
            ..excusePaid = s['excuse_paid'] == true
            ..trackingOff = s['tracking_off'] == true
            ..timeUnverified = s['time_unverified'] == true
            ..lateMinutes = _int(s['late_minutes'])
            ..absent = s['absent'] == true
            ..queued = s['queued'] == true
            ..leaveHalf = s['leave_half'] as String?
            ..monthOpen = s['month_open'] != false;
      shifts.add(sh);
      if (sh.published) {
        published.add('${sh.template.branch}|${weekStart(sh.date)}');
      }
    }
    // The weeks the server published, shifts in them or not (H2-03).
    for (final w in (v['published_weeks'] as List<dynamic>?) ?? const []) {
      final s = w as String;
      final i = s.lastIndexOf('|');
      if (i > 0) {
        published.add('${s.substring(0, i)}|${_date(s.substring(i + 1))}');
      }
    }
    final held = v['loaded'];
    loaded = held is List<dynamic>
        ? [
            for (final r in held)
              if (r is List<dynamic> && r.length == 2)
                (_date(r[0]), _date(r[1])),
          ]
        : null;
    _myNow = (v['my_now'] as List<dynamic>).cast<String>();
    _active = v['active_shift'] as String?;
    _coverable = (v['coverable'] as List<dynamic>).cast<String>();
    for (final f in _list(v['flags'])) {
      flags.add(
        Flag(
          f['id'] as String,
          _flagKind(f['kind'] as String),
          f['emp'] as String,
          _at(f['at']) ?? now,
          shift: f['shift'] as String?,
          minutesAway: _int(f['minutes_away']),
          suggested: _int(f['suggested']),
        )..resolution = f['resolution'] as String?,
      );
    }
    _openFlags = (v['open_flags'] as List<dynamic>).cast<String>();
    for (final r in _list(v['requests'])) {
      reqs.add(
        Req(
            r['id'] as String,
            _enum(ReqKind.values, r['kind'], ReqKind.leave),
            r['emp'] as String,
            _at(r['created']) ?? now,
            status: _enum(ReqStatus.values, r['status'], ReqStatus.pending),
          )
          ..from = r['from'] == null ? null : _date(r['from'])
          ..to = r['to'] == null ? null : _date(r['to'])
          ..half = r['half'] == true
          ..time = r['time'] as int?
          ..time2 = r['time2'] as int?
          ..note = r['note'] as String
          ..amount = _int(r['amount'])
          ..paid = r['paid'] as bool?
          ..shift = r['shift'] as String?
          ..shift2 = r['shift2'] as String?
          ..peer = r['peer'] as String?
          ..installments = _int(r['installments'])
          ..minutes = _int(r['minutes'])
          ..toOwner = r['to_owner'] == true
          ..paidDefault = r['paid_default'] as bool?
          ..leaveHalf = r['leave_half'] as String?
          ..monthOpen = r['month_open'] != false
          ..decidedBy = r['decided_by'] as String?
          ..decisionNote = r['decision_note'] as String?
          ..cancelledBy = r['cancelled_by'] as String?
          ..cancelNote = r['cancel_note'] as String?
          ..cancelledByName = r['cancelled_by_name'] as String?,
      );
    }
    _inbox = (v['inbox'] as List<dynamic>).cast<String>();
    final filed = v['filed'];
    lastFiled = filed is J
        ? (
            id: filed['id'] as String,
            status: _enum(ReqStatus.values, filed['status'], ReqStatus.pending),
            toOwner: filed['to_owner'] == true,
          )
        : null;
    for (final a in _list(v['adjustments'])) {
      adjs.add(
        Adj(
          a['id'] as String,
          a['emp'] as String,
          _int(a['amount']),
          a['reason'] as String,
          a['by'] as String,
          _at(a['at']) ?? now,
          DateTime.tryParse(a['period'] as String) ?? period.start,
          bonus: a['bonus'] == true,
          pct: (a['pct'] as num?)?.toDouble(),
          resolved: _int(a['value']),
          recurring: a['recurring'] == true,
          status: a['status'] as String,
          waived: a['waived'] == true,
        ),
      );
    }
    _adjInbox = (v['adj_inbox'] as List<dynamic>).cast<String>();
    for (final a in _list(v['advances'])) {
      advances.add(
        Advance(
          a['id'] as String,
          a['emp'] as String,
          _int(a['amount']),
          _int(a['installments']),
          _at(a['date']) ?? now,
          a['by'] as String,
          _int(a['collected']),
        ),
      );
    }
    for (final x in _list(v['expenses'])) {
      expenses.add(
        Expense(
          x['id'] as String,
          x['emp'] as String,
          _int(x['amount']),
          _date(x['date']),
          x['branch'] as String,
          x['purpose'] as String,
          x['by'] as String,
          x['via'] as String,
        ),
      );
    }
    for (final n in _list(v['notices'])) {
      notices.add(
        Notice(
          n['text'] as String,
          _at(n['at']) ?? now,
          read: n['read'] == true,
        ),
      );
    }
    Period readPeriod(J p) {
      final out = Period(
        _date(p['start']),
        _date(p['end']),
        id: p['id'] as String?,
      )..status = _enum(PeriodStatus.values, p['status'], PeriodStatus.open);
      (p['paid_by'] as J).forEach((k, m) {
        if (m == 'none') {
          out.settled.add(k);
        } else {
          out.paidBy[k] = _enum(PayMethod.values, m, PayMethod.cash);
        }
      });
      return out;
    }

    period = readPeriod(v['period'] as J);
    history.addAll(_list(v['history']).map(readPeriod));
    for (final s in _list(v['slips'])) {
      final slip = Slip(
        s['emp'] as String,
        _date(s['start']),
        _date(s['end']),
        [
          for (final l in _list(s['lines']))
            Line(
              l['key'] as String,
              l['en'] as String,
              l['ar'] as String,
              _int(l['amount']),
              rule: l['rule'] == true,
              manual: l['manual'] as String?,
              date: l['date'] is String
                  ? DateTime.tryParse(l['date'] as String)
                  : null,
            )..waived = l['waived'] == true,
        ],
        _int(s['net']),
        _int(s['carry_out']),
        (s['collected'] as J).map((k, x) => MapEntry(k, _int(x))),
        frozen: s['frozen'] == true,
      );
      final p = [
        period,
        ...history,
      ].where((p) => sameDay(p.start, slip.start)).firstOrNull;
      if (slip.frozen && p != null) p.frozen[slip.emp] = slip;
      if (p == period) _slips[slip.emp] = slip;
    }
    (v['advance_cap'] as J).forEach((k, x) => _cap[k] = _int(x));
    _outstanding.clear();
    (v['outstanding'] as J).forEach((k, x) => _outstanding[k] = _int(x));
    for (final g in _list(v['suggestions'])) {
      suggestions.add(
        Suggestion(
          g['id'] as String,
          g['branch'] as String,
          _date(g['date']),
          g['text'] as String,
          _int(g['confidence']),
          shift: g['shift'] as String?,
          emp: g['emp'] as String?,
          tpl: g['tpl'] as String?,
          byDefault: g['by_default'] == true,
        ),
      );
    }
    for (final h in _list(v['holidays'])) {
      holidays.add(
        Holiday(
          _date(h['date']),
          h['en'] as String,
          h['ar'] as String,
          h['decision'] as String?,
        ),
      );
    }
    _warnings.clear();
    (v['warnings'] as J).forEach((k, list) {
      _warnings[k] = [
        for (final w in list as List<dynamic>)
          (
            (w as List<dynamic>)[0] as String,
            {
              for (final e in (w[1] as J).entries)
                e.key: e.key == 'date' ? _date(e.value) : e.value as Object,
            },
          ),
      ];
    });
    final st = v['settings'] as J;
    holidayMult = (st['holiday_mult'] as num).toDouble();
    advanceCapPct = (st['advance_cap_pct'] as num).toDouble();
    // Two limits (AD-5), both the server's; an older server sends one.
    final limit = st['adjustment_limit'] as int?;
    managerBonusLimit = limit ?? 1 << 40;
    managerDeductLimit = (st['deduction_limit'] as int?) ?? limit ?? 1 << 40;
    onPayroll = v['on_payroll'] != false;
    rulesSaved = st['rules_saved'] != false;
    _schedulePings();
    notifyListeners();
  }

  static FlagKind _flagKind(String k) => switch (k) {
    'left_mid_shift' => FlagKind.leftMidShift,
    'tracking_off' => FlagKind.trackingOff,
    'time_unverified' => FlagKind.timeUnverified,
    'new_phone' => FlagKind.newPhone,
    'cover' => FlagKind.cover,
    'phone_died' => FlagKind.phoneDied,
    _ => FlagKind.suspicious,
  };

  // ── what the screens read ──
  /// The picture holds every date from [from] to [to] (H2-01). A screen
  /// showing other dates asks for them ([viewRange]) and edits nothing there.
  bool holds(DateTime from, DateTime to) {
    final held = loaded;
    if (held == null) return true;
    for (
      var d = dateOnly(from);
      !d.isAfter(to);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      if (!held.any((r) => !d.isBefore(r.$1) && !d.isAfter(r.$2))) {
        return false;
      }
    }
    return true;
  }

  /// Why [from]–[to] can't be shown or edited, in words: the phone doesn't
  /// hold it yet (H2-01). Null when it does.
  String? notHeld(DateTime from, DateTime to) {
    if (holds(from, to)) return null;
    if (viewing) return tr('staff.week_loading');
    if (offline) return tr('staff.week_needs_connection');
    return tr('staff.week_couldnt_load');
  }

  Iterable<Emp> get visibleEmps => emps.values; // the server scoped them (RO-6)
  bool isPublished(Shift s) => s.published;
  List<Shift> shiftsOn(String emp, DateTime d) =>
      shifts.where((s) => s.emp == emp && sameDay(s.date, d)).toList()
        ..sort((a, b) => a.startAt.compareTo(b.startAt));
  List<Shift> rostered(String emp, DateTime d) =>
      shiftsOn(emp, d).where((s) => s.published).toList();
  Shift? _shift(String? id) => shifts.where((s) => s.id == id).firstOrNull;
  List<Shift> myNow() => [for (final id in _myNow) ?_shift(id)];
  Shift? get activeShift => _shift(_active);
  List<Shift> coverable() => [for (final id in _coverable) ?_shift(id)];
  int lateMinutes(Shift s) => s.lateMinutes;
  bool isAbsent(Shift s) => s.absent;
  List<Req> get inbox => [
    for (final id in _inbox) ?reqs.where((r) => r.id == id).firstOrNull,
  ];
  List<Adj> get adjInbox => [
    for (final id in _adjInbox) ?adjs.where((a) => a.id == id).firstOrNull,
  ];
  List<Flag> get openFlags => [
    for (final id in _openFlags) ?flags.where((f) => f.id == id).firstOrNull,
  ];
  int suggestedAway(Flag f) => f.suggested;
  int outstandingAdvances(String emp) => _outstanding[emp] ?? 0;

  /// The server's cap on what [emp] may owe (AV-5), or null when the server
  /// sent none (their pay is hidden from me). It is never worked out here.
  int? advanceCap(String emp) => _cap[emp];
  List<(String, Map<String, Object>)> warnings(String emp, DateTime ws) =>
      _warnings['$emp|${_d(ws)}'] ?? const [];
  Slip slip(String empId, Period p) =>
      p.frozen[empId] ??
      (identical(p, period) ? _slips[empId] : null) ??
      Slip(
        empId,
        p.start,
        p.end,
        [Line('salary', 'Salary', 'المرتب', 0)],
        0,
        0,
        {},
      );

  /// The run as the server has it (PAY-3): the frozen payslips once
  /// approved, else the live preview. Never a person the server left out —
  /// someone not on payroll (owner decision 2) has no slip, so no row.
  List<Slip> runSlips(Period p) => p.frozen.isNotEmpty
      ? p.frozen.values.toList()
      : identical(p, period)
      ? _slips.values.where((s) => !s.frozen).toList()
      : const [];
  List<Slip> payslipsOf(String emp) => [
    ?period.frozen[emp],
    for (final h in history) ?h.frozen[emp],
  ];
  Iterable<Notice> get myNotices => notices;
  int get unread => notices.where((n) => !n.read).length;

  // ── sign-in (RO-1..RO-5, AT-5) ──
  Future<void> requestCode(String phone) => backend.otpRequest(phone);

  /// `null` = signed in as [pendingUser]; a list = pick a business (RO-5)
  /// and call again with its id.
  Future<List<(String, String, String, bool)>?> verifyCode(
    String phone,
    String code, {
    String? orgId,
  }) async {
    final v = await backend.otpVerify(phone, code, orgId: orgId);
    if (v['needs_org'] == true) {
      return [
        for (final o in _list(v['orgs']))
          (
            o['org_id'] as String,
            o['org_name'] as String,
            o['org_name'] as String,
            o['active'] == true,
          ),
      ];
    }
    final who = v['employee_id'];
    // An answer with no person would crash the privacy step (06 B13).
    if (who is! String || who.isEmpty) {
      throw DawamError(
        trIn('en', 'staff.sign_in_no_person'),
        trIn('ar', 'staff.sign_in_no_person'),
      );
    }
    pendingUser = who;
    return null;
  }

  /// Signed in: load the picture. The app opens once [privacyAccepted]
  /// (the server's record for this phone); until then the notice shows.
  Future<void> enter() => refresh();

  /// "I agree" on the location notice (AT-5): recorded on the server for
  /// this phone, then the app opens. Needs a connection; a refusal is thrown
  /// to the screen.
  Future<void> acceptPrivacy() async {
    // Any failure — the acceptance refused, the connection lost, or the app's
    // picture failing to load after the server recorded it (E2E S11: the
    // owner's context 500) — comes back to the notice in words, so the screen
    // shows it with Try again instead of staying silent.
    DawamError failed() => DawamError(
      trIn('en', 'staff.privacy_open_failed'),
      trIn('ar', 'staff.privacy_open_failed'),
    );
    final String json;
    try {
      json = await backend.act({'action': 'accept_privacy'});
    } on DawamError {
      rethrow;
    } on Object {
      throw failed();
    }
    _applySafely(json);
    if (!privacyAccepted) throw failed();
  }

  /// Take a fresh reading for the fence line (Home opening, a resume). The
  /// core keeps it with its time; nothing is sent (06 B4).
  Future<void> noteFix() async {
    final fix = await backend.locate();
    if (fix == null || me == null) return;
    await _run(() => backend.act({'action': 'note_fix', 'fix': _fixJson(fix)}));
  }

  /// Cold start with the core's saved session (stay signed in). The notice
  /// is NOT accepted by restoring: the server's record decides.
  Future<void> restore() async {
    final u = backend.restoredUser();
    if (u == null) return;
    try {
      _applySafely(await backend.snapshot(refresh: false));
      unawaited(refresh());
    } on Object {
      me = null;
      notifyListeners();
    }
  }

  void signOut() {
    stop();
    _trackingOn = false;
    unawaited(backend.tracking(on: false));
    // Never fall back to the last person's picture.
    _lastGood = null;
    unawaited(backend.signOut());
    me = null;
    pendingUser = null;
    notifyListeners();
  }

  /// Stops the poll, the ping timer and the position stream. Each is
  /// cleared, so the next sign-in starts them again.
  void stop() {
    _poll?.cancel();
    _poll = null;
    unawaited(_track?.cancel());
    _track = null;
  }

  Future<void> refresh() async {
    lastFetch = clock();
    loading = true;
    notifyListeners();
    try {
      _applySafely(await backend.snapshot(refresh: true));
    } on DawamSignedOut catch (e) {
      failures.add(loc(e));
      signOut();
      return;
    } on DawamError catch (e) {
      // The server refused (a server without Dawam, a blip): say so, and
      // keep showing what the phone already has.
      failures.add(loc(e));
      try {
        _applySafely(await backend.snapshot(refresh: false));
      } on Object {
        // nothing saved yet either
      }
    } finally {
      loading = false;
      notifyListeners();
    }
    // The inbox and the team board stay current while the app is open.
    _poll ??= Timer.periodic(const Duration(minutes: 2), (_) {
      if (me != null && !loading) unawaited(_fetch());
    });
  }

  /// Send what is queued, then refresh (the pill's tap; a push).
  void sync() => unawaited(_fetch());

  /// Pull to refresh (every tab, the inbox, the payslip list): send what is
  /// queued, fetch everything, and hold the spinner until the answer. When
  /// the fetch never reached the server — offline, or the server did not
  /// answer — the saved picture stays and the toast says so; a refusal says
  /// why in the server's words.
  Future<void> pull() async {
    if (me == null) return;
    final before = fetchedAt;
    if (!await _fetch()) return; // refused: the toast already said why
    if (offline) {
      failures.add(tr('staff.refresh_offline'));
    } else if (fetchedAt <= before) {
      failures.add(tr('staff.refresh_failed'));
    }
  }

  /// The app came back to the front (it may have sat in the background for
  /// hours): fetch, unless the last fetch was under [resumeQuiet] ago.
  /// Quiet offline — the pill already says so.
  void resumed() {
    if (me == null || !privacyAccepted) return;
    final last = lastFetch;
    if (last != null && clock().difference(last) < resumeQuiet) return;
    unawaited(_fetch());
  }

  /// Send what is queued, then fetch everything (the core's `dawam_sync`).
  /// One at a time: a push, the pill and a pull landing together share it.
  /// True when the core answered with a picture (reached the server or not).
  Future<bool> _fetch() {
    lastFetch = clock();
    return _fetching ??= _run(
      backend.sync,
    ).whenComplete(() => _fetching = null);
  }

  /// While on shift, a ping every 15 minutes, queued by the core offline
  /// (CL-4): the host's background tracking (which outlives the app) and,
  /// while the app runs, its position stream. Stops at clock-out (CL-17).
  void _schedulePings() {
    final on = activeShift != null;
    // The host's background tracking follows the shift, told once per change
    // (and once at start, so a service left running off shift is stopped).
    if (_trackingOn != on) {
      _trackingOn = on;
      unawaited(backend.tracking(on: on));
    }
    if (!on) {
      unawaited(_track?.cancel());
      _track = null;
      return;
    }
    _track ??= backend.track().listen(_onFix, onError: (Object _) {});
  }

  void _onFix(DawamFix fix) {
    if (fix.battery != null) battery = fix.battery!;
    final last = _lastPing;
    if (last != null && DateTime.now().difference(last).inMinutes < 14) return;
    _lastPing = DateTime.now();
    unawaited(_run(() => backend.ping(fix)));
  }

  /// Runs one core call and shows its answer. Inside [awaitingAnswer] (the
  /// screen that asked is waiting: `attempt`), a refusal is thrown back to
  /// it, so its sheet stays open with the server's words and no success is
  /// shown (B1). Anywhere else a refusal arrives on [failures]. An answer
  /// the screens can't read keeps the last picture; it is never a refusal:
  /// the server did accept it. True when the core answered with a picture.
  Future<bool> _run(Future<String> Function() op) async {
    final String json;
    try {
      json = await op();
    } on DawamSignedOut catch (e) {
      signOut();
      if (awaitingAnswer) rethrow;
      failures.add(loc(e));
      return false;
    } on DawamError catch (e) {
      if (awaitingAnswer) {
        _rereadSoon();
        rethrow;
      }
      failures.add(loc(e));
      return false;
    } on Object catch (e) {
      if (awaitingAnswer) throw DawamError('$e', '$e');
      failures.add('$e');
      return false;
    }
    _applySafely(json);
    return true;
  }

  /// After a refusal the screen waited for, the phone's own picture is read
  /// again (no network): a refusal for want of a connection turns the
  /// offline banner and the disabled buttons on at once (E2E S-120, S-167,
  /// S-236), not at the next poll.
  void _rereadSoon() => unawaited(
    backend
        .snapshot(refresh: false)
        .then(_applySafely)
        .catchError((Object _) {}),
  );

  /// The screen that started this call waits for the server's answer.
  static bool get awaitingAnswer => Zone.current[awaitAnswerKey] == true;

  /// Zone key set by `attempt` around the calls it awaits.
  static const awaitAnswerKey = #dawamAwaitAnswer;

  /// A picture the screens can't read (one bad field from the core) never
  /// blanks the app: the last good picture stays, and the fault is reported.
  void _applySafely(String json) {
    try {
      _apply(json);
      _lastGood = json;
    } on Object catch (e, st) {
      // `_apply` clears as it reads: put the last good picture back.
      final good = _lastGood;
      if (good != null) {
        try {
          _apply(good);
        } on Object {
          // it was good once; nothing better to show
        }
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'staff_core',
          context: ErrorDescription('reading the Dawam snapshot'),
        ),
      );
      notifyListeners();
    }
  }

  Future<void> _act(J action) => _run(() => backend.act(action));

  static J _fixJson(DawamFix fix) => {
    'latitude': fix.lat,
    'longitude': fix.lng,
    'accuracy': fix.accuracy,
    'mock': fix.mock,
    'gps_time': fix.gpsTime?.toUtc().toIso8601String(),
    'battery': fix.battery,
  };

  Future<void> _actAt(J action) async {
    final fix = await backend.locate();
    await _run(
      () => backend.act({...action, if (fix != null) 'fix': _fixJson(fix)}),
    );
  }

  /// A screen shows [from]–[to] (the board's week, a calendar page): dates
  /// the picture doesn't hold are fetched and kept for later refreshes
  /// (H2-01). [viewing] while they come; a refusal arrives on [failures].
  Future<void> viewRange(DateTime from, DateTime to) async {
    final a = dateOnly(from);
    var z = dateOnly(to);
    // One read spans at most 62 days (the server's limit).
    final most = DateTime(a.year, a.month, a.day + 62);
    if (z.isAfter(most)) z = most;
    if (me == null || holds(a, z)) return;
    final key = '${_d(a)}|${_d(z)}';
    if (_viewingKey == key) return;
    _viewingKey = key;
    viewing = true;
    notifyListeners();
    try {
      await _run(
        () => backend.act({'action': 'view_range', 'from': _d(a), 'to': _d(z)}),
      );
    } finally {
      if (_viewingKey == key) {
        _viewingKey = null;
        viewing = false;
      }
      notifyListeners();
    }
  }

  // ── what the screens do: each is one core action ──
  Future<void> clockIn(Shift s) async {
    alwaysLocation = await backend.alwaysLocation();
    await _actAt({
      'action': 'clock_in',
      'shift': s.id,
      'tracking_off': !alwaysLocation,
    });
  }

  Future<void> clockOut(Shift s) => _actAt({'action': 'clock_out'});
  Future<void> openCover(Shift s) => _actAt({'action': 'cover', 'shift': s.id});
  Future<void> punchFor(Shift s, String reason) =>
      _act({'action': 'punch_for', 'shift': s.id, 'reason': reason});

  /// Returns what the server made of it ([Filed]), for the screen's words.
  Future<Filed?> file(
    ReqKind kind, {
    DateTime? from,
    DateTime? to,
    bool half = false,
    String? leaveHalf,
    bool? paid,
    int? time,
    int? time2,
    String note = '',
    int amount = 0,
    int installments = 1,
    String? shift,
    String? shift2,
    String? peer,
  }) async {
    lastFiled = null;
    await _act({
      'action': 'file',
      'kind': kind.name,
      if (from != null) 'from': _d(from),
      if (to != null) 'to': _d(to),
      'half': half,
      if (half) 'leave_half': ?leaveHalf,
      'paid': ?paid,
      'time': ?time,
      'time2': ?time2,
      'note': note,
      'amount': amount,
      'installments': installments,
      'shift': ?shift,
      'shift2': ?shift2,
      'peer': ?peer,
    });
    return lastFiled;
  }

  Future<void> claim(Shift s) => _act({'action': 'claim', 'shift': s.id});
  Future<void> peerAnswer(Req r, {required bool yes}) =>
      _act({'action': 'peer_answer', 'req': r.id, 'yes': yes});

  /// [note]: why, required once it was approved (AT-7).
  Future<void> cancel(Req r, {String? note}) =>
      _act({'action': 'cancel', 'req': r.id, 'note': ?note});

  /// A refused decision (decided elsewhere, a closed month, over a limit)
  /// reloads the queue, so a card someone else settled goes (E2E S-235).
  Future<void> decide(
    Req r, {
    required bool approve,
    bool? paid,
    int? amount,
    int? installments,
    String? note,
  }) async {
    try {
      await _act({
        'action': 'decide',
        'req': r.id,
        'approve': approve,
        'paid': ?paid,
        'amount': ?amount,
        'installments': ?installments,
        'note': ?note,
      });
    } on DawamError {
      unawaited(refresh());
      rethrow;
    }
  }

  /// [how]: `excuse_paid` · `excuse_unpaid` · `deduct` · `revoke` · `ignore`.
  Future<void> resolve(Flag f, String how, {int deduct = 0, String? reason}) =>
      _act({
        'action': 'resolve',
        'flag': f.id,
        'how': f.kind == FlagKind.cover && how == 'ignore' ? 'confirm' : how,
        'deduct': deduct,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });

  /// What the server made of the line (AD-5): `pending` when it is over the
  /// adder's limit and waits for the owner.
  Future<Filed?> addAdjustment(
    String emp, {
    required bool bonus,
    required int amount,
    required String reason,
    double? pct,
    bool recurring = false,
  }) async {
    lastFiled = null;
    await _act({
      'action': 'add_adjustment',
      'emp': emp,
      'bonus': bonus,
      'amount': amount,
      'reason': reason,
      'pct': ?pct,
      'recurring': recurring,
    });
    return lastFiled;
  }

  Future<void> decideAdj(Adj a, {required bool yes}) =>
      _act({'action': 'decide_adj', 'adj': a.id, 'yes': yes});
  Future<void> deleteAdj(String adjId) =>
      _act({'action': 'delete_adj', 'adj': adjId});

  /// [reason]: why it stops, kept with the stop (AD-9).
  Future<void> stopAdj(Adj a, String reason) =>
      _act({'action': 'stop_adj', 'adj': a.id, 'reason': reason});
  Future<void> waive(String key, String reason) =>
      _act({'action': 'waive', 'key': key, 'reason': reason});

  /// Undo a waiver with a reason (AT-7): the rule's figure comes back.
  Future<void> unwaive(String key, String reason) =>
      _act({'action': 'unwaive', 'key': key, 'reason': reason});
  Future<void> recordAdvance(String emp, int amount, int installments) => _act({
    'action': 'record_advance',
    'emp': emp,
    'amount': amount,
    'installments': installments,
  });
  Future<void> logExpense(String emp, int amount, String purpose, String via) =>
      _act({
        'action': 'log_expense',
        'emp': emp,
        'amount': amount,
        'purpose': purpose,
        'via': via,
      });
  // Every day write names the board's [branch]: a business-wide block set
  // there is worked there (H2-B8).
  Future<void> setDay(String emp, DateTime d, String? tpl, String branch) =>
      _act({
        'action': 'set_day',
        'emp': emp,
        'date': _d(d),
        'tpl': tpl,
        'branch': branch,
      });

  /// Every block [emp] works on [d] (a split day); empty = a day off.
  Future<void> setShifts(
    String emp,
    DateTime d,
    List<String> tpls, {
    String? branch,
  }) => _act({
    'action': 'set_shifts',
    'emp': emp,
    'date': _d(d),
    'blocks': [
      for (final t in tpls) {'tpl': t},
    ],
    'branch': ?branch,
  });

  /// One more block on the date; the rest of the day stays.
  Future<void> addBlock(String emp, DateTime d, String tpl, {String? branch}) =>
      _act({
        'action': 'add_block',
        'emp': emp,
        'date': _d(d),
        'tpl': tpl,
        'branch': ?branch,
      });

  /// Take this shift off its date; the rest of the day stays.
  Future<void> removeBlock(Shift s, {String? branch}) =>
      _act({'action': 'remove_block', 'shift': s.id, 'branch': ?branch});

  /// Back to the usual pattern for that date.
  Future<void> resetDay(String emp, DateTime d) =>
      _act({'action': 'reset_day', 'emp': emp, 'date': _d(d)});

  /// This one shift's own from/to (minutes of the day); both null = back to
  /// the block's. An end at or before the start is the next day.
  Future<void> setTimes(Shift s, int? start, int? end) => _act({
    'action': 'set_times',
    'shift': s.id,
    'start': ?start,
    'end': ?end,
  });

  /// Give this shift to a colleague; both keep the rest of their day.
  Future<void> giveShift(Shift s, String to) =>
      _act({'action': 'give_shift', 'shift': s.id, 'to': to});

  /// Take an open shift back.
  Future<void> cancelOpen(Shift s) =>
      _act({'action': 'cancel_open', 'shift': s.id});

  /// Ask a colleague to swap: [mine] is MY shift, [theirs] the colleague's.
  Future<void> askSwap(Shift mine, Shift theirs) =>
      _act({'action': 'ask_swap', 'mine': mine.id, 'theirs': theirs.id});
  Future<void> moveShift(Shift s, DateTime day, String tpl, {String? branch}) =>
      _act({
        'action': 'move_shift',
        'shift': s.id,
        'day': _d(day),
        'tpl': tpl,
        'branch': ?branch,
      });
  Future<void> assign(Shift s, String? emp, {String? branch}) =>
      _act({'action': 'assign', 'shift': s.id, 'emp': emp, 'branch': ?branch});
  Future<void> postOpen(String branch, DateTime d, String tpl) => _act({
    'action': 'post_open',
    'branch': branch,
    'date': _d(d),
    'tpl': tpl,
  });
  Future<void> publish(String branch, DateTime ws) =>
      _act({'action': 'publish', 'branch': branch, 'week': _d(ws)});
  Future<void> acceptSuggestion(Suggestion g) =>
      _act({'action': 'accept_suggestion', 'id': g.id});
  Future<void> rejectSuggestion(Suggestion g) =>
      _act({'action': 'reject_suggestion', 'id': g.id});

  /// Replace a branch's weekly coverage grid (SC-13).
  Future<void> setCoverage(String branch, List<J> needs) =>
      _act({'action': 'set_coverage', 'branch': branch, 'needs': needs});
  Future<void> decideHoliday(Holiday h, String d) =>
      _act({'action': 'decide_holiday', 'date': _d(h.date), 'decision': d});

  /// My preferences, or a manager's override of [emp]'s (logged, SC-12).
  Future<void> setPrefs(
    String emp,
    String? time,
    Set<int> cant, {
    String? note,
  }) => _act({
    'action': 'set_prefs',
    'emp': emp,
    'time': time,
    'cant': cant.toList(),
    'note': ?note,
  });
  Future<void> readAll() => _act({'action': 'read_all'});
  Future<void> approvePayroll() => _act({'action': 'approve_payroll'});

  /// Back to a live preview; the reason goes to the audit log (AD-9).
  Future<void> reopenPayroll(String reason) =>
      _act({'action': 'reopen_payroll', 'reason': reason});
  Future<void> markPaid(String emp, PayMethod m) =>
      _act({'action': 'mark_paid', 'emp': emp, 'method': m.name});
}
