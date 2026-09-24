// A till in the background closes its live stream so the server falls back
// to a push (SSE first, FCM only without a live stream), and reopens it when
// it comes back. Transient states keep the stream.
import 'package:app_core/app_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madar/app/boot.dart';

/// A [Ref] to hand `applyTableChanges`, as the realtime armer holds one.
final _ref = Provider<Ref>((ref) => ref);

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

  // Coming back also re-reads every board from the local rows (what the
  // server changed meanwhile lands by the core's catch-up pull when the
  // stream reconnects), at most once per 15 s so app switching is quiet.
  testWidgets('resume reopens the stream and re-reads the boards', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    var now = DateTime(2026, 9, 24, 10);
    var reopened = 0;
    final gate = BackgroundRealtimeGate(
      suspend: () {},
      resume: resumeWith(
        reopen: () => reopened++,
        reread: ResumeReread(
          reread: () => applyTableChanges(c.read(_ref), boardTables),
          clock: () => now,
        ),
      ),
    )..attach();
    addTearDown(gate.detach);
    void away() => [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ].forEach(t.binding.handleAppLifecycleStateChanged);
    int tick(NotifierProvider<TickNotifier, int> p) => c.read(p);

    away();
    expect(reopened, 1);
    expect(tick(ticketTickProvider), 1, reason: 'the bills re-read');
    expect(tick(drawerTickProvider), 1, reason: 'the till re-reads');
    expect(tick(deliveryTickProvider), 1, reason: 'online orders re-read');
    expect(tick(kitchenTickProvider), 1, reason: 'the kitchen re-reads');
    expect(tick(catalogTickProvider), 0, reason: 'the menu is left alone');

    now = now.add(const Duration(seconds: 10));
    away();
    expect(reopened, 2, reason: 'the stream always reopens');
    expect(tick(ticketTickProvider), 1, reason: 'a quick app switch');

    now = now.add(const Duration(seconds: 6));
    away();
    expect(tick(ticketTickProvider), 2);
  });
}
