/// "Use my location" (TEAM-SET-016/017/018): the device's position for a
/// branch pin. The web asks the browser (`navigator.geolocation`, high
/// accuracy, a 15 s timeout, no cached fix); the app asks the device through
/// a [SetupLocator].
///
/// No location plugin ships with the dashboard yet, so the default locator
/// answers [LocationFailure.unsupported] ("This browser can't read its
/// location. Paste a Maps link instead.") and the owner pastes a link. The
/// app installs a real one with
/// `ref.read(setupLocatorProvider.notifier).use(...)` (or a provider
/// override) once it has one; tests install a fake the same way.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'geo.dart';

/// Why no fix came back (the web's three refusals).
enum LocationFailure {
  /// The platform cannot read a location at all (`pinNoGeo`).
  unsupported,

  /// The person (or the system) refused permission (`pinDenied`).
  denied,

  /// No fix in time, or no signal (`pinUnavailable`).
  unavailable,
}

/// A fix, or why there is none.
class LocationResult {
  const LocationResult.fix(LatLng this.at, double this.accuracyMeters)
    : failure = null;
  const LocationResult.failed(LocationFailure this.failure)
    : at = null,
      accuracyMeters = null;

  final LatLng? at;

  /// The fix's accuracy radius, in metres.
  final double? accuracyMeters;
  final LocationFailure? failure;
}

/// Reads the device's position once: high accuracy, at most [timeout], never
/// a cached fix.
abstract interface class SetupLocator {
  Future<LocationResult> locate({Duration timeout});
}

/// The web's options: `{enableHighAccuracy: true, timeout: 15_000,
/// maximumAge: 0}`.
const Duration locateTimeout = Duration(seconds: 15);

/// The default: this build cannot read the device's location.
class UnsupportedLocator implements SetupLocator {
  const UnsupportedLocator();

  @override
  Future<LocationResult> locate({Duration timeout = locateTimeout}) async =>
      const LocationResult.failed(LocationFailure.unsupported);
}

class SetupLocatorNotifier extends Notifier<SetupLocator> {
  @override
  SetupLocator build() => const UnsupportedLocator();

  /// Installs [locator] (the app's platform reader, a test's fake).
  // A setter would read oddly at the call site: `notifier.use(fake)`.
  // ignore: use_setters_to_change_properties
  void use(SetupLocator locator) => state = locator;
}

final setupLocatorProvider =
    NotifierProvider<SetupLocatorNotifier, SetupLocator>(
      SetupLocatorNotifier.new,
    );
