// A device write the core refuses is said, and the till cannot be re-bound
// to another drawer while a till is open on it.

import 'package:app_core/app_core.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _open = TillView(
  id: 'sh-1',
  branchId: 'br-1',
  tellerId: 'u-1',
  tellerName: 'Sara',
  openingCashMinor: 0,
  openedAt: '2026-09-12T15:02:00Z',
  status: 'open',
  isOpen: true,
);

class _Bridge implements MadarBridge {
  TillView? till;
  bool refuseHub = false;
  final List<String?> tillBinds = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    final args = invocation.namedArguments;
    if (name == #tr) return args[#key];
    if (name == #appRoute) return const AppRoute.login();
    if (name == #currentSession) return null;
    if (name == #deviceConfig) {
      return const DeviceConfigView(reconfiguring: false, configured: true);
    }
    if (name == #currentTill) return Future<TillView?>.value(till);
    if (name == #setDeviceTill) {
      tillBinds.add(args[#tillId] as String?);
      return Future<void>.value();
    }
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

  test('the till cannot be re-bound while a shift is open', () async {
    bridge.till = _open;
    final ok = await container
        .read(settingsProvider.notifier)
        .bindTill('till-2');
    expect(ok, isFalse);
    expect(bridge.tillBinds, isEmpty);
    expect(container.read(settingsProvider).writeError, isNotNull);
  });

  test('with no shift the till binds', () async {
    final ok = await container
        .read(settingsProvider.notifier)
        .bindTill('till-2');
    expect(ok, isTrue);
    expect(bridge.tillBinds, ['till-2']);
  });

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
