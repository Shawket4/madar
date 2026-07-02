import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// M1 "hello core" spike — proves every bridge mechanism end-to-end on a
/// device: sync + async calls, mirrors, typed errors, vault + realtime
/// streams, and concurrency on the opaque handle. Replaced by the real app
/// shell in M3.
class SpikeScreen extends StatefulWidget {
  const SpikeScreen({super.key});

  @override
  State<SpikeScreen> createState() => _SpikeScreenState();
}

class _Check {
  _Check(this.name, this.detail, {required this.ok});
  final String name;
  final String detail;
  final bool ok;
}

class _SpikeScreenState extends State<SpikeScreen> {
  final _checks = <_Check>[];
  bool _running = true;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  void _add(String name, String detail, {required bool ok}) {
    setState(() => _checks.add(_Check(name, detail, ok: ok)));
  }

  Future<void> _run() async {
    try {
      // 1. Free sync fns (no bridge handle needed once runtime is up).
      final docs = await getApplicationDocumentsDirectory();
      final core = await MadarCore.start(
        config: MadarConfig(
          baseUrl: 'https://api.madar-pos.cloud',
          environment: 'dev',
          dbPath: '${docs.path}${Platform.pathSeparator}madar-spike.db',
          locale: 'en',
        ),
      );
      _add(
        'construct',
        'MadarBridge.newInstance + unsubscribe protocol',
        ok: true,
      );

      final v = ffiSurfaceVersion();
      _add(
        'ffi version',
        'core says $v (wrapper written against 4)',
        ok: v == 4,
      );
      _add('greet', greet(name: 'Flutter'), ok: true);
      _add('core version', coreVersion(), ok: true);

      // 2. Sync reads on the handle (safe during builds).
      final route = core.bridge.appRoute();
      _add(
        'app_route',
        '$route (fresh db → DeviceSetup)',
        ok: route is AppRoute_DeviceSetup,
      );

      final signIn = core.bridge.tr(key: 'login.sign_in');
      _add(
        'tr(en)',
        'login.sign_in → "$signIn"',
        ok: signIn != 'login.sign_in',
      );
      core.bridge.setLocale(locale: 'ar');
      final rtl = core.bridge.isRtl();
      final signInAr = core.bridge.tr(key: 'login.sign_in');
      core.bridge.setLocale(locale: 'en');
      _add('locale/RTL', 'ar → rtl=$rtl, "$signInAr"', ok: rtl);

      // 3. Vault stream attaches (emits only after a login).
      final vaultEvents = <VaultCommand>[];
      final vaultSub = core.attachVault(vaultEvents.add);
      _add('vault stream', 'attached (commands arrive on login)', ok: true);

      // 4. Async on the worker pool + tokio.
      final pending = await core.bridge.pendingOutboxCount();
      _add('outbox', 'pending = $pending', ok: pending == 0);
      final online = await core.bridge.refreshConnectivity();
      _add(
        'connectivity',
        'refresh_connectivity → $online (either is fine)',
        ok: true,
      );

      // 5. Typed error mapping — signed out, so open_shift must throw.
      try {
        await core.bridge.openShift(openingCashMinor: 0);
        _add('typed error', 'open_shift unexpectedly succeeded', ok: false);
      } on MadarError catch (e) {
        _add(
          'typed error',
          '${e.runtimeType}: "${core.bridge.humanMessage(e)}"',
          ok: e is MadarError_Unauthenticated || e is MadarError_Validation,
        );
      }

      // 6. Realtime while signed out must throw Unauthenticated (async path
      //    that would tokio::spawn on success).
      try {
        await core.startRealtime();
        _add(
          'realtime gate',
          'unexpectedly started while signed out',
          ok: false,
        );
      } on MadarError catch (e) {
        _add(
          'realtime gate',
          '${e.runtimeType} as expected',
          ok: e is MadarError_Unauthenticated,
        );
      }

      // 7. Concurrency on the opaque handle — no deadlock.
      final results = await Future.wait([
        core.bridge.listMenuItems(),
        core.bridge.cartLines(),
        core.bridge.syncStatus(),
      ]);
      _add(
        'concurrency',
        'menu=${(results[0] as List<Object?>).length} '
            'cart=${(results[1] as List<Object?>).length} '
            'syncStatus ok',
        ok: true,
      );

      // Not awaited: the core holds the TokenStore forever, so the vault
      // stream never closes — awaiting cancel() would hang (see the smoke
      // test's vault case).
      unawaited(vaultSub.cancel());
    } on Object catch (e, st) {
      _add('CRASH', '$e\n$st', ok: false);
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final failed = _checks.where((c) => !c.ok).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _running
              ? 'Core spike — running…'
              : failed == 0
              ? 'Core spike — ALL ${_checks.length} PASSED'
              : 'Core spike — $failed FAILED',
        ),
        backgroundColor: _running
            ? null
            : failed == 0
            ? const Color(0xFF16A34A)
            : const Color(0xFFDC2626),
      ),
      body: ListView.builder(
        itemCount: _checks.length,
        itemBuilder: (context, i) {
          final c = _checks[i];
          return ListTile(
            dense: true,
            leading: Icon(
              c.ok ? Icons.check_circle : Icons.error,
              color: c.ok ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
            ),
            title: Text(c.name),
            subtitle: Text(c.detail),
          );
        },
      ),
    );
  }
}
