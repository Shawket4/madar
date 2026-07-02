import 'dart:async';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
// ExternalLibrary is only exported via the for_generated entrypoint; this
// package IS the binding layer, so the import is intentional.
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:rust_bridge/src/generated/api/bridge.dart';
import 'package:rust_bridge/src/generated/api/realtime.dart';
import 'package:rust_bridge/src/generated/api/types.dart';
import 'package:rust_bridge/src/generated/api/vault.dart';
import 'package:rust_bridge/src/generated/frb_generated.dart';

/// Owns the FRB runtime, the single [MadarBridge] handle, and the host-side
/// stream lifecycles (vault + realtime). All business logic stays in Rust —
/// this class only boots, attaches, and tears down.
class MadarCore {
  MadarCore._(this.bridge);

  /// The generated bridge — every core method lives here.
  final MadarBridge bridge;

  static bool _runtimeReady = false;

  /// Boot the Rust runtime (idempotent per engine) and construct the core.
  ///
  /// Hot-restart safe: Rust-side supervisors survive a restart while Dart
  /// stream controllers die, so any live realtime subscription is torn down
  /// before callers re-attach sinks.
  static Future<MadarCore> start({required MadarConfig config}) async {
    if (!_runtimeReady) {
      // On Apple platforms the Cargokit podspec force_loads the Rust
      // staticlib INTO rust_bridge.framework, so the symbols live in the
      // process image — FRB's default macOS loader would instead look for
      // a madar_frb.framework that doesn't exist.
      final externalLibrary = (Platform.isMacOS || Platform.isIOS)
          ? ExternalLibrary.process(iKnowHowToUseIt: true)
          : null;
      await RustBridge.init(externalLibrary: externalLibrary);
      _runtimeReady = true;
    }
    final bridge = await MadarBridge.newInstance(config: config);
    bridge.unsubscribeRealtime();
    return MadarCore._(bridge);
  }

  /// Load a native library from an explicit path — for host-side unit tests
  /// that run against a `cargo build` dylib instead of the bundled binary.
  static Future<void> initForTest({required String dylibPath}) async {
    if (_runtimeReady) return;
    await RustBridge.init(
      externalLibrary: ExternalLibrary.open(dylibPath),
    );
    _runtimeReady = true;
  }

  /// Attach the host vault. The core emits a command whenever the opaque
  /// session blob must be persisted or wiped; persist IMMEDIATELY (no
  /// debounce) — durability of offline sign-in depends on it.
  StreamSubscription<VaultCommand> attachVault(
    void Function(VaultCommand command) onCommand,
  ) {
    return bridge.tokenVaultStream().listen(onCommand);
  }

  /// Open the device's ONE session-level realtime subscription (post-login).
  /// Returns the live session carrying both streams. Idempotent in the core
  /// while a subscription is alive.
  Future<RealtimeSession> startRealtime() async {
    final events = RustStreamSink<RealtimeMessage>();
    final alerts = RustStreamSink<AlertCommand>();
    await bridge.startRealtime(events: events, alerts: alerts);
    return RealtimeSession._(bridge, events.stream, alerts.stream);
  }
}

/// A live realtime subscription. [events] drives board refreshes and the
/// connection indicator; [alerts] carries platform primitives (the core
/// already decided WHEN to alert and built localized text).
class RealtimeSession {
  RealtimeSession._(this._bridge, this.events, this.alerts);

  final MadarBridge _bridge;
  final Stream<RealtimeMessage> events;
  final Stream<AlertCommand> alerts;

  /// Tear down the Rust supervisor FIRST, then cancel Dart subscriptions —
  /// a late event during teardown is dropped safely on the Rust side.
  void stop() => _bridge.unsubscribeRealtime();
}
