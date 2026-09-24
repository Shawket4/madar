/// Pull to refresh: THE one gesture every list screen answers — the staff
/// app's tabs and list sheets, the POS boards. One widget, so the spinner,
/// its colours and what counts as a pull are the same everywhere.
///
/// The spinner is the kit's ring (`MadarSpinner` is a Material ring too), on
/// the raised surface, in the accent. A screen hands [MadarRefresh] the call
/// that brings its data up to date and the list it wraps; the ring stays up
/// until that call's future completes, so it never claims a refresh that is
/// still in flight.
///
/// A pull needs something to pull: a list shorter than the screen does not
/// scroll, so give it [MadarRefresh.physics]. A body that does not scroll at
/// all (a column whose calendar or board takes the rest of the height) goes
/// in [MadarPullable].
library;

import 'package:design_system/src/tokens/colors.dart';
import 'package:flutter/material.dart';

class MadarRefresh extends StatelessWidget {
  /// Creates a pull-to-refresh around [child].
  const MadarRefresh({
    required this.onRefresh,
    required this.child,
    this.nested = false,
    super.key,
  });

  /// Brings the data up to date. The spinner shows until it completes; it
  /// should not throw (say a failure in words, e.g. a toast).
  final Future<void> Function() onRefresh;

  /// The scrollable(s) the pull is read from.
  final Widget child;

  /// Answer a pull from ANY vertical scrollable under this one, not only the
  /// nearest: a shell that wraps whole tabs, whose lists sit at different
  /// depths (a calendar inside a pullable column, a two-pane tablet layout).
  /// Horizontal strips (chips, a week board's days) never pull.
  final bool nested;

  /// The physics a pullable list uses: it can always be dragged, so a pull
  /// works even when the content is shorter than the screen.
  static const ScrollPhysics physics = AlwaysScrollableScrollPhysics();

  static bool _vertical(ScrollNotification n) =>
      n.metrics.axis == Axis.vertical;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: c.accent,
      backgroundColor: c.surface,
      notificationPredicate: nested
          ? _vertical
          : defaultScrollNotificationPredicate,
      child: child,
    );
  }
}

/// A body that does not scroll by itself made pullable: [child] is laid out
/// at exactly the viewport's size (so its `Expanded` calendar or board keeps
/// working), and the viewport can still be dragged down for a pull.
class MadarPullable extends StatelessWidget {
  /// Creates a pullable, non-scrolling body.
  const MadarPullable({required this.child, super.key});

  /// The body, sized to the viewport.
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    physics: MadarRefresh.physics,
    slivers: [SliverFillRemaining(child: child)],
  );
}
