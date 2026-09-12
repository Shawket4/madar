import 'dart:async';
import 'dart:math' as math;

import 'package:design_system/src/scrim.dart';
import 'package:design_system/src/sheet.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/elevation.dart';
import 'package:design_system/src/tokens/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Presents [builder] in the Madar modal side drawer — the start-anchored
/// sibling of `showMadarSheet` (same scrim, springs, and dismissal
/// contract), used where a nav-style surface fits better than a bottom
/// sheet (the narrow layouts' More menu).
///
/// Anatomy: a full-height surface panel anchored to the START edge
/// (mirrors under RTL) with [Radii.xl] far corners, a 1px `borderLight`
/// border, a raised shadow, and a black scrim at [Opacities.scrim]
/// behind it. The panel slides in on the sheet spring while the scrim
/// fades in over [MotionSpec.standardDuration].
///
/// Dismissal — tap the scrim, drag the panel toward its edge past 28% of
/// its width, press system back, or `Navigator.maybePop(result)` from the
/// content — always animates the panel out first; the route completes
/// after [MotionSpec.sheetDismissDelay].
Future<T?> showMadarDrawer<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double width = _drawerWidth,
}) {
  return Navigator.of(
    context,
  ).push(MadarDrawerRoute<T>(builder: builder, width: width));
}

/// Default panel width — the natives' phone drawer.
const double _drawerWidth = 320;

/// Drag distance (fraction of the panel width) past which release
/// dismisses instead of springing back — mirrors the sheet's 0.28.
const double _dragDismissFraction = 0.28;

/// Extra hidden-translation margin so the raised shadow clears the edge.
const double _shadowClearance = 80;

/// The custom [ModalRoute] behind [showMadarDrawer] — the same
/// zero-length-transition + page-owned-spring pattern as MadarSheetRoute.
class MadarDrawerRoute<T> extends ModalRoute<T> {
  /// Creates the drawer route. Prefer [showMadarDrawer].
  MadarDrawerRoute({required this.builder, this.width = _drawerWidth});

  /// Builds the drawer content.
  final WidgetBuilder builder;

  /// Panel width.
  final double width;

  /// The drawer's stake in the shared dim (scrim.dart) — it paints the one
  /// dim only when nothing below already does, and hands it on as it leaves.
  ScrimClaim get scrimClaim => _scrimClaim ??= ScrimClaim.claim();
  ScrimClaim? _scrimClaim;

  @override
  void install() {
    _scrimClaim ??= ScrimClaim.claim();
    super.install();
  }

  @override
  bool didPop(T? result) {
    scrimClaim.release();
    return super.didPop(result);
  }

  @override
  void dispose() {
    scrimClaim.dispose();
    super.dispose();
  }

  @override
  Color? get barrierColor => null; // The page draws its own scrim.

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  bool get opaque => false;

  @override
  Duration get transitionDuration => Duration.zero;

  /// The card leaves on its own springs BEFORE the pop; what this carries is
  /// the dim's fade AFTER it. The dim stays down until the route is popped,
  /// so the surface pushed the instant this one's future resolves takes it
  /// over at full strength (scrim.dart) — no undimmed flash between two
  /// sheets. With nothing following, it fades out over this.
  @override
  Duration get reverseTransitionDuration => MotionSpec.standardDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _MadarDrawerPage<T>(route: this);
  }
}

class _MadarDrawerPage<T> extends StatefulWidget {
  const _MadarDrawerPage({required this.route});

  final MadarDrawerRoute<T> route;

  @override
  State<_MadarDrawerPage<T>> createState() => _MadarDrawerPageState<T>();
}

