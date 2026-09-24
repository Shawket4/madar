import 'package:geolocator/geolocator.dart';

/// Whether this phone may track in the background ("Always" location), and
/// the one ask that gets it (CL-4, CL-5).
///
/// geolocator asks iOS only while the choice is still "not determined", and
/// its first ask is "While Using". A phone that allowed that was never asked
/// for "Always", so every shift read "tracking off" (E2E clocking). The
/// upgrade is asked once per install through the host ([askAlways]: the
/// AppDelegate's `requestAlways`), since iOS shows it only once and does not
/// answer when it doesn't show it; after that the person can still turn it
/// on in Settings.
class AlwaysLocation {
  AlwaysLocation({
    required this.check,
    required this.request,
    required this.askAlways,
    required this.asked,
    required this.markAsked,
  });

  final Future<LocationPermission> Function() check;
  final Future<LocationPermission> Function() request;

  /// The host's ask; true/false once the person answered, null when there
  /// was no answer in time.
  final Future<bool?> Function() askAlways;
  final bool Function() asked;
  final Future<void> Function() markAsked;

  Future<bool> call() async {
    var p = await check();
    if (p == LocationPermission.denied) p = await request();
    if (p == LocationPermission.always) return true;
    if (p != LocationPermission.whileInUse || asked()) return false;
    await markAsked();
    final answer = await askAlways();
    return answer ?? await check() == LocationPermission.always;
  }
}
