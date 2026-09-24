// E2E S-229 (Hana, AR): a swap card read "Mon 28 Sep of Nada Fathy ⇄ Mon 28
// Sep of Nada Fathy" — the requester named on both sides. Each side names the
// person whose shift it is.
import 'package:feature_dawam_requests/src/approvals_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';

void main() {
  setUp(() {
    words = (k) =>
        const {
          'staff.s_s_both_agreed':
              "{name}'s {date} ⇄ {name2}'s {date2} — both agreed",
        }[k] ??
        k;
  });

  test('each side of a swap names its own person', () {
    final text = swapWords(
      requester: 'Nada Fathy',
      requesterDay: 'Mon 28 Sep',
      peer: 'Mahmoud Reda',
      peerDay: 'Mon 28 Sep',
    );
    expect(
      text,
      "Nada Fathy's Mon 28 Sep ⇄ Mahmoud Reda's Mon 28 Sep — both agreed",
    );
  });
}
