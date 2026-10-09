/// What the web's Approvals page works out in the browser
/// (`dawam/approvals-page.tsx`, `dawam/phase-d.ts`, and the request helpers
/// it borrows from `staff/requests-inbox.tsx`): one queue of everything
/// waiting on this person, as pure functions over the read lists.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show DashTone;

import '../shared/team_format.dart';

/// The section filter (`Section`).
enum ApprovalSection { all, requests, money, shifts }

/// Which list an item came from: what Approve and Reject call.
enum PendingType { request, advance, payLine, swap, claim, cover, overtime }

/// What Approve does (`approve`): one call, the pay question, the mission's
/// worked-days check first, or the advance review.
enum ApproveMode { oneClick, withPay, mission, review }

/// A marker beside the kind: an outline badge, a toned pill, a quiet note
/// (inline, or on a line of its own).
sealed class PendingBadge {
  const PendingBadge(this.text);
  final String text;
}

class OutlineBadge extends PendingBadge {
  const OutlineBadge(super.text);
}

class PillBadge extends PendingBadge {
  const PillBadge(super.text, this.tone);
  final DashTone tone;
}

class NoteBadge extends PendingBadge {
  const NoteBadge(super.text, {this.fullLine = false});
  final bool fullLine;
}

/// One thing waiting, whatever its kind (`Pending`).
class Pending {
  const Pending({
    required this.key,
    required this.section,
    required this.type,
    required this.icon,
    required this.who,
    required this.kind,
    required this.detail,
    required this.at,
    required this.source,
    this.badges = const [],
    this.approveMode = ApproveMode.oneClick,
    this.rejectOnly = false,
    this.reasonRequired = false,
    this.reasonOptional = false,
    this.effect,
    this.bulk = false,
  });

  final String key;
  final ApprovalSection section;
  final PendingType type;
  final String icon;
  final String who;
  final String kind;
  final List<PendingBadge> badges;
  final String detail;

  /// Sort key: the server's time (or a claim's day), newest first.
  final String at;

  /// The row it came from ([StaffRequest], [SalaryAdvance], [Adjustment],
  /// [Swap], [OpenShift], [AttendanceRecord]).
  final Object source;
  final ApproveMode approveMode;

  /// Its month is approved or paid: only a rejection goes through.
  final bool rejectOnly;

  /// A rejection that must say why (money, D8).
  final bool reasonRequired;

  /// A rejection that may say why (a request's note).
  final bool reasonOptional;

  /// What approving does, in plain words.
  final String? effect;

  /// Approved in one step with nothing to ask: it can go in a batch.
  final bool bulk;

  /// May be ticked for a batch (`i.bulk && !i.rejectOnly && !i.locked`).
  bool get batchable => bulk && !rejectOnly;
}

// ── requests (staff/requests-inbox.tsx) ─────────────────────────────────────

/// A request kind's glyph and words (`KINDS`).
typedef RequestKindMeta = ({String icon, String labelKey});

const Map<String, RequestKindMeta> _kinds = {
  'leave': (icon: 'calendar-off', labelKey: 'staff.kindLeave'),
  'late_arrival': (icon: 'timer', labelKey: 'staff.kindLateArrival'),
  'early_departure': (icon: 'log-out', labelKey: 'staff.kindEarlyDeparture'),
  'excuse': (icon: 'clock-3', labelKey: 'staff.kindExcuse'),
  'mission': (icon: 'plane', labelKey: 'staff.kindMission'),
  'correction': (icon: 'shield-check', labelKey: 'dawam.kindCorrection'),
};

/// `kindMeta`: an unknown kind reads as leave, as the web's does.
RequestKindMeta requestKindMeta(String kind) =>
    _kinds[kind] ?? _kinds['leave']!;

/// Kinds whose approval carries a paid/unpaid call (`ASKS_PAY`).
const Set<String> asksPay = {'leave', 'excuse', 'early_departure'};

/// The caller's own request: the server says so (`is_own`), else guessed
/// from the employees linked to the signed-in user (`isMine`).
bool isMine(StaffRequest r, Set<String> own) =>
    r.isOwn ?? own.contains(r.employeeId);

/// May the caller approve or reject it (`mayDecide`)? The server decides
/// (`can_decide`); without it, pending and not theirs.
bool mayDecide(StaffRequest r, Set<String> own) =>
    r.status == 'pending' && (r.canDecide ?? !isMine(r, own));

