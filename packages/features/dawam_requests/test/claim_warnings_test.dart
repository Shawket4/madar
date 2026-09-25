// Minor #26 (RU-13): approving an open-shift claim that makes a long day
// warns the approver with the limits it breaks; it never blocks.
import 'package:feature_dawam_requests/src/approvals_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

void main() {
  setUp(() => words = coreWord);

  test('an approval that breaks a limit says which', () {
    expect(approvedWithWarnings(const []), coreWord('staff.approved'));
    final text = approvedWithWarnings([
      (
        'staff.warn_day_hours',
        {'hours': '8', 'worked': '11', 'date': 'Sun 27 Sep'},
      ),
      (
        'staff.warn_presence',
        {'hours': '10', 'worked': '13', 'date': 'Sun 27 Sep'},
      ),
    ]);
    expect(text, startsWith('Approved. Mind: '));
    expect(text, contains('Over 8 h on Sun 27 Sep (11 h)'));
    expect(text, contains('At work over 10 h on Sun 27 Sep (13 h)'));
  });
}
