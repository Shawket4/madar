/// Sync state — the Riverpod spine behind the Sync section (the full Sync
/// screen, the section inside Settings, and the waiter's Me tab all render
/// the same [SyncState]): the durable outbox rows, the one-shot health
/// snapshot (`syncStatus`), whether a drawer is open (the stranded-sales
/// recovery needs one), and the busy flags of the two manual pushes. Every
/// drain / retry / discard / recover refreshes the shell so its chrome (the
/// outbox pill) re-reads.
library;

import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Immutable sync state.
class SyncState {
  const SyncState({
    this.outbox = const [],
    this.status,
    this.hasOpenTill = false,
    this.pushing = false,
    this.recovering = false,
    this.recovered,
  });

  /// The durable outbox: queued / in-flight / failed commands, oldest first.
  final List<OutboxItemView> outbox;

  /// Health counts + online / auth-paused, as the core last reported them.
  /// Null until the first load.
  final SyncStatusView? status;

  /// A drawer is open on this till. `recoverOrphanedOrders` re-points
  /// stranded sales onto the CURRENT till, so without one it has nowhere to
  /// put them.
  final bool hasOpenTill;

  /// A manual force-push is in flight (spins + disables Sync now).
  final bool pushing;

  /// A stranded-sales recovery is in flight.
  final bool recovering;

  /// How many rows the last recovery re-pointed; null until one has run.
  /// Shown once so the teller sees the tap did something.
  final int? recovered;

  /// Rows the server has refused — dead until someone retries or discards.
  List<OutboxItemView> get stuck =>
      outbox.where((item) => item.status == 'dead').toList(growable: false);

  /// Rows still on their way: queued or mid-send.
  List<OutboxItemView> get waiting =>
      outbox.where((item) => item.status != 'dead').toList(growable: false);

  /// Whether any command is dead (shows Retry all).
  bool get hasFailed => stuck.isNotEmpty;

  /// Sales stranded behind a dead `open_till` — the count the rows
  /// themselves cannot show, so it gets its own section.
  int get blocked => status?.blocked ?? 0;

  /// Nothing queued, nothing stuck, nothing stranded.
  bool get isClear => outbox.isEmpty && blocked == 0;

  /// Copy with the given fields replaced. `null` keeps the current value;
  /// [recovered] is replaced whole so a fresh load can clear it.
  SyncState copyWith({
    List<OutboxItemView>? outbox,
    SyncStatusView? status,
    bool? hasOpenTill,
    bool? pushing,
    bool? recovering,
    int? recovered,
    bool clearRecovered = false,
  }) {
    return SyncState(
      outbox: outbox ?? this.outbox,
      status: status ?? this.status,
      hasOpenTill: hasOpenTill ?? this.hasOpenTill,
      pushing: pushing ?? this.pushing,
      recovering: recovering ?? this.recovering,
      recovered: clearRecovered ? null : (recovered ?? this.recovered),
    );
  }
}

/// The sync controller: load / retry / force-push / discard / recover.
class SyncNotifier extends Notifier<SyncState> {
  MadarBridge get _bridge => ref.read(bridgeProvider);

  @override
  SyncState build() => const SyncState();

  /// Swallow bridge failures on best-effort calls (the natives'
  /// `runCatching`) — the inspector must render offline. A transport-class
  /// failure nudges the connectivity service (one debounced probe).
  Future<T?> _quiet<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on Exception catch (e) {
      ref.read(connectivityRefreshProvider.notifier).reportError(e);
      return null;
    }
  }

  /// Re-read the outbox rows, the health snapshot and the till.
  Future<void> load() async {
    final outbox = await _quiet(_bridge.listOutbox) ?? const <OutboxItemView>[];
    final status = await _quiet(() async => _bridge.syncStatus());
    final till = await _quiet(_bridge.currentTill);
    state = state.copyWith(
      outbox: outbox,
      status: status,
      hasOpenTill: till?.isOpen ?? false,
    );
  }

  /// Requeue every FAILED (dead) command and try to send now. The core's
  /// retry is all-or-nothing — there is no per-row retry on the bridge — so
  /// the section offers one "Retry all".
  Future<void> retryAll() async {
    await _quiet(_bridge.retryOutbox);
    await load();
    ref.read(shellProvider.notifier).refresh();
  }

  /// Manual PUSH of the durable outbox — force-drains every QUEUED (not
  /// just failed) command, then pulls the catalogue. Pings first so a queue
  /// parked offline re-probes connectivity + the auth-park, then drains (the
  /// natives' `syncNow`). "Sync now" is also the catalogue refresh: the
  /// separate sync-menu button is gone. Concurrent taps ignored.
  Future<void> syncNow() async {
    if (state.pushing) return;
    state = state.copyWith(pushing: true, clearRecovered: true);
    try {
      await _quiet(_bridge.refreshConnectivity);
      await _quiet(_bridge.syncNow);
      await _quiet(_bridge.refreshCatalog);
    } finally {
      state = state.copyWith(pushing: false);
    }
    await load();
    ref.read(shellProvider.notifier).refresh();
    ref.read(catalogTickProvider.notifier).bump();
  }

  /// Download everything again (long-press on Sync, a manager's act after a
  /// confirm). The core replaces what the server holds and keeps every row
  /// with an unsent change, so nothing waiting to send is lost.
  Future<void> syncFull() async {
    if (state.pushing) return;
    state = state.copyWith(pushing: true, clearRecovered: true);
    try {
      await _quiet(_bridge.refreshConnectivity);
      await _quiet(_bridge.syncFull);
    } finally {
      state = state.copyWith(pushing: false);
    }
    await load();
    ref.read(shellProvider.notifier).refresh();
    ref.read(catalogTickProvider.notifier).bump();
  }

  /// Discard a single DEAD command (the teller gives up on it). The
  /// section confirms first — a discarded row is work that never reaches
  /// the server.
  Future<void> discard(String id) async {
    await _quiet(() => _bridge.discardOutboxItem(id: id));
    await load();
    ref.read(shellProvider.notifier).refresh();
  }

  /// Retry the sales held behind a dead `open_till`. Tills are named by
  /// the id this device minted, so nothing needs re-pointing: the till's
  /// dead commands are sent again, in order. Needs this person's till.
  Future<void> recover() async {
    if (state.recovering) return;
    state = state.copyWith(recovering: true, clearRecovered: true);
    int? count;
    try {
      final till = await _quiet(_bridge.currentTill);
      if (till != null) {
        count = await _quiet(() => _bridge.retryTillOutbox(tillId: till.id));
      }
    } finally {
      state = state.copyWith(recovering: false, recovered: count ?? 0);
    }
    await load();
    ref.read(shellProvider.notifier).refresh();
  }
}

/// The sync section's state provider.
final syncProvider = NotifierProvider<SyncNotifier, SyncState>(
  SyncNotifier.new,
);
