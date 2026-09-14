import 'dart:async';

import 'package:app_core/src/table_changes.dart';

/// Keeps the core's `watchTables` stream attached for the app's life.
///
/// The stream is what makes every board re-read. If it errors or closes (an
/// FRB isolate restart, a core rebuilt after sign-in), the boards would
/// silently freeze — so this:
/// * resubscribes with a doubling backoff ([minBackoff] → [maxBackoff]), reset
///   by the first batch after a resubscribe;
/// * while detached, bumps every board ([CoreTables.all]) every [fallback], so
///   screens keep re-reading local data (the core's own fallback poll keeps
///   pulling from the server whatever the stream does).
///
/// No meaning is decided here: batches are passed through unchanged.
class TableChangeWatcher {
  TableChangeWatcher({
    required Stream<List<String>> Function() subscribe,
    required void Function(Iterable<String> tables) apply,
    this.minBackoff = const Duration(seconds: 1),
    this.maxBackoff = const Duration(seconds: 30),
    this.fallback = const Duration(seconds: 10),
  }) : _subscribe = subscribe,
       _apply = apply;

  final Stream<List<String>> Function() _subscribe;
  final void Function(Iterable<String> tables) _apply;
  final Duration minBackoff;
  final Duration maxBackoff;
  final Duration fallback;

  StreamSubscription<List<String>>? _sub;
  Timer? _retry;
  Timer? _fallbackTimer;
  Duration? _backoff;
  bool _disposed = false;

  /// Attached to the core's stream right now.
  bool get attached => _sub != null;

  /// Subscriptions opened so far (tests read it).
  int subscriptions = 0;

  /// Attach if not attached (idempotent).
  void start() {
    if (_disposed || _sub != null || _retry != null) return;
    _attach();
  }

  void _attach() {
    _retry = null;
    if (_disposed) return;
    try {
      subscriptions++;
      _sub = _subscribe().listen(
        (tables) {
          _backoff = null;
          _apply(tables);
        },
        onError: (Object _) => _detached(),
        onDone: _detached,
        cancelOnError: true,
      );
      _fallbackTimer?.cancel();
      _fallbackTimer = null;
    } on Object {
      _detached();
    }
  }

  void _detached() {
    unawaited(_sub?.cancel());
    _sub = null;
    if (_disposed) return;
    // Nothing tells the boards about changes now: re-read everything once,
    // then keep doing so until the stream is back.
    _apply(const [CoreTables.all]);
    _fallbackTimer ??= Timer.periodic(
      fallback,
      (_) => _apply(const [CoreTables.all]),
    );
    final next = _backoff == null
        ? minBackoff
        : Duration(
            milliseconds: (_backoff!.inMilliseconds * 2).clamp(
              minBackoff.inMilliseconds,
              maxBackoff.inMilliseconds,
            ),
          );
    _backoff = next;
    _retry?.cancel();
    _retry = Timer(next, _attach);
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _fallbackTimer?.cancel();
    unawaited(_sub?.cancel());
    _sub = null;
  }
}
