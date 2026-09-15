import 'dart:async';

/// Keeps the LAN relay started while someone is signed in.
///
/// `lanStart` can fail for reasons that clear on their own: no LAN secret yet
/// (the bundle arrives on the next online sign-in or sync), no network, a
/// socket the OS has not released. A single fire-and-forget call left the
/// device off the LAN until the next app restart, silently. This retries with
/// exponential backoff ([initialDelay] doubling up to [maxDelay]) until the
/// relay runs, and [kick] retries at once on a signal that the situation may
/// have changed (sign-in, network reconnect, app resume).
///
/// Sequencing only — the core decides whether the relay can start and why not
/// (`lanStatus().lastError`).
class LanRetrier {
  LanRetrier({
    required Future<void> Function() start,
    required bool Function() isRunning,
    required bool Function() signedIn,
    this.onStarted,
    this.initialDelay = const Duration(seconds: 5),
    this.maxDelay = const Duration(seconds: 60),
  }) : _start = start,
       _isRunning = isRunning,
       _signedIn = signedIn;

  final Future<void> Function() _start;
  final bool Function() _isRunning;
  final bool Function() _signedIn;

  /// Called after an attempt leaves the relay running.
  final void Function()? onStarted;
  final Duration initialDelay;
  final Duration maxDelay;

  Timer? _timer;
  bool _inFlight = false;
  bool _disposed = false;
  late Duration _delay = initialDelay;

  /// The wait before the next retry, when one is scheduled.
  Duration? get scheduledDelay =>
      _timer?.isActive ?? false ? _lastScheduled : null;
  Duration? _lastScheduled;

  /// Try now (unless an attempt is running). Cancels a pending backoff timer
  /// and resets the backoff: something changed, so start the ladder over.
  void kick() {
    if (_disposed) return;
    if (!_signedIn()) {
      stop();
      return;
    }
    _timer?.cancel();
    _delay = initialDelay;
    unawaited(_attempt());
  }

  /// Stop retrying (sign-out). The caller stops the relay itself.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _delay = initialDelay;
  }

  void dispose() {
    _disposed = true;
    stop();
  }

  Future<void> _attempt() async {
    if (_inFlight || _disposed) return;
    if (!_signedIn()) {
      stop();
      return;
    }
    if (_isRunning()) {
      stop();
      onStarted?.call();
      return;
    }
    _inFlight = true;
    try {
      await _start();
    } on Object {
      // The core recorded why; the status view shows it.
    } finally {
      _inFlight = false;
    }
    if (_disposed) return;
    if (!_signedIn()) {
      stop();
      return;
    }
    if (_isRunning()) {
      stop();
      onStarted?.call();
      return;
    }
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final wait = _lastScheduled = _delay;
    _timer = Timer(wait, () => unawaited(_attempt()));
    final doubled = _delay * 2;
    _delay = doubled > maxDelay ? maxDelay : doubled;
  }
}