String _wire(DashFormat f, String? s) =>
    s == null || s.isEmpty ? '' : f.fmtWireTime(s.length > 5 ? s.substring(0, 5) : s);

/// "10 Sept → 12 Sept", "arriving by 10:00 AM", "in 09:12 AM → 09:00 AM"
/// (`describeWindow`).
String describeWindow(StaffRequest r, Translator t, DashFormat f) {
  switch (r.kind) {
    case 'late_arrival':
      return t(
        'staff.windowLate',
        args: {'date': f.fmtDate(r.onDate), 'time': _wire(f, r.toTime)},
      );
    case 'early_departure':
      return t(
        'staff.windowEarly',
        args: {'date': f.fmtDate(r.onDate), 'time': _wire(f, r.fromTime)},
      );
    case 'excuse':
      return t(
        'staff.windowExcuse',
        args: {
          'date': f.fmtDate(r.onDate),
          'from': _wire(f, r.fromTime),
          'to': _wire(f, r.toTime),
        },
      );
    case 'correction':
      // What changes: the record's punch now → the proposed time.
      final parts = [f.fmtDate(r.onDate)];
      if (r.fromTime != null && r.fromTime!.isNotEmpty) {
        final now = f.fmtTime(r.recordCheckInAt?.toUtc().toIso8601String());
        final to = _wire(f, r.fromTime);
        parts.add(
          now == to
              ? t('staff.correctionInSet', args: {'to': to})
              : t('staff.correctionIn', args: {'now': now, 'to': to}),
        );
      }
      if (r.toTime != null && r.toTime!.isNotEmpty) {
        final now = f.fmtTime(r.recordCheckOutAt?.toUtc().toIso8601String());
        final to = _wire(f, r.toTime);
        parts.add(
          now == to
              ? t('staff.correctionOutSet', args: {'to': to})
              : t('staff.correctionOut', args: {'now': now, 'to': to}),
        );
      }
      return parts.join(' · ');
    case 'leave' when r.isHalfDay:
      return t('staff.windowHalfDay', args: {'date': f.fmtDate(r.onDate)});
    default:
      return r.endDate != null && r.endDate != r.onDate
          ? '${f.fmtDate(r.onDate)} → ${f.fmtDate(r.endDate)}'
          : f.fmtDate(r.onDate);
  }
}

/// What approving a request DOES (`approveMeans`).
String approveMeans(StaffRequest r, Translator t, DashFormat f) =>
    switch (r.kind) {
      'leave' => t('dawamOps.meansLeave'),
      'late_arrival' => t(
        'dawamOps.meansLate',
        args: {'time': _wire(f, r.toTime)},
      ),
      'early_departure' => t(
        'dawamOps.meansEarly',
        args: {'time': _wire(f, r.fromTime)},
      ),
      'excuse' => t('dawamOps.meansExcuse'),
      'mission' => t('dawamOps.meansMission'),
      'correction' => t('dawamOps.meansCorrection'),
      _ => '',
    };

/// What the server says about a request beyond its kind (`RequestBadges`
/// with `mine` false: Approvals never lists the caller's own).
List<PendingBadge> requestBadges(StaffRequest r, Translator t) => [
  if (r.isPaid == false) OutlineBadge(t('staff.unpaidBadge')),
  if (r.kind == 'leave' && r.isHalfDay)
    OutlineBadge(switch (r.leaveHalf) {
      'second' => t('staff.halfSecond'),
      'first' => t('staff.halfFirst'),
      _ => t('staff.halfDayUnsaid'),
    }),
  if (r.toOwner == true) OutlineBadge(t('staff.toOwner')),
  if (r.monthClosed == true && r.status == 'pending')
    OutlineBadge(t('staff.monthClosedRejectOnly')),
];

// ── advances (dawam/phase-d.ts, money-dialogs.tsx) ──────────────────────────

/// Where an advance stands against the owner's cap (`capView`): the figures
/// only when the server sends the cap (null for someone who may not read the
/// salary it reveals).
({bool within, int owed, int? cap}) capView(SalaryAdvance a) =>
    (within: a.withinCap, owed: a.outstandingPiastres, cap: a.capPiastres);

