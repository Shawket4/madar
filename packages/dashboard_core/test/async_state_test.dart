import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('skeleton through automatic retries, error only once they are spent, '
      'kept during a manual retry', () async {
    var calls = 0;
    final p = FutureProvider<int>((ref) async {
      calls++;
      throw StateError('down');
    });
    final c = ProviderContainer(
      retry: (count, _) => count < 1 ? const Duration(milliseconds: 1) : null,
    );
    addTearDown(c.dispose);
    final seen = <(bool, bool)>[];
    c.listen(
      p,
      (_, v) => seen.add((v.awaitingFirst, v.failedFirst)),
      fireImmediately: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls, 2);
    // Never an error while an automatic retry is pending.
    final firstError = seen.indexWhere((s) => s.$2);
    expect(seen.take(firstError).every((s) => s.$1), isTrue);
    expect(c.read(p).failedFirst, isTrue);
    // A manual retry keeps the error up.
    c.invalidate(p);
    final during = c.read(p);
    expect(during.isLoading, isTrue);
    expect(during.failedFirst, isTrue);
    expect(during.awaitingFirst, isFalse);
  });
}
