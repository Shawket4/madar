import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:feature_kds/feature_kds.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
    final motion = ref.watch(motionChoiceProvider);
    final rtl = ref.watch(localeProvider.select((s) => s.rtl));
    final lang = ref.watch(
      localeProvider.select((s) => s.locale.split(RegExp('[-_]')).first),
    );
    // The Done bar's one word, from the core's i18n like every other string
    // the app shows. Set here because this is where the language is known;
    // the bar itself is drawn far from any provider scope.
    MadarKeyboardDone.label = ref.read(bridgeProvider).tr(key: 'common.done');
    return MaterialApp(
      title: 'Madar Cashier',
      debugShowCheckedModeBanner: false,
      theme: MadarTheme.light(),
      darkTheme: MadarTheme.dark(),
      themeMode: choice.mode,
      // Material's built-in words (the text-selection menu, tooltips) follow
      // the core's language too; only the languages the core speaks.
      locale: Locale(lang == 'ar' ? 'ar' : 'en'),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Direction sits ABOVE the navigator, so every pushed screen, sheet
      // and modal mirrors with the locale — not only the home route.
      // The Done bar sits OUTSIDE the direction/motion scopes, over the whole
      // app, because the software keyboard does: the iOS number, decimal and
      // phone pads have no return key, so a field taking one of them has no
      // way to put the keyboard away on its own. It draws nothing at all
      // unless such a field holds focus (`MadarKeyboardDone`).
      builder: (context, child) => MadarKeyboardDoneBar(
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: motionScope(context, motion, orientationProbe(context, child)),
        ),
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
      // Keyed by the SURFACE, not the route: a teller opening their till
      // moves from openTill to order, and the shell they are standing in
      // must not remount for it.
      child: KeyedSubtree(key: ValueKey(screen.runtimeType), child: screen),
    );
  }

  /// The route → surface mapping. Screens are paramless per the contract —
  /// they reach the core through `bridgeProvider` themselves (the KDS
  /// keeps its station binding, pure data).
  /// A kitchen-screen-only person (by capability). Re-read when the person
  /// changes.
  bool _kitchenOnly(WidgetRef ref) {
    ref.watch(shellProvider.select((s) => s.session?.userId));
    final bridge = ref.read(bridgeProvider);
    return isKitchenOnly((c) => bridge.can(cap: c));
  }

  Widget _screenFor(WidgetRef ref, AppRoute route) {
    return switch (route) {
      // A signed-in kitchen device parked on DeviceSetup needs its station
      // bound; everyone else gets the login screen, which embeds the
      // manager device-setup form when the device is unbound.
      AppRoute_DeviceSetup() =>
        _kitchenOnly(ref) ? const StationPickerScreen() : const LoginScreen(),
      AppRoute_Login() => const LoginScreen(),
      // Signed in: the person's shell decides the tabs from the role. A
      // teller with no till is not walled off — the shell opens on Till,
      // where the open-till card is, and the Floor and Queue stay readable.
      AppRoute_OpenTill() ||
      AppRoute_Order() ||
      AppRoute_WaiterTickets() => const RoleShell(),
      AppRoute_KitchenDisplay(:final stationId) => KitchenDisplayScreen(
        stationId: stationId,
      ),
    };
  }
}

/// The Animations setting, applied ABOVE the navigator: Full and Reduced
/// override `MediaQuery.disableAnimations` (which `motionReduced` and every
/// gated widget read), Follow system leaves the platform's flag alone.
Widget motionScope(BuildContext context, MotionChoice choice, Widget child) {
  if (choice == MotionChoice.system) return child;
  return MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(disableAnimations: choice == MotionChoice.reduced),
    child: child,
  );
}