/// The cap note (`AdvanceCapNote`): "Within cap" / "Over cap" / "Over the
/// cap: only the owner can approve", then the figures when sent.
List<PendingBadge> advanceCapNote(
  SalaryAdvance a,
  Translator t,
  DashFormat f, {
  required bool mayPassCap,
}) {
  final v = capView(a);
  return [
    PillBadge(
      v.within
          ? t('dawam.withinCap')
          : mayPassCap
          ? t('dawam.overCap')
          : t('dawam.overCapOwner'),
      v.within ? DashTone.success : DashTone.warning,
    ),
    if (v.cap != null)
      NoteBadge(
        t(
          'dawam.capFigures',
          args: {'owed': f.fmtMoney(v.owed), 'cap': f.fmtMoney(v.cap)},
        ),
      ),
  ];
}

/// A JavaScript number as `${n}` writes it: `10`, `12.5`.
String jsNumber(num n) =>
    n is double && n == n.truncateToDouble() && n.isFinite
    ? n.toInt().toString()
    : '$n';

String _iso(DateTime d) => d.toUtc().toIso8601String();

/// A name or a typed line inside an Arabic sentence keeps its own direction:
/// "Morning · 11 Oct" must not pull the date's figures into the English run.
String _bdi(String? s) => '\u2068$s\u2069';

/// The closed-month note on a cover or overtime (`ClosedMonthNote`).
List<PendingBadge> _closedMonth(Translator t) => [
  OutlineBadge(t('staff.monthClosedRejectOnly')),
  NoteBadge(t('dawam.closedMonthNextLine'), fullLine: true),
];

