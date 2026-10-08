// sse.test.ts and use-branch-realtime.test.ts translated, plus the
// connection loop (backoff, resume, resync) and the provider wiring.
import 'dart:async';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/mock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSseFrames (sse.test.ts)', () {
    test('returns complete frames and carries the partial tail', () {
      final r = parseSseFrames(
        'id: 7\nevent: booking.created\ndata: {"id":1}\n\nevent: table.status_changed\ndata: {"t',
      );
      expect(r.frames, hasLength(1));
      expect(r.frames.single.id, '7');
      expect(r.frames.single.event, 'booking.created');
      expect(r.frames.single.data, '{"id":1}');
      expect(r.rest, 'event: table.status_changed\ndata: {"t');
    });

    test('skips keep-alive comments and tolerates CRLF', () {
      final r = parseSseFrames(
        ': ping\r\n\r\nevent: resync\r\ndata: {"reason":"gap"}\r\n\r\n',
      );
      expect(r.frames, hasLength(1));
      expect(r.frames.single.id, isNull);
      expect(r.frames.single.event, 'resync');
      expect(r.frames.single.data, '{"reason":"gap"}');
      expect(r.rest, '');
    });

    test('joins multi-line data and defaults the event name', () {
      final r = parseSseFrames('data: a\ndata: b\n\n');
      expect(r.frames.single.event, 'message');
      expect(r.frames.single.data, 'a\nb');
    });
  });

  group('invalidationsFor (use-branch-realtime.test.ts)', () {
    test('booking events reach the bookings list AND the floor', () {
      expect(invalidationsFor('booking.created'), ['/bookings', '/floor']);
      expect(invalidationsFor('booking.arriving'), ['/bookings', '/floor']);
    });
    test('floor events stay on the floor and tickets reach both', () {
      expect(invalidationsFor('table.status_changed'), ['/floor']);
      expect(invalidationsFor('ticket.fired'), ['/open-tickets', '/floor']);
      expect(invalidationsFor('ticket.table_changed'), [
        '/floor',
        '/open-tickets',
      ]);
    });
    test('a resync is everything; the unknown is nothing', () {
      expect(invalidationsFor('resync'), ['/']);
      expect(invalidationsFor('something.else'), isEmpty);
    });
    test('the rest of the table', () {
      expect(invalidationsFor('delivery.created'), ['/delivery-orders']);
      expect(invalidationsFor('kitchen.bumped'), ['/kitchen']);
      expect(invalidationsFor('till.closed'), ['/tills', '/reports']);
      expect(invalidationsFor('payment_methods.availability_changed'), [
        '/payment-methods',
      ]);
      expect(invalidationsFor('branch.settings_changed'), ['/branches']);
      expect(invalidationsFor('transfer.requested'), ['/floor']);
      expect(realtimeTopics, 'floor,tickets,bookings,delivery,tills');
    });
  });

  group('the connection loop', () {
    testWidgets('backs off 1, 2, 5, 10, 30 s; resets once a stream opens', (
      tester,
    ) async {
      final gw = MockRealtimeGateway()..refuse(6);
      final bus = RealtimeBus();
      final rt = BranchRealtime(gateway: gw, branchId: 'b1', bus: bus)..start();
      await tester.pump();
      expect(rt.attempt, 1);
      for (final (wait, attempt) in [
        (1, 2),
        (2, 3),
        (5, 4),
        (10, 5),
        (30, 6),
      ]) {
        await tester.pump(
          Duration(seconds: wait) - const Duration(milliseconds: 1),
        );
        expect(rt.attempt, attempt - 1, reason: 'not before $wait s');
        await tester.pump(const Duration(milliseconds: 1));
        expect(rt.attempt, attempt);
      }
      // Still capped at 30 s.
      await tester.pump(const Duration(seconds: 30));
      expect(gw.connections, hasLength(1));
      expect(rt.attempt, 0);
      expect(gw.current!.branchId, 'b1');
      expect(gw.current!.topics, realtimeTopics);
      rt.stop();
      // Closing a stream controller completes on a microtask the fake clock
      // only runs on a pump: never await it inside testWidgets.
      unawaited(bus.dispose());
      await tester.pump();
    });

    testWidgets('resumes from the last id; events reach the bus', (
      tester,
    ) async {
      final gw = MockRealtimeGateway();
      final bus = RealtimeBus();
      final seen = <RealtimeFrame>[];
      final stale = <List<String>>[];
      final s1 = bus.events.listen(seen.add);
      final s2 = bus.invalidations.listen(stale.add);
      final rt = BranchRealtime(gateway: gw, branchId: 'b1', bus: bus)..start();
      await tester.pump();
      gw.current!.emit('booking.created', data: '{"id":1}', id: '41');
      gw.current!.emit('ping.unknown');
      gw.current!.emit('table.status_changed', id: '42');
      await tester.pump();
      expect(seen.map((f) => f.event), [
        'booking.created',
        'ping.unknown',
        'table.status_changed',
      ]);
      expect(stale, [
        ['/bookings', '/floor'],
        ['/floor'],
      ]);
      expect(rt.lastEventId, '42');
      gw.current!.drop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(gw.connections, hasLength(2));
      expect(gw.current!.lastEventId, '42');
      // The server closing the stream also reconnects.
      unawaited(gw.current!.close());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(gw.connections, hasLength(3));
      gw.current!.emit('resync', data: '{"reason":"gap"}');
      await tester.pump();
      expect(stale.last, ['/']);
      rt.stop();
      expect(gw.current!.hasListener, isFalse);
      await tester.pump(const Duration(minutes: 1));
      expect(gw.connections, hasLength(3), reason: 'stopped: no reconnect');
      unawaited(s1.cancel());
      unawaited(s2.cancel());
      unawaited(bus.dispose());
      await tester.pump();
    });
  });

  group('providers', () {
    test('epochs bump for the paths an event makes stale', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final floor = <int>[];
      final bookings = <int>[];
      final tills = <int>[];
      c
        ..listen(
          realtimeEpochProvider('/floor/sections'),
          (_, n) => floor.add(n),
        )
        ..listen(realtimeEpochProvider('/bookings'), (_, n) => bookings.add(n))
        ..listen(
          realtimeEpochProvider('/tills/sessions'),
          (_, n) => tills.add(n),
        );
      final bus = c.read(realtimeBusProvider);
      bus.dispatch(const RealtimeFrame(event: 'table.status_changed'));
      expect(floor, [1]);
      expect(bookings, isEmpty);
      bus.dispatch(const RealtimeFrame(event: 'booking.created'));
      expect(floor, [1, 2]);
      expect(bookings, [1]);
      bus.dispatch(const RealtimeFrame(event: 'resync'));
      expect(floor, [1, 2, 3]);
      expect(bookings, [1, 2]);
      expect(tills, [1]);
      bus.invalidate(['/tills']);
      expect(tills, [1, 2]);
    });

    test(
      'one connection for the selected branch; none for all branches',
      () async {
        final db = MockDb.seeded();
        final server = MockServer(clock: db.clock);
        registerCoreMocks(server, db);
        final gw = MockSessionGateway(server, signedInAs: Persona.owner);
        final rtGw = MockRealtimeGateway();
        final c = ProviderContainer(
          overrides: [
            transportProvider.overrideWithValue(gw.transport),
            sessionGatewayProvider.overrideWithValue(gw),
            preferencesProvider.overrideWithValue(MemoryPreferences()),
            realtimeGatewayProvider.overrideWithValue(rtGw),
            initialLocaleProvider.overrideWithValue('en'),
          ],
        );
        addTearDown(c.dispose);
        c
          ..listen(branchRealtimeProvider, (_, _) {})
          ..listen(activeBranchesProvider, (_, _) {});
        await c.read(sessionProvider.future);
        await Future<void>.delayed(Duration.zero);
        expect(c.read(branchRealtimeProvider), isNull);
        await c.read(scopeProvider.notifier).setBranch(SeedIds.maadi);
        await Future<void>.delayed(Duration.zero);
        final first = c.read(branchRealtimeProvider)!;
        expect(first.branchId, SeedIds.maadi);
        expect(rtGw.connections.single.branchId, SeedIds.maadi);
        await c.read(scopeProvider.notifier).setBranch(SeedIds.zamalek);
        await Future<void>.delayed(Duration.zero);
        expect(first.isStopped, isTrue);
        expect(rtGw.connections.last.branchId, SeedIds.zamalek);
        expect(rtGw.connections.first.hasListener, isFalse);
      },
    );

    test(
      'TransportRealtimeGateway reads the mock server stream envelopes',
      () async {
        final db = MockDb.seeded();
        final server = MockServer(clock: db.clock);
        registerCoreMocks(server, db);
        final gw = TransportRealtimeGateway(server, acceptAfter: Duration.zero);
        final stream = await gw.connect(
          branchId: SeedIds.maadi,
          topics: realtimeTopics,
          lastEventId: '9',
        );
        final got = <RealtimeFrame>[];
        final sub = stream.listen(got.add);
        server.publish(
          realtimeChannel(SeedIds.maadi),
          TransportRealtimeGateway.encode(
            'booking.created',
            data: {'id': 1},
            id: '10',
          ),
        );
        server.publish(realtimeChannel(SeedIds.maadi), 'plain');
        await Future<void>.delayed(Duration.zero);
        expect(got.first.event, 'booking.created');
        expect(got.first.data, '{"id":1}');
        expect(got.first.id, '10');
        expect(got.last.event, 'message');
        expect(got.last.data, 'plain');
        final call = server.callsTo('/realtime/stream').single;
        expect(call.query['branch_id'], [SeedIds.maadi]);
        expect(call.headers['Last-Event-ID'], '9');
        await sub.cancel();
        await server.close();
      },
    );

    test(
      'TransportRealtimeGateway fails connect when the stream is refused',
      () async {
        final db = MockDb.seeded();
        final server = MockServer(persona: Persona.manager, clock: db.clock);
        registerCoreMocks(server, db);
        final gw = TransportRealtimeGateway(server);
        // The manager is not assigned to Maadi: the handler refuses.
        await expectLater(
          gw.connect(branchId: SeedIds.maadi, topics: realtimeTopics),
          throwsA(anything),
        );
        final ok = await gw.connect(
          branchId: SeedIds.zamalek,
          topics: realtimeTopics,
        );
        final sub = ok.listen((_) {});
        await sub.cancel();
        await server.close();
      },
    );

    test('a frame decodes from an envelope or arrives as a message', () {
      final f = TransportRealtimeGateway.decode(
        '{"event":"till.closed","id":"3","data":"x"}',
      );
      expect((f.event, f.data, f.id), ('till.closed', 'x', '3'));
      expect(
        TransportRealtimeGateway.decode('{"no":"event"}').event,
        'message',
      );
      expect(TransportRealtimeGateway.decode('').event, 'message');
    });
  });
}
