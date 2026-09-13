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
        field.trim().isEmpty || coreDetailKeys.containsKey(detail)
            ? detail
            : '${field.replaceAll('_', ' ')} $detail',
      ),
      MadarError_Server(:final detail) => _or(detail),
      MadarError_Transient() => tr(key: 'err.network'),
      MadarError_Forbidden() => tr(key: 'err.not_allowed'),
      MadarError_Internal(:final detail) => _or(detail),
    };
  }

  String _or(String detail) {
    if (detail.trim().isEmpty) return tr(key: 'err.generic');
    final key = coreDetailKeys[detail];
    return key == null ? detail : tr(key: key);
  }
}

/// The core's own refusals (raised in English, so a log reads them) → the key
/// that says the same thing to a teller in the app's language. A detail not
/// listed here is shown as written — a server's sentence, a field message.
/// Pinned against the core's sources by `tests/i18n_call_sites.rs`, which
/// checks every key below exists in both languages.
const Map<String, String> coreDetailKeys = {
  'not signed in': 'err.not_signed_in',
  'token expired': 'err.session_expired',
  'wrong pin': 'err.wrong_pin',
  'PIN not recognized.': 'err.wrong_pin',
  'no offline bundle cached — sign in online once first':
      'err.no_offline_bundle',
  'cart is empty': 'err.cart_empty',
  'no open shift': 'err.no_shift',
  'no shift': 'err.no_shift',
  'held order is being edited on another till': 'err.held_elsewhere',
  'held order not found': 'err.parked_gone',
  'no such parked order': 'err.parked_gone',
  'that line is no longer in the cart': 'err.line_gone',
  'unknown payment method': 'err.unknown_payment',
  'payment method not available here': 'err.payment_method_unavailable',
  'scan a card or type a phone number': 'err.scan_or_phone',
  'a reward can only be redeemed online': 'loyalty.reward_offline',
  'no order to add points to': 'err.no_order_points',
  'table is taken': 'err.table_taken',
  'both tables are empty': 'err.move_both_empty',
  'table needs clearing first': 'err.move_dirty',
  'table is held for a booking': 'err.move_booked',
  'pick two different tables': 'err.move_same',
  'this party already has a waiting transfer': 'err.transfer_waiting',
  'no printer configured for this device': 'printing.no_printer',
  'a note is required for cash movements': 'err.cash_note',
  'amount cannot be zero': 'err.amount_zero',
  'must be greater than zero': 'err.amount_zero',
  'amount is out of range': 'err.amount_range',
  'a refund is cash leaving a drawer; open a shift first':
      'history.refund_needs_shift',
  'a refund names a SYNCED sale; a queued one has no server id yet':
      'err.refund_queued',
  'required — an override with no reason is indistinguishable from a mistake':
      'till.opening_reason_required',
};
