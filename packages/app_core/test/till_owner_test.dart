// The shell is the ONE owner of "which till is open here" (owner report
// 2026-09-25: after a (re)configure → open till, the cart went on saying "No
// till is open" because it held a copy loaded before the till opened). These
// pin the owner itself: it reads the till in the same pass as the route and
// the lock, follows the core without any screen asking, reconciles through
// one door, and never guesses when the core cannot answer.

import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _session = SessionSnapshot(
  userId: 'u-1',
  displayName: 'Sara',
  role: 'teller',
  currencyCode: 'EGP',
  taxRate: 0.14,
  taxInclusive: true,
  serviceChargeRate: 0,
  serviceChargeTaxable: false,
  requireTableForOrders: false,
  online: true,
  permissionsLoaded: true,
);

TillView _till(String id) => TillView(
  id: id,
  branchId: 'b-1',
  tellerId: 'u-1',
  tellerName: 'Sara',
  openingCashMinor: 50000,
  openedAt: '2026-09-25T08:00:00Z',
  status: 'open',
  isOpen: true,
  verification: 'server',
  openedWhileAnotherOpen: false,
);

/// The core in miniature: one till slot that `own_open_till`, `app_route`
/// and `till_lock` all decide from — as the real core does.
class _Core implements MadarBridge {
  TillView? till;

  /// What the next `refresh_till` reconcile adopts (or drops, when null).
  TillView? Function()? reconcileTo;

  /// The core cannot answer the till (a store hiccup).
  bool tillFails = false;

  int refreshTillCalls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #currentSession) return _session;
    if (name == #appRoute) {
      return till == null ? const AppRoute.openTill() : const AppRoute.order();
    }
    if (name == #tillLock) {
      return TillLockView(
        locked: till == null,
        reason: till == null ? 'no_till' : '',
        title: '',
        body: '',
        canOpen: till == null,
        holdsDrawer: true,
      );
    }
    if (name == #ownOpenTill) {
      if (tillFails) throw const MadarError.internal(detail: 'store');
      return till;
    }
    if (name == #refreshTill) {
      refreshTillCalls += 1;
      final to = reconcileTo;
      if (to != null) till = to();
      return Future<TillView?>.value(till);
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  late _Core core;
  late ProviderContainer container;
  late int arms;

  setUp(() {
    core = _Core();
    arms = 0;
    container = ProviderContainer(
      overrides: [
        bridgeProvider.overrideWithValue(core),
        realtimeArmerProvider.overrideWithValue(() => arms += 1),
      ],
    );
    addTearDown(container.dispose);
  });

  test('the till is read in the same pass as the route and the lock', () {
    core.till = _till('t-1');
    final s = container.read(shellProvider);
    expect(s.till?.id, 't-1');
    expect(s.tillOpen, isTrue);
    expect(s.route, const AppRoute.order());
    expect(s.locked, isFalse);
  });

  test('an open reaches the owner on the refresh every open already makes, '
      'and every reader of it at once', () {
    final seen = <String?>[];
    container.listen(
      shellProvider.select((s) => s.till?.id),
      (_, id) => seen.add(id),
    );
    expect(container.read(shellProvider).tillOpen, isFalse);
    expect(container.read(shellProvider).locked, isTrue);

    core.till = _till('t-1');
    container.read(shellProvider.notifier).refresh();

    expect(seen, ['t-1']);
    final s = container.read(shellProvider);
    expect(s.route, const AppRoute.order(), reason: 'route agrees');
    expect(s.locked, isFalse, reason: 'lock agrees');
    expect(arms, 1, reason: 'a refresh still arms realtime');
  });

  test('a close that lands in the core (a pull, a force-close) reaches the '
      'owner on the drawer tick — no screen, no refresh call', () {
    core.till = _till('t-1');
    expect(container.read(shellProvider).tillOpen, isTrue);

    core.till = null;
    container.read(drawerTickProvider.notifier).bump();

    final s = container.read(shellProvider);
    expect(s.till, isNull);
    expect(s.locked, isTrue);
    expect(s.route, const AppRoute.openTill());
    expect(arms, 0, reason: 'a table change is a re-read, not a re-arm');
  });

  test('close → open again names the NEW till, never the closed one', () {
    core.till = _till('t-1');
    expect(container.read(shellProvider).till?.id, 't-1');
    core.till = null;
    container.read(drawerTickProvider.notifier).bump();
    core.till = _till('t-2');
    container.read(shellProvider.notifier).refresh();
    expect(container.read(shellProvider).till?.id, 't-2');
  });

  test('a refresh that finds nothing new notifies nobody', () {
    core.till = _till('t-1');
    var notified = 0;
    container.listen(shellProvider, (_, _) => notified += 1);
    container.read(shellProvider.notifier).refresh();
    container.read(drawerTickProvider.notifier).bump();
    expect(notified, 0);
  });

  test('the reconcile goes through the owner: whatever the core decides '
      'reaches the shell', () async {
    expect(container.read(shellProvider).tillOpen, isFalse);
    // The server holds this person's till for this device; the reconcile
    // adopts it.
    core.reconcileTo = () => _till('t-9');
    await container.read(shellProvider.notifier).reconcileTill();
    expect(core.refreshTillCalls, 1);
    expect(container.read(shellProvider).till?.id, 't-9');

    // A force-close the rows now show: the reconcile drops it.
    core.reconcileTo = () => null;
    await container.read(shellProvider.notifier).reconcileTill();
    expect(container.read(shellProvider).till, isNull);
    expect(container.read(shellProvider).locked, isTrue);
    expect(
      arms,
      0,
      reason: 'the Till tab reconciles on every drawer tick: a re-read only',
    );
  });

  test('a till the core cannot report keeps the last honest reading', () {
    core.till = _till('t-1');
    expect(container.read(shellProvider).till?.id, 't-1');
    core.tillFails = true;
    container.read(shellProvider.notifier).refresh();
    expect(
      container.read(shellProvider).till?.id,
      't-1',
      reason: 'a hiccup is not "no till"',
    );
  });
}
