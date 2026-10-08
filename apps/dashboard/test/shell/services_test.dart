// The shell's services: live branch updates over the realtime gateway, the
// 401 guard, and ask-a-manager.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

MyAuthz _me({
  List<String> caps = const [],
  List<String> ask = const [],
  Map<String, LimitsView> limits = const {},
}) => MyAuthz(
  userId: 'u',
  epoch: 1,
  specVersion: 2,
  owner: false,
  platform: false,
  roleKinds: const ['branch_manager'],
  capabilities: caps,
  askManager: ask,
  limits: limits,
);

void main() {
  group('live updates', () {
    testWidgets('one connection for the picked branch; events refresh paths', (
      tester,
    ) async {
      final h = await pumpShell(
        tester,
        prefs: {
          ScopePrefKeys.branch:
              '{"org":"${SeedIds.sabahOrg}","branch":"${SeedIds.zamalek}"}',
        },
      );
      final conn = h.realtime.current!;
      expect(conn.branchId, SeedIds.zamalek);
      expect(conn.topics, realtimeTopics);
      expect(h.container.read(realtimeEpochProvider('/floor/sections')), 0);
      conn.emit('floor.table_updated', id: '7');
      await h.settle(rounds: 2);
      expect(h.container.read(realtimeEpochProvider('/floor/sections')), 1);
      expect(h.container.read(realtimeEpochProvider('/orders')), 0);
      // Navigating never reconnects.
      await h.go('/tills');
      await h.go('/orders');
      expect(h.realtime.connections, hasLength(1));
    });

    testWidgets('all branches: no connection', (tester) async {
      final h = await pumpShell(tester);
      expect(h.realtime.connections, isEmpty);
    });
  });

  group('the 401 guard', () {
    final req = ApiRequest(method: 'GET', path: '/orders');
    test('ends the session only for an authenticated request', () {
      const e401 = ApiException(status: 401, message: 'x');
      expect(SessionGuardTransport.endsSession(req, e401), isTrue);
      expect(
        SessionGuardTransport.endsSession(
          ApiRequest(method: 'GET', path: '/public/orgs/brand'),
          e401,
        ),
        isFalse,
      );
      expect(
        SessionGuardTransport.endsSession(
          ApiRequest(method: 'POST', path: '/auth/login'),
          e401,
        ),
        isFalse,
      );
      expect(
        SessionGuardTransport.endsSession(
          req,
          const ApiException(status: 403, message: 'x'),
        ),
        isFalse,
      );
    });
  });

  group('ask a manager', () {
    test('held: offered, never waits under the limit', () {
      final a = AskManager(
        Authz.from(
          _me(
            caps: [Cap.hrDeductionsCreate],
            limits: {Cap.hrDeductionsCreate: const LimitsView(maxAmount: 5000)},
          ),
        ),
      );
      expect(a.offers(Cap.hrDeductionsCreate), isTrue);
      expect(a.onlyByAsking(Cap.hrDeductionsCreate), isFalse);
      expect(a.waits(Cap.hrDeductionsCreate, amount: 4000), isFalse);
      expect(a.waits(Cap.hrDeductionsCreate, amount: 6000), isTrue);
    });

    test('askable: offered, only by asking, always waits', () {
      final a = AskManager(Authz.from(_me(ask: [Cap.hrDeductionsCreate])));
      expect(a.offers(Cap.hrDeductionsCreate), isTrue);
      expect(a.onlyByAsking(Cap.hrDeductionsCreate), isTrue);
      expect(a.waits(Cap.hrDeductionsCreate), isTrue);
    });

    test('neither: not offered', () {
      final a = AskManager(Authz.from(_me()));
      expect(a.offers(Cap.hrDeductionsCreate), isFalse);
    });

    testWidgets('the waiting notice uses the web\'s words', (tester) async {
      final h = await pumpShell(tester);
      showAwaitingApproval(tester.element(find.byType(DashSidebar)));
      await h.settle(rounds: 2);
      await h.expectToast(
        'Over your limit: it waits for the owner before it counts.',
      );
    });
  });
}
