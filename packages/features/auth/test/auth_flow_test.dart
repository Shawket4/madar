// The PIN pad and device setup must never strand the person at the till:
// a refused sign-in says why and leaves the pad usable, and a failed branch
// bind stays on the branch list instead of silently logging the manager out.

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

class _Bridge implements MadarBridge {
  bool failBind = false;
  bool failStations = false;
  int logouts = 0;
  int signIns = 0;
  int pinWait = 0;
  bool badCode = false;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final can = fakeCanInvocation(invocation, () => currentSession()?.role);
    if (can != null) return can;
    final name = invocation.memberName;
    if (name == #tr) return invocation.namedArguments[#key];
    if (name == #appRoute) return const AppRoute.login();
    if (name == #currentSession) return null;
    if (name == #pinWaitSeconds) return pinWait;
    if (name == #activateDevice) {
      if (badCode) {
        return Future<BranchView>.error(
          const MadarError.validation(
            field: 'activation_code',
            detail: 'activation code not valid',
          ),
        );
      }
      return Future<BranchView>.value(
        const BranchView(id: 'br-1', name: 'Maadi', isActive: true),
      );
    }
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

  test('an activation code binds the device; a bad one says why', () async {
    bridge.badCode = true;
    await auth().activateDevice('00000000');
    var s = container.read(authProvider);
    expect(s.error, isNotNull);
    expect(s.busy, isFalse);
    expect(s.error!.of(bridge), 'err.activation_code_invalid');

    bridge.badCode = false;
    final version = s.configVersion;
    await auth().activateDevice('40721958');
    s = container.read(authProvider);
    expect(s.error, isNull);
    expect(s.configVersion, greaterThan(version), reason: 'screens re-read');
  });

  test('too many wrong PINs disable the pad and count down', () async {
    '1234'.split('').forEach(auth().pushDigit);
    // The server refused with PIN_THROTTLED; the core stored the wait.
    bridge.pinWait = 15;
    await auth().signInTeller(name: 'Sara');
    final s = container.read(authProvider);
    expect(s.pinWaitSeconds, 15);
    expect(s.error, isNull, reason: 'the countdown speaks, not a banner');
    expect(auth().pushDigit('1'), isFalse, reason: 'keypad disabled');

    bridge.pinWait = 14;
    auth().tickPinWait();
    expect(container.read(authProvider).pinWaitSeconds, 14);

    bridge.pinWait = 0;
    auth().tickPinWait();
    expect(auth().pushDigit('1'), isFalse, reason: 'first digit, not full');
    expect(container.read(authProvider).pin, '1');
  });

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
