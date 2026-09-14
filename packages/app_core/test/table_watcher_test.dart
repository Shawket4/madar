import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const short = Duration(milliseconds: 20);

  TableChangeWatcher watcher(
    List<StreamController<List<String>>> streams,
    List<List<String>> applied,
  ) {
    return TableChangeWatcher(
      subscribe: () {
        final c = StreamController<List<String>>();
        streams.add(c);
        return c.stream;
      },
      apply: (t) => applied.add(t.toList()),
      minBackoff: short,
      maxBackoff: const Duration(milliseconds: 80),
      fallback: const Duration(milliseconds: 30),
    );
  }

  test('batches pass through unchanged', () async {
    final streams = <StreamController<List<String>>>[];
    final applied = <List<String>>[];
    final w = watcher(streams, applied)
      ..start()
      ..start();
    expect(w.subscriptions, 1, reason: 'start is idempotent');
    streams.single.add(['orders', 'tills']);
    await Future<void>.delayed(Duration.zero);
    expect(applied, [
      ['orders', 'tills'],
    ]);
    w.dispose();
  });

  test(
    'an error re-reads every board, keeps them moving, and resubscribes',
    () async {
      final streams = <StreamController<List<String>>>[];
      final applied = <List<String>>[];
      final w = watcher(streams, applied)..start();
      streams.single.addError(StateError('isolate restarted'));
      await Future<void>.delayed(Duration.zero);
      expect(w.attached, isFalse);
      expect(applied.first, ['*'], reason: 'boards re-read at once');
      await Future<void>.delayed(const Duration(milliseconds: 45));
      expect(
        w.subscriptions,
        greaterThanOrEqualTo(2),
        reason: 'resubscribed after the backoff',
      );
      expect(w.attached, isTrue);
      streams.last.add(['kitchen']);
      await Future<void>.delayed(Duration.zero);
      expect(applied.last, ['kitchen']);
      w.dispose();
    },
  );

  test(
    'while the stream stays down the fallback keeps bumping, with a growing backoff',
    () async {
      final streams = <StreamController<List<String>>>[];
      final applied = <List<String>>[];
      final w = TableChangeWatcher(
        subscribe: () {
          streams.add(StreamController<List<String>>());
          // Every attempt fails at once.
          return Stream<List<String>>.error(StateError('down'));
        },
        apply: (t) => applied.add(t.toList()),
        minBackoff: short,
        maxBackoff: const Duration(milliseconds: 80),
        fallback: const Duration(milliseconds: 30),
      )..start();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final alls = applied
          .where((t) => t.length == 1 && t.single == '*')
          .length;
      expect(alls, greaterThanOrEqualTo(4), reason: 'boards never freeze');
      // 20, 40, 80, 80 ms... → fewer attempts than a fixed 20 ms retry would make.
      expect(w.subscriptions, lessThan(250 ~/ 20));
      expect(w.subscriptions, greaterThanOrEqualTo(3));
      w.dispose();
      final after = applied.length;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(applied.length, after, reason: 'dispose stops everything');
    },
  );

  test('a closed stream is a drop too', () async {
    final streams = <StreamController<List<String>>>[];
    final applied = <List<String>>[];
    final w = watcher(streams, applied)..start();
    await streams.single.close();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(w.subscriptions, 2);
    expect(applied.first, ['*']);
    w.dispose();
  });
}
