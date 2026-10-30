// Who sold an order (teller pick): one rule for every screen that names an
// order's teller.
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nobody picked: the signed-in person, and no "Signed in"', () {
    final s = orderSeller(tellerId: 't1', tellerName: 'Ali Hassan');
    expect(s.teller, 'Ali Hassan');
    expect(s.signedIn, isNull);
  });

  test('someone else picked: their name; "Signed in" is the signed-in '
      'person', () {
    final s = orderSeller(
      tellerId: 't1',
      tellerName: 'Ali Hassan',
      soldBy: 'm1',
      soldByName: 'Mona Adel',
    );
    expect(s.teller, 'Mona Adel');
    expect(s.signedIn, 'Ali Hassan');
  });

  test('the signed-in person picked themself: no "Signed in"', () {
    final s = orderSeller(
      tellerId: 't1',
      tellerName: 'Ali Hassan',
      soldBy: 't1',
      soldByName: 'Ali Hassan',
    );
    expect(s.teller, 'Ali Hassan');
    expect(s.signedIn, isNull);
  });
}
