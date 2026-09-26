import 'dart:async';
import 'dart:math' as math;

import 'package:design_system/src/sheet.dart';
import 'package:design_system/src/tokens/motion.dart';
import 'package:flutter/material.dart';

/// Presents [builder] as a card that slides down from the top of the window
/// — the post-sale Done card — as a real route in the kit's surface stack.
///
/// Being a route (not an overlay entry) is the point: a sheet the card opens
/// ("Add points") is pushed ABOVE it and takes the tap, instead of rendering
/// underneath a floating overlay that a stray tap would tear down together
/// with the sheet.
///
/// The card does NOT dim and does NOT block: the sell grid behind it stays
/// lit and live. A pointer down anywhere outside the card puts it away with
/// [barrierResult] AND reaches whatever is under it — the teller's tap on a
/// product tile starts the next sale in one tap. A sheet it opens claims the
/// shared dim (scrim.dart) as the first dimming surface. System back resolves
/// [barrierResult] too. From the content, close it with
/// `MadarSheet.close(context, result)` so it always animates out.
///
/// By default the card is centred at the top of the window. Pass [over] — a
/// key on a region of the screen underneath — to centre it over THAT region
/// instead (the Sell screen's Fast mode: over the menu panel on the end
/// edge, not over the cart). The region is read where it actually is, so it
/// follows the layout and the script: the end edge is the right in English
/// and the left in Arabic. The card never leaves the window's [padding];
/// where the region is narrower than the card, it keeps as close to the
/// region as the window allows.
Future<T?> showMadarTopCard<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  required T barrierResult,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
  double maxWidth = 600,
  bool rootNavigator = true,
  GlobalKey? over,
}) {
  return Navigator.of(context, rootNavigator: rootNavigator).push(
    MadarTopCardRoute<T>(
      builder: builder,
      barrierResult: barrierResult,
      padding: padding,
      maxWidth: maxWidth,
      over: over,
    ),
  );
}

/// The route behind [showMadarTopCard].
class MadarTopCardRoute<T> extends ModalRoute<T> {
  /// Creates the route. Prefer [showMadarTopCard].
  MadarTopCardRoute({
    required this.builder,
    required this.barrierResult,
    this.padding = EdgeInsets.zero,
    this.maxWidth = 600,
    this.over,
  });

  /// Builds the card.
  final WidgetBuilder builder;

  /// What a tap outside the card (or system back) resolves with.
  final T barrierResult;

  /// Inset of the card from the safe area's top/start/end.
  final EdgeInsetsGeometry padding;

  /// Width cap of the card.
  final double maxWidth;

  /// The region to centre the card over; null centres it on the window.
  final GlobalKey? over;

  @override
  Color? get barrierColor => null;

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

  /// The card leaves on its own springs BEFORE the pop; there is no dim to
  /// fade after it.
  @override
  Duration get reverseTransitionDuration => Duration.zero;

  /// No barrier at all: the page behind keeps its taps (see [_TopCardPage]).
  @override
  Widget buildModalBarrier() => const SizedBox.shrink();

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _TopCardPage<T>(route: this);
}

class _TopCardPage<T> extends StatefulWidget {
  const _TopCardPage({required this.route});

  final MadarTopCardRoute<T> route;

  @override
  State<_TopCardPage<T>> createState() => _TopCardPageState<T>();
}

class _TopCardPageState<T> extends State<_TopCardPage<T>>
    with SingleTickerProviderStateMixin
    implements DismissibleSurface {
  /// The card: in on push, out before the pop.
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: MotionSpec.standardDuration,
  );
  final GlobalKey _cardKey = GlobalKey();
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _anim.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: the card is simply there.
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced && !_leaving) _anim.value = 1;
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  void dismissWith(Object? result) => unawaited(_dismiss(result as T?));

  Future<void> _dismiss(T? result) async {
    if (_leaving) return;
    _leaving = true;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      _anim.value = 0;
    } else {
      await _anim.reverse();
    }
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (widget.route.isCurrent) {
      navigator.pop(result);
    } else {
      navigator.removeRoute(widget.route, result);
    }
  }

  /// A pointer down outside the card: put it away. The listener is
  /// translucent, so the same pointer carries on to what lies beneath.
  void _onPointerDown(PointerDownEvent event) {
    if (_leaving || !widget.route.isCurrent) return;
    final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final local = box.globalToLocal(event.position);
      if (box.paintBounds.contains(local)) return;
    }
    unawaited(_dismiss(widget.route.barrierResult));
  }

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: MotionSpec.springOut));
    final card = SlideTransition(
      position: slide,
      child: FadeTransition(
        opacity: _anim,
        child: Material(
          key: _cardKey,
          type: MaterialType.transparency,
          child: Builder(builder: widget.route.builder),
        ),
      ),
    );
    final over = widget.route.over;
    return PopScope<T>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_dismiss(result ?? widget.route.barrierResult));
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        child: over == null
            ? SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: widget.route.padding,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: widget.route.maxWidth,
                      ),
                      child: card,
                    ),
                  ),
                ),
              )
            : _OverRegion(
                region: over,
                insets:
                    MediaQuery.paddingOf(context) +
                    widget.route.padding.resolve(Directionality.of(context)),
                maxWidth: widget.route.maxWidth,
                child: card,
              ),
      ),
    );
  }
}

/// Lays the card at the top, centred over [region] — a box on the page
/// underneath — and kept inside [insets].
///
/// The region is read while THIS widget lays out (a [LayoutBuilder]'s
/// callback, where reading another box's geometry is allowed): the page
/// underneath is an earlier entry of the same overlay and is laid out
/// first, so a rotation moves the card with the panel in the same frame.
class _OverRegion extends StatelessWidget {
  const _OverRegion({
    required this.region,
    required this.insets,
    required this.maxWidth,
    required this.child,
  });

  final GlobalKey region;
  final EdgeInsets insets;
  final double maxWidth;
  final Widget child;

  /// The region's horizontal centre in [target]'s coordinates, or null when
  /// it is not on screen (the card then centres on the window).
  double? _centreIn(RenderObject? target) {
    final box = region.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    if (target == null || !target.attached) return null;
    final transform = box.getTransformTo(target);
    // A zero matrix: the two are not in one tree after all.
    if (transform.determinant() == 0) return null;
    return MatrixUtils.transformRect(
      transform,
      Offset.zero & box.size,
    ).center.dx;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, _) => CustomSingleChildLayout(
      delegate: _OverRegionLayout(
        centre: _centreIn(context.findRenderObject()),
        insets: insets,
        maxWidth: maxWidth,
      ),
      child: child,
    ),
  );
}

class _OverRegionLayout extends SingleChildLayoutDelegate {
  const _OverRegionLayout({
    required this.centre,
    required this.insets,
    required this.maxWidth,
  });

  final double? centre;
  final EdgeInsets insets;
  final double maxWidth;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(
          0,
          math.min(maxWidth, constraints.maxWidth - insets.horizontal),
        ),
        maxHeight: math.max(0, constraints.maxHeight - insets.vertical),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final lo = insets.left;
    final hi = size.width - insets.right;
    final at = centre ?? (lo + hi) / 2;
    final x = (at - childSize.width / 2)
        .clamp(lo, math.max(lo, hi - childSize.width))
        .toDouble();
    return Offset(x, insets.top);
  }

  @override
  bool shouldRelayout(_OverRegionLayout oldDelegate) =>
      centre != oldDelegate.centre ||
      insets != oldDelegate.insets ||
      maxWidth != oldDelegate.maxWidth;
}
