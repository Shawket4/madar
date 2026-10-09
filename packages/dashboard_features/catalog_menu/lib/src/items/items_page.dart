/// `/menu/items`: the menu (Items / Add-ons / Categories tabs), their dialogs,
/// paste rows and the export (MENU-ITEMS rows and the area-wide MENU-AREA
/// rows). Web: `features/menu/menu-items-page.tsx`.
///
/// One card grid for every tab, as the web's `EditableCardGrid` (the same
/// cards at every width: one column on a phone). Items are server-paged 24 at
/// a time with the previous page kept on screen while the next loads;
/// add-ons and categories are whole lists searched and paged here, and their
/// search and page are one state shared by the two tabs, as on the web
/// (MENU-ITEMS-108). A list read that failed with nothing to show says so,
/// with Retry (the web shows its empty state there; see the divergences).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart'
    show
        AddonItem,
        Category,
        CreateMenuItemRequest,
        DashboardApi,
        MenuItemWithCosts,
        PaginatedMenuItems,
        PatchOptionRequest,
        UpdateCategoryRequest,
        UpdateMenuItemRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/category_dialog.dart';
import '../shared/menu_no_org.dart';
import '../shared/menu_providers.dart';
import '../shared/menu_queries.dart';
import '../shared/menu_text.dart';
import '../studio/studio_providers.dart'
    show menuStudioProvider, studioMenuItemProvider;
import 'addon_dialog.dart';
import 'addon_recipe_dialog.dart';
import 'category_reorder_list.dart';
import 'item_dialog.dart';
import 'items_data.dart';
import 'items_export.dart';
import 'items_providers.dart';
import 'items_widgets.dart';

class MenuItemsPage extends ConsumerStatefulWidget {
  const MenuItemsPage({super.key});

  @override
  ConsumerState<MenuItemsPage> createState() => _MenuItemsPageState();
}

class _MenuItemsPageState extends ConsumerState<MenuItemsPage> {
  MenuTab _tab = MenuTab.items;
  String? _category;
  RecipeFilter _recipe = RecipeFilter.all;
  String? _addonType;
  int _itemsPage = 0;
  String _itemsSearch = '';

  /// The add-ons' and categories' search and page: one state for both tabs.
  String _gridSearch = '';
  int _gridPage = 0;
  bool _reordering = false;
  bool _exporting = false;

  /// The last catalog page shown (`keepPreviousData`).
  PaginatedMenuItems? _lastCatalog;

  Translator get _t => ref.read(tProvider);

  CatalogQuery _query(String orgId, bool canRecipes) => (
    orgId: orgId,
    categoryId: _category,
    search: _itemsSearch.isEmpty ? null : _itemsSearch,
    hasRecipe: canRecipes ? hasRecipeParam(_recipe) : null,
    page: _itemsPage + 1,
  );

  String _name(String name, Object? tr) => translatedName(name, tr, _t.lang);

  // ── writes ────────────────────────────────────────────────────────────

  Future<void> _write(Future<void> Function(DashboardApi api) op) async {
    final t = _t;
    final api = ref.read(apiProvider);
    final invalidate = ref.menuInvalidate;
    try {
      await op(api);
      invalidate.catalog();
      if (mounted) DashToast.success(context, t('common.savedChanges'));
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    }
  }

  Future<void> _commitItem(MenuItemWithCosts m, Map<String, Object?> patch) =>
      _write(
        (api) => api.menu.updateMenuItem(
          id: m.id,
          body: UpdateMenuItemRequest.fromJson(patch),
        ),
      );

  /// An add-on is a modifier option: the card's fields map onto the option
  /// patch; its type (the group) is not one of them, so a Type edit sends an
  /// empty patch (MENU-ITEMS-050).
  Future<void> _commitAddon(AddonItem a, Map<String, Object?> patch) => _write(
    (api) => api.menu.patchOption(
      oid: a.id,
      body: PatchOptionRequest(
        price: patch['default_price'] as int?,
        isActive: patch['is_active'] as bool?,
        name: patch['name'] as String?,
      ),
    ),
  );

  Future<void> _commitCategory(Category c, Map<String, Object?> patch) =>
      _write(
        (api) => api.menu.updateCategory(
          id: c.id,
          body: UpdateCategoryRequest.fromJson(patch),
        ),
      );

