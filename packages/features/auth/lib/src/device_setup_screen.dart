import 'package:feature_auth/src/auth_layout.dart';
import 'package:feature_auth/src/device_setup_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// First-run device commissioning — the screen shown while `app_route()` is
/// `AppRoute.deviceSetup` (till not bound to a branch, or reconfiguring): a
/// manager authenticates with org email + password, then binds the till to a
/// branch. KDS station binding follows on `StationPickerScreen` and the till
/// (drawer) binding lives in Settings, exactly like the natives.
///
/// Wide layout: brand panel beside the form at the brand-panel ratio;
/// stacked (logo above the form) on narrow.
class DeviceSetupScreen extends ConsumerWidget {
  /// Creates the device-setup screen.
  const DeviceSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AuthSplitScaffold(
      formBuilder: (context, {required showLogo}) =>
          DeviceSetupForm(showLogo: showLogo),
    );
  }
}
