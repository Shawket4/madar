import 'dart:async';
import 'dart:math' as math;

import 'package:design_system/src/responsive.dart';
import 'package:design_system/src/scrim.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/elevation.dart';
import 'package:design_system/src/tokens/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// How tall the sheet card may grow — mirrors the natives' `SheetSize`
/// (MadarSheet.kt / MadarSheet.swift). Fractions are of the available
/// container height (minus the keyboard inset).
enum SheetSize {
  /// Fills ~88% of the container — the default for medium sheets.
  auto(0.88),

  /// Reaches ~94% — big sheets (checkout / tender).
  large(0.94),

  /// Hugs its content up to a 92% cap and scrolls only on overflow —
  /// item / bundle customize sheets that must not stretch into a tall
  /// empty void.
  hug(0.92);

  const SheetSize(this.heightFraction);

  /// Height cap as a fraction of the available container height.
  final double heightFraction;
}

/// Presents [builder] in the Madar modal bottom sheet — THE shared
/// presenter every sheet in the app uses.
///
/// Anatomy: a bottom-anchored surface card with [Radii.sheet] top corners,
/// a 1px `borderLight` border, the modal shadow, a centered width cap (600
/// on a tablet — the sheet never spans an iPad), and a drag handle; behind
/// it a black scrim at [Opacities.scrim]. On a phone the cap is moot and
/// the sheet is full width. The card slides in on the sheet spring while the
/// scrim fades in over [MotionSpec.standardDuration].
///
/// Dismissal — tap the scrim, drag the handle down past 28% of the
/// sheet height, press system back, or call
/// `Navigator.of(context).maybePop(result)` from the content — always
/// animates the card out first; the route only completes (and the
/// returned future resolves) after [MotionSpec.sheetDismissDelay], so
/// there is no hard cut.
///
/// The sheet is keyboard-aware: it rises above the view insets and its
/// height cap shrinks with them.
///
/// ```dart
/// final tender = await showMadarSheet<Tender>(
///   context,
///   size: SheetSize.large,
///   builder: (context) => const TenderSheet(),
/// );
/// ```
Future<T?> showMadarSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  SheetSize size = SheetSize.auto,
  double maxWidth = Responsive.sheetMaxWidth,
}) {
  return Navigator.of(
    context,
  ).push(MadarSheetRoute<T>(builder: builder, size: size, maxWidth: maxWidth));
}

/// Closing a sheet (or drawer) from its content, ALWAYS with the slide-out.
///
/// `Navigator.of(context).pop()` removes a Madar sheet route with no exit
/// animation (its route transition is zero-length; the page drives the
/// springs). Use [MadarSheet.close] instead — it runs the same dismissal as a
/// scrim tap and resolves the presenter's future with `result` once the card
/// is off-screen. Outside a Madar surface it falls back to `maybePop`.
abstract final class MadarSheet {
  /// Animates the nearest enclosing sheet / drawer out, then pops [result].
  static void close<T>(BuildContext context, [T? result]) {
    DismissibleSurface? surface;
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is DismissibleSurface) {
        surface = element.state as DismissibleSurface;
        return false;
      }
      return true;
    });
    if (surface case final s?) {
      s.dismissWith(result);
    } else {
      Navigator.of(context).maybePop(result);
    }
  }
}

/// A surface page that knows how to animate itself out — see [MadarSheet].
abstract interface class DismissibleSurface {
  /// Plays the exit and pops the route with [result].
  void dismissWith(Object? result);
}

/// The custom [ModalRoute] behind [showMadarSheet].
///
/// It owns its springs: the route's own transitions are zero-length and
/// the page drives the slide with [MotionSpec.sheet] simulations, which
/// is why this is not built on `showModalBottomSheet`.
class MadarSheetRoute<T> extends ModalRoute<T> {
  /// Creates the sheet route. Prefer [showMadarSheet].
  MadarSheetRoute({
    required this.builder,
    this.size = SheetSize.auto,
    this.maxWidth = Responsive.sheetMaxWidth,
    super.settings,
  });

