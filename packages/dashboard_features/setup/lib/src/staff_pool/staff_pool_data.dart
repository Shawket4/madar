/// What the Staff drinks pane reads and works out in the browser
/// (`features/staff-pool/use-staff-pool.ts`, `form-schema.ts`).
///
/// The org row is the default every branch runs on; a branch row REPLACES it
/// wholesale. The API answers a branch query with the settings IN FORCE, so
/// "inherited" is told only by the `branch_id` that came back
/// (`isInheritedScope`).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show MenuItem, StaffPoolSettings;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract final class StaffPoolPaths {
  static const String settings = '/staff-pool/settings';
  static const String menuItems = '/menu-items';
}

/// `GET /staff-pool/settings[?branch_id]` (`useGetStaffPoolSettings`): the
/// settings in force for the header branch (null = the organisation's row).
final staffPoolSettingsProvider = FutureProvider.autoDispose
    .family<StaffPoolSettings, String?>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(StaffPoolPaths.settings));
      return ref
          .watch(apiProvider)
          .staffPool
          .getStaffPoolSettings(branchId: branchId);
    });

/// `GET /menu-items?org_id=` (`useListMenuItems({org_id})`): the picker's
/// list and the chips' names.
final staffPoolMenuProvider = FutureProvider.autoDispose
    .family<List<MenuItem>, String>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(StaffPoolPaths.menuItems));
      return ref.watch(apiProvider).menu.listMenuItems(orgId: orgId);
    });

/// `getTranslatedName`: the Arabic name in Arabic when there is one.
String staffPoolItemName(MenuItem m, String lang) {
  final ar = m.nameTranslations['ar'];
  return lang.startsWith('ar') && ar is String ? ar : m.name;
}

/// `dailyAllowance`: a whole count of drinks, 0 to 1000, as typed.
bool allowanceOk(String v) {
  final s = v.trim();
  if (!RegExp(r'^\d+$').hasMatch(s)) return false;
  final n = int.tryParse(s);
  return n != null && n <= 1000;
}

/// `poolIsOff`: switched off, or nothing a teller could ring up.
bool poolIsOff({required bool enabled, required List<String> itemIds}) =>
    !enabled || itemIds.isEmpty;

/// The form's values (`StaffPoolValues`). Equality is the web's `isDirty`.
@immutable
class StaffPoolForm {
  const StaffPoolForm({
    required this.enabled,
    required this.allowance,
    required this.itemIds,
  });

  /// `fromWire`: a missing allowance reads as 0, never as nothing.
  factory StaffPoolForm.from(StaffPoolSettings s) => StaffPoolForm(
    enabled: s.enabled ?? false,
    allowance: '${s.dailyAllowance ?? 0}',
    itemIds: [...?s.eligibleItemIds],
  );

  final bool enabled;
  final String allowance;
  final List<String> itemIds;

  StaffPoolForm copyWith({
    bool? enabled,
    String? allowance,
    List<String>? itemIds,
  }) => StaffPoolForm(
    enabled: enabled ?? this.enabled,
    allowance: allowance ?? this.allowance,
    itemIds: itemIds ?? this.itemIds,
  );

  /// `toWire`: the scope SAVED TO (never the answer's `branch_id`, which for
  /// a branch is the one in force), the allowance as a number, the items
  /// de-duplicated in their order.
  StaffPoolSettings toWire({required String orgId, String? branchId}) =>
      StaffPoolSettings(
        orgId: orgId,
        branchId: branchId,
        enabled: enabled,
        dailyAllowance: int.parse(allowance.trim()),
        eligibleItemIds: itemIds.toSet().toList(),
        explicitNulls: branchId == null ? const {'branch_id'} : const {},
      );

  @override
  bool operator ==(Object other) =>
      other is StaffPoolForm &&
      other.enabled == enabled &&
      other.allowance == allowance &&
      listEquals(other.itemIds, itemIds);

  @override
  int get hashCode => Object.hash(enabled, allowance, Object.hashAll(itemIds));
}
