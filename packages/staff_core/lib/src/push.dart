import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a tapped push opens (APP-6): a tab on the manager's side, a tab on
/// the person's own side, or — for anything else — the inbox.
typedef PushTarget = ({bool manage, String tab});

const PushTarget _inbox = (manage: false, tab: 'inbox');

/// The screen a notification's core i18n key belongs to. The server sends
/// the key in the push's `data`; this only picks the screen, it decides
/// nothing about what the push says.
PushTarget pushTarget(String? key) {
  final k = (key ?? '').replaceFirst('staff.n_', '');
  if (k.startsWith('flag_')) return (manage: true, tab: 'team');
  return switch (k) {
    // Waiting on a manager or the owner.
    'request' ||
    'swap_pending' ||
    'claim' ||
    'cover' ||
    'overtime' ||
    'adjustment_pending' => (manage: true, tab: 'approvals'),
    // My roster.
    'week_published' ||
    'shift_changed' ||
    'open_shift' ||
    'swap_asked' ||
    'swap_agreed' ||
    'swap_declined' ||
    'swap_approved' ||
    'swap_rejected' ||
    'claim_approved' ||
    'claim_rejected' ||
    'open_shift_cancelled' ||
    'swap_cancelled' ||
    'prefs_changed' => (manage: false, tab: 'shifts'),
    // The roster board: suggestion learning and the fairness audit (owners
    // and managers).
    'learning_frozen' ||
    'learning_resumed' ||
    'fairness_ready' ||
    'fairness_flagged' => (manage: true, tab: 'schedule'),
    // A colleague punched on the till with their PIN (CL-13).
    'till_punch_in' || 'till_punch_out' => (manage: true, tab: 'team'),
    'request_approved' ||
    'request_rejected' ||
    'request_cancelled' => (manage: false, tab: 'requests'),
    // My money.
    'advance_approved' ||
    'advance_rejected' ||
    'bonus_added' ||
    'deduction_added' ||
    'adjustment_approved' ||
    'adjustment_rejected' ||
    'paid' => (manage: false, tab: 'pay'),
    // My punches.
    'punched_for_you' ||
    'cover_confirmed' ||
    'cover_rejected' ||
    'overtime_approved' ||
    'overtime_rejected' => (manage: false, tab: 'timesheet'),
    'charge_phone' => (manage: false, tab: 'home'),
    _ => _inbox,
  };
}

/// The key of the push the person just tapped. The host sets it (boot's
/// Firebase listener, or the push that launched the app); the shell opens
/// the screen and clears it.
final openedPushProvider = Provider<ValueNotifier<String?>>((ref) {
  final n = ValueNotifier<String?>(null);
  ref.onDispose(n.dispose);
  return n;
});

/// A push that arrived while the app is open on Android, where the OS draws
/// nothing (iOS shows its own banner): the host sets it, and the shell shows
/// it as a toast whose action opens the push's screen.
typedef ForegroundPush = ({String text, String? key});

final foregroundPushProvider = Provider<ValueNotifier<ForegroundPush?>>((ref) {
  final n = ValueNotifier<ForegroundPush?>(null);
  ref.onDispose(n.dispose);
  return n;
});

/// One line from a push's title and body, as the toast shows it. The server
/// already wrote both in the phone's language.
String foregroundPushText(String? title, String? body) {
  final t = (title ?? '').trim();
  final b = (body ?? '').trim();
  if (t.isEmpty) return b;
  if (b.isEmpty) return t;
  return '$t · $b';
}
