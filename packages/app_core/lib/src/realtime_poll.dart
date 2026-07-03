import 'dart:async';

import 'package:app_core/src/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A data-refresh poll that runs ONLY while realtime (SSE/LAN) is
/// **disconnected**.
///
/// When realtime is connected — the normal case — the event ticks already
/// drive reloads, so no polling is needed and the timer stays cancelled: a
/// fleet of connected devices makes ZERO periodic traffic. The moment realtime
/// drops, the poll starts as a fallback (one immediate reload, then every
/// `interval`); when it reconnects, the poll stops again.
///
/// Mix into a [ConsumerState] and call [realtimeGatedPoll] once from `build()`:
/// ```dart
/// class _S extends ConsumerState<W> with RealtimeGatedPoll<W> {
///   @override
///   Widget build(BuildContext context) {
///     realtimeGatedPoll(interval: _period, onPoll: () => unawaited(_reload()));
///     ...
///   }
/// }
/// ```
mixin RealtimeGatedPoll<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Timer? _gatedTimer;
  bool _gateSeeded = false;

  /// Wire the gate. Call every `build()` — it (re)subscribes to realtime
  /// connection changes and seeds the initial state once, off-frame.
  void realtimeGatedPoll({
    required Duration interval,
    required VoidCallback onPoll,
  }) {
    ref.listen(realtimeConnectedProvider, (_, connected) {
      _applyGate(connected: connected, interval: interval, onPoll: onPoll);
    });
    if (_gateSeeded) return;
    _gateSeeded = true;
    // A reload is a notifier write — defer the initial seed past the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyGate(
        connected: ref.read(realtimeConnectedProvider),
        interval: interval,
        onPoll: onPoll,
      );
    });
  }

  void _applyGate({
    required bool connected,
    required Duration interval,
    required VoidCallback onPoll,
  }) {
    if (connected) {
      _gatedTimer?.cancel();
      _gatedTimer = null;
    } else if (_gatedTimer == null) {
      // Just went offline (or first seed while offline) — reload now, then poll.
      onPoll();
      _gatedTimer = Timer.periodic(interval, (_) => onPoll());
    }
  }

  @override
  void dispose() {
    _gatedTimer?.cancel();
    super.dispose();
  }
}
