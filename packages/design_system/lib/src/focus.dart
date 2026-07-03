import 'package:flutter/widgets.dart';

/// Requests focus only AFTER the enclosing route's entrance transition (a
/// bottom sheet sliding up, a page pushing in) has finished.
///
/// `autofocus: true` summons the keyboard while the route is still animating
/// in. On iPad that races the route transition and corrupts the shared text
/// input connection: the keyboard flashes up (often as the tiny/floating
/// keyboard) then dismisses, the field loses focus, and because the connection
/// is now wedged, EVERY later tap — on that field or any other — does nothing.
/// Deferring the focus request until the route settles avoids the race.
///
/// Use instead of `autofocus: true`:
/// ```dart
/// class _MyState extends State<MyWidget> with EntranceFocus<MyWidget> {
///   final _focus = FocusNode();
///   @override
///   void initState() {
///     super.initState();
///     if (widget.autofocus) focusAfterEntrance(_focus);
///   }
/// }
/// ```
mixin EntranceFocus<T extends StatefulWidget> on State<T> {
  /// Focuses [node] once the current route's entrance animation completes
  /// (immediately if there is no animation or it has already settled).
  void focusAfterEntrance(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final animation = ModalRoute.of(context)?.animation;
      // No route animation (or already settled) — safe to focus now.
      if (animation == null || animation.isCompleted) {
        node.requestFocus();
        return;
      }
      void onStatus(AnimationStatus status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          animation.removeStatusListener(onStatus);
          if (mounted && status == AnimationStatus.completed) {
            node.requestFocus();
          }
        }
      }

      animation.addStatusListener(onStatus);
    });
  }
}
