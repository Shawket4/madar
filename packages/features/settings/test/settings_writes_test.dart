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
  String? scanCamera;

  /// The plan the core answers, and the device's stored footer choice (off).
  String plan = 'paid';
  int stubWrites = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final can = fakeCanInvocation(invocation, () => currentSession()?.role);
    if (can != null) return can;
    final name = invocation.memberName;
    final args = invocation.namedArguments;
    if (name == #tr) return args[#key];
    if (name == #appRoute) return AppRoute.login;
    if (name == #currentSession) return null;
    if (name == #deviceConfig) {
      // As the core answers it: the device turned both off; Free prints them.
      final free = plan == 'free';
      return DeviceConfigView(
        reconfiguring: false,
        configured: true,
        receiptStub: free,
        receiptGetMadar: free,
        receiptFooterLocked: free,
      );
    }
    if (name == #entitlements) {
      return EntitlementsView(
        plan: plan,
        features: const [],
        realtime: plan == 'paid',
        tillInactive: false,
      );
    }
    if (name == #setDeviceReceiptStub) {
      stubWrites++;
      return Future<void>.value();
    }
    // The one owner's sync read: this person's OWN open till, or none.
    if (name == #ownOpenTill) {
      final t = till;
      return (t?.isOpen ?? false) ? t : null;
    }
    if (name == #currentTill) return Future<TillView?>.value(till);
    if (name == #setDeviceScanCamera) {
      scanCamera = args[#facing] as String?;
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

  test('a refused write is surfaced, then cleared by one that lands', () async {
    bridge.refuseHub = true;
    final notifier = container.read(settingsProvider.notifier);
    await notifier.setLanHub('nonsense');
    expect(container.read(settingsProvider).writeError, isNotNull);
    bridge.refuseHub = false;
    await notifier.setLanHub('10.0.0.2');
    expect(container.read(settingsProvider).writeError, isNull);
  });

  test('the receipt footer follows the plan the moment it changes', () {
    // Paid, with the footer turned off on this device.
    container
      ..listen(settingsProvider, (_, _) {})
      ..listen(entitlementsProvider, (_, _) {});
    var c = container.read(settingsProvider).config;
    expect(
      (c.receiptStub, c.receiptGetMadar, c.receiptFooterLocked),
      (false, false, false),
    );
    // Downgraded to Free: the feed moves, and both print, locked on.
    bridge.plan = 'free';
    container.read(syncTickProvider.notifier).bump();
    container.read(entitlementsProvider);
    c = container.read(settingsProvider).config;
    expect(
      (c.receiptStub, c.receiptGetMadar, c.receiptFooterLocked),
      (true, true, true),
    );
    // Back to Paid: the device's own off choice returns.
    bridge.plan = 'paid';
    container.read(syncTickProvider.notifier).bump();
    container.read(entitlementsProvider);
    c = container.read(settingsProvider).config;
    expect(
      (c.receiptStub, c.receiptGetMadar, c.receiptFooterLocked),
      (false, false, false),
    );
    expect(bridge.stubWrites, 0, reason: 'the plan never rewrites the device');
  });

  test(
    'the scanner camera chosen in Settings is saved on the device',
    () async {
      await container.read(settingsProvider.notifier).setScanCamera('front');
      expect(bridge.scanCamera, 'front');
    },
  );
}
