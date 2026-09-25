/// THE way the app tells the person something happened — one toast, drawn
/// once, above everything.
///
/// Screens used to keep a toast each (`OrderState.toast`, `TillState.toast`,
/// the queue's, the history's, the kitchen board's…) and draw it on their own
/// page. Two things went wrong with that, both silently:
///
/// - The order, cart, floor and bill screens lost the only widgets that drew
///   theirs when the legacy order screen was deleted (944b5fd5). "Being
///   edited on another till", "This bill was closed on another till", a
///   refused round: set, and drawn by nothing, for two weeks.
/// - A page draws its toast only while it is in front. A notice raised while
///   the Till tab was hidden, or under a pushed page or a sheet, was drawn
///   where nobody could see it — and a notice the core hands over once is
///   then gone.
///
/// So nothing keeps a toast any more. Anything that has something to say —
/// a notifier through its `Ref`, a widget through its `WidgetRef` — calls
/// `ref.read(appToastProvider.notifier).show(…)`, and [AppToastHost], mounted
/// ONCE above the navigator ([AppToastLayer], in the app's
/// `MaterialApp.builder`), draws it over whatever is in front: any tab, any
/// pushed page, any sheet or dialog, the sign-in screen and the kitchen
/// board. A screen cannot forget to listen, because no screen listens.
///
/// `apps/madar/test/message_routing_test.dart` pins it: this file is the only
/// place a `ToastData` is built or a `ToastHost` drawn.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The toast on screen, or null. Its action (Undo, View) lives here beside
/// it rather than in the payload, the way the kit's [ToastData] expects.
class AppToastNotifier extends Notifier<ToastData?> {
  VoidCallback? _action;
  int _seq = 0;

  @override
  ToastData? build() => null;

  /// Say [text] over whatever is in front, replacing whatever was said
  /// before. [action] runs when [actionLabel] is tapped (a label with no
  /// action is not drawn: a tap that does nothing is its own silent failure).
  ///
  /// A [sticky] toast stays until [dismiss]ed; the rest leave on their own
  /// after [seconds]. Returns this toast's id, so the one who raised it can
  /// take down THIS toast and never a later one.
  int show(
    String text, {
    ChipTone tone = ChipTone.neutral,
    String? icon,
    String? actionLabel,
    VoidCallback? action,
    double seconds = 2.6,
    bool sticky = false,
  }) {
    _seq += 1;
    _action = action;
    state = ToastData(
      id: _seq,
      text: text,
      tone: tone,
      icon: icon,
      actionLabel: action == null ? null : actionLabel,
      seconds: seconds,
      sticky: sticky,
    );
    return _seq;
  }

  /// Take down toast [id] if it is still the one on screen.
  void dismiss(int id) {
    if (state?.id != id) return;
    _action = null;
    state = null;
  }

  /// The action label was tapped: the toast goes, then its action runs.
  void runAction() {
    final action = _action;
    _action = null;
    state = null;
    action?.call();
  }
}

/// The one toast the app shows. See the library doc.
final appToastProvider = NotifierProvider<AppToastNotifier, ToastData?>(
  AppToastNotifier.new,
);

/// Draws [appToastProvider] — THE toast host. Mounted once, by
/// [AppToastLayer]; nothing else in the app draws a toast.
class AppToastHost extends ConsumerWidget {
  const AppToastHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toast = ref.watch(appToastProvider);
    final notifier = ref.read(appToastProvider.notifier);
    // A live region: a screen reader says the toast as it appears, so the
    // message is not silent for someone who cannot see it either.
    return Semantics(
      liveRegion: true,
      child: ToastHost(
        toast,
        onAction: notifier.runAction,
        onDismiss: notifier.dismiss,
      ),
    );
  }
}

/// [child] (the app's navigator) with [AppToastHost] over it. Put it in
/// `MaterialApp.builder`, ABOVE the navigator: the toast then shows over
/// every route, sheet and dialog the navigator will ever hold.
class AppToastLayer extends StatelessWidget {
  const AppToastLayer({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        const Positioned.fill(child: AppToastHost()),
      ],
    );
  }
}
