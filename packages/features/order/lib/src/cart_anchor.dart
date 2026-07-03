import 'package:flutter/widgets.dart';

// The add-to-cart flight's shared plumbing: one anchor per cart affordance
// (the wide panel header vs the narrow bottom bar), the landing tick the
// anchors listen to for their catch dip, and the resolver the launch sites
// use to pick whichever anchor is actually on screen.

/// Anchors the wide layout's cart-panel header (title + count) — the
/// add-to-cart flight lands here when the cart column is visible.
final GlobalKey cartPanelAnchor = GlobalKey(debugLabel: 'cartPanelAnchor');

/// Anchors the narrow layout's bottom cart bar count — the flight's landing
/// pad when the cart is collapsed into the bar.
final GlobalKey cartBarAnchor = GlobalKey(debugLabel: 'cartBarAnchor');

/// Bumped once per flight landing; the mounted anchor wraps itself in a
/// dip so the cart visibly "catches" the flown dot.
final ValueNotifier<int> cartCatchTick = ValueNotifier<int>(0);

/// The global center of whichever cart anchor is currently mounted — the
/// wide panel first, else the narrow bar — or null when neither is laid
/// out (callers skip the flight then).
Offset? cartAnchorCenter() {
  for (final key in <GlobalKey>[cartPanelAnchor, cartBarAnchor]) {
    final render = key.currentContext?.findRenderObject();
    if (render is RenderBox && render.attached && render.hasSize) {
      return render.localToGlobal(render.size.center(Offset.zero));
    }
  }
  return null;
}
