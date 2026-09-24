import 'dart:async';

import 'package:app_core/src/providers.dart';
import 'package:app_core/src/table_changes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A PERSON's pull to refresh on a board (the Queue, Orders, Bills, the
/// Till): the connection re-checked, the outbox sent and the server's
/// changes pulled — the core's manual sync, `POST /sync/pull` — so the
/// board's own re-read that follows answers from current local rows.
///
/// The network rule (CLAUDE.md) allows this because a person asked for it:
/// no tick, pulse, table change or timer may call it. Offline is not an
/// error: the pull does nothing, the board re-reads what the device holds,
/// and the top bar's pill (re-read by the pulse) says offline.
///
/// A provider so a test can count pulls without a core behind it.
final pullFromServerProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final bridge = ref.read(bridgeProvider);
    try {
      await bridge.refreshConnectivity();
    } on Object {
      // The sync below answers offline on its own.
    }
    try {
      await bridge.syncNow();
    } on Object {
      // Offline or refused: the board still re-reads what is here.
    }
    ref.read(connectivityPulseProvider.notifier).pulse();
  };
});

/// Pull (see [pullFromServerProvider]), then [reread] the board, both
/// awaited: a pull-to-refresh spinner holds until the board shows the answer.
Future<void> pullThenReread(
  WidgetRef ref,
  Future<void> Function() reread,
) async {
  await ref.read(pullFromServerProvider)();
  await reread();
}

/// The board ticks: bumping them makes every open board re-read its local
/// rows. The catalogue is left alone (the menu is not a board, and re-keying
/// it on a resume would redraw the whole Sell grid for nothing).
const List<String> boardTables = [
  CoreTables.tills,
  CoreTables.openTickets,
  CoreTables.kitchen,
  CoreTables.delivery,
  CoreTables.bookings,
  CoreTables.floor,
  CoreTables.sync,
];

/// Re-reads every board from local rows when the app comes back to the
/// front — at most once per [quiet], so flicking between apps is not a
/// re-read storm. Local only: what the server changed meanwhile arrives by
/// the core's own catch-up pull when the live stream reconnects.
class ResumeReread {
  ResumeReread({
    required this.reread,
    this.quiet = const Duration(seconds: 15),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Bumps the boards (the app: [applyTableChanges] with [boardTables]).
  final void Function() reread;

  /// A resume this soon after the last re-read skips its own.
  final Duration quiet;

  final DateTime Function() _clock;
  DateTime? _last;

  /// When the boards were last re-read by a resume.
  DateTime? get last => _last;

  /// The app came back to the front. True when it re-read.
  bool resumed() {
    final now = _clock();
    final last = _last;
    if (last != null && now.difference(last) < quiet) return false;
    _last = now;
    reread();
    return true;
  }
}
