import 'package:rust_bridge_staff/src/generated/api/bridge.dart';
import 'package:rust_bridge_staff/src/generated/api/error.dart';

/// Localize a [MadarError] for the staff app: host-side conditions get
/// core-localized strings; server and validation details pass through
/// verbatim.
extension MadarErrorMessage on MadarBridge {
  String humanMessage(MadarError e) {
    return switch (e) {
      // The staff app has no offline sign-in to set up (that is the POS
      // till's wording): whatever needed the server needs a connection.
      MadarError_Offline() => tr(key: 'staff.needs_connection'),
      MadarError_Unauthenticated(:final detail) => _or(detail),
      // Keep the FIELD in the message: bare details read as "is required" with
      // no subject. Prettify ("password is required" — underscores spaced).
      MadarError_Validation(:final field, :final detail) => _or(
        field.trim().isEmpty ? detail : '${field.replaceAll('_', ' ')} $detail',
      ),
      MadarError_Server(:final detail) => _or(detail),
      MadarError_Transient() => tr(key: 'err.network'),
      MadarError_Forbidden() => tr(key: 'err.not_allowed'),
      MadarError_Internal(:final detail) => _or(detail),
    };
  }

  String _or(String detail) =>
      detail.trim().isEmpty ? tr(key: 'err.generic') : detail;
}
