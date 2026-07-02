import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Host-side bridge regression gate: loads the cargo-built dylib directly
/// (no emulator, no Cargokit) and exercises every bridge mechanism that can
/// run without a backend. Build the dylib first (release only — debug target dirs are huge):
///   cargo build -p madar_frb --release --manifest-path ../madar-pos/rust-core/Cargo.toml
void main() {
  // Release only: debug rust builds are ~8 GB of target dir on this machine.
  final dylib = File(
    '${Directory.current.path}/../../../madar-pos/rust-core/target/release/libmadar_frb.dylib',
  );

  if (!dylib.existsSync()) {
    test('bridge smoke (SKIPPED — dylib not built)', () {
      markTestSkipped(
        'Run: cargo build -p madar_frb --release '
        '(--manifest-path ../madar-pos/rust-core/Cargo.toml)',
      );
    });
    return;
  }

  late MadarCore core;
  late Directory tmp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await MadarCore.initForTest(dylibPath: dylib.path);
    tmp = Directory.systemTemp.createTempSync('madar-frb-test');
    core = await MadarCore.start(
      config: MadarConfig(
        baseUrl: 'http://127.0.0.1:1', // never reached in this suite
        environment: 'dev',
        dbPath: '${tmp.path}/test.db',
        locale: 'en',
      ),
    );
  });

  tearDownAll(() {
    tmp.deleteSync(recursive: true);
  });

  test('ffi surface version matches the wrapper contract', () {
    expect(ffiSurfaceVersion(), 4);
    expect(coreVersion(), isNotEmpty);
    expect(greet(name: 'test'), contains('test'));
  });

  test('fresh store routes to device setup', () {
    expect(core.bridge.appRoute(), isA<AppRoute_DeviceSetup>());
    expect(core.bridge.isAuthenticated(), isFalse);
    expect(core.bridge.currentSession(), isNull);
  });

  test('i18n: tr resolves, locale flips RTL', () {
    final en = core.bridge.tr(key: 'login.sign_in');
    expect(en, isNot('login.sign_in'));
    core.bridge.setLocale(locale: 'ar');
    expect(core.bridge.isRtl(), isTrue);
    expect(core.bridge.tr(key: 'login.sign_in'), isNot(en));
    core.bridge.setLocale(locale: 'en');
    expect(core.bridge.isRtl(), isFalse);
  });

  test('async reads run on the worker pool', () async {
    expect(await core.bridge.pendingOutboxCount(), 0);
    final status = await core.bridge.syncStatus();
    expect(status.pending, 0);
    expect(status.failed, 0);
  });

  test('typed errors cross the boundary with localized messages', () async {
    try {
      await core.bridge.openShift(openingCashMinor: 0);
      fail('open_shift must throw while signed out');
    } on MadarError catch (e) {
      expect(
        e,
        anyOf(isA<MadarError_Unauthenticated>(), isA<MadarError_Validation>()),
      );
      expect(core.bridge.humanMessage(e), isNotEmpty);
    }
  });

  test('realtime is gated on auth', () async {
    expect(
      core.startRealtime,
      throwsA(isA<MadarError_Unauthenticated>()),
    );
  });

  test('vault stream attaches without error', () async {
    // The core holds the Rust-side TokenStore for the process lifetime, so
    // the stream never closes — cancel() must NOT be awaited (it would wait
    // for a close that never comes). Attach-once is the real app semantics.
    final sub = core.attachVault((_) {});
    unawaited(sub.cancel());
  });

  test('concurrent calls on the opaque handle do not deadlock', () async {
    final results = await Future.wait([
      core.bridge.listMenuItems(),
      core.bridge.cartLines(),
      core.bridge.listDrafts(),
      core.bridge.listCategories(),
    ]);
    expect(results, hasLength(4));
  });

  test('cart round-trip: add, total, clear (pure local)', () async {
    final lines = await core.bridge.cartAdd(
      itemId: 'itm-1',
      name: 'Espresso',
      unitPriceMinor: 4500,
    );
    expect(lines, hasLength(1));
    expect(lines.first.qty, 1);
    final totals = await core.bridge.cartTotals();
    expect(totals.subtotalMinor, 4500);
    await core.bridge.cartClear();
    expect(await core.bridge.cartLines(), isEmpty);
  });
}
