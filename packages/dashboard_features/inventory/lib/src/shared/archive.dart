/// Archived ingredients (2026-10-18; web `archive.tsx`). An archived
/// ingredient leaves the pickers, the count sheets (once no branch holds
/// stock) and the reorder suggestions; recipes that use it keep deducting
/// it, and history keeps showing it with [ArchivedBadge]. The catalog read
/// (`GET …/catalog`, no `status`) still returns it with `archived_at`, so
/// name and cost lookups never go blank.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show ApiException, OrgIngredient;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart' show Space;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'inventory_data.dart';

/// The glyph of Archive and of the badge (the design system has no
/// `archive` glyph yet; this box-minus reads as "taken out of the shelf").
const String archiveGlyph = 'package-minus';

/// The glyph of Unarchive.
const String unarchiveGlyph = 'rotate-ccw';

/// Offered in a picker: active and not archived (`isPickable`).
bool isPickable(OrgIngredient c) => c.isActive && c.archivedAt == null;

/// [catalog] as a picker offers it, keeping whatever is already [chosen] so
/// a saved line that uses an archived ingredient still shows its name
/// (`pickableOrChosen`).
List<OrgIngredient> pickableOrChosen(
  Iterable<OrgIngredient> catalog, [
  Iterable<String?> chosen = const [],
]) {
  final keep = {for (final id in chosen) ?id};
  return [
    for (final c in catalog)
      if (isPickable(c) || keep.contains(c.id)) c,
  ];
}

/// The ids of the org's archived ingredients, from the shared catalog read
/// (`useArchivedIngredientIds`); empty while it loads.
final archivedIngredientIdsProvider = Provider.autoDispose
    .family<Set<String>, String>((ref, orgId) {
      final catalog = ref.watch(inventoryCatalogProvider(orgId)).value;
      return {
        for (final c in catalog ?? const <OrgIngredient>[])
          if (c.archivedAt != null) c.id,
      };
    });

/// The archived ids of the signed-in org (empty without one).
Set<String> watchArchivedIds(WidgetRef ref) {
  final orgId = ref.watch(orgIdProvider);
  return orgId == null
      ? const {}
      : ref.watch(archivedIngredientIdsProvider(orgId));
}

/// "Archived" beside an ingredient's name, wherever one shows.
class ArchivedBadge extends ConsumerWidget {
  const ArchivedBadge({this.small = true, super.key});

  final bool small;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DashStatusPill(
    key: const ValueKey('archived-badge'),
    label: ref.watch(tProvider)('inventory.archive.badge'),
    icon: archiveGlyph,
    small: small,
  );
}

/// [name] with [ArchivedBadge] after it when [archived]: a history row's
/// ingredient cell.
class NameWithArchived extends StatelessWidget {
  const NameWithArchived({
    required this.name,
    required this.archived,
    this.style,
    super.key,
  });

  final String name;
  final bool archived;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      name,
      textDirection: dashTextDirectionOf(name),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    if (!archived) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        Flexible(child: text),
        const ArchivedBadge(),
      ],
    );
  }
}

/// The archived ingredient a create or rename collided with (409
/// `INGREDIENT_NAME_ARCHIVED`), if [e] is that refusal.
String? archivedNameHolder(Object? e) {
  if (e is! ApiException || e.code != 'INGREDIENT_NAME_ARCHIVED') return null;
  final details = e.details;
  final vars = details is Map ? details['vars'] : null;
  final id = vars is Map ? vars['ingredient_id'] : null;
  return id is String ? id : null;
}

/// Unarchive [id], refresh every inventory read and say so ("{name} is
/// active again"); a refusal is toasted. True when it worked.
Future<bool> unarchiveIngredient(
  BuildContext context,
  WidgetRef ref, {
  required String orgId,
  required String id,
  required String name,
}) async {
  final t = ref.read(tProvider);
  final api = ref.read(apiProvider);
  final bus = ref.read(realtimeBusProvider);
  try {
    await api.inventory.unarchiveCatalogItem(orgId: orgId, id: id);
  } on Object catch (e) {
    if (context.mounted) DashToast.error(context, errorMessage(e, t));
    return false;
  }
  bus.invalidate(inventoryPathFamilies);
  if (context.mounted) {
    DashToast.success(
      context,
      t('inventory.archive.unarchived', args: {'name': name}),
    );
  }
  return true;
}

/// [child] (an ingredient's name) with [ArchivedBadge] after it when
/// [ingredientId] is archived (looked up in the catalog), or when
/// [archived] says so (a row that carries the flag itself).
class WithArchivedBadge extends ConsumerWidget {
  const WithArchivedBadge({
    required this.child,
    this.ingredientId,
    this.archived,
    super.key,
  });

  final Widget child;
  final String? ingredientId;
  final bool? archived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on =
        archived ??
        (ingredientId != null && watchArchivedIds(ref).contains(ingredientId));
    if (!on) return child;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        Flexible(child: child),
        const ArchivedBadge(),
      ],
    );
  }
}