/// Every item this person may decide, newest first (`items`). A list left
/// null is one this person may not decide (never requested).
List<Pending> buildPending({
  required Translator t,
  required DashFormat f,
  required bool mayPassCap,
  Set<String> own = const {},
  List<StaffRequest>? requests,
  List<SalaryAdvance>? advances,
  List<Adjustment>? payLines,
  List<Swap>? swaps,
  List<OpenShift>? claims,
  List<AttendanceRecord>? covers,
  List<AttendanceRecord>? overtime,
}) {
  final out = <Pending>[];
  for (final r in requests ?? const <StaffRequest>[]) {
    // Only what the server says this caller may decide (`can_decide`).
    if (!mayDecide(r, own)) continue;
    final meta = requestKindMeta(r.kind);
    final pay = asksPay.contains(r.kind);
    final closed = r.monthClosed == true;
    out.add(
      Pending(
        key: 'q|${r.id}',
        section: ApprovalSection.requests,
        type: PendingType.request,
        icon: meta.icon,
        who: r.employeeName ?? '—',
        kind: t(meta.labelKey),
        badges: requestBadges(r, t),
        detail: [
          describeWindow(r, t, f),
          r.title,
          r.reason,
        ].where((s) => s != null && s.isNotEmpty).map(_bdi).join(' · '),
        at: _iso(r.createdAt),
        source: r,
        approveMode: pay
            ? ApproveMode.withPay
            : r.kind == 'mission'
            ? ApproveMode.mission
            : ApproveMode.oneClick,
        rejectOnly: closed,
        reasonOptional: true,
        effect: approveMeans(r, t, f),
        // A pay question or a mission over worked days needs its own look.
        bulk: !pay && r.kind != 'mission' && !closed,
      ),
    );
  }
  for (final a in advances ?? const <SalaryAdvance>[]) {
    if (a.status != 'pending') continue;
    out.add(
      Pending(
        key: 'v|${a.id}',
        section: ApprovalSection.money,
        type: PendingType.advance,
        icon: 'hand-coins',
        who: a.employeeName ?? '—',
        kind: t('dawam.salaryAdvance'),
        detail: [
          t(
            'dawam.advanceMeta',
            args: {'amount': f.fmtMoney(a.amountPiastres)},
            count: a.installments,
          ),
          a.reason,
        ].where((s) => s != null && s.isNotEmpty).map(_bdi).join(' · '),
        at: _iso(a.createdAt),
        source: a,
        badges: advanceCapNote(a, t, f, mayPassCap: mayPassCap),
        approveMode: ApproveMode.review,
        // Over the cap, only the owner can approve; a manager may reject (D7).
        rejectOnly: !capView(a).within && !mayPassCap,
        reasonRequired: true,
        effect: t('dawamOps.meansAdvance'),
      ),
    );
  }
  for (final a in payLines ?? const <Adjustment>[]) {
    final bonus = a.kind == 'bonus';
    out.add(
      Pending(
        key: 'a|${a.kind}|${a.id}',
        section: ApprovalSection.money,
        type: PendingType.payLine,
        icon: 'receipt-text',
        who: a.employeeName,
        kind: bonus ? t('dawam.bonusOverLimit') : t('dawam.deductionOverLimit'),
        detail: [
          a.percentOfBase != null
              ? '${jsNumber(a.percentOfBase!)}%'
              : f.fmtMoney(a.amountPiastres ?? 0),
          _bdi(a.reason),
        ].join(' · '),
        at: _iso(a.createdAt),
        source: a,
        reasonRequired: true,
        effect: bonus ? t('dawamOps.meansBonus') : t('dawamOps.meansDeduction'),
      ),
    );
  }
  for (final s in swaps ?? const <Swap>[]) {
    out.add(
      Pending(
        key: 'w|${s.id}',
        section: ApprovalSection.shifts,
        type: PendingType.swap,
        icon: 'arrow-left-right',
        who: '${s.requesterName} ↔ ${s.peerName}',
        kind: t('dawam.swap'),
        detail:
            '${_bdi(s.requesterShiftName)} ${f.fmtDate(s.requesterDate)} ↔ '
            '${_bdi(s.peerShiftName)} ${f.fmtDate(s.peerDate)}',
        at: _iso(s.createdAt),
        source: s,
        effect: t('dawamOps.meansSwap'),
        bulk: true,
      ),
    );
  }
  for (final o in claims ?? const <OpenShift>[]) {
    if (o.status != 'claimed') continue;
    out.add(
      Pending(
        key: 'o|${o.id}',
        section: ApprovalSection.shifts,
        type: PendingType.claim,
        icon: 'calendar-plus',
        who: o.claimedByName ?? '—',
        kind: t('dawam.openShiftClaim'),
        detail: '${_bdi(o.shiftName)} · ${f.fmtDate(o.onDate)}',
        at: o.onDate,
        source: o,
        effect: t('dawamOps.meansClaim'),
        bulk: true,
      ),
    );
  }
  for (final r in covers ?? const <AttendanceRecord>[]) {
    if (r.coveredEmployeeId == null || r.coverStatus != 'pending') continue;
    final closed = r.monthClosed == true;
    out.add(
      Pending(
        key: 'c|${r.id}',
        section: ApprovalSection.shifts,
        type: PendingType.cover,
        icon: 'user-round-check',
        who: r.employeeName ?? '—',
        kind: t('dawam.cover'),
        detail: t(
          'dawam.coverDetail',
          args: {
            'shift': _bdi(r.workShiftName ?? ''),
            'date': f.fmtDate(r.businessDate),
            'from': f.fmtTime(r.checkInAt?.toUtc().toIso8601String()),
          },
        ),
        at: _iso(r.checkInAt ?? r.createdAt),
        source: r,
        effect: t('dawamOps.meansCover'),
        bulk: !closed,
        // A closed month can't take a confirmed cover; rejecting still goes.
        rejectOnly: closed,
        badges: closed ? _closedMonth(t) : const [],
      ),
    );
  }
  for (final r in overtime ?? const <AttendanceRecord>[]) {
    if (r.overtimeStatus != 'pending') continue;
    final closed = r.monthClosed == true;
    out.add(
      Pending(
        key: 't|${r.id}',
        section: ApprovalSection.shifts,
        type: PendingType.overtime,
        icon: 'timer',
        who: r.employeeName ?? '—',
        kind: t('dawam.overtime'),
        detail:
            '${fmtMinutes(f, r.overtimeMinutes)} · ${f.fmtDate(r.businessDate)}',
        at: _iso(r.checkOutAt ?? r.createdAt),
        source: r,
        effect: t('dawamOps.meansOvertime'),
        bulk: !closed,
        rejectOnly: closed,
        badges: closed ? _closedMonth(t) : const [],
      ),
    );
  }
  return out..sort((a, b) => b.at.compareTo(a.at));
}

/// The items [section] shows.
List<Pending> inSection(List<Pending> items, ApprovalSection section) =>
    section == ApprovalSection.all
    ? items
    : [
        for (final i in items)
          if (i.section == section) i,
      ];
