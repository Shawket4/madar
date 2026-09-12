import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';

// The add-to-cart flight's shared plumbing: one anchor per cart affordance
// (the wide panel header vs the narrow bottom bar), the landing tick the
// anchors listen to for their catch dip, and the resolver the launch sites
// use to pick whichever anchor is actually on screen.
//
// PER SCREEN, not global. `SellScreen.forTable` is pushed over the shell
// while the Sell tab stays mounted underneath; two carts sharing one
// GlobalKey throw "Duplicate GlobalKey", and even when they don't, the dot
// would fly to whichever cart registered last — maybe the hidden one. Each
// SellScreen owns a [CartAnchors] and provides it with [CartAnchorScope];
// the sheets it opens are wrapped in the same scope.

/// One screen's cart landing pads and catch tick.
class CartAnchors {
  /// Anchors the wide layout's cart-panel header — the add-to-cart flight
  /// lands here when the cart column is visible.
  final GlobalKey panel = GlobalKey(debugLabel: 'cartPanelAnchor');

  /// Anchors the narrow layout's bottom cart bar — the flight's landing pad
  /// when the cart is collapsed into the bar.
  final GlobalKey bar = GlobalKey(debugLabel: 'cartBarAnchor');

  /// Bumped once per flight landing; the mounted anchor wraps itself in a
  /// dip so the cart visibly "catches" the flown dot.
  final ValueNotifier<int> catchTick = ValueNotifier<int>(0);

  /// The global center of whichever anchor is currently mounted — the wide
  /// panel first, else the narrow bar — or null when neither is laid out
  /// (callers skip the flight then).
  Offset? center() {
    for (final key in <GlobalKey>[panel, bar]) {
      final render = key.currentContext?.findRenderObject();
      if (render is RenderBox && render.attached && render.hasSize) {
        return render.localToGlobal(render.size.center(Offset.zero));
      }
    }
    return null;
  }

  /// The nearest screen's anchors, or null outside any [CartAnchorScope]
  /// (a cart drawn with no flight to catch).
  static CartAnchors? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CartAnchorScope>()?.anchors;
}

/// Provides one screen's [CartAnchors] to the carts and sheets beneath it.
class CartAnchorScope extends InheritedWidget {
  /// Scopes [anchors] over [child].
  const CartAnchorScope({
    required this.anchors,
    required super.child,
    super.key,
  });

  /// The owning screen's anchors.
  final CartAnchors anchors;

  @override
  bool updateShouldNotify(CartAnchorScope oldWidget) =>
      !identical(anchors, oldWidget.anchors);
}

/// Wraps [child] as a flight landing pad of the nearest scope,
/// dipping when a dot arrives. Without a scope it is just [child].
class CartAnchorPad extends StatelessWidget {
  /// Marks [child] as the panel (or, with [bar], the bar) landing pad.
  const CartAnchorPad({required this.child, this.bar = false, super.key});

  /// The glyph the dot lands on.
  final Widget child;

  /// True for the narrow layout's bar, false for the panel header.
  final bool bar;

  @override
  Widget build(BuildContext context) {
    final anchors = CartAnchors.maybeOf(context);
    if (anchors == null) return child;
    return ValueListenableBuilder<int>(
      valueListenable: anchors.catchTick,
      builder: (context, tick, child) =>
          Nudge(trigger: tick, kind: NudgeKind.dip, child: child!),
      child: KeyedSubtree(key: bar ? anchors.bar : anchors.panel, child: child),
    );
  }
}
