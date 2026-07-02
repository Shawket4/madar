import 'package:feature_auth/src/auth_layout.dart';
import 'package:feature_auth/src/device_setup_form.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// First-run device commissioning — the screen shown while `app_route()` is
/// `AppRoute.deviceSetup` (till not bound to a branch, or reconfiguring): a
/// manager authenticates with org email + password, then binds the till to a
/// branch. KDS station binding follows on `StationPickerScreen` and the till
/// (drawer) binding lives in Settings, exactly like the natives.
///
/// Wide layout: brand panel beside the form at the brand-panel ratio;
/// stacked (logo above the form) on narrow.
class DeviceSetupScreen extends StatelessWidget {
  /// Creates the device-setup screen.
  const DeviceSetupScreen({
    required this.core,
    required this.onStateChanged,
    super.key,
  });

  /// The core handle.
  final MadarCore core;

  /// Notifies the shell after any bridge call that can move the route.
  final void Function() onStateChanged;

  @override
  Widget build(BuildContext context) {
    return AuthSplitScaffold(
      core: core,
      formBuilder: (context, {required showLogo}) => DeviceSetupForm(
        core: core,
        onStateChanged: onStateChanged,
        showLogo: showLogo,
      ),
    );
  }
}
