/// Kitchen-board wording — every string the board shows, resolved through
/// the core's i18n and nothing else.
///
/// The board names a few things the core's table has no key for yet ("Bump
/// all", the round tag, the refused-bumps banner). Those keys are requested
/// in `i18n.rs` (one pass by the master; see the lane's `needsFromOthers`).
/// Until they land, `tr` hands back the key itself, which is how a missing
/// key shows. So every new key is asked for FIRST and, when missing, the
/// nearest key that already exists stands in — never a literal. The moment
/// the key lands in the core the board upgrades by itself.
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
  /// The wanted key, or its stand-in while the core lacks it.
  String trOr((String, String) key) {
    final (wanted, fallback) = key;
    final v = tr(key: wanted);
    return v == wanted ? tr(key: fallback) : v;
  }

  /// The wanted key, or null while the core lacks it — for a word that is
  /// better left out than approximated.
  String? trMaybe((String, String) key) {
    final v = tr(key: key.$1);
    return v == key.$1 ? null : v;
  }
}
