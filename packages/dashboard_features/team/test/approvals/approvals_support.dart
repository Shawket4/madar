// Shared set-up for the Approvals unit's tests: the real app shell with the
// team area on a seeded mock server, edited per test before pumping.
import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/approvals/approvals_data.dart';
import 'package:dashboard_team/src/approvals/approvals_page.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String approvalsPath = '/staff/approvals';
const String requestsT = '/staff/requests';
const String employeesT = '/staff/employees';
const String advancesT = '/staff/payroll/advances';
const String swapsT = '/staff/swaps';
const String claimsT = '/staff/open-shifts';
const String attendanceT = '/staff/attendance';
const String payLinesT = '/staff/adjustments';
const String decideRequestT = '/staff/requests/{id}/decision';
const String reviewAdvanceT = '/staff/advances/{id}/review';
const String decideAdjustmentT = '/staff/adjustments/{kind}/{id}/decision';
const String decideSwapT = '/staff/swaps/{id}/decision';
const String decideClaimT = '/staff/open-shifts/{id}/decision';
const String decideCoverT = '/staff/attendance/{id}/cover';
const String decideOvertimeT = '/staff/attendance/{id}/overtime';

typedef Srv = ({MockServer server, MockDb db});

/// A seeded server with the core's and the team area's handlers.
Srv approvalsServer({
  Persona persona = Persona.owner,
  void Function(MockDb db)? edit,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  teamArea.registerMocks!(server, db);
  _decisionFallbacks(server, db);
  edit?.call(db);
  return (server: server, db: db);
}

/// Opens Approvals as [persona] on [s] (a fresh seeded server by default).
Future<DashHarness> pumpApprovals(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  Srv? s,
  void Function(MockDb db)? edit,
  String path = approvalsPath,
}) {
  final srv = s ?? approvalsServer(persona: persona, edit: edit);
  return DashHarness.pump(
    tester,
    areas: const [teamArea],
    path: path,
    persona: persona,
    size: size,
    locale: locale,
    dark: dark,
    server: srv.server,
    db: srv.db,
    shotArea: 'team',
  );
}

/// Answers `/authz/me` with only [caps] (everywhere unless [everywhere]).
void answerAuthz(
  MockServer server,
  List<String> caps, {
  List<String>? everywhere,
}) {
  server.on('GET', '/authz/me', (req) {
    final sorted = [...caps]..sort();
    return MockResponse.ok({
      'user_id': req.persona.userId,
      'branch_id': req.q('branch_id'),
      'capabilities': sorted,
      'everywhere': everywhere ?? sorted,
      'ask_manager': <String>[],
      'limits': <String, Object?>{},
      'owner': false,
      'platform': false,
      'role_kinds': req.persona.roleKinds,
      'epoch': 1,
      'spec_version': 2,
    });
  });
}

/// The decision endpoints other units own (Requests: `decideRequest`;
/// Payroll: `reviewAdvance`, `decideAdjustment`), answered here only while
/// those units have not registered them, as the backend does: the right,
/// one decision only, a rejection's reason (D8).
void _decisionFallbacks(MockServer server, MockDb db) {
  Never already(MockRequest req, String status, [String code = 'ALREADY_DECIDED']) =>
      req.fail(
        MockResponse.error(
          409,
          'This was already decided ($status).',
          code: code,
          vars: {'status': status},
        ),
      );
  Never noReason(MockRequest req) => req.fail(
    MockResponse.error(400, 'Say why: this needs a reason.', code: 'REASON_REQUIRED'),
  );
  if (!server.handles('PATCH', decideRequestT)) {
    server.on('PATCH', decideRequestT, (req) {
      req.requireCap('hr.leave.edit');
      final row = db[TeamTables.requests].find(req.param('id'));
      if (row == null || row['org_id'] != req.orgId) {
        req.fail(MockResponse.error(404, 'Request not found', code: 'REQUEST_NOT_FOUND'));
      }
      final status = row['status']! as String;
      if (status != 'pending') already(req, status, 'REQUEST_ALREADY_DECIDED');
      final body = req.json;
      final to = body['status']! as String;
      db[TeamTables.requests].update(row['id']! as String, {
        'status': to,
        'decision_note': body['note'],
        if (body.containsKey('is_paid')) 'is_paid': body['is_paid'],
        'decided_by': req.persona.userId,
        'decided_at': db.nowIso,
      });
      return MockResponse.ok(db[TeamTables.requests].find(row['id']! as String));
    });
  }
  if (!server.handles('PATCH', reviewAdvanceT)) {
    server.on('PATCH', reviewAdvanceT, (req) {
      req.requireCap('hr.advances.decide');
      final row = db[TeamTables.advances].find(req.param('id'));
      if (row == null || row['org_id'] != req.orgId) {
        req.fail(MockResponse.error(404, 'Advance not found', code: 'ADVANCE_NOT_FOUND'));
      }
      final body = req.json;
      final approve = body['approve'] == true;
      final reason = ((body['reason'] ?? body['note']) as String?)?.trim() ?? '';
      if (!approve && reason.isEmpty) noReason(req);
      final status = row['status']! as String;
      if (status != 'pending') already(req, status);
      final amount = (body['amount_piastres'] as int?) ?? row['amount_piastres']! as int;
      db[TeamTables.advances].update(row['id']! as String, {
        'status': approve ? 'approved' : 'rejected',
        'amount_piastres': amount,
        if (body['installments'] != null) 'installments': body['installments'],
        'decision_note': reason.isEmpty ? null : reason,
      });
      return MockResponse.ok(db[TeamTables.advances].find(row['id']! as String));
    });
  }
  if (!server.handles('PATCH', decideAdjustmentT)) {
    server.on('PATCH', decideAdjustmentT, (req) {
      req.requireCap('hr.payroll.run');
      final row = db[TeamTables.adjustments].find(req.param('id'));
      if (row == null || row['kind'] != req.param('kind')) {
        req.fail(MockResponse.error(404, 'Adjustment not found', code: 'ADJUSTMENT_NOT_FOUND'));
      }
      final body = req.json;
      final approve = body['approve'] == true;
      final reason = (body['reason'] as String?)?.trim() ?? '';
      if (!approve && reason.isEmpty) noReason(req);
      final status = row['status']! as String;
      if (status != 'pending') already(req, status);
      db[TeamTables.adjustments].update(row['id']! as String, {
        'status': approve ? 'approved' : 'rejected',
        'decision_note': reason.isEmpty ? null : reason,
      });
      return MockResponse.ok(db[TeamTables.adjustments].find(row['id']! as String));
    });
  }
}

