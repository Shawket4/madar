/// "What do you want to count?" (INV-CNT-018…023, -061; the scope dialog in
/// `counts-page.tsx`): the whole branch, one category or chosen
/// ingredients. It reads the categories and the catalog only while open,
/// and starts fresh every time it opens.
library;

import 'package:dashboard_api/dashboard_api.dart' show CreateStocktakeRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/archive.dart';
import '../shared/inventory_data.dart';
import 'counts_data.dart';

class StartCountDialog extends ConsumerStatefulWidget {
  const StartCountDialog({
    required this.branchId,
    required this.orgId,
    super.key,
  });

  final String branchId;

  /// The org whose categories and catalog the pickers offer (none without
  /// one).
  final String? orgId;

  @override
  ConsumerState<StartCountDialog> createState() => _StartCountDialogState();
}

class _StartCountDialogState extends ConsumerState<StartCountDialog> {
  CountScope _scope = CountScope.full;
  String? _category;
  final List<String> _items = [];
  bool _starting = false;

  bool get _ready => switch (_scope) {
    CountScope.full => true,
    CountScope.category => _category != null,
    CountScope.items => _items.isNotEmpty,
  };

  Future<void> _start() async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    final category = _scope == CountScope.category ? _category : null;
    final ids = _scope == CountScope.items && _items.isNotEmpty
        ? [..._items]
        : null;
    setState(() => _starting = true);
    try {
      await api.stocktakes.createStocktake(
        branchId: widget.branchId,
        body: CreateStocktakeRequest(
          categoryId: category,
          orgIngredientIds: ids,
          explicitNulls: {
            'note',
            if (category == null) 'category_id',
            if (ids == null) 'org_ingredient_ids',
          },
        ),
      );
    } on Object catch (e) {
      if (mounted) {
        DashToast.error(context, errorMessage(e, t));
        setState(() => _starting = false);
      }
      return;
    }
    bus.invalidate(inventoryPathFamilies);
    if (!mounted) return;
    DashToast.success(context, t('inventory.stocktakes.started'));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final orgId = widget.orgId;
    final categories = orgId == null
        ? null
        : ref.watch(ingredientCategoriesProvider(orgId)).value;
    final catalog = orgId == null
        ? null
        : ref.watch(inventoryCatalogProvider(orgId)).value;
    String nameOf(String id) =>
        catalog?.where((i) => i.id == id).firstOrNull?.name ?? id;

    return DashSurface(
      key: const ValueKey('count-scope-dialog'),
      title: t('inventory.stocktakes.scopeTitle'),
      description: t('inventory.stocktakes.scopeHint'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          DashSelect<CountScope>(
            key: const ValueKey('count-scope'),
            semanticLabel: t('inventory.stocktakes.scopeTitle'),
            value: _scope,
            onChanged: (v) => setState(() => _scope = v),
            options: [
              DashOption(
                value: CountScope.full,
                label: t('inventory.stocktakes.scopeFull'),
              ),
              DashOption(
                value: CountScope.category,
                label: t('inventory.stocktakes.scopeCategory'),
              ),
              DashOption(
                value: CountScope.items,
                label: t('inventory.stocktakes.scopeItems'),
              ),
            ],
          ),
          if (_scope == CountScope.category)
            DashSelect<String>(
              key: const ValueKey('count-scope-category'),
              placeholder: t('inventory.catalog.category'),
              semanticLabel: t('inventory.catalog.category'),
              value: _category,
              onChanged: (v) => setState(() => _category = v),
              options: [
                for (final cat in categories ?? const [])
                  DashOption(
                    value: cat.id,
                    label: '${cat.name} (${cat.ingredientCount})',
                  ),
              ],
            ),
          if (_scope == CountScope.items)
            DashSelect<String>(
              key: const ValueKey('count-scope-add'),
              placeholder: t('inventory.stocktakes.addItem'),
              semanticLabel: t('inventory.stocktakes.addItem'),
              searchable: true,
              value: null,
              onChanged: (id) {
                if (!_items.contains(id)) setState(() => _items.add(id));
              },
              options: [
                // An archived (or inactive) ingredient is not offered.
                for (final i in pickableOrChosen(catalog ?? const []))
                  if (!_items.contains(i.id))
                    DashOption(
                      value: i.id,
                      label: i.name,
                      hint: i.categoryName,
                    ),
              ],
            ),
          if (_scope == CountScope.items && _items.isNotEmpty)
            Column(
              key: const ValueKey('count-scope-items'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.xs,
              children: [
                for (final id in _items)
                  Container(
                    key: ValueKey('count-scope-item-$id'),
                    padding: const EdgeInsetsDirectional.only(
                      start: Space.md,
                      end: Space.xs,
                      top: Space.xs,
                      bottom: Space.xs,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: c.hairline),
                      borderRadius: BorderRadius.circular(Radii.xs),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: MadarClippedText(
                            nameOf(id),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DashType.body.copyWith(color: c.textPrimary),
                          ),
                        ),
                        DashIconButton(
                          icon: 'x',
                          iconSize: IconSize.xs,
                          semanticLabel: t('common.remove'),
                          onPressed: () => setState(() => _items.remove(id)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(
          key: const ValueKey('count-scope-start'),
          label: t('inventory.stocktakes.startCount'),
          loading: _starting,
          onPressed: _ready ? _start : null,
        ),
      ],
    );
  }
}
