/// The menu items left out of Items Sold, per org on this device: one
/// setting shared by the Orders page's Items Sold KPI and the Operations
/// report's (`components/app/exclude-items-control.tsx`,
/// `madar.excluded-line-items.<orgId>`).
library;

import 'package:dashboard_core/src/gateways/preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The device setting's key.
String excludedItemsPrefKey(String orgId) => 'madar.excluded-line-items.$orgId';

/// The excluded menu item ids for [orgId]. Read again whenever a page
/// mounts or the org changes; nothing is saved without an org.
class ExcludedItems extends Notifier<List<String>> {
  ExcludedItems(this.orgId);

  final String? orgId;

  @override
  List<String> build() {
    final org = orgId;
    if (org == null) return const [];
    final raw = ref.read(preferencesProvider).getJson(excludedItemsPrefKey(org));
    return raw is List ? [for (final v in raw) '$v'] : const [];
  }

  void set(List<String> ids) {
    state = List.unmodifiable(ids);
    final org = orgId;
    if (org != null) {
      ref.read(preferencesProvider).setJson(excludedItemsPrefKey(org), ids);
    }
  }

  void toggle(String id) => set(toggledIds(state, id));
}

/// [ids] with [id] taken out, or added at the end.
List<String> toggledIds(List<String> ids, String id) =>
    ids.contains(id) ? [...ids.where((x) => x != id)] : [...ids, id];

final excludedItemsProvider = NotifierProvider.autoDispose
    .family<ExcludedItems, List<String>, String?>(ExcludedItems.new);

/// `excludeItemsParam`: the comma list, or null when nothing is excluded.
String? excludeItemsParam(List<String> ids) =>
    ids.isEmpty ? null : ids.join(',');
