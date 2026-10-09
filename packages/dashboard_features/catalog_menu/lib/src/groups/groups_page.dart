/// `/menu/groups`: choice groups (MENU-GRP-001..016). Web:
/// `features/menu/groups/groups-page.tsx`.
///
/// - Every shared group, inactive ones included, by `sort` then name, with
///   its pick rule, what choosing does, its option count and where it is
///   used (one usage read per group).
/// - With `menu.items.edit`: "New group", reorder (drag or the arrows; each
///   group whose position moved gets its new `sort`), edit, delete. Without
///   it the names still open the editor read-only and "Used on" the usage
///   dialog read-only.
/// - `?edit=<id>|new` opens the editor (the studio's "Edit group" links
///   here); closing it drops `?edit`.
/// - No realtime: the list refreshes on its own writes.
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart'
    show GroupOut, PatchGroupRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/menu_no_org.dart';
import '../shared/menu_providers.dart';
import '../shared/menu_queries.dart';
import '../shared/menu_text.dart';
import 'group_editor_dialog.dart';
import 'group_model.dart';
import 'group_usage_dialog.dart';
import 'groups_providers.dart';
// The size labels' item read, warmed with the editor.
import '../studio/studio_providers.dart' show studioMenuItemProvider;

class GroupsPage extends ConsumerStatefulWidget {
  const GroupsPage({this.edit, super.key});

  /// `?edit=<groupId>|new`: the editor to open.
  final String? edit;

