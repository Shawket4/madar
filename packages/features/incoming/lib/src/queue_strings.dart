/// Queue wording — every string the Queue shows, resolved through the core's
/// i18n and nothing else.
///
/// The redesign names things the core's table does not yet have a key for
/// ("Queue", "Accept", "Decline", "Ready in"). Those keys are requested in
/// `i18n.rs` (one pass by the master; see the lane's `needsFromOthers`).
/// Until they land, `tr` hands back the key itself, which is how a missing
/// key shows. So every new key is asked for FIRST and, when missing, the
/// nearest key that already exists is used in its place — never a literal.
/// The moment the key lands in the core the screen upgrades by itself.
library;

import 'package:rust_bridge/rust_bridge.dart';

/// The keys the Queue introduces, each with the existing key that stands in
/// for it. Kept as one table so the ask to `i18n.rs` is this list, verbatim.
abstract final class QueueKeys {
  static const title = ('queue.title', 'incoming.title');
  static const bills = ('queue.bills', 'waiter.tickets');
  static const online = ('queue.online', 'delivery.title');
  static const accept = ('queue.accept', 'delivery.action.confirmed');
  static const decline = ('queue.decline', 'delivery.reject');
  static const declineReason = (
    'queue.decline_reason',
    'delivery.cancel_reason',
  );
  static const readyIn = ('queue.ready_in', 'delivery.prep_time');
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
