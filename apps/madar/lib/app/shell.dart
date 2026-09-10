import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:feature_kds/feature_kds.dart';
import 'package:feature_order/feature_order.dart';
import 'package:feature_shift/feature_shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:madar/app/chrome.dart';
import 'package:madar/app/observability.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The route-driven shell. The core's `app_route()` is the single source of
/// truth for which screen shows — the natives' exact model. Screens call
/// `ref.read(shellProvider.notifier).refresh()` after any state-changing
/// bridge call and this widget swaps content with a gentle cross-fade.
class MadarShell extends ConsumerWidget {
  const MadarShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = ref.watch(darkModeProvider);
    return MaterialApp(
      title: 'Madar Cashier',
      debugShowCheckedModeBanner: false,
      theme: MadarTheme.light(),
      darkTheme: MadarTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: orientationProbe,
      home: const _RouteHost(),
    );
  }
}

class _RouteHost extends ConsumerStatefulWidget {
  const _RouteHost();

  @override
  ConsumerState<_RouteHost> createState() => _RouteHostState();
}

class _RouteHostState extends ConsumerState<_RouteHost> {
  @override
  void initState() {
    super.initState();
    // Seed the first transaction name; the listener in build covers the rest.
    setRouteTransaction(ref.read(shellProvider).route.runtimeType.toString());
  }

  @override
  Widget build(BuildContext context) {
    final rtl = ref.watch(localeProvider.select((s) => s.rtl));
    final route = ref.watch(shellProvider.select((s) => s.route));
    // Name the Sentry transaction after the route PATTERN. This app has no
    // Navigator routes for `SentryNavigatorObserver` to observe, and the type
    // name is a pattern by construction — it can never carry an order id, so it
    // cannot produce one transaction group per record.
    //
    // On CHANGE, not on every build: this widget also rebuilds when the locale
    // flips direction (and on any ancestor rebuild), and `configureScope` is a
    // real SDK call — setRouteTransaction's own contract says "whenever the
    // route changes".
    ref.listen(
      shellProvider.select((s) => s.route),
      (_, next) => setRouteTransaction(next.runtimeType.toString()),
    );
    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: AnimatedSwitcher(
        duration: MotionSpec.gentleDuration,
        switchInCurve: MotionSpec.gentleCurve,
        switchOutCurve: MotionSpec.gentleCurve,
        child: KeyedSubtree(
          key: ValueKey(route.runtimeType),
          child: _screenFor(ref, route),
        ),
      ),
    );
  }

  /// The route → screen mapping. Screens are paramless per the contract —
  /// they reach the core through `bridgeProvider` themselves (the KDS
  /// keeps its station binding, pure data).
  Widget _screenFor(WidgetRef ref, AppRoute route) {
    return switch (route) {
      // A signed-in kitchen device parked on DeviceSetup needs its station
      // bound; everyone else gets the login screen, which embeds the
      // manager device-setup form when the device is unbound (the natives'
      // exact mapping in App.kt).
      AppRoute_DeviceSetup() =>
        ref.watch(shellProvider.select((s) => s.session?.role)) == 'kitchen'
            ? const StationPickerScreen()
            : const LoginScreen(),
      AppRoute_Login() => const LoginScreen(),
      AppRoute_OpenShift() => const OpenShiftScreen(),
      // A shop that puts every dine-in sale on a table STARTS on the table.
      //
      // The rule is not a validation to discover at the end — the server
      // refuses a table-less till sale, and being told that after the items are
      // rung up is far too late to be useful. So the floor is the home screen:
      // pick a table, ring up a few things, and the order screen takes itself
      // away again once the round is in.
      //
      // Only where there IS a floor. A branch with no tables cannot seat
      // anybody, so it keeps the order screen it has always had — which is the
      // same exemption the server applies.
      AppRoute_Order() || AppRoute_WaiterTickets() =>
        ref.watch(
                  shellProvider.select(
                    (s) => s.session?.requireTableForOrders ?? false,
                  ),
                ) &&
                ref.watch(orderProvider.select((s) => s.hasFloor))
            ? const MadarChrome(child: TablesScreen(isHome: true))
            : const MadarChrome(child: OrderScreen()),
      AppRoute_KitchenDisplay(:final stationId) => KitchenDisplayScreen(
        stationId: stationId,
      ),
    };
  }
}
