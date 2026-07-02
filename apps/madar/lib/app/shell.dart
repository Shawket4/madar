import 'package:design_system/design_system.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:feature_order/feature_order.dart';
import 'package:feature_shift/feature_shift.dart';
import 'package:flutter/material.dart';
import 'package:madar/app/app_state.dart';
import 'package:madar/spike_screen.dart';
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
      AppRoute_Order() || AppRoute_WaiterTickets() => OrderScreen(
        core: core,
        onStateChanged: onChanged,
      ),
      AppRoute_KitchenDisplay(:final stationId) => _Placeholder(
        state: state,
        name: 'KDS ($stationId) — M6',
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

/// M4 replaces these one by one; until then each names itself, proves the
/// route machine works, and links the dev tools.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.state, required this.name});

  final MadarAppState state;
  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Scaffold(
      appBar: AppBar(
        title: Text('$name — M4', style: MadarType.h3),
        actions: [
          IconButton(
            tooltip: 'Core spike',
            icon: const Icon(Icons.biotech_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SpikeScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Design gallery',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GalleryScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Toggle theme',
            icon: const Icon(Icons.brightness_6_outlined),
            onPressed: () => state.setThemeMode(
              state.themeMode == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark,
            ),
          ),
          IconButton(
            tooltip: 'EN ⇄ AR',
            icon: const Icon(Icons.translate_outlined),
            onPressed: () =>
                state.setLocale(state.locale == 'ar' ? 'en' : 'ar'),
          ),
        ],
      ),
      body: Center(
        child: EmptyState(
          icon: 'hammer',
          title: name,
          message:
              '${state.tr('login.sign_in')} · locale=${state.locale} · '
              'rtl=${state.rtl}',
        ),
      ),
      backgroundColor: colors.bg,
    );
  }
}
