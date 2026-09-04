import 'package:geolocator/geolocator.dart';

/// Why a fix could not be taken. Each maps to one line of copy the user can act
/// on — "something went wrong" is useless when the fix is a settings toggle.
enum LocationFailure { serviceDisabled, permissionDenied, unavailable }

/// A position, or the reason there isn't one.
sealed class LocationResult {
  const LocationResult();
}

class LocationFix extends LocationResult {
  const LocationFix(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class LocationDenied extends LocationResult {
  const LocationDenied(this.reason);

  final LocationFailure reason;
}

/// Platform glue, and ONLY platform glue.
///
/// This acquires coordinates. It does not decide whether they are close enough
/// to the branch, and it must never be given that job: the geofence lives on the
/// server precisely because a phone can be told to report any position it likes.
/// What comes back here is evidence to submit, not a verdict.
class LocationService {
  const LocationService();

  /// A best-effort current position with a hard timeout — a check-in button that
  /// spins forever is worse than one that says "try again".
  Future<LocationResult> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationDenied(LocationFailure.serviceDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return const LocationDenied(LocationFailure.permissionDenied);
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // The fence is tens of metres wide, so a coarse fix would produce
          // false refusals at the door.
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return LocationFix(position.latitude, position.longitude);
    } on Object {
      return const LocationDenied(LocationFailure.unavailable);
    }
  }
}
