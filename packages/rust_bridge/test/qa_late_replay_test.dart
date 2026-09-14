@Tags(['qa-late-replay'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

import 'host_library.dart';

/// Reproduces the cross-till close race and its fix: a teller queues orders
/// OFFLINE, ANOTHER till closes the till server-side, then the queue drains.
/// The replayed sales must land onto the (now closed) till and reconcile its
/// cash total instead of dead-lettering forever.
///
/// Run behind a killable proxy so "offline" is real:
///   tool/qa_late_replay.sh   (MADAR_QA_API points at the proxy; the runner
///   toggles it and, on the offline signal, closes the till via psql).
void main() {
  final api = Platform.environment['MADAR_QA_API'];
  final email = Platform.environment['MADAR_QA_EMAIL'];
  final password = Platform.environment['MADAR_QA_PASSWORD'];
  final markers = Platform.environment['MADAR_QA_MARKERS'];

  if (api == null || email == null || password == null || markers == null) {
    test('late replay (SKIPPED — run via tool/qa_late_replay.sh)', () {
      markTestSkipped('needs the proxy + shift-closer runner');
    });
    return;
  }

  Future<void> signal(String phase) async {
    File('$markers/$phase.req').createSync(recursive: true);
    final ack = File('$markers/$phase.ack');
    for (var i = 0; i < 150; i++) {
      if (ack.existsSync()) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('runner never acked $phase');
  }

  final dylib = hostLibrary();

  late MadarCore core;
  late Directory tmp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await MadarCore.initForTest(dylibPath: dylib.path);
    tmp = Directory.systemTemp.createTempSync('madar-late-replay');
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
    // Best-effort: the core still holds the SQLite file open, and Windows
    // refuses to remove a directory containing an open handle. See
    // `bridge_smoke_test.dart` — housekeeping must not fail a green suite.
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // Left for the OS to sweep.
    }
  });

  test(
    'orders queued offline replay into a shift closed by another till',
    () async {
      // Online setup + an open till with a known opening float.
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
      final till = await core.bridge.refreshTill();
      if (!(till?.isOpen ?? false)) {
        await core.bridge.openTill(openingCashMinor: 20000);
      }
      final openTill = await core.bridge.currentTill();
      final tillId = openTill!.id;
      final report0 = await core.bridge.tillReport();
      final expectedBefore = report0.expectedCashMinor;

      final items = await core.bridge.listMenuItems();
      final espresso = items.firstWhere((i) => i.name == 'Espresso');
      final methods = await core.bridge.listPaymentMethods();
      final cash = methods.firstWhere(
        (m) => m.isCash,
        orElse: () => methods.first,
      );

      // ── Network drops; drive the failure streak to flip offline. ──
      await signal(
        'qa_offline',
      ); // runner: kill proxy AND close the till (psql)
      var online = true;
      for (var i = 0; i < 12 && online; i++) {
        online = await core.bridge.refreshConnectivity();
      }
      expect(online, isFalse);

      // Two CASH sales while offline → both queue against the (now-closed) till.
      var cashTotal = 0;
      for (var i = 0; i < 2; i++) {
        await core.bridge.cartClear();
        await core.bridge.cartAddConfigured(
          itemId: espresso.id,
          sizeLabel: 'Double',
          addons: const [],
          optionalFieldIds: const [],
          qty: 1,
        );
        final totals = await core.bridge.cartTotals();
        cashTotal += totals.totalMinor;
        await core.bridge.checkout(
          input: CheckoutInput(
            paymentMethodId: cash.id,
            amountTenderedMinor: totals.totalMinor,
            tipMinor: 0,
            splits: const [],
            loyaltyRedemptions: const [],
          ),
        );
      }
      expect(await core.bridge.pendingOutboxCount(), greaterThanOrEqualTo(2));

      // ── Network returns; the queue drains. ──
      await signal('qa_online');
      var pending = await core.bridge.pendingOutboxCount();
      for (var i = 0; i < 40 && pending > 0; i++) {
        await core.bridge.refreshConnectivity();
        await Future<void>.delayed(const Duration(seconds: 1));
        pending = await core.bridge.pendingOutboxCount();
      }
      final status = core.bridge.syncStatus();
      expect(
        pending,
        0,
        reason:
            'late sales must NOT dead-letter (pending=${status.pendingOutbox} '
            'failed=${status.deadOutbox} authPaused=${status.authPaused})',
      );

      // The closed till's Z-report must now include the two late cash sales.
      final report1 = await core.bridge.tillReportFor(tillId: tillId);
      expect(
        report1.isOpen,
        isFalse,
        reason: 'shift was closed by the other till',
      );
      expect(
        report1.expectedCashMinor,
        expectedBefore + cashTotal,
        reason: 'expected cash must reconcile to include the replayed sales',
      );
    },
  );
}
