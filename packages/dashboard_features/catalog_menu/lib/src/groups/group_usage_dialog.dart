/// "Used on N items → Manage…": tick the items that offer a group (the web's
/// `features/menu/groups/group-usage-dialog.tsx`, MENU-GRP-017..022, -050).
/// Apply re-writes each changed item's attachment set through the studio's
/// own endpoint: read the item's attachments, add or drop this group, write
/// them back, keeping every other group's per-item rules.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        GroupAttachInput,
        GroupOut,
        GroupUsageItem,
        MenuItem,
        ModifierGroupOut,
        PutModifierGroupsRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/menu_queries.dart';
import 'group_model.dart';
import 'groups_providers.dart';

/// Opens the dialog for [group]; [readOnly] without `menu.items.edit`.
Future<void> showGroupUsageDialog(
  BuildContext context, {
  required String orgId,
  required GroupOut group,
  bool readOnly = false,
}) => showDashDialog<void>(
  context,
  width: GroupUsageDialog.width,
  builder: (_) =>
      GroupUsageDialog(orgId: orgId, group: group, readOnly: readOnly),
);

/// The attachment set an item keeps after [group] is added to or dropped
/// from it (the web's `apply` body): the others keep their overrides and
/// allowlists, an added group goes last with its own rules and every option.
List<GroupAttachInput> rewriteAttachments(
  List<ModifierGroupOut> current,
  GroupOut group, {
  required bool add,
}) {
  final sorted = [...current]..sort((a, b) => a.sort - b.sort);
  final out = [
    for (final g in sorted)
      if (g.groupId != group.id || add) g,
  ].indexed.map((e) => _attach(e.$2, e.$1)).toList();
  if (add && !current.any((g) => g.groupId == group.id)) {
    out.add(
      GroupAttachInput(
        groupId: group.id,
        sort: out.length,
        minOverride: group.minSelections,
        maxOverride: group.maxSelections,
        isRequiredOverride: group.isRequired,
        explicitNulls: {
          if (group.maxSelections == null) 'max_override',
          'included_option_ids',
        },
      ),
    );
  }
  return out;
}

GroupAttachInput _attach(ModifierGroupOut g, int sort) {
  final all = g.options.every((o) => o.included);
  return GroupAttachInput(
    groupId: g.groupId,
    sort: sort,
    minOverride: g.min,
    maxOverride: g.max,
    isRequiredOverride: g.isRequired,
    includedOptionIds: all
        ? null
        : [
            for (final o in g.options)
              if (o.included) o.id,
          ],
    explicitNulls: {
      if (g.max == null) 'max_override',
      if (all) 'included_option_ids',
    },
  );
}

class GroupUsageDialog extends ConsumerStatefulWidget {
  const GroupUsageDialog({
    required this.orgId,
    required this.group,
    this.readOnly = false,
    super.key,
  });

  /// The web's `sm:max-w-lg`.
  static const double width = 512;

  final String orgId;
  final GroupOut group;
  final bool readOnly;

  @override
  ConsumerState<GroupUsageDialog> createState() => _GroupUsageDialogState();
}

class _GroupUsageDialogState extends ConsumerState<GroupUsageDialog> {
  /// The usage the ticks were last seeded from (re-seeded when it changes).
  List<GroupUsageItem>? _seededFrom;
  Set<String> _picked = {};
  String _query = '';
  bool _busy = false;

