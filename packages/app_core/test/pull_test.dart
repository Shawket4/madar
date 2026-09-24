// A person's pull to refresh (pull.dart): the connection re-checked, then the
// core's manual sync, then the pill re-read; offline or refused is not an
// error. And the resume re-read: every board, at most once per 15 seconds.
import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

class _Bridge implements MadarBridge {
  final calls = <Symbol>[];

  /// When set, both network calls throw it (offline, refused).
  Object? fail;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #refreshConnectivity || name == #syncNow) {
      calls.add(name);
      final f = fail;
      if (f != null) return Future<Never>.error(f);
      return Future<Object?>.value(name == #refreshConnectivity ? true : null);
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  (ProviderContainer, _Bridge) mount() {
    final bridge = _Bridge();
    final c = ProviderContainer(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
    );
    addTearDown(c.dispose);
    return (c, bridge);
  }

  test(
    'a pull re-checks the connection, syncs, then pulses the pill',
    () async {
      final (c, bridge) = mount();
      final pulses = c.read(connectivityPulseProvider);
      await c.read(pullFromServerProvider)();
      expect(bridge.calls, [#refreshConnectivity, #syncNow]);
      expect(c.read(connectivityPulseProvider), pulses + 1);
    },
  );

  test('offline or refused: no error, the pill still re-reads', () async {
    final (c, bridge) = mount();
    bridge.fail = const MadarError.offline(detail: 'no network');
    await c.read(pullFromServerProvider)();
    expect(bridge.calls, [#refreshConnectivity, #syncNow]);
    expect(c.read(connectivityPulseProvider), 1);
  });

  test('the board tables bump every board tick but the catalogue', () {
    final ticks = ticksForTables(boardTables);
    expect(ticks, contains(drawerTickProvider));
    expect(ticks, contains(ticketTickProvider));
    expect(ticks, contains(kitchenTickProvider));
    expect(ticks, contains(deliveryTickProvider));
    expect(ticks, contains(floorTickProvider));
    expect(ticks, contains(bookingTickProvider));
    expect(ticks, contains(syncTickProvider));
    expect(ticks, isNot(contains(catalogTickProvider)));
  });

  test('a resume re-reads, but not within 15 s of the last one', () {
    var now = DateTime(2026, 9, 24, 10);
    var rereads = 0;
    final r = ResumeReread(reread: () => rereads++, clock: () => now);

    expect(r.resumed(), isTrue, reason: 'the first resume re-reads');
    expect(rereads, 1);

    now = now.add(const Duration(seconds: 14));
    expect(r.resumed(), isFalse, reason: 'a quick app switch');
    expect(rereads, 1);

    now = now.add(const Duration(seconds: 2));
    expect(r.resumed(), isTrue);
    expect(rereads, 2);
    expect(r.last, now);
  });
}
