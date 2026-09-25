// staff_core's own tests: the store's contract with the screens (06 B1, B13,
// B16), times in the branch's zone (AT-1), and where a tapped push opens.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';

/// The real core's picture for the employee persona (written by madar-core's
/// `dawam_fixture` test).
String _fixture() =>
    File('../../apps/staff/test/fixtures/e1.json').readAsStringSync();

class _Backend implements DawamBackend {
  _Backend();

  /// What the next action answers: a snapshot, or a refusal.
  Future<String> Function() answer = () async => _fixture();
  final acts = <Map<String, dynamic>>[];
  int signOuts = 0;

  @override
  Future<String> act(Map<String, dynamic> action) {
    acts.add(action);
    return answer();
  }

  int refreshes = 0;

  /// What the core says about the connection in the next picture.
  bool online = true;

  /// Any other change to the picture a snapshot answers.
  void Function(Map<String, dynamic>)? edit;

  @override
  Future<String> snapshot({required bool refresh}) async {
    if (refresh) refreshes++;
    final v = jsonDecode(_fixture()) as Map<String, dynamic>;
    v['online'] = online;
    edit?.call(v);
    return jsonEncode(v);
  }

  /// What a fetch (`dawam_sync`) answers, and how many were asked for.
  Future<String> Function() fetched = () async => _fixture();
  int syncs = 0;

  @override
  Future<String> sync() {
    syncs++;
    return fetched();
  }

  @override
  Future<String> ping(DawamFix fix) async => _fixture();
  @override
  Future<void> otpRequest(String phone) async {}
  @override
  Future<Map<String, dynamic>> otpVerify(
    String phone,
    String code, {
    String? orgId,
  }) async {
    log.add('verify');
    return {'employee_id': 'e2'};
  }

  @override
  Future<DawamFix?> locate() async => null;
  @override
  Stream<DawamFix> track() => const Stream.empty();
  int alwaysAsks = 0;
  @override
  Future<bool> alwaysLocation() async {
    alwaysAsks++;
    return true;
  }

  final trackingCalls = <bool>[];
  @override
  Future<void> tracking({required bool on}) async => trackingCalls.add(on);
  @override
  String? restoredUser() => 'e1';

  /// Holds a sign-out open (Firebase forgetting the token can take 5 s).
  Completer<void>? signOutGate;
  final log = <String>[];
  @override
  Future<void> signOut() async {
    signOuts++;
    log.add('signOut:start');
    await signOutGate?.future;
    log.add('signOut:done');
  }
}

final _refused = DawamError(
  'Outside Zamalek: 340 m away.',
  'برّه الزمالك: على بعد 340 م.',
);

Future<(DawamStore, _Backend)> _store() async {
  final b = _Backend();
  final s = DawamStore(b);
  await s.restore();
  // The restored store polls (2 min) and pings on shift (15 min): stop both,
  // or the test process never goes idle.
  addTearDown(s.stop);
  return (s, b);
}

