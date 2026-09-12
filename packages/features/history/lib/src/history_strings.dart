import 'package:rust_bridge/rust_bridge.dart';

/// Localise a Sales-history string.
///
/// A plain pass-through to the core, which owns every word in both hosts.
///
/// This used to carry its own English+Arabic table for keys the core had not
/// learned yet. That was the right call while the keys were landing and the
/// wrong thing to leave behind: a key missing from `i18n.rs` came out as
/// untranslated ENGLISH to an Arabic teller instead of as a visible raw key,
/// so the gap was invisible and kept being re-reported as "missing strings".
/// The table is gone and `tests/i18n_call_sites.rs` fails the build instead.
String historyTr(MadarBridge bridge, String key) => bridge.tr(key: key);
