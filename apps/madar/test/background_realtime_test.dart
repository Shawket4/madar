// A till in the background closes its live stream so the server falls back
// to a push (SSE first, FCM only without a live stream), and reopens it when
// it comes back. Transient states keep the stream.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madar/app/boot.dart';

void main() {
  testWidgets('background closes the stream, resume reopens it', (t) async {
    final log = <String>[];
    final gate = BackgroundRealtimeGate(
      suspend: () => log.add('suspend'),
      resume: () => log.add('resume'),
    )..attach();
    addTearDown(gate.detach);
    void go(List<AppLifecycleState> states) =>
        states.forEach(t.binding.handleAppLifecycleStateChanged);

    // A call banner or Control Center: the till is still in front.
    go([AppLifecycleState.inactive, AppLifecycleState.resumed]);
    expect(log, isEmpty);

    // Sent to the background: the stream closes once.
    go([
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    expect(log, ['suspend']);

    // Back in front: it reopens once.
    go([
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    expect(log, ['suspend', 'resume']);

    // A second resume without a background in between changes nothing.
    go([AppLifecycleState.inactive, AppLifecycleState.resumed]);
    expect(log, ['suspend', 'resume']);
  });
}
