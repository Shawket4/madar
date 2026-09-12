/// Kitchen-board state — the Riverpod spine behind the kitchen display
/// board AND Queue's Kitchen segment, keyed by station (null = every
/// station, the expo board / the till's view).
///
/// The core is the single truth for what is bumped: `kdsList` overlays the
/// still-queued bumps from the outbox onto the server feed, so two readers
/// of the same core can never disagree about a line. What they CAN do is
/// go stale against each other — the board bumps a line and the Queue
/// segment keeps showing it open until its next tick. [kdsRevisionProvider]
/// closes that gap: every mutation bumps it and every live family member
/// reloads, whichever screen made the change.
///
/// Bump and unbump are outbox-first in the core (queued through a blip,
/// drained when it can), so a tap that cannot reach the server is QUEUED,
/// not failed — the board says so in its pill. A tap the server refused
/// lands as a dead outbox row; the board reads those back and offers Retry.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Family TYPE annotations moved to the misc library in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The outbox op types a kitchen tap writes (the core's `enqueue_bump`).
const Set<String> kKitchenOpTypes = {'bump_kitchen', 'unbump_kitchen'};

/// Bumped after every bump / unbump / retry / discard, from whichever
/// screen made it. Every [KdsNotifier] listens and reloads, so the board and
/// Queue's Kitchen segment show the same lines at the same moment.
final NotifierProvider<TickNotifier, int> kdsRevisionProvider =
    NotifierProvider<TickNotifier, int>(TickNotifier.new);

/// copyWith sentinel — lets callers CLEAR the nullable `toast` by passing an
/// explicit `null`.
const Object _unset = Object();

/// Immutable board state: outstanding tickets, the station directory, what
/// is in flight, and the honest picture of the kitchen's outbox.
class KdsState {
  const KdsState({
    this.tickets = const [],
    this.stations = const [],
    this.loaded = false,
    this.busyLineIds = const {},
    this.bumpingAllIds = const {},
    this.queuedBumps = 0,
    this.deadBumps = const [],
    this.online = true,
    this.clockSkewMinutes = 0,
    this.toast,
  });

  /// Outstanding tickets for the bound station (or every station), in the
  /// core's order: oldest first, ready tickets last.
  final List<KdsTicketView> tickets;

  /// The branch's kitchen stations — resolves the header's station name.
  final List<KdsStationView> stations;

  /// The first fetch has landed. Before it the board shows nothing rather
  /// than a false "all caught up".
  final bool loaded;

  /// Lines with a bump / unbump in flight — the row shows a spinner instead
  /// of its check and ignores a second tap.
  final Set<String> busyLineIds;

  /// Tickets whose Bump all is running — the button spins.
  final Set<String> bumpingAllIds;

  /// Kitchen taps still waiting in the outbox (`pending` | `inflight`).
  final int queuedBumps;

  /// Kitchen taps the server refused (`dead`) — Retry or Discard.
  final List<OutboxItemView> deadBumps;

  /// The core's view of reachability, from `syncStatus()`.
  final bool online;

  /// Server-minus-device clock skew, so a ticket's age is the SERVER's age.
  final int clockSkewMinutes;

  /// The board's floating toast, sequence-keyed.
  final ToastData? toast;

  /// The bound station's display name, or null when unknown (the header
  /// falls back to the localized board title).
  String? stationName(String? stationId) {
    if (stationId == null) return null;
    for (final station in stations) {
      if (station.id == stationId) return station.name;
    }
    return null;
  }

  /// Tickets with cooking still to do — the header's count.
  int get openCount =>
      tickets.where((t) => t.items.any((l) => !l.bumped)).length;

  /// The pill's state, from the kitchen's own outbox rows plus the core's
  /// reachability. Refused work outranks everything: it needs a person.
  OutboxState get outboxState {
    if (deadBumps.isNotEmpty) return OutboxState.stuck;
    if (!online) return OutboxState.offline;
    if (queuedBumps > 0) return OutboxState.queued;
    return OutboxState.synced;
  }

  /// The count the pill shows beside its word.
  int get outboxCount => deadBumps.isNotEmpty ? deadBumps.length : queuedBumps;

