import 'package:flutter/foundation.dart';
import 'package:rust_bridge/src/generated/api/bridge.dart';

final Set<String> _reported = <String>{};

/// `tr`, but a key the core cannot answer is reported instead of swallowed.
///
/// The core hands a missing key back as itself. A screen showing
/// `order.clear_cart_body` is at least visible; the old Dart fallback tables
/// that dressed it up in English were not, and the gap kept coming back as
/// "missing strings". In debug builds this prints each missing key once, so
/// the gap shows on the console the first time a screen asks for it. Release
/// builds pay nothing but the comparison. `tests/i18n_call_sites.rs` in the
/// core is the build-time half of the same guard.
extension CheckedTr on MadarBridge {
  String trChecked(String key) {
    final v = tr(key: key);
    if (kDebugMode && v == key && _reported.add(key)) {
      debugPrint(
        '[i18n] MISSING KEY "$key" — add it to '
        'rust-core/crates/madar-core/src/i18n.rs in BOTH en and ar',
      );
    }
    return v;
  }
}
