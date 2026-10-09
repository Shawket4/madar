/// Inventory settings (`/inventory/settings`, the INV-SET rows; web
/// `src/features/inventory/settings-page.tsx`): the org's stock-count
/// variance tolerance and its ingredient categories (add, rename, packaging,
/// delete with a reassign target).
///
/// Only the packaging switch is gated in page (`inventory.adjust`); Save,
/// rename, delete and add are the server's to refuse (INV-SET-023).
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/inventory_data.dart';
import '../shared/inventory_lib.dart';
import '../shared/no_org.dart';

/// INV-SET-003 `GET /inventory/orgs/{org_id}/settings` (getInventorySettings).
final inventorySettingsProvider = FutureProvider.autoDispose
    .family<OrgInventorySettings, String>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/inventory/orgs/$orgId/settings'));
      return ref
          .watch(apiProvider)
          .inventory
          .getInventorySettings(orgId: orgId);
    });

/// INV-SET-009: by `sort_order`, then name.
List<IngredientCategory> sortedCategories(List<IngredientCategory> all) =>
    [...all]..sort((a, b) {
      final s = a.sortOrder.compareTo(b.sortOrder);
      return s != 0 ? s : a.name.compareTo(b.name);
    });

/// A category row's height (`min-h-14`).
const double _rowHeight = Space.xxl + Space.xl;

class InventorySettingsPage extends ConsumerStatefulWidget {
  const InventorySettingsPage({super.key});

  @override
  ConsumerState<InventorySettingsPage> createState() =>
      _InventorySettingsPageState();
}

class _InventorySettingsPageState extends ConsumerState<InventorySettingsPage> {
  /// What the person typed; null = the server's value (re-seeds on refresh).
  String? _pct;

  /// Saved: drop [_pct] once the refetch lands.
  bool _saved = false;
  String? _pctError;
  bool _busy = false;

  String _newName = '';
  bool _adding = false;

  ({String id, String name})? _editing;
  bool _working = false;

