/// Sync-center state — the Riverpod spine behind the sync screen: the durable
/// outbox rows plus the manual-push busy flag. Every drain/retry/discard
/// refreshes the shell so its sync chrome (chip counts) re-reads.
library;

import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Immutable sync-center state.
class SyncState {
  const SyncState({this.outbox = const [], this.pushing = false});

  /// The durable outbox: queued / in-flight / failed commands.
  final List<OutboxItemView> outbox;

  /// A manual force-push is in flight (spins + disables the pill).
  final bool pushing;

  /// Whether any command is dead (shows the Retry action).
  bool get hasFailed => outbox.any((item) => item.status == 'dead');

  /// Copy with the given fields replaced.
  SyncState copyWith({List<OutboxItemView>? outbox, bool? pushing}) {
    return SyncState(
      outbox: outbox ?? this.outbox,
      pushing: pushing ?? this.pushing,
    );
  }
}

/// The sync-center controller: load / retry / force-push / discard.
class SyncNotifier extends Notifier<SyncState> {
  MadarBridge get _bridge => ref.read(bridgeProvider);

  @override
  SyncState build() => const SyncState();

  /// Swallow bridge failures on best-effort calls (the natives'
  /// `runCatching`) — the inspector must render offline.
  Future<T?> _quiet<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on Exception {
      return null;
    }
  }

  /// Re-read the outbox rows.
  Future<void> load() async {
    final outbox = await _quiet(_bridge.listOutbox) ?? const <OutboxItemView>[];
    state = state.copyWith(outbox: outbox);
  }

  /// Requeue every FAILED (dead) command and try to send now.
  Future<void> retry() async {
    await _quiet(_bridge.retryOutbox);
    await load();
    ref.read(shellProvider.notifier).refresh();
  }

  /// Manual PUSH of the durable outbox — force-drains every QUEUED (not
  /// just failed) command. Pings first so a queue parked offline re-probes
  /// connectivity + the auth-park, then drains (the natives' `syncNow`).
  /// Concurrent taps ignored.
  Future<void> syncNow() async {
    if (state.pushing) return;
    state = state.copyWith(pushing: true);
    try {
      await _quiet(_bridge.refreshConnectivity);
      await _quiet(_bridge.syncNow);
    } finally {
      state = state.copyWith(pushing: false);
    }
    await load();
    ref.read(shellProvider.notifier).refresh();
  }

  /// Discard a single DEAD command (the teller gives up on it).
  Future<void> discard(String id) async {
    await _quiet(() => _bridge.discardOutboxItem(id: id));
    await load();
    ref.read(shellProvider.notifier).refresh();
  }
}

/// The sync center's state provider.
final syncProvider = NotifierProvider<SyncNotifier, SyncState>(
  SyncNotifier.new,
);
