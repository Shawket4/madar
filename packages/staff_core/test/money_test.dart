import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';

void main() {
  late DawamStore store;
  setUp(() => store = DawamStore());
  tearDown(() => store.stop());

  test('suggested amounts round to the nearest 5 EGP (RU-12)', () {
    expect(round5(1249), 1000);
    expect(round5(1250), 1500);
    expect(round5(73300), 73500);
  });

  test('deductions over pay stop at zero and carry the rest (PAY-12)', () {
    store
      ..me = store.ownerId
      ..addAdjustment('e8', bonus: false, amount: 900000, reason: 'test');
    final s = store.slip('e8', store.period);
    expect(s.net, 0);
    expect(s.carryOut, s.deducted - s.earned);
    expect(s.collected, isEmpty, reason: 'advances take what is left (AV-4)');
  });

  test('approve → reopen never collects an installment twice (AV-6)', () {
    store.me = store.ownerId;
    final sara = store.advances.firstWhere((a) => a.emp == 'e1');
    final before = sara.collected;
    store.approvePayroll();
    expect(sara.collected, greaterThan(before));
    store
      ..reopenPayroll()
      ..approvePayroll()
      ..reopenPayroll();
    expect(sara.collected, before);
  });

  test('a waived rule line stays waived through recalculation (AD-8)', () {
    store.me = store.ownerId;
    final line = store.slip('e8', store.period).lines.firstWhere((l) => l.rule);
    store.waive(line.key, 'first week');
    final again = store
        .slip('e8', store.period)
        .lines
        .firstWhere((l) => l.key == line.key);
    expect(again.waived, isTrue);
    expect(again.amount, 0);
  });

  test('overlapping requests of one kind are refused (RQ-11)', () {
    store.me = 'e1';
    final d = store.today.add(const Duration(days: 2));
    store.file(ReqKind.leave, from: d);
    expect(
      () => store.file(ReqKind.leave, from: d),
      throwsA(isA<DawamError>()),
    );
  });

  test('a mid-period joiner is paid pro rata by calendar days (PAY-13)', () {
    final karim = store.slip('e5', store.period).lines.first;
    expect(karim.amount, lessThan(store.emp('e5').salary));
    expect(karim.amount, greaterThan(0));
  });
}