  /// INV-SET-006. A blank, unreadable or negative value asks nothing.
  Future<void> _save(String orgId, String text) async {
    final value = dashParseNumber(text);
    if (value == null || value < 0) {
      final k = context.dashStrings;
      setState(
        () => _pctError = value == null
            ? k.notANumber(text)
            : k.atLeast(context.dashFormats.figure(0), ' %'),
      );
      return;
    }
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    setState(() => _busy = true);
    try {
      await api.inventory.updateInventorySettings(
        orgId: orgId,
        body: UpdateInventorySettingsRequest(
          stocktakeVarianceThresholdPct: value,
        ),
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        DashToast.error(context, errorMessage(e, t));
      }
      return;
    }
    bus.invalidate(inventoryPathFamilies);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _saved = true;
    });
    DashToast.success(context, t('inventory.settings.saved'));
  }

  /// INV-SET-020.
  Future<void> _add(String orgId) async {
    final name = _newName.trim();
    if (name.isEmpty || _adding) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    setState(() => _adding = true);
    try {
      await api.inventory.createIngredientCategory(
        orgId: orgId,
        body: CreateIngredientCategoryRequest(name: name),
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() => _adding = false);
        DashToast.error(context, errorMessage(e, t));
      }
      return;
    }
    bus.invalidate(inventoryPathFamilies);
    if (mounted) {
      setState(() {
        _adding = false;
        _newName = '';
      });
    }
  }

  /// INV-SET-010/026: not optimistic; the switch shows the server's value.
  Future<void> _setPackaging(
    String orgId,
    IngredientCategory c,
    bool value,
  ) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    try {
      await api.inventory.updateIngredientCategory(
        orgId: orgId,
        id: c.id,
        body: UpdateIngredientCategoryRequest(isPackaging: value),
      );
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
      return;
    }
    bus.invalidate(inventoryPathFamilies);
  }

  /// INV-SET-012.
  Future<void> _rename(String orgId) async {
    final e = _editing;
    if (e == null || e.name.trim().isEmpty || _working) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    setState(() => _working = true);
    try {
      await api.inventory.updateIngredientCategory(
        orgId: orgId,
        id: e.id,
        body: UpdateIngredientCategoryRequest(name: e.name.trim()),
      );
    } on Object catch (err) {
      if (mounted) {
        setState(() => _working = false);
        DashToast.error(context, errorMessage(err, t));
      }
      return;
    }
    bus.invalidate(inventoryPathFamilies);
    if (mounted) {
      setState(() {
        _working = false;
        if (_editing?.id == e.id) _editing = null;
      });
    }
  }

  /// INV-SET-013.
  void _delete(String orgId, IngredientCategory c) => showDashDialog<void>(
    context,
    builder: (_) => DeleteCategoryDialog(orgId: orgId, category: c),
  );

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final orgId = ref.watch(orgIdProvider);
    if (orgId == null) {
      return InventoryNoOrgPage(
        title: t('inventory.settings.title'),
        icon: 'settings-2',
        width: DashPageWidth.reading,
      );
    }
    final settings = ref.watch(inventorySettingsProvider(orgId));
    ref.listen(inventorySettingsProvider(orgId), (_, next) {
      if (_saved && next.hasValue && !next.isLoading && !next.hasError) {
        setState(() {
          _saved = false;
          _pct = null;
        });
      }
    });
    final canAdjust = ref.watch(
      authzProvider.select((a) => a.can(Cap.inventoryAdjust)),
    );
    final server = settings.value?.stocktakeVarianceThresholdPct;
    final pct = _pct ?? (server == null ? '' : jsNumberString(server));

    return DashPageScaffold(
      title: t('inventory.settings.title'),
      subtitle: t('inventory.settings.subtitle'),
      width: DashPageWidth.reading,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          _card(
            key: const ValueKey('inv-settings-tolerance'),
            header: DashSectionHeader(
              title: t('inventory.settings.varianceThreshold'),
              description: t('inventory.settings.varianceThresholdHint'),
            ),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: Space.xxl * 6),
                  child: DashFormField<String>(
                    label: t('inventory.settings.percent'),
                    errorText: _pctError,
                    builder: (context, invalid) => DashTextInput(
                      key: const ValueKey('inv-settings-pct'),
                      value: pct,
                      semanticLabel: t('inventory.settings.percent'),
                      enabled: !(settings.awaitingFirst || settings.hasError),
                      invalid: invalid,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textDirection: TextDirection.ltr,
                      trailing: Text(
                        '%',
                        style: DashType.body.copyWith(
                          color: context.madarColors.textSecondary,
                        ),
                      ),
                      onChanged: (v) => setState(() {
                        _pct = v;
                        _saved = false;
                        _pctError = null;
                      }),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: DashButton(
                  key: const ValueKey('inv-settings-save'),
                  label: t('common.save'),
                  loading: _busy,
                  onPressed: settings.awaitingFirst || pct.isEmpty
                      ? null
                      : () => _save(orgId, pct),
                ),
              ),
            ],
          ),
          _card(
            key: const ValueKey('inv-settings-categories'),
            header: DashSectionHeader(
              icon: 'tags',
              title: t('inventory.settings.categories'),
              description: t('inventory.settings.categoriesHint'),
            ),
            children: [
              _categoryList(orgId, canAdjust),
              Row(
                spacing: Space.sm,
                children: [
                  Expanded(
                    child: DashTextInput(
                      key: const ValueKey('inv-settings-new-name'),
                      value: _newName,
                      placeholder: t('inventory.catalog.newCategoryName'),
                      semanticLabel: t('inventory.catalog.newCategoryName'),
                      onChanged: (v) => setState(() => _newName = v),
                      onSubmitted: (_) => _add(orgId),
                    ),
                  ),
                  DashButton(
                    key: const ValueKey('inv-settings-add'),
                    label: t('common.add'),
                    icon: 'plus',
                    loading: _adding,
                    onPressed: _newName.trim().isEmpty
                        ? null
                        : () => _add(orgId),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The web's `Card` (header, then `space-y` content).
  Widget _card({
    required Key key,
    required Widget header,
    required List<Widget> children,
  }) => DashCard(
    key: key,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [header, const SizedBox(height: Space.xs), ...children],
    ),
  );

  /// INV-SET-009/017/018/019: the list, its skeleton, error and empty line.
  Widget _categoryList(String orgId, bool canAdjust) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final q = ref.watch(ingredientCategoriesProvider(orgId));
    if (q.failedFirst) {
      return DashErrorState(
        key: const ValueKey('inv-settings-categories-error'),
        title: t('inventory.settings.categoriesFailed'),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(ingredientCategoriesProvider(orgId)),
      );
    }
    final List<Widget> rows;
    if (q.awaitingFirst) {
      rows = [
        for (var i = 0; i < 4; i++)
          const _Row(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    spacing: Space.xs + DashMetrics.hair,
                    children: [
                      DashSkeleton(width: Space.xxl * 4, height: Space.lg),
                      DashSkeleton(width: Space.xxl * 3, height: Space.md),
                    ],
                  ),
                ),
                DashSkeleton(
                  width: Space.xxl,
                  height: Space.xxl,
                  radius: Radii.xs,
                ),
              ],
            ),
          ),
      ];
    } else {
      final sorted = sortedCategories(q.value ?? const []);
      rows = sorted.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.lg,
                  vertical: Space.xl,
                ),
                child: Text(
                  t('inventory.settings.noCategoriesHint'),
                  textAlign: TextAlign.center,
                  style: DashType.body.copyWith(color: c.textSecondary),
                ),
              ),
            ]
          : [for (final cat in sorted) _categoryRow(orgId, cat, canAdjust)];
    }
    return Container(
      key: ValueKey(
        q.awaitingFirst
            ? 'inv-settings-categories-loading'
            : 'inv-settings-category-list',
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: c.hairline),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: c.hairline)),
              ),
              child: rows[i],
            ),
        ],
      ),
    );
  }

  Widget _categoryRow(String orgId, IngredientCategory cat, bool canAdjust) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final editing = _editing;
    if (editing != null && editing.id == cat.id) {
      return _Row(
        key: ValueKey('inv-category-${cat.id}'),
        child: Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: DashTextInput(
                key: const ValueKey('inv-category-rename'),
                value: editing.name,
                autofocus: true,
                semanticLabel: t('inventory.catalog.newCategoryName'),
                onChanged: (v) =>
                    setState(() => _editing = (id: cat.id, name: v)),
                onSubmitted: (_) => _rename(orgId),
                onKeyEvent: (node, e) {
                  if (e is KeyDownEvent &&
                      e.logicalKey == LogicalKeyboardKey.escape) {
                    setState(() => _editing = null);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
              ),
            ),
            DashIconButton(
              key: const ValueKey('inv-category-rename-save'),
              icon: 'check',
              semanticLabel: t('common.save'),
              loading: _working,
              onPressed: () => _rename(orgId),
            ),
            DashIconButton(
              key: const ValueKey('inv-category-rename-cancel'),
              icon: 'x',
              semanticLabel: t('common.cancel'),
              onPressed: () => setState(() => _editing = null),
            ),
          ],
        ),
      );
    }
    final meta = DashType.small.copyWith(color: c.textSecondary);
    return _Row(
      key: ValueKey('inv-category-${cat.id}'),
      child: Row(
        spacing: Space.sm,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MadarClippedText(
                  cat.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: cat.slug,
                        style: DashType.mono.copyWith(
                          fontSize: meta.fontSize,
                          color: c.textSecondary,
                        ),
                      ),
                      TextSpan(
                        text:
                            ' · ${t('inventory.settings.ingredientCount', count: cat.ingredientCount)}',
                      ),
                    ],
                  ),
                  style: meta,
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: Space.sm),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.sm,
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        t('modeling.packaging.isPackaging'),
                        style: meta,
                      ),
                    ),
                    DashSwitch(
                      key: ValueKey('inv-category-packaging-${cat.id}'),
                      value: cat.isPackaging,
                      enabled: canAdjust,
                      semanticLabel: t(
                        'modeling.packaging.isPackagingAria',
                        args: {'name': cat.name},
                      ),
                      onChanged: (v) => _setPackaging(orgId, cat, v),
                    ),
                  ],
                ),
              ),
              if (cat.slug == 'general')
                DashBadge(t('inventory.settings.defaultCategory')),
              DashIconButton(
                key: ValueKey('inv-category-edit-${cat.id}'),
                icon: 'pencil',
                semanticLabel: t('common.edit'),
                onPressed: () =>
                    setState(() => _editing = (id: cat.id, name: cat.name)),
              ),
              if (cat.slug != 'general')
                DashIconButton(
                  key: ValueKey('inv-category-delete-${cat.id}'),
                  icon: 'trash-2',
                  semanticLabel: t('common.delete'),
                  color: c.textSecondary,
                  onPressed: () => _delete(orgId, cat),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One list row (`min-h-14 ps-4 pe-2 py-2`).
class _Row extends StatelessWidget {
  const _Row({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: _rowHeight),
    child: Padding(
      padding: const EdgeInsetsDirectional.only(
        start: Space.lg,
        end: Space.sm,
        top: Space.sm,
        bottom: Space.sm,
      ),
      child: Align(alignment: AlignmentDirectional.centerStart, child: child),
    ),
  );
}

/// INV-SET-014/015/016: delete a category, moving its ingredients first
/// when it has any.
class DeleteCategoryDialog extends ConsumerStatefulWidget {
  const DeleteCategoryDialog({
    required this.orgId,
    required this.category,
    super.key,
  });

  final String orgId;
  final IngredientCategory category;

  @override
  ConsumerState<DeleteCategoryDialog> createState() =>
      _DeleteCategoryDialogState();
}

class _DeleteCategoryDialogState extends ConsumerState<DeleteCategoryDialog> {
  String? _reassignTo;
  bool _working = false;

  bool get _inUse => widget.category.ingredientCount > 0;

  Future<void> _remove() async {
    if (_inUse && _reassignTo == null) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    setState(() => _working = true);
    try {
      await api.inventory.deleteIngredientCategory(
        orgId: widget.orgId,
        id: widget.category.id,
        reassignTo: _reassignTo,
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() => _working = false);
        DashToast.error(context, errorMessage(e, t));
      }
      return;
    }
    bus.invalidate(inventoryPathFamilies);
    if (!mounted) return;
    Navigator.of(context).pop();
    DashToast.success(context, t('common.done'));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final cat = widget.category;
    // The page's own list (cached): the dialog asks nothing more.
    final others = [
      for (final c in sortedCategories(
        ref.watch(ingredientCategoriesProvider(widget.orgId)).value ??
            const [],
      ))
        if (c.id != cat.id) c,
    ];
    final lead = _inUse
        ? t(
            'inventory.settings.deleteCategoryReassign',
            count: cat.ingredientCount,
          )
        : t('inventory.settings.deleteCategoryEmpty');
    return DashSurface(
      key: const ValueKey('inv-delete-category-dialog'),
      title: t('inventory.settings.deleteCategory', args: {'name': cat.name}),
      description: '$lead ${t('inventory.settings.deleteCategoryConsequence')}',
      body: _inUse
          ? DashSelectField<String>(
              key: const ValueKey('inv-delete-category-target'),
              label: t('inventory.settings.moveTo'),
              placeholder: t('inventory.catalog.category'),
              value: _reassignTo,
              onChanged: (v) => setState(() => _reassignTo = v),
              options: [
                for (final c in others) DashOption(value: c.id, label: c.name),
              ],
            )
          : const SizedBox.shrink(),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(
          key: const ValueKey('inv-delete-category-confirm'),
          label: t('common.delete'),
          variant: DashButtonVariant.destructive,
          loading: _working,
          onPressed: _inUse && _reassignTo == null ? null : _remove,
        ),
      ],
    );
  }
}