  /// Minutes a ticket has waited, by the server's clock, clamped at 0 (a
  /// malformed stamp reads as fresh, never stale).
  int ageMinutes(KdsTicketView ticket, DateTime now) {
    final then = DateTime.tryParse(ticket.createdAt);
    if (then == null) return 0;
    final serverNow = now.toUtc().add(Duration(minutes: clockSkewMinutes));
    final minutes = serverNow.difference(then.toUtc()).inMinutes;
    return minutes < 0 ? 0 : minutes;
  }

  /// Copy with the given fields replaced; `toast` clears on an explicit
  /// `null`.
  KdsState copyWith({
    List<KdsTicketView>? tickets,
    List<KdsStationView>? stations,
    bool? loaded,
    Set<String>? busyLineIds,
    Set<String>? bumpingAllIds,
    int? queuedBumps,
    List<OutboxItemView>? deadBumps,
    bool? online,
    int? clockSkewMinutes,
    Object? toast = _unset,
  }) {
    return KdsState(
      tickets: tickets ?? this.tickets,
      stations: stations ?? this.stations,
      loaded: loaded ?? this.loaded,
      busyLineIds: busyLineIds ?? this.busyLineIds,
      bumpingAllIds: bumpingAllIds ?? this.bumpingAllIds,
      queuedBumps: queuedBumps ?? this.queuedBumps,
      deadBumps: deadBumps ?? this.deadBumps,
      online: online ?? this.online,
      clockSkewMinutes: clockSkewMinutes ?? this.clockSkewMinutes,
      toast: identical(toast, _unset) ? this.toast : toast as ToastData?,
    );
  }
}

/// The board controller, one per station id (the family arg).
class KdsNotifier extends Notifier<KdsState> {
  /// Creates the notifier for one family [arg].
  KdsNotifier(this.arg);

  /// The bound station id (null = every station).
  final String? arg;

  int _toastSeq = 0;

  MadarBridge get _bridge => ref.read(bridgeProvider);

  @override
  KdsState build() {
    // Whichever screen changed the kitchen, this member re-reads the core.
    ref.listen(kdsRevisionProvider, (_, _) => unawaited(load()));
    // Every `kitchen.*` realtime event the shell surfaces.
    ref.listen(kitchenTickProvider, (_, _) => unawaited(load()));
    // Reachability changed under us — the pill must follow.
    ref.listen(connectivityPulseProvider, (_, _) => unawaited(loadOutbox()));
    return const KdsState();
  }

  /// Fetch the board. A failed fetch keeps the last good board on screen
  /// (a blip never blanks a busy kitchen); the core itself falls back to its
  /// cache, so this mostly guards a lost session.
  Future<void> load() async {
    try {
      final tickets = await _bridge.kdsList(stationId: arg);
      state = state.copyWith(
        tickets: tickets,
        loaded: true,
        clockSkewMinutes: _skew(),
      );
    } on MadarError catch (e) {
      ref.read(connectivityRefreshProvider.notifier).reportError(e);
    } on Object {
      // Keep the previous tickets.
    }
    await loadOutbox();
  }

  /// Fetch the station directory (names the header).
  Future<void> loadStations() async {
    try {
      final stations = await _bridge.kdsListStations();
      state = state.copyWith(stations: stations);
    } on Object {
      // Keep the previous directory.
    }
  }

  /// Re-read the kitchen's slice of the outbox and the core's reachability.
  /// Both are cheap local reads that always succeed offline.
  Future<void> loadOutbox() async {
    try {
      final status = await _bridge.syncStatus();
      final rows = await _bridge.listOutbox();
      final kitchen = rows.where((r) => kKitchenOpTypes.contains(r.opType));
      state = state.copyWith(
        online: status.online,
        queuedBumps: kitchen.where((r) => r.status != 'dead').length,
        deadBumps: kitchen.where((r) => r.status == 'dead').toList(),
      );
    } on Object {
      // Keep the previous picture.
    }
  }

  /// Tap a line: bump ⇄ recall.
  Future<void> toggleLine(KdsLineView line) =>
      setBumped(line, bumped: !line.bumped);