  /// Builds the sheet content, laid out below the drag handle.
  final WidgetBuilder builder;

  /// Height behavior of the card.
  final SheetSize size;

  /// Centered width cap of the card.
  final double maxWidth;

  /// This sheet's stake in the shared dim (scrim.dart). Taken when the route
  /// is installed, given back the moment it starts to leave.
  ScrimClaim get scrimClaim => _scrimClaim ??= ScrimClaim.claim();
  ScrimClaim? _scrimClaim;

  @override
  void install() {
    _scrimClaim ??= ScrimClaim.claim(); // Before the first frame.
    super.install();
  }

  @override
  bool didPop(T? result) {
    // A bare Navigator.pop lands here without the page's own dismiss — the
    // dim must still be handed on before the caller's future resolves.
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
    return _MadarSheetPage<T>(route: this);
  }
}

/// Drag distance (fraction of the sheet height) past which release
/// dismisses instead of springing back — the natives' 0.28.
const double _dragDismissFraction = 0.28;

/// Extra hidden-translation margin so the raised shadow clears the
/// bottom edge too — the natives' `+ 80f`.
const double _shadowClearance = 80;

/// Drag-handle pill size — the natives' 40 × 5.
const double _handleWidth = 40;
const double _handleHeight = 5;

/// System v2: a sheet's top corners are the sheet radius, 20.
const BorderRadius _cardRadius = BorderRadius.vertical(
  top: Radius.circular(Radii.sheet),
);

class _MadarSheetPage<T> extends StatefulWidget {
  const _MadarSheetPage({required this.route});

  final MadarSheetRoute<T> route;

  @override
  State<_MadarSheetPage<T>> createState() => _MadarSheetPageState<T>();
}

