// "When someone isn't allowed" (ADM-ROL-019..022): the business-wide
// ask-a-manager policy under the selected role, driven through the Roles
// page on the mock server.
import 'package:dashboard_admin/src/roles/ask_manager_card.dart';
import 'package:dashboard_admin/src/shared/capability_catalog.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder get _card => find.byType(AskManagerCard);

Finder _inCard(String text) =>
    find.descendant(of: _card, matching: find.text(text));

DashSegmentedControl<bool> _control(WidgetTester tester, String cap) =>
    tester.widget(policyControl(cap));

Future<void> _choose(DashHarness h, String cap, String label) => h.tap(
  find.descendant(of: policyControl(cap), matching: find.text(label)),
);

void main() {
  testWidgets('ADM-ROL-019 the card under the role, with roles.manage: '
      'heading and hint', (tester) async {
    final h = await pumpRoles(tester);
    expect(_inCard("When someone isn't allowed"), findsOneWidget);
    expect(
      _inCard(
        'Hide the action, or let them ask a manager to approve it with '
        'their PIN.',
      ),
      findsOneWidget,
    );
    // Under the capability list.
    expect(
      tester.getRect(_card).top,
      greaterThan(tester.getRect(capabilityRow('Refund money')).bottom),
    );
    expect(h.server.callsTo(policyRoute), hasLength(1));
  });

  testWidgets('ADM-ROL-020 one row per approval capability, current from '
      'the policy', (tester) async {
    final h = await pumpRoles(tester);
    final caps = approvalCapabilities();
    expect(caps, hasLength(15));
    expect(
      find.descendant(of: _card, matching: find.byType(DashSegmentedControl<bool>)),
      findsNWidgets(caps.length),
    );
    expect(_inCard('Void orders'), findsOneWidget);
    expect(_control(tester, 'orders.void').value, isTrue);
    expect(_control(tester, 'refunds.create').value, isTrue);
    expect(_control(tester, 'orders.discount.manual_percent').value, isTrue);
    expect(_control(tester, 'tickets.void').value, isFalse);
    expect(
      find.descendant(
        of: policyControl('tickets.void'),
        matching: find.text('Hidden'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: policyControl('tickets.void'),
        matching: find.text('Ask a manager'),
      ),
      findsOneWidget,
    );
    await h.scrollUntilVisible(policyControl('tickets.void'));
    await h.shot('roles/ask-manager');
  });

  testWidgets('ADM-ROL-020 loading: one skeleton per capability',
      (tester) async {
    final s = rolesServer();
    final gate = s.server.hold('GET', policyRoute);
    final h = await pumpRoles(tester, server: s.server, db: s.db);
    expect(
      find.descendant(of: _card, matching: find.byType(DashSkeleton)),
      findsNWidgets(approvalCapabilities().length),
    );
    expect(policyControl('orders.void'), findsNothing);
    gate.release();
    await h.settle();
    expect(policyControl('orders.void'), findsOneWidget);
  });

  testWidgets('ADM-ROL-021 changing a row: PUT {capability, ask_manager}, '
      'the policy asked again, no toast', (tester) async {
    final h = await pumpRoles(tester);
    final reads = h.server.callsTo(policyRoute, method: 'GET').length;
    await _choose(h, 'tickets.void', 'Ask a manager');
    expect(lastBody(h.server, policyRoute, method: 'PUT'), {
      'ask_manager': true,
      'capability': 'tickets.void',
    });
    expect(h.server.callsTo(policyRoute, method: 'GET').length, reads + 1);
    expect(_control(tester, 'tickets.void').value, isTrue);
    expect(toasts, findsNothing);
    await _choose(h, 'orders.void', 'Hidden');
    expect(lastBody(h.server, policyRoute, method: 'PUT'), {
      'ask_manager': false,
      'capability': 'orders.void',
    });
    expect(_control(tester, 'orders.void').value, isFalse);
  });

  testWidgets('ADM-ROL-021 a failed change toasts the server\'s words and the '
      'row keeps its value', (tester) async {
    final s = rolesServer();
    final refusal = MockResponse.denied('staff.roles.manage');
    s.server.fail('PUT', policyRoute, refusal);
    final h = await pumpRoles(tester, server: s.server, db: s.db);
    await _choose(h, 'tickets.void', 'Ask a manager');
    await h.expectToast(shown(h, refusal));
    expect(_control(tester, 'tickets.void').value, isFalse);
    expect(_control(tester, 'tickets.void').enabled, isTrue);
  });

  testWidgets('ADM-ROL-021/022 (divergence) a row is disabled while it '
      'saves; the others stay live', (tester) async {
    final s = rolesServer();
    final gate = s.server.hold('PUT', policyRoute);
    final h = await pumpRoles(tester, server: s.server, db: s.db);
    await _choose(h, 'tickets.void', 'Ask a manager');
    expect(_control(tester, 'tickets.void').enabled, isFalse);
    expect(_control(tester, 'orders.void').enabled, isTrue);
    // A second tap on the saving row sends nothing.
    await _choose(h, 'tickets.void', 'Hidden');
    expect(h.server.callsTo(policyRoute, method: 'PUT'), hasLength(1));
    gate.release();
    await h.settle();
    expect(_control(tester, 'tickets.void').enabled, isTrue);
    expect(_control(tester, 'tickets.void').value, isTrue);
  });

  testWidgets('ADM-ROL-022 absent while the roles load', (tester) async {
    final s = rolesServer();
    final gate = s.server.hold('GET', rolesRoute);
    final h = await pumpRoles(tester, server: s.server, db: s.db);
    expect(_card, findsNothing);
    expect(h.server.callsTo(policyRoute), isEmpty);
    gate.release();
    await h.settle();
    expect(_card, findsOneWidget);
  });

  testWidgets('ADM-ROL-022 absent when the roles failed', (tester) async {
    final s = rolesServer();
    s.server.fail('GET', rolesRoute, MockResponse.error(500, 'x'), times: null);
    final h = await pumpRoles(tester, server: s.server, db: s.db);
    expect(_card, findsNothing);
    expect(h.server.callsTo(policyRoute), isEmpty);
  });

  testWidgets('ADM-ROL-022 the same policy under every role, the owner\'s '
      'included', (tester) async {
    final h = await pumpRoles(tester);
    await _choose(h, 'tickets.void', 'Ask a manager');
    await h.tap(roleRow(roleId('org_admin')));
    expect(_control(tester, 'tickets.void').value, isTrue);
    await h.tap(roleRow(roleId('kitchen')));
    expect(_control(tester, 'tickets.void').value, isTrue);
  });

  testWidgets('ADM-ROL-022 (divergence) a failed policy read says so, with '
      'Retry for that read only', (tester) async {
    final s = rolesServer();
    s.server.fail(
      'GET',
      policyRoute,
      MockResponse.error(500, 'boom'),
      times: null,
    );
    final h = await pumpRoles(tester, server: s.server, db: s.db);
    expect(policyControl('orders.void'), findsNothing);
    expect(_inCard("Couldn't load this"), findsOneWidget);
    await h.scrollUntilVisible(_inCard('Retry'));
    await h.shot('roles/ask-manager-failed');
    final roles = h.server.callsTo(rolesRoute).length;
    s.server.clearFailures();
    await h.tap(_inCard('Retry'));
    expect(h.server.callsTo(rolesRoute).length, roles);
    expect(policyControl('orders.void'), findsOneWidget);
    expect(_control(tester, 'orders.void').value, isTrue);
  });

  testWidgets('ADM-ROL-020 Arabic: capability names and choices in Arabic',
      (tester) async {
    await pumpRoles(tester, locale: 'ar');
    expect(_inCard('عندما لا يُسمح لشخص'), findsOneWidget);
    expect(
      find.descendant(
        of: policyControl('orders.void'),
        matching: find.text('اطلب من المدير'),
      ),
      findsOneWidget,
    );
  });
}
