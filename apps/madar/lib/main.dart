import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:madar/app/boot.dart';
import 'package:madar/app/connectivity.dart';
import 'package:madar/app/shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock orientation by device class: tablets/desktop → one landscape (with
  // a user flip, no auto-rotate), phones → portrait. Seed from the platform
  // view now; the MaterialApp builder confirms it from MediaQuery on the
  // first frame (physicalSize can be 0 pre-frame → default to tablet).
  final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
  final size = view == null
      ? Size.zero
      : view.physicalSize / view.devicePixelRatio;
  OrientationController.instance.setDeviceClass(
    isTablet:
        size.shortestSide == 0 ||
        size.shortestSide >= OrientationController.tabletShortestSide,
  );
  runApp(const ProviderScope(child: MadarApp()));
}

/// Root widget: splash while the core boots, an ErrorState on failure, the
/// core-scoped shell once ready — cross-faded like the natives.
class MadarApp extends ConsumerWidget {
  const MadarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(bootProvider);
    return AnimatedSwitcher(
      duration: MotionSpec.gentleDuration,
      switchInCurve: MotionSpec.gentleCurve,
      switchOutCurve: MotionSpec.gentleCurve,
      child: boot.when(
        loading: () => const _BootApp(key: ValueKey('splash'), home: _Splash()),
        error: (error, _) => _BootApp(
          key: const ValueKey('boot-failed'),
          home: Scaffold(
            body: ErrorState(
              message: error is BootFailure ? error.message : '$error',
              retryLabel: error is BootFailure
                  ? error.retryLabel
                  : 'sync.retry',
              onRetry: () => ref.invalidate(bootProvider),
            ),
          ),
        ),
        data: (data) => _ReadyScope(key: const ValueKey('ready'), boot: data),
      ),
    );
  }
}

/// The pre-core MaterialApp (splash / boot failure). Light theme — the
/// vault preference is seeded onto the READY subtree once boot completes,
/// matching the old shell's pre-boot default.
class _BootApp extends StatelessWidget {
  const _BootApp({required this.home, super.key});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Madar Cashier',
      debugShowCheckedModeBanner: false,
      theme: MadarTheme.light(),
      darkTheme: MadarTheme.dark(),
      themeMode: ThemeMode.light,
      builder: orientationProbe,
      home: home,
    );
  }
}

/// The READY subtree: a FRESH root container (not parent-linked — the
/// app_core providers declare no `dependencies:`, so a child-scope
/// override of [coreProvider] would not be visible to the providers
/// derived from it) carrying the booted core + the host hooks. Everything
/// under [MadarShell] resolves against this container.
class _ReadyScope extends StatefulWidget {
  const _ReadyScope({required this.boot, super.key});

  final BootData boot;

  @override
  State<_ReadyScope> createState() => _ReadyScopeState();
}

class _ReadyScopeState extends State<_ReadyScope> {
  late ProviderContainer _container;
  ConnectivityService? _connectivity;

  @override
  void initState() {
    super.initState();
    _container = _createContainer();
  }

  @override
  void didUpdateWidget(_ReadyScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A re-boot (retry after a transient failure) yields a new core — the
    // old container's state is all derived from the dead handle.
    if (!identical(oldWidget.boot, widget.boot)) {
      _connectivity?.dispose();
      _container.dispose();
      _container = _createContainer();
    }
  }

  ProviderContainer _createContainer() {
    final container = ProviderContainer(
      overrides: readyScopeOverrides(widget.boot),
    );
    // Arm the session-gated realtime subscription for a restored session —
    // the natives' post-boot lifecycle; `refresh()` re-arms after login.
    // Deferred past the frame: this state mounts DURING a build, where
    // provider mutations (tick bumps, connection flips) are forbidden.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_container, container)) {
        container.read(realtimeArmerProvider)();
        // App-wide connectivity awareness — OS network state + app resume +
        // an adaptive periodic probe drive the core's online decision.
        _connectivity?.dispose();
        _connectivity = ConnectivityService(
          core: widget.boot.core,
          onPulse: () =>
              container.read(connectivityPulseProvider.notifier).pulse(),
        )..start();
      }
    });
    return container;
  }

  @override
  void dispose() {
    _connectivity?.dispose();
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: _container,
      child: const MadarShell(),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

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
