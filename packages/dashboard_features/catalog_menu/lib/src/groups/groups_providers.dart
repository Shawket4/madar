/// The reads of the choice-groups unit (the web's `use-group-usage.ts` and
/// the usage dialog's `useListMenuItems`), each watching its API path so the
/// web's prefix invalidations refetch it. The group lists themselves are the
/// shared `modifierGroupsProvider`.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/menu_queries.dart';

/// `GET /modifier-groups/{gid}/usage`: the items offering a group (one read
/// per group, inactive items included).
final groupUsageProvider = FutureProvider.autoDispose
    .family<List<GroupUsageItem>, String>((ref, gid) {
      watchMenuPath(ref, MenuPaths.groupUsage(gid));
      return ref.watch(apiProvider).menu.getGroupUsage(gid: gid);
    });

/// `GET /menu-items/{id}` (`getMenuItem`).
final groupMenuItemProvider = FutureProvider.autoDispose
    .family<MenuItemFull, String>((ref, id) {
      watchMenuPath(ref, MenuPaths.menuItem(id));
      return ref.watch(apiProvider).menu.getMenuItem(id: id);
    });

/// `GET /menu-items?org_id`: every item of the org (the usage dialog).
final groupOrgItemsProvider = FutureProvider.autoDispose
    .family<List<MenuItem>, String>((ref, orgId) {
      watchMenuPath(ref, MenuPaths.menuItems);
      return ref.watch(apiProvider).menu.listMenuItems(orgId: orgId);
    });

/// `useGroupSizeLabels`: the distinct size labels (Cup, Can…) of the items a
/// group is attached to — the per-size columns its options offer. Empty
/// until the reads land.
final groupSizeLabelsProvider = Provider.autoDispose
    .family<List<String>, String>((ref, gid) {
      final usage = ref.watch(groupUsageProvider(gid)).value ?? const [];
      final labels = <String>{};
      for (final u in usage) {
        final item = ref.watch(groupMenuItemProvider(u.itemId)).value;
        for (final s in item?.sizes ?? const <ItemSize>[]) {
          if (s.label.isNotEmpty) labels.add(s.label);
        }
      }
      return labels.toList();
    });
