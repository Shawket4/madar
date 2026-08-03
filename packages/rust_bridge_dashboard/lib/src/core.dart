import 'dart:async';
import 'dart:io';

// ExternalLibrary is only exported via the for_generated entrypoint; this
// package IS the binding layer, so the import is intentional.
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:rust_bridge_dashboard/src/generated/api/bridge.dart';
import 'package:rust_bridge_dashboard/src/generated/api/types.dart';
import 'package:rust_bridge_dashboard/src/generated/frb_generated.dart';

/// Owns the FRB runtime and the single [MadarBridge] handle. All business logic
/// stays in Rust — this class only boots and constructs the handle. (The
/// dashboard bridge has no realtime stream surface; that's POS-only.)
class MadarCore {
  MadarCore._(this.bridge);

  /// The generated bridge — every dashboard core method lives here.
  final MadarBridge bridge;

  static bool _runtimeReady = false;

  /// Boot the Rust runtime (idempotent per engine) and construct the core.
  static Future<MadarCore> start({required MadarConfig config}) async {
    if (!_runtimeReady) {
      // On Apple platforms the Cargokit podspec force_loads the Rust staticlib
      // INTO the framework, so the symbols live in the process image — FRB's
      // default macOS loader would instead look for a framework that doesn't
      // exist.
      final externalLibrary = (Platform.isMacOS || Platform.isIOS)
          ? ExternalLibrary.process(iKnowHowToUseIt: true)
          : null;
      await DashboardBridge.init(externalLibrary: externalLibrary);
      _runtimeReady = true;
    }
    final bridge = await MadarBridge.newInstance(config: config);
    return MadarCore._(bridge);
  }

  /// Load a native library from an explicit path — for host-side unit tests
  /// that run against a `cargo build` dylib instead of the bundled binary.
  static Future<void> initForTest({required String dylibPath}) async {
    if (_runtimeReady) return;
    await DashboardBridge.init(
      externalLibrary: ExternalLibrary.open(dylibPath),
    );
    _runtimeReady = true;
  }
}
