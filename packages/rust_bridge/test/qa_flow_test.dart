@Tags(['qa'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// End-to-end flow test against a LOCAL QA backend + seeded demo org —
/// exercises the same bridge calls the screens make (bind → PIN login →
/// catalog sync → configured cart add). Skipped unless MADAR_QA_API is set:
///   MADAR_QA_API=http://127.0.0.1:8081 MADAR_QA_EMAIL=... MADAR_QA_PASSWORD=... \
///   flutter test --tags qa test/qa_flow_test.dart
void main() {
  final api = Platform.environment['MADAR_QA_API'];
  final email = Platform.environment['MADAR_QA_EMAIL'];
  final password = Platform.environment['MADAR_QA_PASSWORD'];

  if (api == null || email == null || password == null) {
    test('qa flow (SKIPPED — set MADAR_QA_API/EMAIL/PASSWORD)', () {
      markTestSkipped('needs the local QA backend + seeded org');
    });
    return;
  }

  final dylib = File(
    '${Directory.current.path}/../../rust-core/target/release/libmadar_frb.dylib',
  );

  late MadarCore core;
  late Directory tmp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await MadarCore.initForTest(dylibPath: dylib.path);
    tmp = Directory.systemTemp.createTempSync('madar-qa-flow');
    core = await MadarCore.start(
      config: MadarConfig(
        baseUrl: api,
        environment: 'dev',
        dbPath: '${tmp.path}/qa.db',
        locale: 'en',
      ),
    );
  });

  tearDownAll(() {
    tmp.deleteSync(recursive: true);
  });

  test('bind device, PIN login, sync, configured add keeps the size', () async {
    // Manager bind — the device-setup screen's exact calls.
    await core.bridge.login(
      req: LoginRequest(
        mode: LoginMode.email,
        email: email,
        password: password,
      ),
    );
    final branches = await core.bridge.listBranches();
    expect(branches, isNotEmpty, reason: 'seeded org must have a branch');
    await core.bridge.setDeviceBranch(
      branchId: branches.first.id,
      branchName: branches.first.name,
    );
    await core.bridge.logout(wipeOutbox: false);

    // Teller PIN login — the login screen's exact call (branch from the
    // device binding).
    await core.bridge.login(
      req: LoginRequest(
        mode: LoginMode.pin,
        name: 'Sara',
        pin: '123456',
        branchId: branches.first.id,
      ),
    );
    expect(core.bridge.currentSession(), isNotNull);

    // Catalog sync — the order screen's boot.
    await core.bridge.refreshCatalog();
    final items = await core.bridge.listMenuItems();
    expect(items, isNotEmpty, reason: 'menu must sync from the QA backend');

    final latte = items.firstWhere((i) => i.name == 'Latte');
    expect(latte.sizes, hasLength(2));
    final large = latte.sizes.firstWhere((s) => s.label == 'Large');

    // The item-detail sheet's exact commit.
    await core.bridge.cartClear();
    final lines = await core.bridge.cartAddConfigured(
      itemId: latte.id,
      sizeLabel: large.label,
      addons: const [],
      optionalFieldIds: const [],
      qty: 1,
    );

    expect(lines, hasLength(1));
    expect(
      lines.single.sizeLabel,
      'Large',
      reason: 'the configured size must survive the bridge',
    );
    expect(lines.single.unitPriceMinor, large.priceMinor);
  });

  test('checkout produces a receipt and clears the cart (M5 gate)', () async {
    // An open shift is required — adopt the branch's shift or open one,
    // exactly like the open-shift screen.
    final shift = await core.bridge.refreshShift();
    if (!(shift?.isOpen ?? false)) {
      await core.bridge.openShift(openingCashMinor: 50000);
    }

    await core.bridge.cartClear();
    final items = await core.bridge.listMenuItems();
    final espresso = items.firstWhere((i) => i.name == 'Espresso');
    await core.bridge.cartAddConfigured(
      itemId: espresso.id,
      sizeLabel: 'Double',
      addons: const [],
      optionalFieldIds: const [],
      qty: 2,
    );
    final totals = await core.bridge.cartTotals();
    expect(totals.totalMinor, greaterThan(0));

    final methods = await core.bridge.listPaymentMethods();
    expect(methods, isNotEmpty, reason: 'seeded org must have pay methods');
    final cash = methods.firstWhere(
      (m) => m.isCash,
      orElse: () => methods.first,
    );

    final receipt = await core.bridge.checkout(
      input: CheckoutInput(
        paymentMethodId: cash.id,
        amountTenderedMinor: totals.totalMinor + 5000,
        tipMinor: 0,
        splits: const [],
      ),
    );
    expect(receipt.localOrderId, isNotEmpty);
    expect(await core.bridge.cartLines(), isEmpty);

    // The receipt renderer must produce ESC/POS bytes without a printer.
    final bytes = await core.bridge.renderReceipt(
      receipt: receipt,
      storeName: 'QA Cafe',
      currency: 'EGP',
      width: 42,
      brand: PrinterBrand.epson,
    );
    expect(bytes, isNotEmpty);

    // Close the shift — the close-shift screen's call — and confirm the
    // route machine leaves the order surface.
    final report = await core.bridge.shiftReport();
    expect(report.isOpen, isTrue);
    await core.bridge.closeShift(
      closingCashMinor: report.expectedCashMinor,
    );
    final after = await core.bridge.currentShift();
    expect(after?.isOpen ?? false, isFalse);
  });

  test(
    'session persists in the core store (restart restore)',
    () async {
      // Fresh sign-in cycle → the core persists session:blob in ITS store.
      final branches = await core.bridge.listBranches();
      await core.bridge.logout(wipeOutbox: false);
      await core.bridge.login(
        req: LoginRequest(
          mode: LoginMode.pin,
          name: 'Sara',
          pin: '123456',
          branchId: branches.first.id,
        ),
      );

      // A "restarted app": a second handle over the SAME sqlite restores the
      // session from the core's own store — the shell's exact boot path.
      final rebooted = await MadarCore.start(
        config: MadarConfig(
          baseUrl: api,
          environment: 'dev',
          dbPath: '${tmp.path}/qa.db',
          locale: 'en',
        ),
      );
      final restored = rebooted.bridge.restoreSessionCached();
      expect(
        restored,
        isNotNull,
        reason: 'login must persist the session into the core store',
      );
      expect(restored!.displayName, 'Sara');
      final route = rebooted.bridge.appRoute();
      expect(
        route,
        isNot(isA<AppRoute_Login>()),
        reason: 'a restored session must land past the login screen',
      );
      expect(route, isNot(isA<AppRoute_DeviceSetup>()));
    },
  );
}