  Future<void> _apply(Set<String> usedIds) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).menu;
    final invalidate = ref.menuInvalidate;
    final add = [
      for (final id in _picked)
        if (!usedIds.contains(id)) id,
    ];
    final remove = [
      for (final id in usedIds)
        if (!_picked.contains(id)) id,
    ];
    setState(() => _busy = true);
    var failed = 0;
    for (final itemId in [...add, ...remove]) {
      try {
        final studio = await api.getStudio(id: itemId);
        await api.putModifierGroups(
          id: itemId,
          body: PutModifierGroupsRequest(
            groups: rewriteAttachments(
              studio.modifierGroups,
              widget.group,
              add: add.contains(itemId),
            ),
          ),
        );
      } on Object catch (e) {
        failed++;
        if (mounted) DashToast.error(context, errorMessage(e, t));
      }
    }
    invalidate
      ..catalog()
      ..paths(const [
        MenuPaths.catalog,
        MenuPaths.anyStudio,
        MenuPaths.modifierGroups,
      ]);
    if (!mounted) return;
    setState(() => _busy = false);
    if (failed == 0) {
      DashToast.success(context, t('common.savedChanges'));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final lang = ref.watch(localeProvider);
    final uses =
        ref.watch(groupUsageProvider(widget.group.id)).value ??
        const <GroupUsageItem>[];
    final usedIds = {for (final u in uses) u.itemId};
    final useById = {for (final u in uses) u.itemId: u};
    if (!identical(uses, _seededFrom)) {
      _seededFrom = uses;
      _picked = {...usedIds};
    }
    final itemsQ = ref.watch(groupOrgItemsProvider(widget.orgId));
    String shown(MenuItem i) => shownName(i.name, i.nameTranslations, lang);
    // By the name shown (the web sorts the names it shows, `localeCompare`).
    final items = [
      for (final i in itemsQ.value ?? const <MenuItem>[])
        if (i.deletedAt == null) i,
    ]..sort((a, b) => shown(a).toLowerCase().compareTo(shown(b).toLowerCase()));
    final q = _query.trim().toLowerCase();
    final visible = [
      for (final i in items)
        if (i.name.toLowerCase().contains(q) ||
            shown(i).toLowerCase().contains(q))
          i,
    ];
    final dirty =
        _picked.length != usedIds.length ||
        _picked.any((id) => !usedIds.contains(id));

    Widget list;
    if (itemsQ.hasError && !itemsQ.hasValue) {
      list = DashErrorState(
        framed: false,
        title: t('common.loadFailed'),
        message: errorMessage(itemsQ.error, t),
        retryLabel: t('common.retry'),
        retrying: itemsQ.isLoading,
        onRetry: () => ref.invalidate(groupOrgItemsProvider(widget.orgId)),
      );
    } else if (!itemsQ.hasValue) {
      list = const Padding(
        padding: EdgeInsets.all(Space.lg),
        child: DashSkeleton(height: Space.xxl * 4),
      );
    } else if (visible.isEmpty) {
      list = Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Text(
          t('common.noResults'),
          textAlign: TextAlign.center,
          style: DashType.body.copyWith(color: c.textMuted),
        ),
      );
    } else {
      // The whole list, as the web renders it (no paging).
      Widget row(MenuItem item) {
        final use = useById[item.id];
        final on = _picked.contains(item.id);
        void toggle() => setState(() {
          on ? _picked.remove(item.id) : _picked.add(item.id);
        });
        return Padding(
          key: ValueKey(item.id),
          padding: const EdgeInsetsDirectional.only(end: Space.md),
          child: Row(
            spacing: Space.xs,
            children: [
              DashCheckbox(
                value: on,
                enabled: !widget.readOnly,
                semanticLabel: shown(item),
                onChanged: (_) => toggle(),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: widget.readOnly ? null : toggle,
                  child: ExcludeSemantics(
                    child: MadarClippedText(
                      shown(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashType.body.copyWith(color: c.textPrimary),
                    ),
                  ),
                ),
              ),
              if (!item.isActive)
                GroupBadge(
                  t('common.inactive'),
                  variant: GroupBadgeVariant.outline,
                ),
              if (use != null)
                GroupBadge(
                  use.isRequired
                      ? t('menu.groups.usage.required')
                      : t('menu.groups.usage.optional'),
                ),
            ],
          ),
        );
      }

      list = SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (n, item) in visible.indexed) ...[
              if (n > 0) const MadarHairline.row(),
              row(item),
            ],
          ],
        ),
      );
    }

    return DashSurface(
      title: t(
        'menu.groups.usage.title',
        args: {
          'name': shownName(
            widget.group.name,
            widget.group.nameTranslations,
            lang,
          ),
        },
      ),
      description: t('menu.groups.usage.desc'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          DashSearchInput(
            value: _query,
            placeholder: t('common.search'),
            onChanged: (v) => setState(() => _query = v),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height / 2,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: c.hairline),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.sm),
                child: list,
              ),
            ),
          ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        if (!widget.readOnly)
          DashButton(
            label: t('menu.groups.usage.apply'),
            loading: _busy,
            onPressed: dirty ? () => _apply(usedIds) : null,
          ),
      ],
    );
  }
}

/// The web's `Badge` variants the groups pages use: `outline` (a hairline
/// pill), `secondary` (the grey wash) and `default` (ink, for a swap).
enum GroupBadgeVariant { outline, secondary, filled }

class GroupBadge extends StatelessWidget {
  const GroupBadge(
    this.label, {
    this.variant = GroupBadgeVariant.secondary,
    this.mono = false,
    super.key,
  });

  final String label;
  final GroupBadgeVariant variant;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: DashMetrics.hair,
      ),
      decoration: BoxDecoration(
        color: switch (variant) {
          GroupBadgeVariant.outline => null,
          GroupBadgeVariant.secondary => c.surfaceAlt,
          GroupBadgeVariant.filled => c.accent,
        },
        border: variant == GroupBadgeVariant.outline
            ? Border.all(color: c.hairline)
            : null,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        mono ? dashFigure(label) : label,
        style: DashType.small.copyWith(
          color: variant == GroupBadgeVariant.filled
              ? c.textOnAccent
              : c.textPrimary,
        ),
      ),
    );
  }
}
