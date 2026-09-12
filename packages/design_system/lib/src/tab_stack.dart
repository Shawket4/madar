/// Pages live INSIDE the shell. Each tab owns a nested [Navigator], so a
/// page pushed from a tab (a bill, the close-shift count, Settings) renders in
/// the content area with the rail, the top bar and the phone's tab bar still
/// standing around it — the one page shell, on every screen.
///
/// The split between the two navigators is a rule, not a per-call guess:
///
/// * **Pages** go on the tab's navigator: [MadarPages.navigatorOf].
/// * **Surfaces** — sheets, the drawer, modals, the Done card — go on the
///   ROOT navigator, so they overlay the whole window under the one shared
///   scrim. A surface closes its own route (see `sheet.dart`), so a page
///   pushed on the tab in the same tap is never what a close takes down.
///
/// A page pushed from inside a surface (a sheet's "Open bill") belongs to the
/// tab the surface was opened over; [MadarPages.navigatorOf] finds that tab
/// even though the surface itself sits on the root navigator.
library;

import 'package:flutter/material.dart';

/// Where pages are pushed.
abstract final class MadarPages {
  /// The tab stack in front of the person, if a shell is mounted.
  static GlobalKey<NavigatorState>? _active;

  /// The navigator a PAGE pushed from [context] belongs on: the tab stack
  /// [context] sits in; from a root surface (a sheet) or from the shell's own
  /// chrome, the tab stack in front; with no shell mounted, the nearest
  /// navigator.
  static NavigatorState navigatorOf(BuildContext context) {
    if (context.getInheritedWidgetOfExactType<_TabStackScope>() != null) {
      return Navigator.of(context);
    }
    return _active?.currentState ?? Navigator.of(context);
  }

  /// Push [page] as a page — see [navigatorOf].
  static Future<T?> push<T>(BuildContext context, WidgetBuilder page) =>
      navigatorOf(context).push(MaterialPageRoute<T>(builder: page));

  /// Whether the tab [context] sits in is the one in front. Registers a
  /// dependency, so a page rebuilds (and `didChangeDependencies` runs) when
  /// its tab is shown or hidden. True outside any tab stack.
  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TabStackScope>()?.active ??
      true;
}

/// One tab's page stack: a nested [Navigator] whose first route is [child].
///
/// Hidden tabs keep their stacks; [active] marks the one in front, which is
/// where [MadarPages.navigatorOf] sends pages pushed from outside any tab.
/// [onStackChanged] fires after every push, pop or removal, so the shell can
/// keep system back pointed at the right stack.
class MadarTabStack extends StatefulWidget {
  /// Creates a tab stack.
  const MadarTabStack({
    required this.navigatorKey,
    required this.active,
    required this.child,
    this.onStackChanged,
    super.key,
  });

  /// The nested navigator's key — the shell pops it to root on a re-tap.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Whether this tab is the one in front.
  final bool active;

  /// The tab's body, the stack's first route.
  final Widget child;

  /// Called after the stack changed.
  final VoidCallback? onStackChanged;

  @override
  State<MadarTabStack> createState() => _MadarTabStackState();
}

class _MadarTabStackState extends State<MadarTabStack> {
  late final _observer = _StackObserver(() => widget.onStackChanged?.call());

  @override
  void initState() {
    super.initState();
    if (widget.active) MadarPages._active = widget.navigatorKey;
  }

  @override
  void didUpdateWidget(MadarTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active) {
      MadarPages._active = widget.navigatorKey;
    } else if (MadarPages._active == oldWidget.navigatorKey) {
      MadarPages._active = null;
    }
  }

  @override
  void dispose() {
    if (MadarPages._active == widget.navigatorKey) MadarPages._active = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _TabStackScope(
      active: widget.active,
      child: Navigator(
        key: widget.navigatorKey,
        observers: [_observer],
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => widget.child,
        ),
      ),
    );
  }
}

class _TabStackScope extends InheritedWidget {
  const _TabStackScope({required this.active, required super.child});

  final bool active;

  @override
  bool updateShouldNotify(_TabStackScope oldWidget) =>
      active != oldWidget.active;
}

class _StackObserver extends NavigatorObserver {
  _StackObserver(this.changed);

  final VoidCallback changed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      changed();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => changed();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      changed();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      changed();
}
