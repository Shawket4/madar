// The words the Sell / Floor / Bill screens say, resolved through the core.
//
// This used to carry its own English and Arabic table for keys the core had
// not learned yet. Those keys all live in `rust-core/crates/madar-core/src/
// i18n.rs` now, and a local table only hid the next gap: a key missing from
// the core came out as the table's English to an Arabic teller instead of as
// a visible raw key. The core answers; a miss is reported in debug builds
// and fails `tests/i18n_call_sites.rs` in the core.
import 'package:rust_bridge/rust_bridge.dart';

/// `bridge.tr(key)`, with a missing key reported in debug builds.
String orderWord(MadarBridge bridge, String key) => bridge.trChecked(key);
