/// The seams the app (real mode) or the test harness (mock mode) fills in,
/// and the services built on them.
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' show ApiTransport;
import 'package:dashboard_core/src/data/core_api.dart';
import 'package:dashboard_core/src/gateways/export.dart';
import 'package:dashboard_core/src/gateways/files.dart';
import 'package:dashboard_core/src/gateways/realtime.dart';
import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:dashboard_core/src/scope/scope.dart';
import 'package:dashboard_core/src/session/session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every API call's transport: `CoreTransport` in the app, the
/// `MockServer` in tests and mock mode.
final transportProvider = Provider<ApiTransport>(
  (ref) => throw StateError('transportProvider must be overridden at boot'),
);

/// The calls dashboard_core makes for itself (session, authz, scope).
final coreApiProvider = Provider<CoreApi>(
  (ref) => CoreApi(ref.watch(transportProvider)),
);

/// `exportToExcel` / `exportToCsv` in the active language and zone.
final exporterProvider = Provider<DashExporter>(
  (ref) => DashExporter(
    exports: ref.watch(exportGatewayProvider),
    files: ref.watch(fileGatewayProvider),
    format: ref.watch(formatProvider),
    t: ref.watch(tProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Where realtime events land. One per app.
final realtimeBusProvider = Provider<RealtimeBus>((ref) {
  final bus = RealtimeBus();
  ref.onDispose(() => unawaited(bus.dispose()));
  return bus;
});

/// The one connection, for the selected branch (`useBranchRealtime`). The
/// shell watches this once; it reconnects only when the branch changes.
/// Null when no single branch is selected.
final branchRealtimeProvider = Provider<BranchRealtime?>((ref) {
  final session = ref.watch(currentSessionProvider);
  final branchId = ref.watch(scopeProvider.select((s) => s.branchId));
  if (session == null || branchId == null) return null;
  final rt = BranchRealtime(
    gateway: ref.watch(realtimeGatewayProvider),
    branchId: branchId,
    bus: ref.watch(realtimeBusProvider),
  )..start();
  ref.onDispose(rt.stop);
  return rt;
});

/// Bumps whenever a realtime event makes data read from [path] stale (the
/// web's prefix invalidation). A provider that reads `/floor/sections`
/// watches `realtimeEpochProvider('/floor/sections')` and refetches.
class RealtimeEpoch extends Notifier<int> {
  RealtimeEpoch(this.path);

  final String path;

  @override
  int build() {
    final sub = ref.watch(realtimeBusProvider).invalidations.listen((prefixes) {
      if (prefixes.any((p) => pathInvalidatedBy(path, p))) state = state + 1;
    });
    ref.onDispose(sub.cancel);
    return 0;
  }
}

final realtimeEpochProvider =
    NotifierProvider.family<RealtimeEpoch, int, String>(RealtimeEpoch.new);

/// Raw events, for the rare page that needs them (`onRealtimeEvent`).
final realtimeEventsProvider = StreamProvider<RealtimeFrame>(
  (ref) => ref.watch(realtimeBusProvider).events,
);