  Future<void> _confirmDelete(
    String name,
    String description,
    Future<void> Function(DashboardApi api) run,
  ) async {
    final ok = await showDashConfirm(
      context,
      title: _t('common.confirmDelete', args: {'name': name}),
      description: description,
      confirmLabel: _t('common.delete'),
      destructive: true,
    );
    if (ok && mounted) await _write(run);
  }

  Future<void> _duplicate(MenuItemWithCosts m) async {
    final t = _t;
    final api = ref.read(apiProvider).menu;
    final invalidate = ref.menuInvalidate;
    try {
      final copy = await api.duplicateItem(id: m.id);
      await api.updateMenuItem(
        id: copy.id,
        body: const UpdateMenuItemRequest(isActive: false),
      );
      invalidate.catalog();
      if (mounted) {
        DashToast.success(
          context,
          t(
            'menu.grid.duplicated',
            args: {'name': _name(m.name, m.nameTranslations)},
          ),
        );
      }
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    }
  }

  Future<void> _createFromPaste(
    String orgId,
    List<Category> categories,
    List<Map<String, String>> rows,
  ) async {
    final t = _t;
    final api = ref.read(apiProvider).menu;
    final invalidate = ref.menuInvalidate;
    final r = await runBulk(rows, (row) async {
      final categoryId = pasteCategoryId(row, categories);
      if (categoryId == null) throw StateError(row['category'] ?? '');
      final desc = row['description'] ?? '';
      await api.createMenuItem(
        body: CreateMenuItemRequest(
          orgId: orgId,
          name: row['name'] ?? '',
          basePrice: pastePricePiastres(row),
          categoryId: categoryId,
          description: desc.isEmpty ? null : desc,
          explicitNulls: const {'description'},
        ),
      );
    });
    invalidate.catalog();
    if (!mounted) return;
    if (r.failed.isNotEmpty) {
      DashToast.show(
        context,
        t(
          'menu.grid.bulkCreateFailed',
          args: {'ok': r.ok.length, 'failed': r.failed.length},
        ),
        kind: DashToastKind.error,
        actionLabel: t('menu.grid.retryFailed'),
        onAction: () => _createFromPaste(orgId, categories, r.failed),
      );
    } else {
      DashToast.success(
        context,
        t('menu.grid.bulkCreated', args: {'count': r.ok.length}),
      );
    }
  }