class _MadarSheetPageState<T> extends State<_MadarSheetPage<T>>
    with TickerProviderStateMixin
    implements DismissibleSurface {
  @override
  void dismissWith(Object? result) => _dismiss(result: result as T?);

  /// Base slide, in fractions of the hidden extent: 1 = off-screen,
  /// 0 = shown. Spring-driven both ways.
  late final AnimationController _slide;

  /// The user's live drag offset in pixels (>= 0), kept separate so a
  /// released-but-not-dismissed drag springs back on its own.
  late final AnimationController _drag;

  late final AnimationController _scrim;
  late final CurvedAnimation _scrimOpacity;

  /// The route's own exit fade — see [MadarSheetRoute.reverseTransitionDuration].
  late final CurvedAnimation _routeFade;

  /// What is actually painted: faded in by [_scrimOpacity], out by the route.
  late final Animation<double> _scrimVisible;

  Timer? _popTimer;
  bool _dismissing = false;

  /// The inset last applied while this sheet was on top. A sheet covered by
  /// another keeps it, so a keyboard raised for the sheet ABOVE does not
  /// reflow (jump) the one beneath.
  double _ownInset = 0;

  // Captured during layout for the gesture + dismiss math.
  double _sheetHeight = 0;
  double _hiddenExtent = 0;

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
    // Taking over from a surface still fading out: pick up its dim where it
    // is, so the handoff never flashes the page undimmed.
    _scrim.value = claim.startOpacity;
    _routeFade = CurvedAnimation(
      parent: widget.route.animation!,
      curve: MotionSpec.standardCurve,
    )..addStatusListener(_onRouteStatus);
    _scrimVisible = AnimationMin<double>(_scrimOpacity, _routeFade);
    // Slide in on the sheet spring, fade the scrim in alongside.
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

  /// Animates out, THEN completes the route — the caller's future only
  /// resolves once the card is off-screen (no hard cut).
  void _dismiss({T? result, double velocity = 0}) {
    if (_dismissing) return;
    _dismissing = true;
    widget.route.scrimClaim.release();
    _slide.animateWith(
      SpringSimulation(MotionSpec.sheet, _slide.value, 1, velocity),
    );
    _popTimer = Timer(MotionSpec.sheetDismissDelay, () {
      if (!mounted) return;
      Navigator.of(context).pop(result);
    });
  }

  void _handleScrimTap() => _dismiss();

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_dismissing) return;
    _drag.value = math.max(0, _drag.value + details.delta.dy);
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_dismissing) return;
    final velocity = details.primaryVelocity ?? 0;
    if (_drag.value > _sheetHeight * _dragDismissFraction) {
      _dismiss(velocity: _hiddenExtent > 0 ? velocity / _hiddenExtent : 0);
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

  Widget _buildCard(BuildContext context, MadarColors colors) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hug = widget.route.size == SheetSize.hug;

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: _cardRadius,
        border: Border.all(color: colors.borderLight),
        boxShadow: MadarElevation.raised.shadows(colors, dark: dark),
      ),
      child: ClipRRect(
        borderRadius: _cardRadius,
        // Material ancestor for the sheet's content — the route lives outside
        // any Scaffold, and sheet bodies contain TextFields/ink effects.
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: hug ? MainAxisSize.min : MainAxisSize.max,
            children: [
              // Grab handle — full-width drag strip.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: _handleDragUpdate,
                onVerticalDragEnd: _handleDragEnd,
                onVerticalDragCancel: _handleDragCancel,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: Space.md,
                      bottom: Space.sm,
                    ),
                    child: SizedBox(
                      width: _handleWidth,
                      height: _handleHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.border,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(Radii.pill),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (hug)
                Flexible(child: Builder(builder: widget.route.builder))
              else
                Expanded(child: Builder(builder: widget.route.builder)),
            ],
          ),
        ),
      ),
    );

    final sized = hug
        ? ConstrainedBox(
            constraints: BoxConstraints(maxHeight: _sheetHeight),
            child: card,
          )
        : SizedBox(height: _sheetHeight, child: card);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.route.maxWidth),
      child: SizedBox(width: double.infinity, child: sized),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final route = ModalRoute.of(context);
    if (route == null || route.isCurrent) {
      _ownInset = MediaQuery.viewInsetsOf(context).bottom;
    }
    final bottomInset = _ownInset;
    final dismissLabel = Localizations.of<MaterialLocalizations>(
      context,
      MaterialLocalizations,
    )?.modalBarrierDismissLabel;

    return PopScope<T>(
      // System back and `Navigator.maybePop(result)` land here so the
      // route only truly pops after the slide-out.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _dismiss(result: result);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          _sheetHeight =
              math.max(0, constraints.maxHeight - bottomInset) *
              widget.route.size.heightFraction;
          // Fully-hidden translation: the whole container height plus a
          // margin so the shadow clears the bottom edge too.
          _hiddenExtent = constraints.maxHeight + _shadowClearance;
          final hiddenExtent = _hiddenExtent;

          return Stack(
            children: [
              // Scrim — tap to dismiss. Sits below the card.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleScrimTap,
                  child: Semantics(
                    label: dismissLabel,
                    // Still full-bleed and still tappable when it paints
                    // nothing — the dim is suppressed, never the tap.
                    child: StackScrim(
                      claim: widget.route.scrimClaim,
                      opacity: _scrimVisible,
                    ),
                  ),
                ),
              ),
              // The card — base spring offset + live drag offset.
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomInset),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_slide, _drag]),
                    // Clamped at 0: the sheet spring is underdamped (.9), and
                    // an overshoot past rest would lift the bottom-anchored
                    // card off the screen edge, flashing the screen behind
                    // through the gap (visible on drag-release spring-back).
                    builder: (context, child) => Transform.translate(
                      offset: Offset(
                        0,
                        math.max(0, _slide.value * hiddenExtent + _drag.value),
                      ),
                      child: child,
                    ),
                    child: _buildCard(context, colors),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
