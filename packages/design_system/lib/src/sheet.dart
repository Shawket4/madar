import 'dart:async';
import 'dart:math' as math;

import 'package:design_system/src/responsive.dart';
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
  hug(0.92)
  ;

  const SheetSize(this.heightFraction);

  /// Height cap as a fraction of the available container height.
  final double heightFraction;
}

/// Presents [builder] in the Madar modal bottom sheet — THE shared
/// presenter every sheet in the app uses.
///
/// Anatomy (matching the natives): a bottom-anchored surface card with
/// [Radii.xl] top corners, a 1px `borderLight` border, a raised shadow,
/// a centered width cap, and a drag handle; behind it a black scrim at
/// [Opacities.scrim]. The card slides in on the sheet spring while the
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
  return Navigator.of(context).push(
    MadarSheetRoute<T>(builder: builder, size: size, maxWidth: maxWidth),
  );
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

/// The natives scrim with pure black in BOTH themes (Compose
/// `Color.Black`), pre-multiplied here with [Opacities.scrim].
const Color _scrimColor = Color.from(
  alpha: Opacities.scrim,
  red: 0,
  green: 0,
  blue: 0,
);

const BorderRadius _cardRadius = BorderRadius.vertical(
  top: Radius.circular(Radii.xl),
);

class _MadarSheetPage<T> extends StatefulWidget {
  const _MadarSheetPage({required this.route});

  final MadarSheetRoute<T> route;

  @override
  State<_MadarSheetPage<T>> createState() => _MadarSheetPageState<T>();
}

class _MadarSheetPageState<T> extends State<_MadarSheetPage<T>>
    with TickerProviderStateMixin {
  /// Base slide, in fractions of the hidden extent: 1 = off-screen,
  /// 0 = shown. Spring-driven both ways.
  late final AnimationController _slide;

  /// The user's live drag offset in pixels (>= 0), kept separate so a
  /// released-but-not-dismissed drag springs back on its own.
  late final AnimationController _drag;

  late final AnimationController _scrim;
  late final CurvedAnimation _scrimOpacity;

  Timer? _popTimer;
  bool _dismissing = false;

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
    // Slide in on the sheet spring, fade the scrim in alongside.
    unawaited(_slide.animateWith(SpringSimulation(MotionSpec.sheet, 1, 0, 0)));
    unawaited(_scrim.forward());
  }

  @override
  void dispose() {
    _popTimer?.cancel();
    _scrimOpacity.dispose();
    _scrim.dispose();
    _drag.dispose();
    _slide.dispose();
    super.dispose();
  }

  /// Animates out, THEN completes the route — the caller's future only
  /// resolves once the card is off-screen (no hard cut).
  void _dismiss({T? result, double velocity = 0}) {
    if (_dismissing) return;
    _dismissing = true;
    unawaited(
      _slide.animateWith(
        SpringSimulation(MotionSpec.sheet, _slide.value, 1, velocity),
      ),
    );
    unawaited(_scrim.reverse());
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
      unawaited(
        _drag.animateWith(
          SpringSimulation(MotionSpec.sheet, _drag.value, 0, velocity),
        ),
      );
    }
  }

  void _handleDragCancel() {
    if (_dismissing) return;
    unawaited(
      _drag.animateWith(SpringSimulation(MotionSpec.sheet, _drag.value, 0, 0)),
    );
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
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
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
                    child: FadeTransition(
                      opacity: _scrimOpacity,
                      child: const ColoredBox(color: _scrimColor),
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
                    builder: (context, child) => Transform.translate(
                      offset: Offset(
                        0,
                        _slide.value * hiddenExtent + _drag.value,
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
