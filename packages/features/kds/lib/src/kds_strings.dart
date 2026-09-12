/// Kitchen-board wording — every string the board shows, resolved through
/// the core's i18n and nothing else.
///
/// Every key below has landed in `i18n.rs`. The second key in each record
/// is the stand-in that used to cover for a missing first key; it is no longer
/// consulted (see the extension), because a plausible stand-in hid gaps.
library;

import 'package:rust_bridge/rust_bridge.dart';

/// The keys the board introduces, each with the existing key that stands in
/// for it. Kept as one table so the ask to `i18n.rs` is this list, verbatim.
abstract final class KdsKeys {
  /// The card's one button. "Done" is the honest stand-in: pressing it
  /// marks the whole card done.
  static const bumpAll = ('kds.bump_all', 'common.done');

  /// The round tag on a waiter's card ("R3"). No stand-in reads right, so
  /// the card falls back to the bare figure behind a `#` — see [KdsTr.trMaybe].
  static const round = ('kds.round', 'kds.round');

  /// The header's "N open" word. Dropped, not approximated, while missing.
  static const open = ('kds.open', 'kds.open');

  /// The age unit after the mono figure ("7m"). Dropped while missing — the
  /// clock glyph beside the figure says what it is.
  static const ageMin = ('kds.age_min', 'kds.age_min');

  /// The live-updates dot's label (screen readers).
  static const live = ('kds.live', 'chrome.online');

  /// The state tag on a fully bumped card.
  static const ready = ('kds.ready', 'delivery.status.ready');

  /// The outbox pill's words, by state.
  static const pillSynced = ('kds.pill_synced', 'chrome.online');
  static const pillQueued = ('kds.pill_queued', 'sync.queued');
  static const pillOffline = ('kds.pill_offline', 'chrome.offline');
  static const pillStuck = ('kds.pill_stuck', 'sync.failed');

  /// The banners.
  static const offlineBanner = ('kds.offline_banner', 'chrome.offline_banner');
  static const refused = ('kds.refused', 'sync.failed');
  static const retry = ('kds.retry', 'sync.retry');
  static const discard = ('kds.discard', 'sync.discard');
}

extension KdsTr on MadarBridge {
  /// The key's words. The second half of each record names the key that used
  /// to stand in while the core lacked the first; every first key has landed
  /// in `i18n.rs`, so the stand-in is never consulted again — a stand-in only
  /// hid the next gap as a wrong-but-plausible word. A miss now shows as the
  /// raw key, is reported in debug builds, and fails the core's
  /// `tests/i18n_call_sites.rs`.
  String trOr((String, String) key) => trChecked(key.$1);

  /// The same; kept nullable for the call sites written against the old
  /// "drop the word while missing" contract.
  String? trMaybe((String, String) key) => trChecked(key.$1);

  /// The key itself, for state that stores what to say rather than the words.
  String trKey((String, String) key) => key.$1;
}