class _MadarDrawerPageState<T> extends State<_MadarDrawerPage<T>>
    with TickerProviderStateMixin
    implements DismissibleSurface {
  @override
  void dismissWith(Object? result) => _dismiss(result: result as T?);

  /// Base slide, in fractions of the hidden extent: 1 = off-screen
  /// past the start edge, 0 = shown.
  late final AnimationController _slide;

  /// Live drag toward the start edge in pixels (>= 0).
  late final AnimationController _drag;

  late final AnimationController _scrim;
  late final CurvedAnimation _scrimOpacity;

  /// The route's own exit fade — see [MadarDrawerRoute.reverseTransitionDuration].
  late final CurvedAnimation _routeFade;

  /// What is actually painted: faded in by [_scrimOpacity], out by the route.
  late final Animation<double> _scrimVisible;

  Timer? _popTimer;
  bool _dismissing = false;

  double get _hiddenExtent => widget.route.width + _shadowClearance;

  @override
  void initState() {
    super.initState();
    _slide = AnimationController.unbounded(vsync: this, value: 1);
    _drag = AnimationController.unbounded(vsync: this);
    _scrim = AnimationController(
      vsync: this,
      duration: MotionSpec.standardDuration,
      reverseDuration: MotionSpec.standardDuration,
    );
    _scrimOpacity = CurvedAnimation(
      parent: _scrim,
      curve: MotionSpec.standardCurve,
      reverseCurve: MotionSpec.standardCurve,
    );
    final claim = widget.route.scrimClaim
      ..visibleOpacity = () => _scrimVisible.value;
    _scrim.value = claim.startOpacity;
    _routeFade = CurvedAnimation(
      parent: widget.route.animation!,
      curve: MotionSpec.standardCurve,
    )..addStatusListener(_onRouteStatus);
    _scrimVisible = AnimationMin<double>(_scrimOpacity, _routeFade);
    _slide.animateWith(SpringSimulation(MotionSpec.sheet, 1, 0, 0));
    _scrim.forward();
  }

  @override
  void dispose() {
    _popTimer?.cancel();
    _routeFade
      ..removeStatusListener(_onRouteStatus)
      ..dispose();
    _scrimOpacity.dispose();
    _scrim.dispose();
    _drag.dispose();
    _slide.dispose();
    super.dispose();
  }

  /// A bare `Navigator.pop` skipped [_dismiss]: send the card away while
  /// the route's exit fade runs, rather than leaving it standing.
  void _onRouteStatus(AnimationStatus status) {
    if (status != AnimationStatus.reverse || _dismissing) return;
    _dismissing = true;
    _slide.animateWith(SpringSimulation(MotionSpec.sheet, _slide.value, 1, 0));
  }

  void _dismiss({T? result, double velocity = 0}) {
    if (_dismissing) return;
    _dismissing = true;
    widget.route.scrimClaim.release();
    _slide.animateWith(
      SpringSimulation(MotionSpec.sheet, _slide.value, 1, velocity),
    );
    _popTimer = Timer(MotionSpec.sheetDismissDelay, () {
      if (!mounted) return;
      // Complete THIS route, not whatever is on top. The caller may already
      // have pushed its next screen the instant it asked to close (a sheet
      // button that pops then pushes): a bare `pop` here would take that
      // screen down and leave this card off-screen under a live, dismissed
      // (so un-tappable) scrim — the app frozen.
      final route = widget.route;
      if (route.isCurrent) {
        Navigator.of(context).pop(result);
      } else if (route.isActive) {
        route.navigator?.removeRoute(route, result);
      }
    });
  }

  /// +1 when "hiding" means translating right (RTL start edge), −1 left.
  double _hideSign(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl ? 1 : -1;

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_dismissing) return;
    // Dragging toward the start edge hides; away springs against 0.
    _drag.value = math.max(
      0,
      _drag.value + details.delta.dx * _hideSign(context),
    );
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_dismissing) return;
    final velocity = (details.primaryVelocity ?? 0) * _hideSign(context);
    if (_drag.value > widget.route.width * _dragDismissFraction) {
      _dismiss(velocity: velocity / _hiddenExtent);
    } else {
      _drag.animateWith(
        SpringSimulation(MotionSpec.sheet, _drag.value, 0, velocity),
      );
    }
  }

  void _handleDragCancel() {
    if (_dismissing) return;
    _drag.animateWith(SpringSimulation(MotionSpec.sheet, _drag.value, 0, 0));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final dismissLabel = Localizations.of<MaterialLocalizations>(
      context,
      MaterialLocalizations,
    )?.modalBarrierDismissLabel;
    const radius = BorderRadiusDirectional.horizontal(
      end: Radius.circular(Radii.xl),
    );

    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: radius.resolve(Directionality.of(context)),
        border: Border.all(color: colors.borderLight),
        boxShadow: MadarElevation.raised.shadows(colors, dark: dark),
      ),
      child: ClipRRect(
        borderRadius: radius.resolve(Directionality.of(context)),
        // Material ancestor — the route lives outside any Scaffold.
        child: Material(
          type: MaterialType.transparency,
          child: Builder(builder: widget.route.builder),
        ),
      ),
    );

    return PopScope<T>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _dismiss(result: result);
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismiss,
              child: Semantics(
                label: dismissLabel,
                child: StackScrim(
                  claim: widget.route.scrimClaim,
                  opacity: _scrimVisible,
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 0,
            bottom: 0,
            start: 0,
            width: widget.route.width,
            // Horizontal drags anywhere on the panel; taps pass through to
            // the rows (different recognizers).
            child: GestureDetector(
              onHorizontalDragUpdate: _handleDragUpdate,
              onHorizontalDragEnd: _handleDragEnd,
              onHorizontalDragCancel: _handleDragCancel,
              child: AnimatedBuilder(
                animation: Listenable.merge([_slide, _drag]),
                // Clamped at 0: the spring is underdamped (.9); overshoot
                // past rest would pull the panel off its edge and flash
                // the screen behind through the gap (the sheet's lesson).
                builder: (context, child) => Transform.translate(
                  offset: Offset(
                    _hideSign(context) *
                        math.max(0, _slide.value * _hiddenExtent + _drag.value),
                    0,
                  ),
                  child: child,
                ),
                child: panel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
