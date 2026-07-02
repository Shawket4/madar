import 'package:design_system/design_system.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:feature_kds/feature_kds.dart';
import 'package:feature_order/feature_order.dart';
import 'package:feature_shift/feature_shift.dart';
import 'package:flutter/material.dart';
import 'package:madar/app/app_state.dart';
import 'package:madar/app/chrome.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The route-driven shell. The core's `app_route()` is the single source of
/// truth for which screen shows — the natives' exact model. Screens call
/// [MadarAppState.refreshRoute] after any state-changing bridge call and
/// this widget swaps content with a gentle cross-fade.
class MadarShell extends StatelessWidget {
  const MadarShell({required this.state, super.key});

  final MadarAppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Directionality(
          textDirection: state.rtl ? TextDirection.rtl : TextDirection.ltr,
          child: AnimatedSwitcher(
            duration: MotionSpec.gentleDuration,
            switchInCurve: MotionSpec.gentleCurve,
            switchOutCurve: MotionSpec.gentleCurve,
            child: _body(context),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    switch (state.phase) {
      case AppPhase.booting:
        return const _Splash(key: ValueKey('splash'));
      case AppPhase.failed:
        return Scaffold(
          key: const ValueKey('boot-failed'),
          body: ErrorState(
            message: state.bootError ?? 'Boot failed',
            retryLabel: state.tr('common.retry'),
            onRetry: state.boot,
          ),
        );
      case AppPhase.ready:
        return KeyedSubtree(
          key: ValueKey(state.route.runtimeType),
          child: _screenFor(state.route),
        );
    }
  }

  Widget _screenFor(AppRoute route) {
    final core = state.core;
    final onChanged = state.refreshRoute;
    return switch (route) {
      // A signed-in kitchen device parked on DeviceSetup needs its station
      // bound; everyone else gets the login screen, which embeds the
      // manager device-setup form when the device is unbound (the natives'
      // exact mapping in App.kt).
      AppRoute_DeviceSetup() =>
        state.session != null && state.session!.role == 'kitchen'
            ? StationPickerScreen(core: core, onStateChanged: onChanged)
            : LoginScreen(core: core, onStateChanged: onChanged),
      AppRoute_Login() => LoginScreen(core: core, onStateChanged: onChanged),
      AppRoute_OpenShift() => OpenShiftScreen(
        core: core,
        onStateChanged: onChanged,
      ),
      AppRoute_Order() || AppRoute_WaiterTickets() => MadarChrome(
        state: state,
        child: OrderScreen(core: core, onStateChanged: onChanged),
      ),
      AppRoute_KitchenDisplay(:final stationId) => KitchenDisplayScreen(
        core: core,
        onStateChanged: onChanged,
        stationId: stationId,
        realtimeTick: state.kitchenTick,
      ),
    };
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MadarSymbol(size: 72),
            const SizedBox(height: Space.lg),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                minHeight: 3,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