  Future<void> _export(
    CatalogQuery query,
    List<Category> categories,
    List<AddonItem> addons,
  ) async {
    setState(() => _exporting = true);
    try {
      await exportMenu(
        context,
        ref,
        query: query,
        categories: categories,
        addons: addons,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// The web's combo check: a combo opens its own editor.
  void _openEditor(MenuItemWithCosts m) => m.kind == 'combo'
      ? context.go('/menu/combos/${m.id}')
      : context.go('/menu/items/${m.id}');

  void _prefetchAddons(String orgId) {
    final warm = DashPrefetcher(
      ProviderScope.containerOf(context, listen: false),
    );
    warm(addonItemsProvider(orgId));
    warm(addonCostsProvider(orgId));
  }

  // ── build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final orgId = ref.watch(orgIdProvider);
    if (orgId == null) {
      return DashPageScaffold(
        title: t('nav.menu'),
        body: const MenuNoOrgState(),
      );
    }
    final branchId = ref.watch(scopeProvider.select((s) => s.branchId));
    final canRecipes = ref.watch(
      authzProvider.select((a) => a.can(Cap.recipesRead)),
    );
    final query = _query(orgId, canRecipes);

    // The export's logo (`useExportLogo`): the org's public brand, on mount.
    ref.watch(publicBrandProvider);
    final categoriesQ = ref.watch(menuCategoriesProvider(orgId));
    final addonsQ = ref.watch(addonItemsProvider(orgId));
    final catalogQ = ref.watch(menuCatalogProvider(query));
    final catalog = catalogQ.value ?? (catalogQ.hasError ? null : _lastCatalog);
    if (catalogQ.hasValue) _lastCatalog = catalogQ.value;
    final categories = categoriesQ.value ?? const <Category>[];
    final addons = addonsQ.value ?? const <AddonItem>[];

    final tabs = MenuTabsBar(
      value: _tab,
      onChanged: (v) => setState(() => _tab = v),
      onHoverAddons: () => _prefetchAddons(orgId),
      tabs: [
        (tab: MenuTab.items, label: t('nav.items'), count: catalog?.total ?? 0),
        (tab: MenuTab.addons, label: t('menu.addons'), count: addons.length),
        (
          tab: MenuTab.categories,
          label: t('menu.categories'),
          count: categories.length,
        ),
      ],
    );

    final Widget grid = switch (_tab) {
      MenuTab.items => _itemsGrid(
        orgId: orgId,
        branchId: branchId,
        canRecipes: canRecipes,
        query: query,
        catalog: catalog,
        loading: catalog == null && catalogQ.isLoading && !catalogQ.hasError,
        failed: catalog == null && catalogQ.hasError
            ? _failed(
                catalogQ,
                () => ref.invalidate(menuCatalogProvider(query)),
              )
            : null,
        categories: categories,
        addons: addons,
      ),
      MenuTab.addons => _addonsGrid(
        orgId: orgId,
        branchId: branchId,
        addons: addons,
        loading: addonsQ.isLoading && !addonsQ.hasValue && !addonsQ.hasError,
        failed: addonsQ.hasError && !addonsQ.hasValue
            ? _failed(addonsQ, () => ref.invalidate(addonItemsProvider(orgId)))
            : null,
      ),
      MenuTab.categories => _categoriesTab(
        orgId: orgId,
        categories: categories,
        loading:
            categoriesQ.isLoading &&
            !categoriesQ.hasValue &&
            !categoriesQ.hasError,
        failed: categoriesQ.hasError && !categoriesQ.hasValue
            ? _failed(
                categoriesQ,
                () => ref.invalidate(menuCategoriesProvider(orgId)),
              )
            : null,
      ),
    };

    return DashPageScaffold(
      title: t('nav.menu'),
      subtitleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: DashMetrics.hair,
        children: [
          Text(
            t('menu.subtitle'),
            style: DashType.body.copyWith(
              color: context.madarColors.textSecondary,
            ),
          ),
          const PriceTaxHint(),
        ],
      ),
      tabs: tabs,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          if (branchId == null && _tab != MenuTab.categories)
            Row(
              spacing: Space.sm,
              children: [
                DashIcon(
                  'store',
                  size: IconSize.sm,
                  color: context.madarColors.textSecondary,
                ),
                Expanded(
                  child: Text(
                    t('menu.branchToggleHint'),
                    style: DashType.body.copyWith(
                      color: context.madarColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          grid,
        ],
      ),
    );
  }

  /// A read that failed with nothing to show: its words and Retry (the
  /// button spins while the retry runs). The web shows the empty state here;
  /// see the divergence log.
  Widget _failed(AsyncValue<Object?> q, VoidCallback retry) => DashErrorState(
    key: const ValueKey('menu-read-failed'),
    title: _t('common.loadFailed'),
    message: errorMessage(q.error, _t),
    retryLabel: _t('common.retry'),
    retrying: q.isLoading,
    onRetry: retry,
  );

  DashEditableField<T> _title<T>(
    String Function(T) raw,
    String Function(T) shown,
  ) => DashEditableField<T>(
    key: 'name',
    label: _t('common.name'),
    getValue: raw,
    display: (context, r) => Text(
      shown(r),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: DashType.bodyStrong.copyWith(
        color: context.madarColors.textPrimary,
      ),
    ),
  );

  Widget _itemsGrid({
    required String orgId,
    required String? branchId,
    required bool canRecipes,
    required CatalogQuery query,
    required PaginatedMenuItems? catalog,
    required bool loading,
    required Widget? failed,
    required List<Category> categories,
    required List<AddonItem> addons,
  }) {
    final t = _t;
    final overrides = branchId == null
        ? null
        : ref.watch(branchMenuOverridesProvider(branchId)).value;
    final byItem = {for (final o in overrides ?? const []) o.menuItemId: o};
    // Pointing at a card (or focusing in it) warms the item and its studio
    // (`prefetchItem`); the kit card has no hover hook of its own, so its
    // tile, title and footer carry it.
    Widget warm(MenuItemWithCosts m, Widget child) => WarmOnIntent(
      warm: (w) {
        w(studioMenuItemProvider(m.id));
        w(menuStudioProvider(m.id));
      },
      child: child,
    );
    final pages = catalog?.totalPages ?? 0;
    final grid = DashEditableCardGrid<MenuItemWithCosts>(
      key: const ValueKey('menu-grid-items'),
      rows: catalog?.data ?? const [],
      rowKey: (m) => m.id,
      titleField: DashEditableField<MenuItemWithCosts>(
        key: 'name',
        label: t('common.name'),
        getValue: (m) => m.name,
        display: (context, m) => warm(
          m,
          Text(
            _name(m.name, m.nameTranslations),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashType.bodyStrong.copyWith(
              color: context.madarColors.textPrimary,
            ),
          ),
        ),
      ),
      fields: [
        DashEditableField(
          key: 'base_price',
          label: t('common.price'),
          type: DashEditableType.money,
          getValue: (m) => m.basePrice,
          editable: false,
        ),
        DashEditableField(
          key: 'category_id',
          label: t('common.category'),
          type: DashEditableType.select,
          options: [
            for (final c in categories)
              DashOption(value: c.id, label: _name(c.name, c.nameTranslations)),
          ],
          getValue: (m) => m.categoryId ?? '',
        ),
        DashEditableField(
          key: 'is_active',
          label: t('common.active'),
          type: DashEditableType.boolean,
          getValue: (m) => m.isActive,
        ),
      ],
      onCommit: _commitItem,
      image: (context, m) => warm(
        m,
        MenuImageTile(url: menuImageUrl(m.image, m.imageUrl), icon: 'cup-soda'),
      ),
      footer: (context, m) => warm(
        m,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm,
          children: [
            ItemCostFooter(item: m),
            if (branchId != null)
              ItemBranchSwitch(
                key: ValueKey('branch-switch-${m.id}'),
                branchId: branchId,
                itemId: m.id,
                row: byItem[m.id],
              ),
          ],
        ),
      ),
      actions: (m) => [
        if (m.kind == 'combo')
          DashMenuItem(
            label: t('menu.grid.comboEditor'),
            icon: 'pencil',
            onSelected: () => _openEditor(m),
          )
        else ...[
          DashMenuItem(
            label: t('menu.grid.fullEditor'),
            icon: 'pencil',
            onSelected: () => _openEditor(m),
          ),
          DashMenuItem(
            label: t('menu.grid.duplicate'),
            icon: 'copy',
            onSelected: () => unawaited(_duplicate(m)),
          ),
        ],
        DashMenuItem(
          label: t('common.delete'),
          icon: 'trash-2',
          destructive: true,
          onSelected: () => unawaited(
            _confirmDelete(
              _name(m.name, m.nameTranslations),
              t('menu.deleteItemConsequence'),
              (api) => api.menu.deleteMenuItem(id: m.id),
            ),
          ),
        ),
      ],
      searchValue: _itemsSearch,
      onSearchChanged: (v) => setState(() {
        _itemsSearch = v;
        _itemsPage = 0;
      }),
      searchPlaceholder: t('common.search'),
      page: _itemsPage,
      // The pager is drawn below (its Next warms the next page).
      pageCount: 1,
      onPageChanged: (p) => setState(() => _itemsPage = p),
      loading: loading,
      onAdd: () => showMenuItemDialog(
        context,
        orgId: orgId,
        defaultCategoryId: _category,
      ),
      addLabel: t('menu.newItem'),
      empty:
          failed ??
          DashEmptyState(icon: 'utensils-crossed', title: t('menu.noItems')),
      toolbar: Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DashFilterSelect<String>(
            key: const ValueKey('filter-category'),
            label: t('common.category'),
            allLabel: t('menu.allCategories'),
            minWidth: 144,
            options: [
              for (final c in categories)
                DashOption(
                  value: c.id,
                  label: _name(c.name, c.nameTranslations),
                ),
            ],
            value: _category,
            onChanged: (v) => setState(() {
              _category = v;
              _itemsPage = 0;
            }),
          ),
          if (canRecipes)
            DashFilterSelect<RecipeFilter>(
              key: const ValueKey('filter-recipe'),
              label: t('menu.recipeFilter'),
              allLabel: t('menu.recipeAll'),
              minWidth: 144,
              options: [
                DashOption(
                  value: RecipeFilter.missing,
                  label: t('menu.recipeMissing'),
                ),
                DashOption(value: RecipeFilter.has, label: t('menu.recipeHas')),
              ],
              value: _recipe == RecipeFilter.all ? null : _recipe,
              onChanged: (v) => setState(() {
                _recipe = v ?? RecipeFilter.all;
                _itemsPage = 0;
              }),
            ),
          DashExportButton(
            loading: _exporting,
            onExport: () => unawaited(_export(query, categories, addons)),
          ),
        ],
      ),
      onPasteRows: (rows) => _createFromPaste(orgId, categories, rows),
      pasteValidate: (row) {
        final key = pasteRowError(row, categories);
        return key == null ? null : t(key);
      },
      pasteColumns: [
        DashPasteColumn(key: 'name', header: t('common.name')),
        DashPasteColumn(
          key: 'base_price',
          header:
              '${t('common.price')} (${ref.read(formatProvider).currencyLabel()})',
        ),
        DashPasteColumn(key: 'category', header: t('common.category')),
        DashPasteColumn(key: 'description', header: t('common.description')),
      ],
    );
    if (loading || pages <= 1) return grid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        grid,
        MenuPager(
          pageIndex: _itemsPage,
          pageCount: pages,
          onChanged: (p) => setState(() => _itemsPage = p),
          // `prefetchNextItemsPage`: the same params, the page after.
          onWarmNext: (w) {
            if (_itemsPage + 1 >= pages) return;
            w(
              menuCatalogProvider((
                orgId: query.orgId,
                categoryId: query.categoryId,
                search: query.search,
                hasRecipe: query.hasRecipe,
                page: query.page + 1,
              )),
            );
          },
        ),
      ],
    );
  }

  /// [rows] searched and paged with the shared grid state: the page clamped
  /// to the last one (`safePage`).
  ({List<T> rows, int page, int pageCount}) _clientPage<T>(
    List<T> all,
    String Function(T) text,
  ) {
    final hits = searchRows(all, _gridSearch, text);
    final pageCount = math.max(1, (hits.length / itemsPerPage).ceil());
    final page = math.min(_gridPage, pageCount - 1);
    return (
      rows: hits.skip(page * itemsPerPage).take(itemsPerPage).toList(),
      page: page,
      pageCount: pageCount,
    );
  }

  void _setGridSearch(String v) => setState(() {
    _gridSearch = v;
    _gridPage = 0;
  });

  Widget _addonsGrid({
    required String orgId,
    required String? branchId,
    required List<AddonItem> addons,
    required bool loading,
    required Widget? failed,
  }) {
    final t = _t;
    final costs = ref.watch(addonCostsProvider(orgId)).value;
    final costOf = {for (final c in costs ?? const []) c.addonItemId: c};
    final overrides = branchId == null
        ? null
        : ref.watch(branchAddonOverridesProvider(branchId)).value;
    final byAddon = {for (final o in overrides ?? const []) o.addonItemId: o};
    final types = {for (final a in addons) a.addonType}.toList()..sort();
    final filtered = _addonType == null
        ? addons
        : [
            for (final a in addons)
              if (a.addonType == _addonType) a,
          ];
    final p = _clientPage(filtered, (a) => '${a.name} ${a.addonType}');
    return DashEditableCardGrid<AddonItem>(
      key: const ValueKey('menu-grid-addons'),
      rows: p.rows,
      rowKey: (a) => a.id,
      titleField: _title(
        (a) => a.name,
        (a) => _name(a.name, a.nameTranslations),
      ),
      fields: [
        DashEditableField(
          key: 'addon_type',
          label: t('menu.addonType'),
          getValue: (a) => a.addonType,
        ),
        DashEditableField(
          key: 'default_price',
          label: t('common.price'),
          type: DashEditableType.money,
          getValue: (a) => a.defaultPrice,
        ),
        DashEditableField(
          key: 'is_active',
          label: t('common.active'),
          type: DashEditableType.boolean,
          getValue: (a) => a.isActive,
        ),
      ],
      onCommit: _commitAddon,
      image: (context, a) => const MenuImageTile(url: null, icon: 'tag'),
      footer: (context, a) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          AddonCostFooter(addonId: a.id, cost: costOf[a.id]),
          if (branchId != null)
            AddonBranchSwitch(
              key: ValueKey('branch-switch-${a.id}'),
              branchId: branchId,
              addonId: a.id,
              row: byAddon[a.id],
            ),
        ],
      ),
      actions: (a) => [
        DashMenuItem(
          label: t('common.edit'),
          icon: 'pencil',
          onSelected: () => showAddonDialog(context, orgId: orgId, addon: a),
        ),
        DashMenuItem(
          label: t('menu.addonRecipe.edit'),
          icon: 'chef-hat',
          onSelected: () =>
              showAddonRecipeDialog(context, orgId: orgId, addon: a),
        ),
        DashMenuItem(
          label: t('common.delete'),
          icon: 'trash-2',
          destructive: true,
          onSelected: () => unawaited(
            _confirmDelete(
              _name(a.name, a.nameTranslations),
              t('menu.deleteAddonConsequence'),
              (api) => api.menu.deleteOption(oid: a.id),
            ),
          ),
        ),
      ],
      searchValue: _gridSearch,
      onSearchChanged: _setGridSearch,
      searchPlaceholder: t('common.search'),
      page: p.page,
      pageCount: p.pageCount,
      onPageChanged: (n) => setState(() => _gridPage = n),
      loading: loading,
      onAdd: () => showAddonDialog(context, orgId: orgId),
      addLabel: t('menu.newAddon'),
      empty: failed ?? DashEmptyState(icon: 'tag', title: t('menu.noAddons')),
      toolbar: types.isEmpty
          ? null
          : DashFilterSelect<String>(
              key: const ValueKey('filter-addon-type'),
              label: t('menu.addonType'),
              allLabel: t('menu.allTypes'),
              minWidth: 128,
              options: [
                for (final ty in types) DashOption(value: ty, label: ty),
              ],
              value: _addonType,
              onChanged: (v) => setState(() => _addonType = v),
            ),
    );
  }

  Widget _categoriesTab({
    required String orgId,
    required List<Category> categories,
    required bool loading,
    required Widget? failed,
  }) {
    final t = _t;
    if (_reordering && failed != null) return failed;
    if (_reordering) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: DashButton(
              label: t('menu.categoriesDoneReordering'),
              variant: DashButtonVariant.outline,
              size: DashButtonSize.compact,
              onPressed: () => setState(() => _reordering = false),
            ),
          ),
          CategoryReorderList(
            orgId: orgId,
            categories: categories,
            loading: loading,
          ),
        ],
      );
    }
    final p = _clientPage(
      categories,
      (c) => '${c.name} ${_name(c.name, c.nameTranslations)}',
    );
    return DashEditableCardGrid<Category>(
      key: const ValueKey('menu-grid-categories'),
      rows: p.rows,
      rowKey: (c) => c.id,
      titleField: _title(
        (c) => c.name,
        (c) => _name(c.name, c.nameTranslations),
      ),
      fields: [
        DashEditableField(
          key: 'is_active',
          label: t('common.active'),
          type: DashEditableType.boolean,
          getValue: (c) => c.isActive,
        ),
      ],
      onCommit: _commitCategory,
      image: (context, c) =>
          MenuImageTile(url: menuImageUrl(c.image, c.imageUrl), icon: 'tag'),
      actions: (c) => [
        DashMenuItem(
          label: t('common.edit'),
          icon: 'pencil',
          onSelected: () =>
              showCategoryDialog(context, orgId: orgId, category: c),
        ),
        DashMenuItem(
          label: t('common.delete'),
          icon: 'trash-2',
          destructive: true,
          onSelected: () => unawaited(
            _confirmDelete(
              _name(c.name, c.nameTranslations),
              t('menu.deleteCategoryConsequence'),
              (api) => api.menu.deleteCategory(id: c.id),
            ),
          ),
        ),
      ],
      searchValue: _gridSearch,
      onSearchChanged: _setGridSearch,
      searchPlaceholder: t('common.search'),
      page: p.page,
      pageCount: p.pageCount,
      onPageChanged: (n) => setState(() => _gridPage = n),
      loading: loading,
      onAdd: () => showCategoryDialog(context, orgId: orgId),
      addLabel: t('menu.newCategory'),
      empty:
          failed ?? DashEmptyState(icon: 'tag', title: t('menu.noCategories')),
      toolbar: categories.length > 1
          ? DashButton(
              label: t('menu.categoriesReorder'),
              variant: DashButtonVariant.outline,
              size: DashButtonSize.compact,
              onPressed: () => setState(() => _reordering = true),
            )
          : null,
    );
  }
}
