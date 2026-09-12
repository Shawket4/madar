// The PIN pad and device setup must never strand the person at the till:
// a refused sign-in says why and leaves the pad usable, and a failed branch
// bind stays on the branch list instead of silently logging the manager out.

import 'package:app_core/app_core.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

class _Bridge implements MadarBridge {
  bool failBind = false;
  bool failStations = false;
  int logouts = 0;
  int signIns = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #tr) return invocation.namedArguments[#key];
    if (name == #appRoute) return const AppRoute.login();
    if (name == #currentSession) return null;
    if (name == #deviceConfig) {
      return const DeviceConfigView(
        reconfiguring: true,
        configured: true,
        branchId: 'br-1',
      );
    }
    if (name == #setDeviceBranch) {
      if (failBind) {
        return Future<void>.error(const MadarError.offline(detail: 'offline'));
      }
      return Future<void>.value();
    }
    if (name == #logout) {
      logouts++;
      return Future<void>.value();
    }
    if (name == #signIn) {
      signIns++;
      return Future<SessionSnapshot>.error(
        const MadarError.offline(detail: 'offline'),
      );
    }
    if (name == #kdsListStations) {
      if (failStations) {
        return Future<List<KdsStationView>>.error(
          const MadarError.offline(detail: 'offline'),
        );
      }
      return Future<List<KdsStationView>>.value(const []);
    }
    return null;
  }
}

void main() {
  late _Bridge bridge;
  late ProviderContainer container;

  setUp(() {
    bridge = _Bridge();
    container = ProviderContainer(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
    );
  });
  tearDown(() => container.dispose());

  AuthNotifier auth() => container.read(authProvider.notifier);

  test('a sixth digit with no name clears the pad and says why', () async {
    for (final d in '12345'.split('')) {
      expect(auth().pushDigit(d), isFalse);
    }
    expect(auth().pushDigit('6'), isTrue);
    await auth().signInTeller(name: '  ');
    final s = container.read(authProvider);
    expect(s.pin, isEmpty, reason: 'a full buffer refuses every digit');
    expect(s.error, isNotNull);
    expect(bridge.signIns, 0);
    // The pad takes digits again.
    expect(auth().pushDigit('1'), isFalse);
    expect(container.read(authProvider).pin, '1');
  });

  test('a four digit PIN signs in on submit', () async {
    '1234'.split('').forEach(auth().pushDigit);
    await auth().signInTeller(name: 'Sara');
    expect(bridge.signIns, 1);
  });

  test('a hardware key that is not a digit is ignored', () {
    expect(auth().pushDigit('a'), isFalse);
    expect(container.read(authProvider).pin, isEmpty);
  });

  test('a failed branch bind stays on the list with the reason', () async {
    bridge.failBind = true;
    await auth().bindBranch(
      const BranchView(id: 'br-2', name: 'Zamalek', isActive: true),
    );
    final s = container.read(authProvider);
    expect(s.error, isNotNull);
    expect(s.busy, isFalse);
    expect(bridge.logouts, 0, reason: 'the manager is not signed out');
  });

  test(
    'stations that cannot be read are an error, not an empty branch',
    () async {
      bridge.failStations = true;
      await auth().loadStations();
      final s = container.read(authProvider);
      expect(s.stationsError, isNotNull);
      expect(s.stationsLoading, isFalse);
    },
  );
}
