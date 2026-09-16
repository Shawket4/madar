// A device write the core refuses is said.

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

class _Bridge implements MadarBridge {
  TillView? till;
  bool refuseHub = false;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final can = fakeCanInvocation(invocation, () => currentSession()?.role);
    if (can != null) return can;
    final name = invocation.memberName;
    final args = invocation.namedArguments;
    if (name == #tr) return args[#key];
    if (name == #appRoute) return const AppRoute.login();
    if (name == #currentSession) return null;
    if (name == #deviceConfig) {
      return const DeviceConfigView(reconfiguring: false, configured: true);
    }
    if (name == #currentTill) return Future<TillView?>.value(till);
    if (name == #setDeviceLanHub) {
      return refuseHub
          ? Future<void>.error(
              const MadarError.validation(field: 'hub', detail: 'bad'),
            )
          : Future<void>.value();
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

  test('a refused write is surfaced, then cleared by one that lands', () async {
    bridge.refuseHub = true;
    final notifier = container.read(settingsProvider.notifier);
    await notifier.setLanHub('nonsense');
    expect(container.read(settingsProvider).writeError, isNotNull);
    bridge.refuseHub = false;
    await notifier.setLanHub('10.0.0.2');
    expect(container.read(settingsProvider).writeError, isNull);
  });
}
