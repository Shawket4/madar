import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:feature_kds/feature_kds.dart';
import 'package:feature_order/feature_order.dart';
import 'package:feature_shift/feature_shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:madar/app/chrome.dart';
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

class _RouteHost extends ConsumerWidget {
  const _RouteHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rtl = ref.watch(localeProvider.select((s) => s.rtl));
    final route = ref.watch(shellProvider.select((s) => s.route));
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
      AppRoute_Order() ||
      AppRoute_WaiterTickets() => const MadarChrome(child: OrderScreen()),
      AppRoute_KitchenDisplay(:final stationId) => KitchenDisplayScreen(
        stationId: stationId,
      ),
    };
  }
}
