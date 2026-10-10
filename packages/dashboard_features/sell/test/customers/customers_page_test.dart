// Customers (SELL-CUS rows): what each persona is shown and refused, and
// the module gate. The rows' own tests live beside this file.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_sell/src/customers/customers_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  // persona → (Add, Edit, Merge, Erase, card, Adjust, Remove, Wallet)
  const matrix = {
    Persona.owner: (true, true, true, true, true, true, true, false),
    Persona.manager: (true, true, true, false, true, false, false, false),
    Persona.limited: (false, false, false, false, false, false, false, false),
    Persona.platform: (true, true, true, true, true, true, true, true),
  };
  for (final MapEntry(key: p, value: m) in matrix.entries) {
    testWidgets('SELL-CUS-003/030/042 refusals: ${p.name}', (tester) async {
      final h = await pumpCustomers(tester, persona: p);
      Matcher shown(bool v) => v ? findsWidgets : findsNothing;
      expect(pageText('Add customer'), shown(m.$1));
      await openNada(h);
      expect(sheetText('Edit'), shown(m.$2));
      expect(sheetText('Merge into…'), shown(m.$3));
      expect(sheetText('Erase customer'), shown(m.$4));
      expect(sheetText('Loyalty'), shown(m.$5));
      expect(sheetText('Adjust balance'), shown(m.$6));
      expect(sheetText('Remove from loyalty programme'), shown(m.$7));
      expect(sheetText('Google Wallet object'), shown(m.$8));
    });
  }

  testWidgets('SELL-ALL-002 a Dawam-only org: the module gate, no reads', (
    tester,
  ) async {
    final h = await pumpCustomers(tester, persona: Persona.dawamOnly);
    expect(find.byType(CustomersPage), findsNothing);
    expect(listCalls(h), isEmpty);
    expect(find.text(h.t('dawam.moduleOffTitle')), findsOneWidget);
    expect(find.text(h.t('dawam.modulePosOff')), findsOneWidget);
  });

  testWidgets('signed out: the sign-in screen, no reads', (tester) async {
    final h = await pumpCustomers(tester, persona: null);
    expect(find.byType(CustomersPage), findsNothing);
    expect(listCalls(h), isEmpty);
    expect(h.container.read(currentSessionProvider), isNull);
  });
}
