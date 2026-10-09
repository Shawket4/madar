/// TEAM-ALL-022's failed-refresh toast for one read, subscribed ONCE.
///
/// `listenStaffRefreshFailure` calls `ref.listen` in build, which Riverpod
/// re-subscribes on every rebuild, and `webCache()` refetches a stale read on
/// every new listener: a rebuild 30 s after the last answer (a toggle, a
/// keystroke in the coverage grid) would refetch it. The web refetches only
/// on focus, and the coverage editor not even then (TEAM-ALL-009).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../shared/refresh_toast.dart';

class ScheduleRefreshListener<T> extends ConsumerStatefulWidget {
  const ScheduleRefreshListener({
    required this.read,
    required this.child,
    this.onAnswer,
    super.key,
  });

  /// Null: nothing to listen to (the read is off).
  final ProviderListenable<AsyncValue<T>>? read;

  /// A fresh answer landed.
  final VoidCallback? onAnswer;
  final Widget child;

  @override
  ConsumerState<ScheduleRefreshListener<T>> createState() =>
      _ScheduleRefreshListenerState<T>();
}

class _ScheduleRefreshListenerState<T>
    extends ConsumerState<ScheduleRefreshListener<T>> {
  ProviderSubscription<AsyncValue<T>>? _sub;

  void _listen() {
    _sub?.close();
    _sub = null;
    final read = widget.read;
    if (read == null) return;
    _sub = ref.listenManual<AsyncValue<T>>(read, (prev, next) {
      if (next.hasValue && !next.isLoading) widget.onAnswer?.call();
      if (!next.hasError || !next.hasValue) return;
      if (prev != null && prev.hasError && identical(prev.error, next.error)) {
        return;
      }
      if (mounted) {
        showStaffRefreshFailure(context, ref.read(tProvider), next.error);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(ScheduleRefreshListener<T> old) {
    super.didUpdateWidget(old);
    if (old.read != widget.read) _listen();
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
