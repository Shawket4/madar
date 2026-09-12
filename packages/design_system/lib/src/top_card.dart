import 'dart:async';

import 'package:design_system/src/scrim.dart';
import 'package:design_system/src/sheet.dart';
import 'package:design_system/src/tokens/motion.dart';
import 'package:flutter/material.dart';

/// Presents [builder] as a card that slides down from the top of the window
/// — the post-sale Done card — as a real route in the kit's surface stack.
///
/// Being a route (not an overlay entry) is the point: a sheet the card opens
/// ("Add points") is pushed ABOVE it and dims it through the shared scrim,
/// instead of rendering underneath a floating overlay that a stray tap would
/// tear down together with the sheet.
///
/// It paints the shared dim (scrim.dart) and dismisses through its own
/// barrier: a tap outside the card pops [barrierResult]. System back does the
/// same. From the content, close it with `MadarSheet.close(context, result)`
/// so it always animates out.
Future<T?> showMadarTopCard<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  required T barrierResult,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
  double maxWidth = 600,
  bool rootNavigator = true,
}) {
  return Navigator.of(context, rootNavigator: rootNavigator).push(
    MadarTopCardRoute<T>(
      builder: builder,
      barrierResult: barrierResult,
      padding: padding,
      maxWidth: maxWidth,
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
  });

  /// Builds the card.
  final WidgetBuilder builder;

  /// What a tap outside the card (or system back) resolves with.
  final T barrierResult;

  /// Inset of the card from the safe area's top/start/end.
  final EdgeInsetsGeometry padding;

  /// Width cap of the card.
  final double maxWidth;

  /// The card's stake in the shared dim.
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
  ) => _TopCardPage<T>(route: this);
}

class _TopCardPage<T> extends StatefulWidget {
  const _TopCardPage({required this.route});

  final MadarTopCardRoute<T> route;

  @override
  State<_TopCardPage<T>> createState() => _TopCardPageState<T>();
}

class _TopCardPageState<T> extends State<_TopCardPage<T>>
    with TickerProviderStateMixin
    implements DismissibleSurface {
  /// The card: in on push, out before the pop.
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: MotionSpec.standardDuration,
  );

  /// The dim: rises with the card and HOLDS while the card slides away; the
  /// route's exit fade takes it out after the pop (see
  /// [MadarTopCardRoute.reverseTransitionDuration]).
  late final AnimationController _dimIn = AnimationController(
    vsync: this,
    duration: MotionSpec.standardDuration,
  );
  late final CurvedAnimation _dimCurve = CurvedAnimation(
    parent: _dimIn,
    curve: MotionSpec.standardCurve,
  );
  late final CurvedAnimation _routeFade = CurvedAnimation(
    parent: widget.route.animation!,
    curve: MotionSpec.standardCurve,
  );
  late final Animation<double> _scrimVisible = AnimationMin<double>(
    _dimCurve,
    _routeFade,
  );
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    final claim = widget.route.scrimClaim
      ..visibleOpacity = () => _scrimVisible.value;
    _dimIn.value = claim.startOpacity;
    _dimIn.forward();
    _anim.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: the card is simply there.
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced && !_leaving) {
      _anim.value = 1;
      _dimIn.value = 1;
    }
  }

  @override
  void dispose() {
    _routeFade.dispose();
    _dimCurve.dispose();
    _dimIn.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  void dismissWith(Object? result) => unawaited(_dismiss(result as T?));

  Future<void> _dismiss(T? result) async {
    if (_leaving) return;
    _leaving = true;
    widget.route.scrimClaim.release();
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

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: MotionSpec.springOut));
    final dismissLabel = Localizations.of<MaterialLocalizations>(
      context,
      MaterialLocalizations,
    )?.modalBarrierDismissLabel;
    return PopScope<T>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_dismiss(result ?? widget.route.barrierResult));
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(_dismiss(widget.route.barrierResult)),
              child: Semantics(
                label: dismissLabel,
                button: true,
                child: StackScrim(
                  claim: widget.route.scrimClaim,
                  opacity: _scrimVisible,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: widget.route.padding,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: widget.route.maxWidth),
                  child: SlideTransition(
                    position: slide,
                    child: FadeTransition(
                      opacity: _anim,
                      child: Material(
                        type: MaterialType.transparency,
                        child: Builder(builder: widget.route.builder),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