  @override
  ConsumerState<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends ConsumerState<GroupsPage> {
  /// The order shown while a reorder saves (and until the refetch lands).
  List<GroupOut>? _order;

  /// The listed groups [_order] was made over.
  List<GroupOut>? _orderBase;
  bool _saving = false;

  /// The `?edit` value whose editor is up.
  String? _openFor;

  /// The `?edit` value whose editor just closed (its removal is on its way).
  String? _closedFor;

  GroupsQuery _listKey(String orgId) => (orgId: orgId, includeInactive: true);

  /// The web's `groupsQ.refetch()`, captured before an await so it runs
  /// even when the page has gone by the time the write lands.
  VoidCallback _listRefetcher(String orgId) {
    final container = ProviderScope.containerOf(context, listen: false);
    final key = _listKey(orgId);
    return () => container.invalidate(modifierGroupsProvider(key));
  }

  /// The editor's reads ([group] null = a new group), warmed on intent.
  void _warmEditor(String orgId, GroupOut? group) {
    ref
      ..warm(ingredientCatalogProvider(orgId))
      ..warm(modifierGroupsProvider((orgId: orgId, includeInactive: false)))
      ..warm(ingredientCategoriesProvider(orgId));
    if (group == null) return;
    // Its size labels: each item the (listed) usage names.
    for (final u in ref.read(groupUsageProvider(group.id)).value ?? const []) {
      ref.warm(studioMenuItemProvider(u.itemId));
    }
  }

  /// `navigate({search: {...prev, edit}, replace: true})`.
  void _setEdit(String? edit) {
    final current = GoRouterState.of(context).uri;
    final q = Map<String, String>.of(current.queryParameters);
    edit == null ? q.remove('edit') : q['edit'] = edit;
    GoRouter.of(context).go(
      Uri(path: current.path, queryParameters: q.isEmpty ? null : q).toString(),
    );
  }

  void _syncEditor(String orgId, List<GroupOut>? groups, bool canEdit) {
    final edit = widget.edit;
    if (edit != _closedFor) _closedFor = null;
    if (_openFor != null || edit == null || edit == _closedFor) return;
    GroupOut? group;
    if (edit == 'new') {
      if (!canEdit) return;
    } else {
      group = groups?.firstWhereOrNull((g) => g.id == edit);
      if (group == null) return;
    }
    _openFor = edit;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final refetch = _listRefetcher(orgId);
      final saved = await showGroupEditorDialog(
        context,
        orgId: orgId,
        group: group,
        usedOn: group == null
            ? null
            : ref.read(groupUsageProvider(group.id)).value?.length,
        onManageItems: group == null
            ? null
            : () => showGroupUsageDialog(
                context,
                orgId: orgId,
                group: group!,
                readOnly: !canEdit,
              ),
        readOnly: !canEdit,
      );
      // The web's `onSaved`: the page's list refetches.
      if (saved != null) refetch();
      if (!mounted) return;
      _openFor = null;
      _closedFor = edit;
      if (GoRouterState.of(context).uri.queryParameters['edit'] != null) {
        _setEdit(null);
      }
    });
  }

  /// Persists [next]: `sort` = the new index on every group that moved, one
  /// by one; failure restores the order; the list and the catalog refetch
  /// either way.
  Future<void> _commit(
    String orgId,
    List<GroupOut> next,
    List<GroupOut>? base,
  ) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).menu;
    final invalidate = ref.menuInvalidate;
    final refetch = _listRefetcher(orgId);
    setState(() {
      _order = next;
      _orderBase = base;
      _saving = true;
    });
    try {
      for (final (i, g) in next.indexed) {
        if (g.sort != i) {
          await api.patchGroup(
            gid: g.id,
            body: PatchGroupRequest(sort: i),
          );
        }
      }
      if (mounted) DashToast.success(context, t('common.savedChanges'));
    } on Object catch (e) {
      if (mounted) {
        setState(() => _order = null);
        DashToast.error(context, errorMessage(e, t));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
      refetch();
      invalidate.catalog();
    }
  }

  Future<void> _delete(String orgId, GroupOut g) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t(
        'menu.groups.deleteTitle',
        args: {
          'name': shownName(
            g.name,
            g.nameTranslations,
            ref.read(localeProvider),
          ),
        },
      ),
      description: t('menu.groups.deleteConsequence'),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final refetch = _listRefetcher(orgId);
    final invalidate = ref.menuInvalidate;
    try {
      await ref.read(apiProvider).menu.deleteGroup(gid: g.id);
      refetch();
      invalidate.catalog();
      if (mounted) DashToast.success(context, t('common.savedChanges'));
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final orgId = ref.watch(orgIdProvider);
    final canEdit = ref.watch(
      authzProvider.select((a) => a.can(Cap.menuItemsEdit)),
    );
    if (orgId == null) {
      return const Padding(
        padding: EdgeInsets.all(Space.lg),
        child: MenuNoOrgState(),
      );
    }
    final listProvider = modifierGroupsProvider(_listKey(orgId));
    final q = ref.watch(listProvider);
    final raw = q.value;
    final groups = raw == null ? null : sharedGroups(raw);
    _syncEditor(orgId, groups, canEdit);
    final order = _order != null && (_saving || identical(_orderBase, raw))
        ? _order!
        : groups ?? const <GroupOut>[];

    final Widget body;
    if (q.failedFirst) {
      body = DashErrorState(
        title: t('common.loadFailed'),
        message: errorMessage(q.error, t),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(listProvider),
      );
    } else if (groups == null) {
      body = const DashSkeleton(height: Space.xxl * 5);
    } else if (order.isEmpty) {
      body = DashEmptyState(icon: 'layers', title: t('menu.groups.empty'));
    } else {
      void move(int from, int to) {
        if (to < 0 || to >= order.length || from == to) return;
        _commit(orgId, arrayMove(order, from, to), raw);
      }

      body = Semantics(
        container: true,
        liveRegion: _saving,
        child: ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: move,
          proxyDecorator: (child, _, _) => Material(
            type: MaterialType.transparency,
            child: Opacity(opacity: 0.7, child: child),
          ),
          children: [
            for (final (i, g) in order.indexed)
              Padding(
                key: ValueKey(g.id),
                padding: EdgeInsets.only(
                  bottom: i == order.length - 1 ? 0 : Space.sm,
                ),
                child: _GroupRow(
                  group: g,
                  index: i,
                  count: order.length,
                  canEdit: canEdit,
                  saving: _saving,
                  onMoveUp: () => move(i, i - 1),
                  onMoveDown: () => move(i, i + 1),
                  onEdit: () => _setEdit(g.id),
                  onEditIntent: () => _warmEditor(orgId, g),
                  onManageIntent: () => ref.warm(groupOrgItemsProvider(orgId)),
                  onManage: () => showGroupUsageDialog(
                    context,
                    orgId: orgId,
                    group: g,
                    readOnly: !canEdit,
                  ),
                  onDelete: () => _delete(orgId, g),
                ),
              ),
          ],
        ),
      );
    }

    return DashPageScaffold(
      title: t('menu.groups.title'),
      subtitle: t('menu.groups.subtitle'),
      actions: [
        if (canEdit)
          DashButton(
            label: t('menu.groups.new'),
            icon: 'plus',
            size: DashButtonSize.compact,
            onPressed: () => _setEdit('new'),
            onIntent: () => _warmEditor(orgId, null),
          ),
      ],
      body: body,
    );
  }
}

