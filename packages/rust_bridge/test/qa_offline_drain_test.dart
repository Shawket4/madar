@Tags(['qa-offline'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Reproduces the offline→online outbox drain against a local backend
/// behind a killable TCP proxy (tool/tcp_proxy.py). Orchestrated by marker
/// files — the runner script kills/starts the proxy when asked:
///   test touches  qa_offline.req  → runner kills proxy,  touches qa_offline.ack
///   test touches  qa_online.req   → runner starts proxy, touches qa_online.ack
/// Run via: tool/qa_offline_drain.sh
void main() {
  final api = Platform.environment['MADAR_QA_API'];
  final email = Platform.environment['MADAR_QA_EMAIL'];
  final password = Platform.environment['MADAR_QA_PASSWORD'];
  final markers = Platform.environment['MADAR_QA_MARKERS'];

  if (api == null || email == null || password == null || markers == null) {
    test('offline drain (SKIPPED — run via tool/qa_offline_drain.sh)', () {
      markTestSkipped('needs the proxy runner');
    });
    return;
  }

  Future<void> signal(String phase) async {
    File('$markers/$phase.req').createSync(recursive: true);
    final ack = File('$markers/$phase.ack');
    for (var i = 0; i < 100; i++) {
      if (ack.existsSync()) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('runner never acked $phase');
  }

  final dylib = File(
    '${Directory.current.path}/../../../madar-pos/rust-core/target/release/libmadar_frb.dylib',
  );

  late MadarCore core;
  late Directory tmp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await MadarCore.initForTest(dylibPath: dylib.path);
    tmp = Directory.systemTemp.createTempSync('madar-qa-drain');
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

  test('orders queued offline drain after connectivity returns', () async {
    // Online setup — the screens' exact calls.
    await core.bridge.login(
      req: LoginRequest(
        mode: LoginMode.email,
        email: email,
        password: password,
      ),
    );
    final branches = await core.bridge.listBranches();
    await core.bridge.setDeviceBranch(
      branchId: branches.first.id,
      branchName: branches.first.name,
    );
    await core.bridge.logout(wipeOutbox: false);
    await core.bridge.login(
      req: LoginRequest(
        mode: LoginMode.pin,
        name: 'Sara',
        pin: '123456',
        branchId: branches.first.id,
      ),
    );
    await core.bridge.refreshCatalog();
    final shift = await core.bridge.refreshShift();
    if (!(shift?.isOpen ?? false)) {
      await core.bridge.openShift(openingCashMinor: 10000);
    }
    final items = await core.bridge.listMenuItems();
    final espresso = items.firstWhere((i) => i.name == 'Espresso');
    final methods = await core.bridge.listPaymentMethods();
    final cash = methods.firstWhere(
      (m) => m.isCash,
      orElse: () => methods.first,
    );

    // ── Network drops ──
    await signal('qa_offline');
    // The core debounces transient probe failures — a single blip never
    // flips offline. Drive the failure streak like repeated heartbeats.
    var online = true;
    for (var i = 0; i < 10 && online; i++) {
      online = await core.bridge.refreshConnectivity();
    }
    expect(online, isFalse, reason: 'proxy is dead — core must go offline');

    // Two offline checkouts → both must queue.
    for (var i = 0; i < 2; i++) {
      await core.bridge.cartClear();
      await core.bridge.cartAddConfigured(
        itemId: espresso.id,
        sizeLabel: 'Single',
        addons: const [],
        optionalFieldIds: const [],
        qty: 1,
      );
      final totals = await core.bridge.cartTotals();
      await core.bridge.checkout(
        input: CheckoutInput(
          paymentMethodId: cash.id,
          amountTenderedMinor: totals.totalMinor,
          tipMinor: 0,
          splits: const [],
        ),
      );
    }
    final queued = await core.bridge.pendingOutboxCount();
    expect(queued, greaterThanOrEqualTo(2), reason: 'offline sales must queue');

    // ── Network returns ──
    await signal('qa_online');
    expect(await core.bridge.refreshConnectivity(), isTrue);

    // The drain rides the SAME call the app's heartbeat/manual sync makes.
    var pending = queued;
    for (var i = 0; i < 30 && pending > 0; i++) {
      await core.bridge.refreshConnectivity();
      await Future<void>.delayed(const Duration(seconds: 1));
      pending = await core.bridge.pendingOutboxCount();
    }
    final status = await core.bridge.syncStatus();
    expect(
      pending,
      0,
      reason:
          'outbox must drain once online (status: pending=${status.pending} '
          'failed=${status.failed} authPaused=${status.authPaused})',
    );
  });
}