/// A screen with a button that runs [call] through `attempt`, and records
/// what `attempt` said.
Widget _screen(
  DawamStore store,
  Future<void> Function(DawamStore) call,
  List<bool> results,
) => ProviderScope(
  overrides: [dawamProvider.overrideWith((_) => store)],
  child: MaterialApp(
    theme: MadarTheme.light(),
    home: Consumer(
      builder: (context, ref, _) => Scaffold(
        body: Column(
          children: [
            TextButton(
              onPressed: () async =>
                  results.add(await attempt(ref, () => call(store), ok: 'ok')),
              child: const Text('go'),
            ),
            Text(ref.watch(toastProvider)?.text ?? 'no toast'),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  setUp(() => currentLang = 'en');

  testWidgets(
    'a send refused for want of a connection shows the offline state (E2E S-120, S-167)',
    (t) async {
      final (store, backend) = await _store();
      expect(store.offline, isFalse);
      backend
        ..online = false
        ..answer = () async => throw DawamError(
          'This needs a connection.',
          'This needs a connection.',
        );
      final results = <bool>[];
      await t.pumpWidget(
        _screen(
          store,
          (s) => s.file(ReqKind.leave, from: DateTime(2026, 9, 30)),
          results,
        ),
      );
      await t.tap(find.text('go'));
      await t.pump(const Duration(milliseconds: 50));
      await t.pump(const Duration(milliseconds: 50));
      expect(results, [false]);
      expect(
        store.offline,
        isTrue,
        reason: 'the banner and the disabled buttons follow at once',
      );
      await t.pump(const Duration(seconds: 3));
      store.stop();
    },
  );

  testWidgets(
    'a refused decision reloads the queue (E2E S-235: decided elsewhere)',
    (t) async {
      final (store, backend) = await _store();
      backend.answer = () async => throw DawamError(
        'This request is already approved',
        'This request is already approved',
      );
      final before = backend.refreshes;
      final results = <bool>[];
      await t.pumpWidget(
        _screen(
          store,
          (s) => s.decide(
            Req('q|x', ReqKind.leave, 'e2', DateTime(2026, 9, 22)),
            approve: true,
          ),
          results,
        ),
      );
      await t.tap(find.text('go'));
      await t.pump(const Duration(milliseconds: 50));
      expect(results, [false]);
      expect(
        backend.refreshes,
        greaterThan(before),
        reason: 'the stale card goes: the picture is reloaded',
      );
      await t.pump(const Duration(seconds: 3));
      store.stop();
    },
  );

  // Decision #8: declining a pay line or an advance says why. The sheet
  // sends nothing without a reason, then sends the typed one.
  testWidgets('declining asks why and sends the reason (D8)', (t) async {
    final (store, backend) = await _store();
    final adj = Adj(
      'a|bonus|b1',
      'e2',
      50000,
      'Weekend',
      'e3',
      DateTime(2026, 9, 20),
      DateTime(2026, 8, 26),
      bonus: true,
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [dawamProvider.overrideWith((_) => store)],
        child: MaterialApp(
          theme: MadarTheme.light(),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => declineWithReason(
                  context,
                  (why) => store.decideAdj(adj, yes: false, reason: why),
                ),
                child: const Text('decline'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('decline'));
    await t.pumpAndSettle();
    final send = find.widgetWithText(MadarButton, 'staff.decline');
    await t.tap(send);
    await t.pump();
    expect(backend.acts, isEmpty, reason: 'no reason: nothing is sent');
    await t.enterText(find.byType(TextField), '  Paid twice ');
    await t.tap(send);
    await t.pump(const Duration(milliseconds: 50));
    expect(backend.acts.single, {
      'action': 'decide_adj',
      'adj': 'a|bonus|b1',
      'yes': false,
      'reason': 'Paid twice',
    });
    await t.pump(const Duration(seconds: 3));
    store.stop();
  });

  // Minor #12: "Always" location is asked right after the privacy notice,
  // which already explains tracking, so the first clock-in doesn't wait on
  // a permission prompt.
  test('agreeing to the notice asks for Always location at once', () async {
    final (store, backend) = await _store();
    expect(backend.alwaysAsks, 0);
    await store.acceptPrivacy();
    expect(backend.acts.single['action'], 'accept_privacy');
    expect(backend.alwaysAsks, 1, reason: 'asked with the notice');
    expect(store.alwaysLocation, isTrue);
  });

  // Minor #26: an approved claim that makes a long day comes back with the
  // limits it breaks; the approver is warned, never blocked.
  test('an approved claim carries the limits it breaks', () async {
    final (store, backend) = await _store();
    backend.answer = () async {
      final v = jsonDecode(_fixture()) as Map<String, dynamic>;
      v['filed'] = {
        'id': 'o|o1',
        'status': 'approved',
        'to_owner': false,
        'warnings': [
          [
            'staff.warn_day_hours',
            {'date': '2026-09-27', 'hours': '8', 'worked': '11'},
          ],
        ],
      };
      return jsonEncode(v);
    };
    await store.decide(
      Req('o|o1', ReqKind.openShift, 'e4', DateTime(2026, 9, 25)),
      approve: true,
    );
    expect(store.lastWarnings, hasLength(1));
    expect(store.lastWarnings.single.$1, 'staff.warn_day_hours');
    expect(store.lastWarnings.single.$2['date'], DateTime(2026, 9, 27));
    backend.answer = () async => _fixture();
    await store.decide(
      Req('o|o2', ReqKind.openShift, 'e4', DateTime(2026, 9, 25)),
      approve: true,
    );
    expect(store.lastWarnings, isEmpty);
  });

  group('attempt waits for the server (06 B1)', () {
    testWidgets('a refusal is shown in the server words, never a success', (
      t,
    ) async {
      final (store, backend) = await _store();
      backend.answer = () async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        throw _refused;
      };
      final results = <bool>[];
      final failures = <String>[];
      final sub = store.failures.stream.listen(failures.add);
      await t.pumpWidget(
        _screen(store, (s) => s.clockOut(s.shifts.first), results),
      );
      await t.tap(find.text('go'));
      await t.pump();
      expect(
        results,
        isEmpty,
        reason: 'nothing is said before the server answers',
      );
      expect(find.text('ok'), findsNothing);
      await t.pump(const Duration(milliseconds: 60));
      expect(results, [false]);
      expect(find.text('Outside Zamalek: 340 m away.'), findsOneWidget);
      expect(find.text('ok'), findsNothing);
      expect(failures, isEmpty, reason: 'shown once, by the screen that asked');
      // Not awaited: a broadcast cancel answers from the root zone, and
      // awaiting it inside the fake clock stalls every later pump.
      unawaited(sub.cancel());
      await t.pump(const Duration(seconds: 3));
      store.stop();
    });

    testWidgets('a success is confirmed only after the answer', (t) async {
      final (store, backend) = await _store();
      final gate = Completer<String>();
      backend.answer = () => gate.future;
      final results = <bool>[];
      await t.pumpWidget(_screen(store, (s) => s.readAll(), results));
      await t.tap(find.text('go'));
      await t.pump();
      expect(find.text('ok'), findsNothing);
      gate.complete(_fixture());
      await t.pump();
      await t.pump();
      expect(results, [true]);
      expect(find.text('ok'), findsOneWidget);
      expect(backend.acts.single['action'], 'read_all');
      await t.pump(const Duration(seconds: 3));
      store.stop();
    });

    testWidgets('offline "needs a connection" is a refusal, not a success', (
      t,
    ) async {
      final (store, backend) = await _store();
      backend.answer = () async =>
          throw DawamError('This needs a connection.', 'ده محتاج اتصال.');
      final results = <bool>[];
      await t.pumpWidget(
        _screen(
          store,
          (s) => s.file(ReqKind.leave, from: s.today, note: 'Exam'),
          results,
        ),
      );
      await t.tap(find.text('go'));
      await t.pump();
      await t.pump();
      expect(results, [false]);
      expect(find.text('This needs a connection.'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      store.stop();
    });
  });

  test(
    'outside attempt, a refusal arrives on failures and never throws',
    () async {
      final (store, backend) = await _store();
      backend.answer = () async => throw _refused;
      final failures = <String>[];
      final sub = store.failures.stream.listen(failures.add);
      await store.publish('b', DateTime(2026, 9, 19));
      await Future<void>.delayed(Duration.zero);
      expect(failures, ['Outside Zamalek: 340 m away.']);
      await sub.cancel();
    },
  );

  test(
    'a queued punch refused on reconnect is said once, as a red toast (S-035)',
    () async {
      // E2E posnotif S-035/S-036: a clock-out made offline was refused when
      // the poll sent it; the core reported it and the app said nothing.
      final (store, backend) = await _store();
      const why = "You're 1201 m from the branch. Clock in within 200 m.";
      String withRefused(List<String> r) => jsonEncode(
        (jsonDecode(_fixture()) as Map<String, dynamic>)..['refused'] = r,
      );
      final failures = <String>[];
      final sub = store.failures.stream.listen(failures.add);
      backend.fetched = () async => withRefused([why]);
      store.sync();
      await Future<void>.delayed(Duration.zero);
      expect(failures, [why]);
      backend.fetched = () async => withRefused([]);
      store.sync();
      await Future<void>.delayed(Duration.zero);
      expect(failures, [why], reason: 'the core says it once');
      await sub.cancel();
    },
  );

  test(
    'un-waiving, reopening and a flag deduction carry their reason',
    () async {
      final (store, backend) = await _store();
      await store.unwaive('d|x', 'the cup was not his');
      await store.reopenPayroll('a line was missing');
      final flag = Flag(
        'f1',
        FlagKind.leftMidShift,
        'e2',
        DateTime(2026, 9, 2),
      );
      await store.resolve(flag, 'deduct', deduct: 500, reason: 'left early');
      expect(backend.acts, [
        {'action': 'unwaive', 'key': 'd|x', 'reason': 'the cup was not his'},
        {'action': 'reopen_payroll', 'reason': 'a line was missing'},
        {
          'action': 'resolve',
          'flag': 'f1',
          'how': 'deduct',
          'deduct': 500,
          'reason': 'left early',
        },
      ]);
    },
  );

  test(
    'the record-advance act is one call with what the manager typed',
    () async {
      final (store, backend) = await _store();
      await store.recordAdvance('e2', 150000, 3);
      expect(backend.acts.single, {
        'action': 'record_advance',
        'emp': 'e2',
        'amount': 150000,
        'installments': 3,
      });
    },
  );

  test('a screen asks the core only for dates the phone does not hold, one '
      'ask at a time (H2-01)', () async {
    final (store, backend) = await _store();
    // An older core's picture: no `loaded` (the fixtures now carry one).
    backend.edit = (v) => v.remove('loaded');
    await store.refresh();
    expect(
      store.holds(DateTime(2000), DateTime(2100)),
      isTrue,
      reason: 'a core that says nothing holds whatever it shows',
    );
    final ws = weekStart(store.today);
    DateTime at(int n) => DateTime(ws.year, ws.month, ws.day + n);
    String d(DateTime x) =>
        '${x.year}-${x.month.toString().padLeft(2, '0')}-'
        '${x.day.toString().padLeft(2, '0')}';
    final base = [d(at(-28)), d(at(27))];
    String held(List<List<String>> spans) {
      final v = jsonDecode(_fixture()) as Map<String, dynamic>;
      v['loaded'] = spans;
      return jsonEncode(v);
    }

    backend.edit = (v) => v['loaded'] = [base];
    await store.refresh();
    expect(store.holds(at(0), at(6)), isTrue);
    expect(store.holds(at(21), at(34)), isFalse, reason: 'straddles the end');
    await store.viewRange(at(0), at(6));
    expect(backend.acts, isEmpty, reason: 'held already: nothing to ask');

    final gate = Completer<String>();
    backend.answer = () => gate.future;
    final first = store.viewRange(at(28), at(34));
    expect(store.viewing, isTrue);
    unawaited(store.viewRange(at(28), at(34)));
    expect(backend.acts, [
      {'action': 'view_range', 'from': d(at(28)), 'to': d(at(34))},
    ], reason: 'the same ask while the first is out goes once');
    gate.complete(
      held([
        base,
        [d(at(28)), d(at(34))],
      ]),
    );
    await first;
    expect(store.viewing, isFalse);
    expect(store.holds(at(28), at(34)), isTrue);
  });

  test('the server says who is on payroll and both pay-line limits', () async {
    final (store, _) = await _store();
    expect(store.onPayroll, isTrue, reason: 'the fixture person is paid here');
    expect(store.managerDeductLimit, isNotNull);
  });

  test('an unreadable answer keeps the last picture (06 B13)', () async {
    final (store, backend) = await _store();
    final shifts = store.shifts.length;
    final reported = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = old);
    final broken = jsonDecode(_fixture()) as Map<String, dynamic>;
    ((broken['shifts'] as List<dynamic>).first
            as Map<String, dynamic>)['date'] =
        '';
    backend.answer = () async => jsonEncode(broken);
    await store.readAll();
    expect(store.me, 'e1', reason: 'still signed in');
    expect(store.shifts.length, shifts, reason: 'the last good picture stays');
    expect(reported, hasLength(1), reason: 'and the fault is reported');
  });

  test(
    'after a sign-out a bad picture never brings the last person back',
    () async {
      final (store, backend) = await _store();
      final old = FlutterError.onError;
      FlutterError.onError = (_) {};
      addTearDown(() => FlutterError.onError = old);
      await Future<void>.delayed(Duration.zero); // restore's refresh lands
      store.signOut();
      expect(store.me, isNull);
      expect(backend.signOuts, 1);
      final broken = jsonDecode(_fixture()) as Map<String, dynamic>;
      ((broken['shifts'] as List<dynamic>).first
              as Map<String, dynamic>)['date'] =
          '';
      backend.answer = () async => jsonEncode(broken);
      await store.readAll();
      expect(store.shifts, isEmpty, reason: "no fallback to e1's shifts");
    },
  );

  // E2E roster m3: signing out finishes in the background (the server,
  // then Firebase, then the core). A code typed before it finished was
  // verified first, and the old sign-out then wiped the new session: the
  // notice's "I agree" had nobody to send for.
  test('a new sign-in waits for the last sign-out to finish', () async {
    final (store, backend) = await _store();
    await Future<void>.delayed(Duration.zero); // restore's refresh lands
    final gate = Completer<void>();
    backend.signOutGate = gate;
    store.signOut();
    final verified = store.verifyCode('01000001003', '123456');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(backend.log, ['signOut:start'], reason: 'the code waits');
    gate.complete();
    expect(await verified, isNull);
    expect(backend.log, ['signOut:start', 'signOut:done', 'verify']);
    expect(store.pendingUser, 'e2');
  });

  test('a snapshot with no clock does not crash', () async {
    final (store, backend) = await _store();
    final v = jsonDecode(_fixture()) as Map<String, dynamic>..remove('now');
    backend.answer = () async => jsonEncode(v);
    await store.readAll();
    expect(store.now.difference(DateTime.now()).inSeconds.abs(), lessThan(5));
  });

  test(
    'my claims keep how they ended: approved, declined, withdrawn (B-H1-1)',
    () async {
      final (store, backend) = await _store();
      final v = jsonDecode(_fixture()) as Map<String, dynamic>;
      final requests = v['requests'] as List<dynamic>;
      final base = requests.first as Map<String, dynamic>;
      Map<String, dynamic> claim(String id, String status) => {
        ...base,
        'id': id,
        'kind': 'openShift',
        'emp': v['me'],
        'status': status,
        'created': '2026-09-24T10:30:00+03:00',
        'from': '2026-10-24',
        'shift': 'open|o1',
      };
      requests.addAll([
        claim('o|o1', 'pending'),
        claim('oc|c0', 'withdrawn'),
        claim('oc|c2', 'approved'),
        claim('oc|c3', 'rejected'),
      ]);
      backend.answer = () async => jsonEncode(v);
      await store.readAll();
      ReqStatus status(String id) =>
          store.reqs.firstWhere((r) => r.id == id).status;
      expect(status('o|o1'), ReqStatus.pending);
      expect(status('oc|c0'), ReqStatus.withdrawn);
      expect(status('oc|c2'), ReqStatus.approved);
      expect(status('oc|c3'), ReqStatus.rejected);
      // The chip says so in its own word, not "Cancelled" or "Pending".
      expect(statusOf(ReqStatus.withdrawn).label, 'staff.withdrawn');
      // When it was claimed, on the branch's wall clock (AT-1).
      expect(
        store.reqs.firstWhere((r) => r.id == 'oc|c0').created,
        DateTime(2026, 9, 24, 10, 30),
      );
    },
  );

  group('times are the branch wall clock (AT-1)', () {
    test('the offset is dropped, never converted to the phone zone', () {
      expect(
        branchWall('2026-09-23T09:02:00+03:00'),
        DateTime(2026, 9, 23, 9, 2),
      );
      expect(
        branchWall('2026-01-16T00:30:00.123456+02:00'),
        DateTime(2026, 1, 16, 0, 30, 0, 123, 456),
      );
      expect(branchWall('2026-09-23T06:02:00Z'), DateTime(2026, 9, 23, 6, 2));
      expect(branchWall('2026-09-23T09:02:00+03:00')!.isUtc, isFalse);
    });

    test('garbage is null, not a crash', () {
      expect(branchWall(''), isNull);
      expect(branchWall('yesterday'), isNull);
    });

    test("the store's clock and shift times read the branch's hours", () async {
      final (store, _) = await _store();
      // The fixture pins `now` to 09:30 in Cairo, whatever the phone's zone.
      final raw =
          (jsonDecode(_fixture()) as Map<String, dynamic>)['now'] as String;
      final wall = branchWall(raw)!;
      expect((wall.hour, wall.minute), (9, 30));
      expect(store.now.difference(wall).inMinutes.abs(), lessThan(2));
    });
  });

  group('a push that arrives with the app open (Android)', () {
    test("reads as one line of the server's title and body", () {
      expect(foregroundPushText('Dawam', 'Paid'), 'Dawam · Paid');
      expect(foregroundPushText(' Dawam ', null), 'Dawam');
      expect(foregroundPushText(null, 'Paid'), 'Paid');
      expect(foregroundPushText('', '  '), '');
    });
  });

  group('a tapped push opens its screen (06 B8)', () {
    test('by the key the server sent', () {
      expect(pushTarget('staff.n_flag_left_mid_shift'), (
        manage: true,
        tab: 'team',
      ));
      expect(pushTarget('staff.n_request'), (manage: true, tab: 'approvals'));
      // Decision #9: someone added with no salary opens the owner's Team.
      expect(pushTarget('staff.n_salary_missing'), (manage: true, tab: 'team'));
      // Phase D: an advance asked for waits in Approvals; an undecided
      // holiday is the owner's Schedule; a week's open shifts are Shifts.
      expect(pushTarget('staff.n_advance_requested'), (
        manage: true,
        tab: 'approvals',
      ));
      expect(pushTarget('staff.n_holiday_undecided'), (
        manage: true,
        tab: 'schedule',
      ));
      expect(pushTarget('staff.n_open_shifts_week'), (
        manage: false,
        tab: 'shifts',
      ));
      expect(pushTarget('staff.n_week_published'), (
        manage: false,
        tab: 'shifts',
      ));
      expect(pushTarget('staff.n_request_approved'), (
        manage: false,
        tab: 'requests',
      ));
      expect(pushTarget('staff.n_request_cancelled'), (
        manage: false,
        tab: 'requests',
      ));
      expect(pushTarget('staff.n_paid'), (manage: false, tab: 'pay'));
      expect(pushTarget('staff.n_punched_for_you'), (
        manage: false,
        tab: 'timesheet',
      ));
      expect(pushTarget('staff.n_charge_phone'), (manage: false, tab: 'home'));
      // A claim taken back: the shift is open again on the board (B-H1-5).
      expect(pushTarget('staff.n_claim_withdrawn'), (
        manage: true,
        tab: 'schedule',
      ));
      // The server tells the person when someone else cancels their request
      // (B-TEAM-3): it opens Requests like the approval did.
      expect(pushTarget('staff.n_request_cancelled'), (
        manage: false,
        tab: 'requests',
      ));
    });

    test('anything else opens the inbox', () {
      expect(pushTarget('staff.n_new_phone'), (manage: false, tab: 'inbox'));
      expect(pushTarget(null), (manage: false, tab: 'inbox'));
      expect(pushTarget('something.new'), (manage: false, tab: 'inbox'));
    });

    test('every key the server pushes is routed on purpose', () {
      // The server's words table: a new push key must be given a screen.
      final words = File(
        '../../rust-core/crates/madar-core/src/i18n.rs',
      ).readAsStringSync();
      final keys = RegExp(
        r'"(staff\.n_[a-z_]+)"',
      ).allMatches(words).map((m) => m.group(1)!).toSet();
      final toInbox = {'staff.n_new_phone', 'staff.n_title'};
      // A plural form of a counted notice (`staff.n_open_shifts_week_one`,
      // i18n.rs PLURAL FORMS) is words, never a key the server sends.
      bool form(String k) =>
          RegExp(r'_(zero|one|two|few|many)$').hasMatch(k) &&
          keys.contains(k.substring(0, k.lastIndexOf('_')));
      for (final k in keys) {
        if (toInbox.contains(k) || k.startsWith('staff.n_kind') || form(k)) {
          continue;
        }
        expect(
          pushTarget(k).tab,
          isNot('inbox'),
          reason: '$k has no screen; add it to pushTarget or to toInbox',
        );
      }
    });
  });

  group('staying up to date: pull and resume', () {
    /// The fixture as the core answers a fetch: [at] its `fetched_at`.
    String answer(int at, {bool online = true, bool throttled = false}) {
      final v = jsonDecode(_fixture()) as Map<String, dynamic>;
      v['fetched_at'] = at;
      v['online'] = online;
      v['throttled'] = throttled;
      return jsonEncode(v);
    }

    Future<(DawamStore, _Backend, List<String>)> pulled(
      String Function() next,
    ) async {
      final (store, b) = await _store();
      b.fetched = () async => answer(100);
      await store.pull(); // where the phone starts: fetched at 100
      final failures = <String>[];
      final sub = store.failures.stream.listen(failures.add);
      addTearDown(sub.cancel);
      b.fetched = () async => next();
      await store.pull();
      await Future<void>.delayed(Duration.zero);
      return (store, b, failures);
    }

    test('a pull that reached the server says nothing', () async {
      final (store, b, failures) = await pulled(() => answer(200));
      expect(b.syncs, 2);
      expect(store.fetchedAt, 200);
      expect(failures, isEmpty);
    });

    test('offline: the toast says so', () async {
      final (store, _, failures) = await pulled(
        () => answer(100, online: false),
      );
      expect(store.offline, isTrue);
      expect(failures, ['staff.refresh_offline']);
    });

    // Addendum 2: with the server's limiter on, a pull read "Couldn't reach
    // the server". The server asked to slow down; the picture stays.
    test('throttled: the toast says slow down, not unreachable', () async {
      final (store, _, failures) = await pulled(
        () => answer(100, throttled: true),
      );
      expect(failures, ['staff.refresh_throttled']);
      expect(store.me, 'e1');
    });

    test('online, but the fetch never got an answer: said too', () async {
      final (_, _, failures) = await pulled(() => answer(100));
      expect(failures, ['staff.refresh_failed']);
    });

    test('refused: the server words, once, and the picture stays', () async {
      final (store, _, failures) = await pulled(() => throw _refused);
      expect(failures, ['Outside Zamalek: 340 m away.']);
      expect(store.fetchedAt, 100);
      expect(store.me, 'e1');
    });

    test(
      'pulls, pushes and the pill landing together share one fetch',
      () async {
        final (store, b) = await _store();
        final gate = Completer<String>();
        b.fetched = () => gate.future;
        final pulls = [store.pull(), store.pull()];
        store.sync();
        expect(b.syncs, 1);
        gate.complete(answer(5));
        await Future.wait(pulls);
        expect(store.fetchedAt, 5);
        await store.pull();
        expect(b.syncs, 2, reason: 'the next pull fetches again');
      },
    );

    test('a resume fetches unless the last fetch was under 15 s ago', () async {
      final (store, b) = await _store();
      var now = DateTime(2026, 9, 23, 10);
      store.clock = () => now;
      await store.pull();
      expect(store.lastFetch, now);
      expect(b.syncs, 1);

      now = now.add(const Duration(seconds: 14));
      store.resumed();
      expect(b.syncs, 1, reason: 'a quick app switch');

      now = now.add(const Duration(seconds: 2));
      store.resumed();
      expect(b.syncs, 2);
      expect(store.lastFetch, now);
    });

    test('a resume before the notice is accepted fetches nothing', () async {
      final (store, b) = await _store();
      store
        ..privacyAccepted = false
        ..lastFetch = null
        ..resumed();
      expect(b.syncs, 0);
    });
  });

  test('an empty name has an avatar initial', () {
    expect(initialOf(''), '·');
    expect(initialOf('  '), '·');
    expect(initialOf('Omar'), 'O');
  });

  test('an amount typed on an Arabic keyboard is read (APP-4)', () {
    expect(readNumber('١٢٥٠'), 1250);
    expect(readNumber('۱۲۵'), 125);
    expect(readNumber('١٬٢٥٠٫٥'), 1250.5);
    expect(readNumber('1,250.50'), 1250.5);
    expect(readNumber(' 40 '), 40);
    expect(readNumber('abc'), isNull);
    expect(readNumber(''), isNull);
    expect(readMoney(TextEditingController(text: '٤٠')), 4000);
    expect(readMoney(TextEditingController(text: '٠')), isNull);
  });

  // Minor #27: with this month's payroll approved, a new pay line lands in
  // the first open month; the core says which, the sheet says so.
  test('a new pay line says the month it lands in (M27)', () async {
    final (store, backend) = await _store();
    backend.edit = (v) => v['lines_land'] = {
      'date': '2026-10-26',
      'start': '2026-10-26',
      'end': '2026-11-25',
      'later': true,
    };
    await store.refresh();
    expect(store.linesLand, (
      from: DateTime(2026, 10, 26),
      to: DateTime(2026, 11, 25),
    ));
    backend.edit = (v) => v['lines_land'] = {
      'date': '2026-09-25',
      'start': '2026-09-26',
      'end': '2026-10-25',
      'later': false,
    };
    await store.refresh();
    expect(store.linesLand, isNull, reason: 'this month is open');
    backend.edit = (v) => v.remove('lines_land');
    await store.refresh();
    expect(store.linesLand, isNull, reason: 'an older core says nothing');
  });

  // H2-P1: an older month not fully paid comes with its figures and its
  // live preview, and every payroll action names its month.
  test('an older unsettled month is read and settled by its id', () async {
    final (store, backend) = await _store();
    backend.edit = (v) {
      (v['history'] as List<dynamic>).add({
        'end': '2026-07-25',
        'id': 'p0',
        'paid_by': <String, dynamic>{},
        'start': '2026-06-26',
        'status': 'open',
      });
      final slip = Map<String, dynamic>.of(
        (v['slips'] as List<dynamic>).first as Map<String, dynamic>,
      );
      (v['slips'] as List<dynamic>).add({
        ...slip,
        'start': '2026-06-26',
        'end': '2026-07-25',
        'frozen': false,
        'net': 777700,
      });
      v['unsettled'] = [
        {
          'id': 'p0',
          'start': '2026-06-26',
          'end': '2026-07-25',
          'status': 'open',
          'net': 777700,
          'paid_count': 0,
          'people': 1,
        },
      ];
    };
    await store.refresh();
    final u = store.unsettled.single;
    expect(
      (u.id, u.status, u.net, u.paidCount, u.people),
      ('p0', PeriodStatus.open, 777700, 0, 1),
    );
    final p = store.periodById('p0')!;
    expect(store.runSlips(p).single.net, 777700, reason: 'its live preview');
    expect(
      store.runSlips(store.period).any((s) => s.net == 777700),
      isFalse,
      reason: 'not this month',
    );
    await store.approvePayroll(period: 'p0');
    expect(backend.acts.last, {'action': 'approve_payroll', 'period': 'p0'});
    await store.markPaid('e1', PayMethod.cash, period: 'p0');
    expect(backend.acts.last, {
      'action': 'mark_paid',
      'emp': 'e1',
      'method': 'cash',
      'period': 'p0',
    });
    await store.approvePayroll();
    expect(backend.acts.last, {'action': 'approve_payroll'});
    backend.edit = null;
    await store.refresh();
    expect(store.unsettled, isEmpty, reason: 'an older core says nothing');
  });
}
