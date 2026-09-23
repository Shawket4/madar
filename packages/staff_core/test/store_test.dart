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

  @override
  Future<String> snapshot({required bool refresh}) async => _fixture();
  @override
  Future<String> sync() async => _fixture();
  @override
  Future<String> ping(DawamFix fix) async => _fixture();
  @override
  Future<void> otpRequest(String phone) async {}
  @override
  Future<Map<String, dynamic>> otpVerify(
    String phone,
    String code, {
    String? orgId,
  }) async => {};
  @override
  Future<DawamFix?> locate() async => null;
  @override
  Stream<DawamFix> track() => const Stream.empty();
  @override
  Future<bool> alwaysLocation() async => true;
  @override
  String? restoredUser() => 'e1';
  @override
  Future<void> signOut() async => signOuts++;
}

final _refused = DawamError(
  'Outside Zamalek: 340 m away.',
  'برّه الزمالك: على بعد 340 م.',
);

Future<(DawamStore, _Backend)> _store() async {
  final b = _Backend();
  final s = DawamStore(b);
  await s.restore();
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
      await sub.cancel();
      await t.pump(const Duration(seconds: 3));
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
    'a waiver is final: un-waiving is refused, not silently ignored',
    () async {
      final (store, _) = await _store();
      final failures = <String>[];
      final sub = store.failures.stream.listen(failures.add);
      await store.unwaive('late|x');
      await Future<void>.delayed(Duration.zero);
      expect(failures, hasLength(1));
      await sub.cancel();
    },
  );

  test('an unreadable answer keeps the last picture (06 B13)', () async {
    final (store, backend) = await _store();
    final shifts = store.shifts.length;
    final reported = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = old);
    final broken = jsonDecode(_fixture()) as Map<String, dynamic>;
    (broken['shifts'] as List<dynamic>).first['date'] = '';
    backend.answer = () async => jsonEncode(broken);
    await store.readAll();
    expect(store.me, 'e1', reason: 'still signed in');
    expect(store.shifts.length, shifts, reason: 'the last good picture stays');
    expect(reported, hasLength(1), reason: 'and the fault is reported');
  });

  test('a snapshot with no clock does not crash', () async {
    final (store, backend) = await _store();
    final v = jsonDecode(_fixture()) as Map<String, dynamic>..remove('now');
    backend.answer = () async => jsonEncode(v);
    await store.readAll();
    expect(store.now.difference(DateTime.now()).inSeconds.abs(), lessThan(5));
  });

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
      final raw = jsonDecode(_fixture())['now'] as String;
      final wall = branchWall(raw)!;
      expect((wall.hour, wall.minute), (9, 30));
      expect(store.now.difference(wall).inMinutes.abs(), lessThan(2));
    });
  });

  group('a tapped push opens its screen (06 B8)', () {
    test('by the key the server sent', () {
      expect(pushTarget('staff.n_flag_left_mid_shift'), (
        manage: true,
        tab: 'team',
      ));
      expect(pushTarget('staff.n_request'), (manage: true, tab: 'approvals'));
      expect(pushTarget('staff.n_week_published'), (
        manage: false,
        tab: 'shifts',
      ));
      expect(pushTarget('staff.n_request_approved'), (
        manage: false,
        tab: 'requests',
      ));
      expect(pushTarget('staff.n_paid'), (manage: false, tab: 'pay'));
      expect(pushTarget('staff.n_punched_for_you'), (
        manage: false,
        tab: 'timesheet',
      ));
      expect(pushTarget('staff.n_charge_phone'), (manage: false, tab: 'home'));
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
      for (final k in keys) {
        if (toInbox.contains(k) || k.startsWith('staff.n_kind')) continue;
        expect(
          pushTarget(k).tab,
          isNot('inbox'),
          reason: '$k has no screen; add it to pushTarget or to toInbox',
        );
      }
    });
  });

  test('an empty name has an avatar initial', () {
    expect(initialOf(''), '·');
    expect(initialOf('  '), '·');
    expect(initialOf('Omar'), 'O');
  });
}
