/// `/menu/bases`: recipe bases, the shared line sets item sizes expand
/// (MENU-BAS-001..009). The editor is `base_editor_dialog.dart`.
/// Web: `features/menu/recipe/bases-page.tsx`.
///
/// - The list is fetched only with an org in scope; without one (a platform
///   admin who has not picked) the page shows its empty state (MENU-AREA-010).
/// - "New base" and the row actions need `menu.items.edit`; without it the
///   list is read-only (MENU-BAS-008).
/// - No realtime: the list refreshes on its own writes (bases + the
///   catalog, `invalidateCatalog()`).
library;

import 'package:dashboard_api/dashboard_api.dart' show RecipeBaseOut;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/menu_providers.dart';
import '../shared/menu_queries.dart';
import 'base_editor_dialog.dart';
import 'bases_widgets.dart';

class RecipeBasesPage extends ConsumerWidget {
  const RecipeBasesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final orgId = ref.watch(orgIdProvider);
    final canEdit = ref.watch(
      authzProvider.select((a) => a.can(Cap.menuItemsEdit)),
    );
    final empty = DashEmptyState(
      icon: 'layers-3',
      title: t('modeling.bases.empty'),
      description: t('modeling.bases.emptyHint'),
    );

    Widget body;
    if (orgId == null) {
      body = empty;
    } else {
      final provider = recipeBasesProvider(orgId);
      final bases = ref.watch(provider);
      if (bases.hasError) {
        body = DashErrorState(
          title: t('modeling.bases.loadError'),
          message: errorMessage(bases.error, t),
          retrying: bases.isLoading,
          onRetry: () => ref.invalidate(provider),
        );
      } else if (!bases.hasValue) {
        body = const ModelingSkeleton();
      } else if (bases.requireValue.isEmpty) {
        body = empty;
      } else {
        body = ModelingList(
          children: [
            for (final b in bases.requireValue)
              ModelingRow(
                key: ValueKey(b.id),
                name: b.name,
                active: b.isActive,
                inactiveLabel: t('common.inactive'),
                subtitle:
                    '${t('modeling.bases.affects', args: {'items': b.itemCount, 'sizes': b.sizeCount})}'
                    ' · '
                    '${t('modeling.bases.lineCount', count: b.lines.length)}',
                editLabel: t('common.edit'),
                deleteLabel: t('common.delete'),
                onEdit: canEdit
                    ? () => showBaseEditor(context, orgId: orgId, base: b)
                    : null,
                onDelete: canEdit
                    ? () => _delete(context, ref, b)
                    : null,
              ),
          ],
        );
      }
    }

    return DashPageScaffold(
      title: t('modeling.bases.title'),
      subtitle: t('modeling.bases.subtitle'),
      width: DashPageWidth.reading,
      actions: [
        if (canEdit)
          DashButton(
            label: t('modeling.bases.new'),
            icon: 'plus',
            size: DashButtonSize.compact,
            onPressed: () => showBaseEditor(context, orgId: orgId, base: null),
          ),
      ],
      body: body,
    );
  }

  /// MENU-BAS-009: confirm (not destructive-styled), delete, toast, refresh
  /// the bases and the catalog; a refusal shows the server's words.
  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    RecipeBaseOut b,
  ) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('modeling.bases.deleteTitle', args: {'name': b.name}),
      description: t('modeling.bases.deleteDesc'),
      confirmLabel: t('common.delete'),
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(apiProvider).menu.deleteBase(id: b.id);
      if (!context.mounted) return;
      DashToast.success(context, t('modeling.bases.deleted'));
      ref.menuInvalidate
        ..paths(const [MenuPaths.recipeBases])
        ..catalog();
    } on Object catch (e) {
      if (!context.mounted) return;
      DashToast.error(context, errorMessage(e, t));
    }
  }
}