  /// Bump or recall one line. A second tap while the first is in flight is
  /// ignored rather than queued twice. A failure is SAID — the board's old
  /// silence is how thousands of tickets sat firing forever.
  Future<void> setBumped(KdsLineView line, {required bool bumped}) async {
    if (state.busyLineIds.contains(line.id)) return;
    _setBusy(line.id, busy: true);
    try {
      if (bumped) {
        await _bridge.kdsBump(itemId: line.id);
      } else {
        await _bridge.kdsUnbump(itemId: line.id);
      }
    } on MadarError catch (e) {
      _fail(e);
    } finally {
      _setBusy(line.id, busy: false);
      _changed();
    }
  }

  /// Bump every open line on a ticket, in order, one outbox op each (there
  /// is no ticket-level op on the wire). Stops at the first refusal and says
  /// so; the lines before it stay bumped, the ones after stay open, and the
  /// reload shows exactly that.
  Future<void> bumpAll(KdsTicketView ticket) async {
    if (state.bumpingAllIds.contains(ticket.id)) return;
    final open = ticket.items.where((l) => !l.bumped).toList();
    if (open.isEmpty) return;
    state = state.copyWith(bumpingAllIds: {...state.bumpingAllIds, ticket.id});
    try {
      for (final line in open) {
        // A line already mid-tap has its own op in flight.
        if (state.busyLineIds.contains(line.id)) continue;
        await _bridge.kdsBump(itemId: line.id);
      }
    } on MadarError catch (e) {
      _fail(e);
    } finally {
      state = state.copyWith(
        bumpingAllIds: {...state.bumpingAllIds}..remove(ticket.id),
      );
      _changed();
    }
  }

  /// Requeue every dead command and try to send now. The bridge's retry is
  /// all-or-nothing across the outbox, so this is one button, not one per
  /// row.
  Future<void> retryRefused() async {
    try {
      await _bridge.retryOutbox();
    } on MadarError catch (e) {
      _fail(e);
    } finally {
      _changed();
    }
  }

  /// Give up on the refused kitchen taps (the server will not take them —
  /// a voided ticket, a line that no longer exists). Only the kitchen's
  /// rows; a dead sale is the Sync screen's business.
  Future<void> discardRefused() async {
    try {
      for (final row in state.deadBumps) {
        await _bridge.discardOutboxItem(id: row.id);
      }
    } on MadarError catch (e) {
      _fail(e);
    } finally {
      _changed();
    }
  }

  /// Show a floating toast. A new id restarts the auto-dismiss timer.
  void showToast(
    String text, {
    ChipTone tone = ChipTone.neutral,
    String? icon,
  }) {
    state = state.copyWith(
      toast: ToastData(id: ++_toastSeq, text: text, tone: tone, icon: icon),
    );
  }

  /// Clear the toast once its timer elapses (ignores a stale id).
  void dismissToast(int id) {
    if (state.toast?.id == id) state = state.copyWith(toast: null);
  }

  void _setBusy(String lineId, {required bool busy}) {
    final next = {...state.busyLineIds};
    if (busy) {
      next.add(lineId);
    } else {
      next.remove(lineId);
    }
    state = state.copyWith(busyLineIds: next);
  }

  /// Every member of the family re-reads the core — see the library doc.
  void _changed() => ref.read(kdsRevisionProvider.notifier).bump();

  void _fail(MadarError e) {
    if (e is MadarError_Unauthenticated && _bridge.currentSession() != null) {
      ref.read(reauthRequestProvider.notifier).request();
    }
    ref.read(connectivityRefreshProvider.notifier).reportError(e);
    showToast(
      _bridge.humanMessage(e),
      tone: ChipTone.danger,
      icon: 'xmark.circle',
    );
  }

  int _skew() {
    try {
      return _bridge.clockSkewMinutes();
    } on Object {
      return 0;
    }
  }
}

/// The kitchen board's state provider, keyed by station id (null = every
/// station). Queue's Kitchen segment reads `kdsProvider(null)`; the board
/// reads its bound station. Both reload on every change either makes.
final NotifierProviderFamily<KdsNotifier, KdsState, String?> kdsProvider =
    NotifierProvider.family<KdsNotifier, KdsState, String?>(KdsNotifier.new);