// ── Seed helpers ───────────────────────────────────────────────────────────

String emp(String key) => SeedIds.employee(key);

/// Today in Cairo (`2026-10-08`) and [n] days from it.
String day([int n = 0]) {
  final d = DateTime.utc(2026, 10, 8).add(Duration(days: n));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Every pending row of every list removed: the queue is empty.
void emptyQueue(MockDb db) {
  db[TeamTables.requests].removeWhere((r) => r['status'] == 'pending');
  db[TeamTables.advances].removeWhere((r) => r['status'] == 'pending');
  db[TeamTables.adjustments].removeWhere((r) => r['status'] == 'pending');
  db[TeamTables.swaps].removeWhere((r) => r['status'] == 'pending');
  db[TeamTables.openShifts].removeWhere((r) => r['status'] == 'claimed');
  for (final r in db[TeamTables.attendance].rows) {
    if (r['cover_status'] == 'pending' || r['overtime_status'] == 'pending') {
      db[TeamTables.attendance].update(r['id']! as String, {
        if (r['cover_status'] == 'pending') 'cover_status': 'confirmed',
        if (r['overtime_status'] == 'pending') 'overtime_status': 'approved',
      });
    }
  }
}

/// Only [keep]'s lists keep their pending rows (`requests`, `advances`,
/// `payLines`, `swaps`, `claims`, `covers`, `overtime`).
void onlyPending(MockDb db, Set<String> keep) {
  if (!keep.contains('requests')) {
    db[TeamTables.requests].removeWhere((r) => r['status'] == 'pending');
  }
  if (!keep.contains('advances')) {
    db[TeamTables.advances].removeWhere((r) => r['status'] == 'pending');
  }
  if (!keep.contains('payLines')) {
    db[TeamTables.adjustments].removeWhere((r) => r['status'] == 'pending');
  }
  if (!keep.contains('swaps')) {
    db[TeamTables.swaps].removeWhere((r) => r['status'] == 'pending');
  }
  if (!keep.contains('claims')) {
    db[TeamTables.openShifts].removeWhere((r) => r['status'] == 'claimed');
  }
  for (final r in db[TeamTables.attendance].rows) {
    db[TeamTables.attendance].update(r['id']! as String, {
      if (!keep.contains('covers') && r['cover_status'] == 'pending')
        'cover_status': 'confirmed',
      if (!keep.contains('overtime') && r['overtime_status'] == 'pending')
        'overtime_status': 'approved',
    });
  }
}

/// A request row as the model writes it, for a test's own data.
MockRow requestRow({
  required String id,
  required String employeeKey,
  required String kind,
  required String onDate,
  String? endDate,
  String? fromTime,
  String? toTime,
  String? reason,
  String? title,
  bool isHalfDay = false,
  String? leaveHalf,
  bool? paidDefault,
  bool? isPaid,
  bool? canDecide,
  bool? isOwn,
  bool? toOwner,
  bool? monthClosed,
  List<String>? workedDates,
  DateTime? recordCheckInAt,
  DateTime? recordCheckOutAt,
  DateTime? createdAt,
}) {
  final e = MockSeed.instance.employees.firstWhere((e) => e.id == emp(employeeKey));
  final at = createdAt ?? DateTime.utc(2026, 10, 7, 9);
  return StaffRequest(
    id: id,
    orgId: e.orgId,
    employeeId: e.id,
    employeeName: e.name,
    kind: kind,
    status: 'pending',
    onDate: onDate,
    endDate: endDate,
    fromTime: fromTime,
    toTime: toTime,
    isHalfDay: isHalfDay,
    leaveHalf: leaveHalf,
    paidDefault: paidDefault,
    isPaid: isPaid,
    canDecide: canDecide,
    isOwn: isOwn,
    toOwner: toOwner,
    monthClosed: monthClosed,
    workedDates: workedDates,
    recordCheckInAt: recordCheckInAt,
    recordCheckOutAt: recordCheckOutAt,
    reason: reason,
    title: title,
    createdAt: at,
    updatedAt: at,
  ).toJson();
}

// ── Finders ────────────────────────────────────────────────────────────────

final Finder page = find.byType(ApprovalsQueue);

Finder inPage(Finder f) => find.descendant(of: page, matching: f);

Finder pageText(String s) => inPage(find.text(s));

/// Text containing [s] (rich text too) on the page.
Finder pageHas(String s) => inPage(find.textContaining(s, findRichText: true));

/// The row of the item whose title or words show [text].
Finder rowOf(String text) => find
    .ancestor(of: pageHas(text).first, matching: find.byType(PendingRow))
    .first;

Finder inRow(String text, Finder f) =>
    find.descendant(of: rowOf(text), matching: f);

/// The row's Approve button.
Finder approveIn(String text) => inRow(
  text,
  find.byWidgetPredicate((w) => w is DashButton && w.icon == 'check'),
);

/// The row's Reject control (a word from 640 wide, a glyph below).
Finder rejectIn(String text) => inRow(
  text,
  find.byWidgetPredicate(
    (w) =>
        (w is DashButton && w.icon == 'x') ||
        (w is DashIconButton && w.icon == 'x'),
  ),
);

/// The [index]th row of [type] (newest first).
Finder rowOfType(PendingType type, {int? index}) {
  final f = find.byWidgetPredicate(
    (w) => w is PendingRow && w.item.type == type,
  );
  return index == null ? f : f.at(index);
}

/// The item a row shows.
Pending itemOf(WidgetTester tester, Finder row) =>
    tester.widget<PendingRow>(row).item;

/// [row]'s Approve button.
Finder approveOf(Finder row) => find.descendant(
  of: row,
  matching: find.byWidgetPredicate((w) => w is DashButton && w.icon == 'check'),
);

/// [row]'s Reject control.
Finder rejectOf(Finder row) => find.descendant(
  of: row,
  matching: find.byWidgetPredicate(
    (w) =>
        (w is DashButton && w.icon == 'x') ||
        (w is DashIconButton && w.icon == 'x'),
  ),
);

/// The open dialog / sheet (the last `DashSurface`).
Finder surface() => find.byType(DashSurface).last;

Finder inSurface(Finder f) => find.descendant(of: surface(), matching: f);

Finder surfaceText(String s) => inSurface(find.text(s));

/// The confirm card.
Finder confirmCard() => find.byType(DashConfirmDialog);

Finder inConfirm(Finder f) => find.descendant(of: confirmCard(), matching: f);

/// How many shown rows may go in a batch.
int batchCount(WidgetTester tester) => tester
    .widgetList<PendingRow>(inPage(find.byType(PendingRow)))
    .where((r) => r.item.batchable)
    .length;

/// How many rows the queue lists.
int rowCount() => inPage(find.byType(PendingRow)).evaluate().length;

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  final scroll = find
      .descendant(of: page, matching: find.byType(Scrollable))
      .evaluate()
      .map((e) => (e as StatefulElement).state as ScrollableState)
      .where((s) => s.position.axis == Axis.vertical)
      .toList();
  if (scroll.isEmpty) {
    final outer = find
        .ancestor(of: page, matching: find.byType(Scrollable))
        .evaluate()
        .map((e) => (e as StatefulElement).state as ScrollableState)
        .where((s) => s.position.axis == Axis.vertical)
        .toList();
    scroll.addAll(outer);
  }
  if (scroll.isEmpty) {
    await h.shot('approvals/$name-1');
    return;
  }
  final position = scroll.first.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('approvals/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}
