/// The builder's reads (the web's `features/branch-builder/api.ts`).
///
/// - [branchPlanProvider]: `GET /branch-plan?branch_id=` (getPlan). A
///   notifier, so a save can write its answer into the cache as the web's
///   `setQueryData` does, without a second read.
/// - [planVersionsProvider]: `GET /branch-plan/versions?branch_id=`
///   (listVersions), watched only while the History menu is open.
///
/// Both refetch on `branch.plan_changed` (the core maps it to
/// `/branch-plan`); a save invalidates the versions and every `/kitchen*`
/// read, and a setup code every `/devices*` read.
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract final class BranchPlanPaths {
  static const String plan = '/branch-plan';
  static const String versions = '/branch-plan/versions';
  static const String kitchen = '/kitchen';
  static const String devices = '/devices';
  static const String kitchenRouting = '/settings/kitchen-routing';
}

class BranchPlanNotifier extends AsyncNotifier<BranchPlanView> {
  BranchPlanNotifier(this.branchId);

  final String branchId;

  @override
  Future<BranchPlanView> build() {
    ref.webCache();
    ref.watch(realtimeEpochProvider(BranchPlanPaths.plan));
    return ref.watch(apiProvider).branchPlan.getPlan(branchId: branchId);
  }

  /// The saved plan the server answered with (the web's `setQueryData`).
  void write(BranchPlanView view) => state = AsyncData(view);
}

final branchPlanProvider = AsyncNotifierProvider.autoDispose
    .family<BranchPlanNotifier, BranchPlanView, String>(BranchPlanNotifier.new);

final planVersionsProvider = FutureProvider.autoDispose
    .family<List<PlanVersionView>, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(BranchPlanPaths.versions));
      return ref
          .watch(apiProvider)
          .branchPlan
          .listVersions(branchId: branchId);
    });

/// A device reports in at most every 5 minutes; twice that is still online.
const Duration kOnlineWithin = Duration(minutes: 10);

enum Presence { online, offline, unclaimed }

/// A slot's live state from the install filling it.
({Presence presence, PlanRegisteredDevice? seen}) presenceOf(
  String? deviceId,
  Map<String, PlanRegisteredDevice> registered,
  DateTime now,
) {
  final seen = deviceId == null ? null : registered[deviceId];
  if (seen == null) return (presence: Presence.unclaimed, seen: null);
  final online = now.difference(seen.lastSeenAt) <= kOnlineWithin;
  return (presence: online ? Presence.online : Presence.offline, seen: seen);
}

/// The registered install kind a slot takes: a kitchen screen runs the KDS.
String installKindFor(String kind) => kind == 'kitchen' ? 'kds' : kind;

final math.Random _random = math.Random.secure();

/// A new piece id (the web's `crypto.randomUUID()`).
String newPieceId() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
