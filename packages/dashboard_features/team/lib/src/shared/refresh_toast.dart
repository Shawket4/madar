/// TEAM-ALL-022 (`data/api/query.ts:22-39`): when a team read fails to
/// refresh while its last data is on screen (a focus refetch, the Refresh
/// button, the Team board's poll, an invalidation), one error toast says so,
/// deduplicated by kind (`dawam-refresh-429` for a 429, `dawam-refresh-failed`
/// otherwise) so repeated failures replace each other instead of stacking.
/// A read that fails with no data shows no toast: its error state says it.
library;

import 'package:dashboard_api/dashboard_api.dart' show ApiException;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

/// Listens to [read] (call from a page's `build`) and toasts a failed
/// background refresh.
void listenStaffRefreshFailure<T>(
  WidgetRef ref,
  BuildContext context,
  ProviderListenable<AsyncValue<T>> read,
) {
  ref.listen<AsyncValue<T>>(read, (prev, next) {
    if (!next.hasError || !next.hasValue) return;
    if (prev != null && prev.hasError && identical(prev.error, next.error)) {
      return;
    }
    if (!context.mounted) return;
    showStaffRefreshFailure(context, ref.read(tProvider), next.error);
  });
}

final Map<String, (DashToastHandle, DateTime)> _shown = {};

/// The toast id of a failed refresh (`dawam-refresh-429` / `-failed`).
String staffRefreshToastId(Object? error) =>
    error is ApiException && error.status == 429
    ? 'dawam-refresh-429'
    : 'dawam-refresh-failed';

/// Shows the failed-refresh toast, replacing a live one of the same kind.
void showStaffRefreshFailure(
  BuildContext context,
  Translator t,
  Object? error,
) {
  final id = staffRefreshToastId(error);
  final now = DateTime.now();
  final prev = _shown.remove(id);
  // Only a toast still on screen is replaced (an expired one is gone).
  if (prev != null && now.difference(prev.$2) < DashToast.duration) {
    prev.$1.dismiss();
  }
  _shown[id] = (DashToast.error(context, errorMessage(error, t)), now);
}
