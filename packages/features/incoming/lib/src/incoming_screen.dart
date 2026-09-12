/// The app's existing entry to this surface. The shell pushes
/// `IncomingScreen()` from its rail and from the sticky new-order toast's
/// *View*; that name and its `initialTab` keep working so the app compiles
/// unchanged while the shells migrate to `QueueScreen` directly.
library;

import 'package:feature_incoming/src/incoming_provider.dart';
import 'package:feature_incoming/src/queue_screen.dart';
import 'package:flutter/widgets.dart';

class IncomingScreen extends StatelessWidget {
  const IncomingScreen({super.key, this.initialTab = 0});

  /// The old tab index the natives' alerts steer by: 0 = the online orders
  /// (what a new-order ping is about), 1 = the bills.
  final int initialTab;

  @override
  Widget build(BuildContext context) => QueueScreen(
    initialSegment: initialTab == 0 ? QueueSegment.online : QueueSegment.bills,
  );
}
