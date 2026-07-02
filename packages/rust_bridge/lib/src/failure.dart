import 'package:rust_bridge/src/generated/api/bridge.dart';
import 'package:rust_bridge/src/generated/api/error.dart';

/// Localize a [MadarError] exactly the way the native apps do (their
/// `humanMessage`): host-side conditions get core-localized strings; server
/// and validation details pass through verbatim.
extension MadarErrorMessage on MadarBridge {
  String humanMessage(MadarError e) {
    return switch (e) {
      MadarError_Offline() => tr(key: 'err.offline_no_setup'),
      MadarError_Unauthenticated(:final detail) => _or(detail),
      // Keep the FIELD in the message: bare details read as "is required"
      // with no subject. The natives show the raw Display ("invalid:
      // password: is required"); we prettify instead ("password is
      // required" — underscores spaced).
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
