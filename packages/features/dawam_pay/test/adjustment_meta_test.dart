// Minor #30: a rule-made line in the pay lines list read "One-off · by —".
// It says it is the rule's.
import 'package:feature_dawam_pay/feature_dawam_pay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

void main() {
  setUp(() => words = coreWord);

  Adj line({String? rule}) => Adj(
    'a|deduction|d1',
    'e4',
    25000,
    'Absent',
    '',
    DateTime(2026, 9, 24),
    DateTime(2026, 9, 24),
    bonus: false,
    rule: rule,
  );

  test('a rule line says so; a hand-added one says who', () {
    final ruled = adjustmentMeta(line(rule: 'Rule · absence'), '—');
    expect(ruled, startsWith('Rule · absence · '));
    expect(ruled, isNot(contains('One-off')));
    final typed = adjustmentMeta(line(), 'Omar');
    expect(typed, startsWith('${coreWord('staff.one_off')} · '));
    expect(typed, contains('Omar'));
  });
}