/// One group: [drag handle], name (+ Arabic), badges, "Used on", actions.
/// One line when there is room; below that the badges, "Used on" and the
/// actions flow under the name (the web's `flex-wrap`).
class _GroupRow extends ConsumerWidget {
  const _GroupRow({
    required this.group,
    required this.index,
    required this.count,
    required this.canEdit,
    required this.saving,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onEdit,
    required this.onEditIntent,
    required this.onManage,
    required this.onManageIntent,
    required this.onDelete,
  });

  final GroupOut group;
  final int index;
  final int count;
  final bool canEdit;
  final bool saving;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onEditIntent;
  final VoidCallback onManage;
  final VoidCallback onManageIntent;
  final VoidCallback onDelete;

  /// Below this the row wraps.
  static const double oneLine = Space.xxl * 30;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final g = group;
    final ar = arOf(g.nameTranslations);
    final usedOn = ref.watch(groupUsageProvider(g.id)).value?.length;
    final (pickKey, upTo) = pickBadge(g);

    final handle = canEdit
        ? ReorderableDragStartListener(
            index: index,
            child: Semantics(
              container: true,
              button: true,
              label: t('menu.groups.dragToReorder', args: {'name': g.name}),
              child: ExcludeSemantics(
                child: SizedBox.square(
                  dimension: DashMetrics.target,
                  child: Center(
                    child: DashIcon(
                      'grip-vertical',
                      size: IconSize.sm,
                      color: c.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          )
        : null;

    final name = DashPressable(
      onTap: onEdit,
      onIntent: onEditIntent,
      semanticLabel: g.name,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MadarClippedText(
              g.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashType.bodyMedium.copyWith(color: c.textPrimary),
            ),
            if (ar.isNotEmpty)
              MadarClippedText(
                ar,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.rtl,
                style: DashType.small.copyWith(color: c.textMuted),
              ),
          ],
        ),
      ),
    );

    final badges = Wrap(
      spacing: Space.xs + DashMetrics.hair,
      runSpacing: Space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        GroupBadge(
          upTo == null ? t(pickKey) : t(pickKey, count: upTo),
          variant: GroupBadgeVariant.outline,
        ),
        GroupBadge(
          t(effectBadgeKey(g)),
          variant: groupSwaps(g)
              ? GroupBadgeVariant.filled
              : GroupBadgeVariant.secondary,
        ),
        GroupBadge(t('menu.groups.optionCount', count: g.options.length)),
        if (!g.isActive)
          GroupBadge(t('common.inactive'), variant: GroupBadgeVariant.outline),
      ],
    );

    final used = DashButton(
      label: usedOn == null ? '…' : t('menu.groups.usedOn', count: usedOn),
      variant: DashButtonVariant.link,
      size: DashButtonSize.compact,
      onPressed: usedOn == null ? null : onManage,
      onIntent: usedOn == null ? null : onManageIntent,
    );

    final actions = canEdit
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DashIconButton(
                icon: 'arrow-up',
                semanticLabel: t('menu.studio.steps.moveUp'),
                onPressed: saving || index == 0 ? null : onMoveUp,
              ),
              DashIconButton(
                icon: 'arrow-down',
                semanticLabel: t('menu.studio.steps.moveDown'),
                onPressed: saving || index == count - 1 ? null : onMoveDown,
              ),
              DashIconButton(
                icon: 'pencil',
                semanticLabel: t('common.edit'),
                onPressed: onEdit,
                onIntent: onEditIntent,
              ),
              DashIconButton(
                icon: 'trash-2',
                color: c.danger,
                semanticLabel: t('common.delete'),
                onPressed: onDelete,
              ),
            ],
          )
        : null;

    return Container(
      padding: const EdgeInsets.all(Space.sm + DashMetrics.hair),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.hairline),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth >= oneLine
            ? Row(
                spacing: Space.md,
                children: [
                  ?handle,
                  Expanded(child: name),
                  badges,
                  used,
                  ?actions,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.xs,
                children: [
                  Row(
                    spacing: Space.md,
                    children: [
                      ?handle,
                      Expanded(child: name),
                    ],
                  ),
                  Wrap(
                    spacing: Space.md,
                    runSpacing: Space.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [badges, used, ?actions],
                  ),
                ],
              ),
      ),
    );
  }
}
