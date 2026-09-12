import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:feature_kds/feature_kds.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:madar/app/chrome.dart';
import 'package:madar/app/observability.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The route-driven shell. The core's `app_route()` is the single source of
/// truth for which surface shows — sign-in, the kitchen board, or the
/// signed-in person's shell. Screens call
/// `ref.read(shellProvider.notifier).refresh()` after any state-changing
/// bridge call and this widget swaps content with a gentle cross-fade.
class MadarShell extends ConsumerWidget {
  const MadarShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(themeChoiceProvider);
    final rtl = ref.watch(localeProvider.select((s) => s.rtl));
    return MaterialApp(
      title: 'Madar Cashier',
      debugShowCheckedModeBanner: false,
      theme: MadarTheme.light(),
      darkTheme: MadarTheme.dark(),
      themeMode: switch (choice) {
        ThemeChoice.light => ThemeMode.light,
        ThemeChoice.dark => ThemeMode.dark,
        ThemeChoice.system => ThemeMode.system,
      },
      // The rail wears a native platform view on iOS 26 (design_system's
      // MadarGlassSurface), and iOS composites those above Flutter's own
      // layers unless something tells the plugin a modal went up.
      navigatorObservers: [glassRouteObserver()],
      // Direction sits ABOVE the navigator, so every pushed screen, sheet
      // and modal mirrors with the locale — not only the home route.
      builder: (context, child) => Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: orientationProbe(context, child),
      ),
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
    final route = ref.watch(shellProvider.select((s) => s.route));
    // Name the Sentry transaction after the route PATTERN. This app has no
    // Navigator routes for `SentryNavigatorObserver` to observe, and the type
    // name is a pattern by construction — it can never carry an order id, so
    // it cannot produce one transaction group per record. On CHANGE, not on
    // every build: `configureScope` is a real SDK call.
    ref.listen(
      shellProvider.select((s) => s.route),
      (_, next) => setRouteTransaction(next.runtimeType.toString()),
    );
    final screen = _screenFor(ref, route);
    return AnimatedSwitcher(
      duration: MotionSpec.gentleDuration,
      switchInCurve: MotionSpec.gentleCurve,
      switchOutCurve: MotionSpec.gentleCurve,
      // Keyed by the SURFACE, not the route: a teller opening their shift
      // moves from openShift to order, and the shell they are standing in
      // must not remount for it.
      child: KeyedSubtree(key: ValueKey(screen.runtimeType), child: screen),
    );
  }

  /// The route → surface mapping. Screens are paramless per the contract —
  /// they reach the core through `bridgeProvider` themselves (the KDS
  /// keeps its station binding, pure data).
  Widget _screenFor(WidgetRef ref, AppRoute route) {
    return switch (route) {
      // A signed-in kitchen device parked on DeviceSetup needs its station
      // bound; everyone else gets the login screen, which embeds the
      // manager device-setup form when the device is unbound.
      AppRoute_DeviceSetup() =>
        ref.watch(shellProvider.select((s) => s.session?.role)) == 'kitchen'
            ? const StationPickerScreen()
            : const LoginScreen(),
      AppRoute_Login() => const LoginScreen(),
      // Signed in: the person's shell decides the tabs from the role. A
      // teller with no shift is not walled off — the shell opens on Till,
      // where the open-shift card is, and the Floor and Queue stay readable.
      AppRoute_OpenShift() ||
      AppRoute_Order() ||
      AppRoute_WaiterTickets() => const RoleShell(),
      AppRoute_KitchenDisplay(:final stationId) => KitchenDisplayScreen(
        stationId: stationId,
      ),
    };
  }
}
