/// A page's "leave?" (the web's `useBlocker` and unsaved-changes prompt):
/// while a [DashLeaveGuard] says there is something to lose, leaving its page
/// asks first, whichever way the person goes: the sidebar, the palette, the
/// header's links and any other in-app link (every page route's `onExit`),
/// and a back/pop (`PopScope`). Signing out never asks.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The open pages' prompts, by the page's route key; the router asks the one
/// of the page being left.
class DashLeaveGuards {
  final Map<LocalKey, FutureOr<bool> Function()> _asks = {};

  /// Whether the page with [pageKey] may be left: true at once without a
  /// guard (the navigation stays synchronous), else its prompt's answer.
  FutureOr<bool> leave(LocalKey pageKey) => _asks[pageKey]?.call() ?? true;
}

final dashLeaveGuardsProvider = Provider<DashLeaveGuards>(
  (_) => DashLeaveGuards(),
);

/// Asks [ask] before its page is left while [when] is true.
///
/// ```dart
/// DashLeaveGuard(when: _dirty, ask: _confirmLeave, child: editor)
/// ```
class DashLeaveGuard extends ConsumerStatefulWidget {
  const DashLeaveGuard({
    required this.when,
    required this.ask,
    required this.child,
    super.key,
  });

  /// Whether leaving would lose something (unsaved changes).
  final ValueListenable<bool> when;

  /// The prompt; true leaves.
  final Future<bool> Function() ask;

  final Widget child;

  @override
  ConsumerState<DashLeaveGuard> createState() => _DashLeaveGuardState();
}

class _DashLeaveGuardState extends ConsumerState<DashLeaveGuard> {
  late final DashLeaveGuards _guards = ref.read(dashLeaveGuardsProvider);
  LocalKey? _page;

  /// A pop the person agreed to is let through.
  bool _released = false;

  FutureOr<bool> _leave() => widget.when.value ? widget.ask() : true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    LocalKey? page;
    try {
      page = GoRouterState.of(context).pageKey;
    } on GoError {
      page = null; // not under the router (a page pumped alone): pop only
    }
    if (page == _page) return;
    _unregister();
    _page = page;
    if (page != null) _guards._asks[page] = _leave;
  }

  void _unregister() {
    if (_page != null && _guards._asks[_page] == _leave) {
      _guards._asks.remove(_page);
    }
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: widget.when,
    builder: (context, dirty, child) => PopScope(
      canPop: !dirty || _released,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (!await widget.ask() || !mounted) return;
        setState(() => _released = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          nav.maybePop();
          if (mounted) _released = false;
        });
      },
      child: child!,
    ),
    child: widget.child,
  );
}
