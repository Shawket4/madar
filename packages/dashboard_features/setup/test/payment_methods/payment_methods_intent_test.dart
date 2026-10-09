// Intent warming on Payment methods: pointing at the Availability tab warms
// its reads, so switching asks the server nothing more. And the editor takes
// a fresher row until the person changes something.
import 'package:dashboard_core/dashboard_core.dart' show realtimeBusProvider;
import 'package:dashboard_setup/src/payment_methods/payment_method_dialog.dart';
import 'package:dashboard_setup/src/payment_methods/pm_data.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'pm_support.dart';

void main() {
  testWidgets('SET-PAY-022 (intent) resting on Availability warms its reads; '
      'the switch asks nothing more', (tester) async {
    final h = await pumpPm(tester, query: zamalek);
    int n(String r) => h.server.callsTo(r, method: 'GET').length;
    (int, int, int) reads() =>
        (n(PmRoutes.availability), n(PmRoutes.users), n(PmRoutes.devices));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final tab = inPage(
      find.descendant(
        of: find.byKey(const ValueKey('pm-tabs')),
        matching: find.text(h.t('paymentMethods.availability.title')),
      ),
    );
    expect(reads(), (0, 0, 0));
    await mouse.moveTo(tester.getCenter(tab));
    await tester.pump(const Duration(milliseconds: 90));
    await h.settle();
    expect(reads(), (1, 1, 1), reason: 'the tab\'s reads are warmed');
    await h.tap(tab);
    expect(find.byKey(const ValueKey('pm-availability-loading')), findsNothing);
    expect(reads(), (1, 1, 1), reason: 'the tab opened from the cache');
  });

  testWidgets('SET-PAY-011 (re-seed) the editor takes a fresher row until '
      'the person types; then their words stay', (tester) async {
    final m = setupMockServer();
    final h = await pumpPm(tester, query: '?edit=${pmId('card')}', backend: m);
    final dialog = find.byType(PaymentMethodDialog);
    final label = find.descendant(
      of: dialog,
      matching: find.byKey(const ValueKey('pm-label-en')),
    );
    final input = find.descendant(
      of: label,
      matching: find.byType(EditableText),
    );
    String shown() => tester.widget<EditableText>(input).controller.text;
    Future<void> relabel(String en) async {
      m.db[PmSeed.methodsTable].find(pmId('card'))!['label_translations'] = {
        'en': en,
        'ar': 'بطاقة',
      };
      h.container.read(realtimeBusProvider).invalidate(const [PmPaths.list]);
      await h.settle();
    }

    expect(dialog, findsOneWidget);
    await relabel('Bank card');
    expect(shown(), 'Bank card');
    await h.enterText(input, 'Visa');
    await relabel('Debit card');
    expect(shown(), 'Visa');
  });
}
