/// Queue wording — every string the Queue shows, resolved through the core's
/// i18n and nothing else.
///
/// Every key below has landed in `i18n.rs`. The second key in each record
/// is the stand-in that used to cover for a missing first key; it is no longer
/// consulted (see the extension), because a plausible stand-in hid gaps.
library;

import 'package:rust_bridge/rust_bridge.dart';

/// The keys the Queue introduces, each with the existing key that stands in
/// for it. Kept as one table so the ask to `i18n.rs` is this list, verbatim.
abstract final class QueueKeys {
  static const title = ('queue.title', 'incoming.title');
  static const bills = ('queue.bills', 'waiter.tickets');
  static const online = ('queue.online', 'delivery.title');
  static const kitchen = ('queue.kitchen', 'kds.title');
  static const accept = ('queue.accept', 'delivery.action.confirmed');
  static const decline = ('queue.decline', 'delivery.reject');
  static const declineReason = (
    'queue.decline_reason',
    'delivery.cancel_reason',
  );
  static const readyIn = ('queue.ready_in', 'delivery.prep_time');

  /// "Ready by 19:25" — the promise the shop made when it accepted.
  static const readyBy = ('queue.ready_by', 'delivery.prep_time');

  /// "Ready 19:19" — the fact, once the kitchen finished.
  static const readyAt = ('queue.ready_at', 'delivery.status.ready');
  static const chargeBill = ('queue.charge', 'waiter.settle');
  static const chargeOnline = ('queue.charge', 'delivery.finalize');
  static const pickedUp = (
    'queue.picked_up',
    'delivery.action.out_for_delivery',
  );
  static const emptyBills = ('queue.empty', 'waiter.no_tickets');
  static const emptyOnline = ('queue.empty', 'delivery.empty');
  static const offlineNotice = ('queue.offline_notice', 'chrome.offline');
  static const noTable = ('queue.no_table', 'waiter.ticket');
  static const accepted = ('queue.accepted', 'delivery.status.confirmed');
  static const declined = ('queue.declined', 'delivery.status.rejected');
  static const view = ('queue.view', 'chrome.view');
  static const needShift = ('queue.need_shift', 'waiter.need_shift');
  static const minutes = ('queue.minutes', 'delivery.prep_time');
}

extension QueueTr on MadarBridge {
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
