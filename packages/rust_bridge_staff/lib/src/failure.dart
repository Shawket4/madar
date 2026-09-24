import 'package:rust_bridge_staff/src/generated/api/bridge.dart';
import 'package:rust_bridge_staff/src/generated/api/error.dart';

/// Localize a [MadarError] for the staff app: host-side conditions get
/// core-localized strings; server and validation details pass through
/// verbatim.
extension MadarErrorMessage on MadarBridge {
  String humanMessage(MadarError e) => staffErrorText(e, (k) => tr(key: k));
}

/// The staff app's words for [e]; [words] looks up a core i18n key.
String staffErrorText(MadarError e, String Function(String key) words) {
  String or(String detail) =>
      detail.trim().isEmpty ? words('err.generic') : detail;
  return switch (e) {
    // Dawam has no offline sign-in to set up (that is the POS teller's
    // sentence, E2E clocking C1): offline, an action that needs the server
    // says so.
    MadarError_Offline() => words('staff.needs_connection'),
    MadarError_Unauthenticated(:final detail) => or(detail),
    // Keep the FIELD in the message: bare details read as "is required" with
    // no subject. Prettify ("password is required" — underscores spaced).
    MadarError_Validation(:final field, :final detail) => or(
      field.trim().isEmpty ? detail : '${field.replaceAll('_', ' ')} $detail',
    ),
    MadarError_Server(:final detail) => or(detail),
    MadarError_Transient() => words('err.network'),
    MadarError_Forbidden() => words('err.not_allowed'),
    MadarError_Internal(:final detail) => or(detail),
  };
}
