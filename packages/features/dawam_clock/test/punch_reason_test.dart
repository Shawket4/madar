// BC-1 (FOLLOWUPS): a manager's punch-out carries its own reason beside the
// punch-in's. The Timesheet shows each reason next to its punch.
import 'package:feature_dawam_clock/feature_dawam_clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

void main() {
  setUp(() => words = coreWord);

  test('each punch says who made it and why', () {
    expect(
      punchLabel(coreWord('staff.out'), Method.manager, 'Sent home sick'),
      '${coreWord('staff.out')} · ${coreWord('staff.by_manager')} · '
      '“Sent home sick”',
    );
    expect(
      punchLabel(coreWord('staff.in_label'), Method.app, null),
      '${coreWord('staff.in_label')} · ${coreWord('staff.app')}',
    );
    expect(punchLabel('Out', null, '  '), 'Out');
  });
}
