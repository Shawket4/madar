// The Requests unit's mock handlers against hand-computed answers and the
// backend's refusals (MadarRust `src/staff/requests.rs`).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show Translator, ensureTimeZones;
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/requests/requests_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'requests_support.dart';

Matcher refused(int status, [String? code]) => throwsA(
  isA<ApiException>()
      .having((e) => e.status, 'status', status)
      .having((e) => e.code, 'code', code),
);

void main() {
  late MockDb db;
  StaffApi api([Persona p = Persona.owner]) {
    final s = MockServer(persona: p, clock: db.clock);
    registerCoreMocks(s, db);
    registerTeamMocks(s, db);
    return DashboardApi(s).staff;
  }

  setUpAll(ensureTimeZones);
  setUp(() => TeamSeed.loadInto(db = MockDb.seeded()));

  group('GET /staff/requests', () {
    test('pending first, then the latest day; filters by status and kind', () async {
      final all = await api().listRequests();
      final pending = all.takeWhile((r) => r.status == 'pending').length;
      expect(all.skip(pending).where((r) => r.status == 'pending'), isEmpty);
      final days = [for (final r in all.take(pending)) r.onDate];
      expect(days, [...days]..sort((a, b) => b.compareTo(a)));
      final leave = await api().listRequests(kind: 'leave', status: 'pending');
      expect(leave, isNotEmpty);
      expect(leave.every((r) => r.kind == 'leave' && r.status == 'pending'), isTrue);
      await expectLater(api().listRequests(status: 'done'), refused(400, 'STATUS_UNKNOWN'));
      await expectLater(api().listRequests(kind: 'nap'), refused(400, 'REQUEST_KIND_UNKNOWN'));
    });

    test('works out is_own, can_decide, to_owner and month_closed for the caller', () async {
      db[TeamTables.requests].insertAll([
        requestRow(id: 'rq-karim', employeeKey: 'karim', kind: 'late_arrival',
            onDate: day(1), toTime: '10:00:00'),
        requestRow(id: 'rq-laila', employeeKey: 'laila', kind: 'late_arrival',
            onDate: day(1), toTime: '10:00:00'),
        requestRow(id: 'rq-old', employeeKey: 'laila', kind: 'leave',
            onDate: '2026-09-29', endDate: '2026-10-02'),
      ]);
      StaffRequest of(List<StaffRequest> rows, String id) =>
          rows.firstWhere((r) => r.id == id);
      final owner = await api().listRequests();
      // A manager's request goes to the owner, who outranks them.
      expect(of(owner, 'rq-karim').toOwner, isTrue);
      expect(of(owner, 'rq-karim').canDecide, isTrue);
      expect(of(owner, 'rq-laila').toOwner, isFalse);
      // September is paid: a leave reaching into it is in a closed month.
      expect(of(owner, 'rq-old').monthClosed, isTrue);
      expect(of(owner, 'rq-laila').monthClosed, isFalse);
      final manager = await api(Persona.manager).listRequests();
      expect(of(manager, 'rq-karim').isOwn, isTrue);
      expect(of(manager, 'rq-karim').canDecide, isFalse);
      expect(of(manager, 'rq-laila').canDecide, isTrue);
      // Karim sees only Zamalek's people.
      expect(manager.map((r) => r.employeeName).toSet(),
          everyElement(isIn(['Karim Adel', 'Laila Ehab', 'Youssef Samir',
              'Mariam Fathy', 'Adham Reda', 'Hassan Ibrahim'])));
      await expectLater(api(Persona.limited).listRequests(), refused(403));
    });
  });

  group('POST /staff/requests', () {
    NewRequestForm form(String kind, String who) => NewRequestForm(onDate: day(3))
      ..kind = kind
      ..employeeId = emp(who);

    test('files pending for someone else, with the shape its kind needs', () async {
      final excuse = await api().createRequestAdmin(
        body: newRequestBody(form('excuse', 'laila')
          ..fromTime = '22:00'
          ..toTime = '01:00'),
      );
      expect(excuse.status, 'pending');
      // Ending before it starts runs past midnight.
      expect(excuse.endDate, day(4));
      final mission = await api().createRequestAdmin(
        body: newRequestBody(form('mission', 'laila')..reason = 'Roastery visit'),
      );
      expect(mission.title, 'Roastery visit');
      await expectLater(
        api().createRequestAdmin(body: newRequestBody(form('mission', 'ali'))),
        refused(400, 'MISSION_TITLE_REQUIRED'),
      );
      await expectLater(
        api().createRequestAdmin(body: newRequestBody(form('excuse', 'laila')
          ..fromTime = '22:30'
          ..toTime = '23:00')),
        refused(409, 'OVERLAPPING_REQUEST'),
      );
      await expectLater(
        api().createRequestAdmin(body: newRequestBody(
            NewRequestForm(onDate: '2026-09-20')
              ..kind = 'late_arrival'
              ..employeeId = emp('ali'))),
        refused(409, 'PERIOD_CLOSED'),
      );
    });

    test('one\'s own leave with self-approve is approved as filed, and must say paid', () async {
      final own = form('leave', 'nour');
      await expectLater(
        api().createRequestAdmin(body: newRequestBody(own)),
        refused(400, 'LEAVE_PAY_REQUIRED'),
      );
      final row = await api().createRequestAdmin(body: newRequestBody(own..pay = 'unpaid'));
      expect(row.status, 'approved');
      expect(row.isPaid, isFalse);
      expect(row.decidedByName, 'Nour El-Sayed');
    });

    test('refusals: no right, someone outside the branch', () async {
      await expectLater(
        api(Persona.manager).createRequestAdmin(body: newRequestBody(form('leave', 'laila'))),
        refused(403),
      );
    });
  });

  group('PATCH /staff/requests/{id}/decision', () {
    setUp(() => db[TeamTables.requests].insertAll([
      requestRow(id: 'rq-l', employeeKey: 'laila', kind: 'leave', onDate: day(5)),
      requestRow(id: 'rq-k', employeeKey: 'karim', kind: 'late_arrival',
          onDate: day(1), toTime: '10:00:00'),
      requestRow(id: 'rq-c', employeeKey: 'laila', kind: 'correction',
          onDate: day(-1), fromTime: '09:00:00', status: 'approved'),
    ]));

    test('approve leave needs is_paid; one decision only', () async {
      await expectLater(
        api().decideRequest(id: 'rq-l', body: const RequestDecision(status: 'approved')),
        refused(400, 'LEAVE_PAY_REQUIRED'),
      );
      final ok = await api().decideRequest(
        id: 'rq-l',
        body: const RequestDecision(status: 'approved', isPaid: false),
      );
      expect((ok.status, ok.isPaid, ok.decidedByName), ('approved', false, 'Nour El-Sayed'));
      await expectLater(
        api().decideRequest(id: 'rq-l', body: const RequestDecision(status: 'rejected')),
        refused(409, 'REQUEST_ALREADY_DECIDED'),
      );
    });

    test('never one\'s own; a manager\'s is decided above them', () async {
      await expectLater(
        api(Persona.manager).decideRequest(
            id: 'rq-k', body: const RequestDecision(status: 'rejected')),
        refused(403, 'OWN_REQUEST'),
      );
      final r = await api().decideRequest(
          id: 'rq-k', body: const RequestDecision(status: 'rejected'));
      expect(r.status, 'rejected');
    });

    test('cancel: someone else\'s or an approved one says why; never an applied correction', () async {
      await expectLater(
        api().decideRequest(id: 'rq-l', body: const RequestDecision(status: 'cancelled')),
        refused(400, 'CANCEL_REASON_REQUIRED'),
      );
      // One's own pending request goes without a reason, and needs no right.
      final own = await api(Persona.manager).decideRequest(
          id: 'rq-k', body: const RequestDecision(status: 'cancelled'));
      expect((own.status, own.cancelledByName), ('cancelled', 'Karim Adel'));
      await expectLater(
        api().decideRequest(
            id: 'rq-c', body: const RequestDecision(status: 'cancelled', note: 'Wrong')),
        refused(409, 'CORRECTION_APPLIED'),
      );
      final done = await api().decideRequest(
          id: 'rq-l', body: const RequestDecision(status: 'cancelled', note: 'Shop closed'));
      expect((done.cancelNote, done.decisionNote), ('Shop closed', null));
    });

    test('a closed month refuses approving, never rejecting', () async {
      db[TeamTables.requests].insert(requestRow(id: 'rq-old', employeeKey: 'laila',
          kind: 'late_arrival', onDate: '2026-09-20', toTime: '10:00:00'));
      await expectLater(
        api().decideRequest(id: 'rq-old', body: const RequestDecision(status: 'approved')),
        refused(409, 'PERIOD_CLOSED'),
      );
      final r = await api().decideRequest(
          id: 'rq-old', body: const RequestDecision(status: 'rejected'));
      expect(r.status, 'rejected');
    });
  });

  group('the form\'s rules', () {
    const t = _T();
    test('newRequestBody sends what the web sends, kind by kind', () {
      final late = NewRequestForm(onDate: '2026-10-10')
        ..employeeId = 'e1'
        ..reason = '  ';
      expect(newRequestBody(late).toJson(), {
        'employee_id': 'e1',
        'kind': 'late_arrival',
        'on_date': '2026-10-10',
        'end_date': null,
        'from_time': null,
        'to_time': '14:00:00',
        'title': null,
        'reason': null,
      });
      final half = NewRequestForm(onDate: '2026-10-10')
        ..kind = 'leave'
        ..halfDay = true
        ..leaveHalf = 'second';
      expect(newRequestBody(half).toJson(), containsPair('is_half_day', true));
      expect(newRequestBody(half).toJson(), containsPair('leave_half', 'second'));
      expect(newRequestBody(half).toJson(), containsPair('end_date', null));
    });

    test('problems: the end before the start, a time missing, a mission with no words', () {
      final v = NewRequestForm(onDate: '2026-10-10')
        ..kind = 'mission'
        ..endDate = '2026-10-09';
      expect(newRequestProblems(v, t).keys, containsAll(['end_date', 'title']));
      final e = NewRequestForm(onDate: '2026-10-10')
        ..kind = 'excuse'
        ..fromTime = '';
      expect(newRequestProblems(e, t).keys, ['from_time']);
    });
  });
}

/// A translator that answers with the key.
class _T implements Translator {
  const _T();
  @override
  dynamic noSuchMethod(Invocation i) => i.positionalArguments.first;
}
