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
import 'package:dashboard_core/shell.dart'
    show DashRoutePrefetch, publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../recipes/recipe_providers.dart' show addonIngredientsProvider;
import '../shared/category_dialog.dart';
import '../shared/menu_no_org.dart';
import '../shared/menu_providers.dart';
import '../shared/menu_queries.dart';
import '../shared/menu_text.dart';
import 'addon_dialog.dart';
import 'addon_recipe_dialog.dart';
import 'category_reorder_list.dart';
import 'item_dialog.dart';
import 'items_data.dart';
import 'items_export.dart';
import 'items_providers.dart';
import 'items_widgets.dart';

class MenuItemsPage extends ConsumerStatefulWidget {
  const MenuItemsPage({this.recipe, super.key});

  /// `?recipe=missing|has` (the Setup page's recipes row): opens the items
  /// tab on that filter, over what the page remembered.
  final String? recipe;

  @override
  ConsumerState<MenuItemsPage> createState() => _MenuItemsPageState();
}

class _MenuItemsPageState extends ConsumerState<MenuItemsPage>
    with DashRememberedState {
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

  // ── memory: the tab, filters, searches and pages come back with the page
  // (from the item studio, a combo, anywhere), `DashRememberedState`. ──

  @override
  String get memoryKey => 'menu.items';

  @override
  Map<String, Object?> get rememberedValues => {
    'tab': _tab.name,
    'category': _category,
    'recipe': _recipe.name,
    'addonType': _addonType,
    'itemsPage': _itemsPage,
    'itemsSearch': _itemsSearch,
    'gridSearch': _gridSearch,
    'gridPage': _gridPage,
  };

  @override
  void restoreRemembered(DashMemo m) {
    _tab = m.enumOr('tab', MenuTab.values, MenuTab.items);
    _category = m.string('category');
    _recipe = m.enumOr('recipe', RecipeFilter.values, RecipeFilter.all);
    _addonType = m.string('addonType');
    _itemsPage = m.getOr('itemsPage', 0);
    _itemsSearch = m.getOr('itemsSearch', '');
    _gridSearch = m.getOr('gridSearch', '');
    _gridPage = m.getOr('gridPage', 0);
    final asked = RecipeFilter.values.asNameMap()[widget.recipe];
    if (asked != null) {
      _tab = MenuTab.items;
      _recipe = asked;
      _itemsPage = 0;
    }
  }

  /// A remembered category or add-on type that is gone (deleted, renamed
  /// away) is dropped once the lists say so: back to All.
  void _dropStale(
    AsyncValue<List<Category>> categoriesQ,
    AsyncValue<List<AddonItem>> addonsQ,
  ) {
    var dropped = false;
    final categories = categoriesQ.hasValue ? categoriesQ.value : null;
    if (dashStale(_category, categories?.map((c) => c.id))) {
      _category = null;
      _itemsPage = 0;
      dropped = true;
    }
    final addons = addonsQ.hasValue ? addonsQ.value : null;
    if (dashStale(_addonType, addons?.map((a) => a.addonType))) {
      _addonType = null;
      _gridPage = 0;
      dropped = true;
    }
    if (dropped) rememberNow();
  }

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
    // Opened from a ⋯ menu: wait for the menu to close, or its focus
    // hand-back lands after the confirm's and Esc no longer reaches it.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
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

  /// The page an item opens: a combo its own editor (the web's combo check).
  static String _editorPath(MenuItemWithCosts m) =>
      m.kind == 'combo' ? '/menu/combos/${m.id}' : '/menu/items/${m.id}';

  void _openEditor(MenuItemWithCosts m) {
    final to = _editorPath(m);
    // Its Back returns here, with this page's filters (`DashListMemory`).
    ref.dashOpenedFrom(context, to);
    context.go(to);
  }

  // ── intent warm-ups (owner rule): the read a press is about to make ──

  /// A tab's reads (`prefetchAddons` for Add-ons; the others' lists).
  void _warmTab(MenuTab tab, String orgId, String? branchId, CatalogQuery q) {
    switch (tab) {
      case MenuTab.items:
        ref.warm(menuCatalogProvider(q));
        if (branchId != null) ref.warm(branchMenuOverridesProvider(branchId));
      case MenuTab.addons:
        ref
          ..warm(addonItemsProvider(orgId))
          ..warm(addonCostsProvider(orgId));
        if (branchId != null) ref.warm(branchAddonOverridesProvider(branchId));
      case MenuTab.categories:
        ref.warm(menuCategoriesProvider(orgId));
    }
  }

  /// The page a card opens (the studio, or a combo's editor), warmed
  /// through the route registry.
  void _warmItem(MenuItemWithCosts m) => ref.prefetchRoute(_editorPath(m));

  /// The catalog page [q] with other filters (page 1 unless given).
  static CatalogQuery _with(
    CatalogQuery q, {
    String? categoryId,
    bool? hasRecipe,
    int page = 1,
  }) => (
    orgId: q.orgId,
    categoryId: categoryId,
    search: q.search,
    hasRecipe: hasRecipe,
    page: page,
  );

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
    // The export's logo (`useExportLogo`): the org's public brand, on mount.
    ref.watch(publicBrandProvider);
    final categoriesQ = ref.watch(menuCategoriesProvider(orgId));
    final addonsQ = ref.watch(addonItemsProvider(orgId));
    _dropStale(categoriesQ, addonsQ);
    final query = _query(orgId, canRecipes);
    final catalogQ = ref.watch(menuCatalogProvider(query));
    final catalog = catalogQ.value ?? (catalogQ.hasError ? null : _lastCatalog);
    if (catalogQ.hasValue) _lastCatalog = catalogQ.value;
    final categories = categoriesQ.value ?? const <Category>[];
    final addons = addonsQ.value ?? const <AddonItem>[];

    final tabs = MenuTabsBar(
      value: _tab,
      onChanged: (v) => setState(() => _tab = v),
      onIntent: (v) => _warmTab(v, orgId, branchId, query),
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
        loading: catalog == null && catalogQ.awaitingFirst,
        failed: catalog == null && catalogQ.failedFirst
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
        loading: addonsQ.awaitingFirst,
        failed: addonsQ.failedFirst
            ? _failed(addonsQ, () => ref.invalidate(addonItemsProvider(orgId)))
            : null,
      ),
      MenuTab.categories => _categoriesTab(
        orgId: orgId,
        categories: categories,
        loading: categoriesQ.awaitingFirst,
        failed: categoriesQ.failedFirst
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
    final pages = catalog?.totalPages ?? 0;
    return DashEditableCardGrid<MenuItemWithCosts>(
      key: const ValueKey('menu-grid-items'),
      rows: catalog?.data ?? const [],
      rowKey: (m) => m.id,
      titleField: DashEditableField<MenuItemWithCosts>(
        key: 'name',
        label: t('common.name'),
        getValue: (m) => m.name,
        display: (context, m) => Text(
          _name(m.name, m.nameTranslations),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: DashType.bodyStrong.copyWith(
            color: context.madarColors.textPrimary,
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
      image: (context, m) => MenuImageTile(
        url: menuImageUrl(m.image, m.imageUrl),
        icon: 'cup-soda',
      ),
      footer: (context, m) => Column(
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
      // Pointing at a card (or focusing in it) warms the page it opens.
      onItemIntent: _warmItem,
      actions: (m) => [
        if (m.kind == 'combo')
          DashMenuItem(
            label: t('menu.grid.comboEditor'),
            icon: 'pencil',
            onSelected: () => _openEditor(m),
            to: '/menu/combos/${m.id}',
          )
        else ...[
          DashMenuItem(
            label: t('menu.grid.fullEditor'),
            icon: 'pencil',
            onSelected: () => _openEditor(m),
            to: _editorPath(m),
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
      pageCount: pages,
      onPageChanged: (p) => setState(() => _itemsPage = p),
      // `prefetchNextItemsPage`, both ways: the same params, that page.
      onPageIntent: (p) {
        if (p < 0 || p >= pages) return;
        ref.warm(
          menuCatalogProvider(
            _with(
              query,
              categoryId: query.categoryId,
              hasRecipe: query.hasRecipe,
              page: p + 1,
            ),
          ),
        );
      },
      loading: loading,
      onAdd: () => showMenuItemDialog(
        context,
        orgId: orgId,
        defaultCategoryId: _category,
      ),
      // The new-item dialog's reads (the page already holds the categories).
      onAddIntent: () => ref
        ..warm(menuCategoriesProvider(orgId))
        ..warm(ingredientCatalogProvider(orgId))
        ..warm(addonItemsProvider(orgId))
        ..warm(modifierGroupsProvider((orgId: orgId, includeInactive: false))),
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
            onOptionIntent: (v) => ref.warm(
              menuCatalogProvider(
                _with(query, categoryId: v, hasRecipe: query.hasRecipe),
              ),
            ),
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
              onOptionIntent: (v) => ref.warm(
                menuCatalogProvider(
                  _with(
                    query,
                    categoryId: query.categoryId,
                    hasRecipe: hasRecipeParam(v ?? RecipeFilter.all),
                  ),
                ),
              ),
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
          onIntent: () => ref.warm(
            modifierGroupsProvider((orgId: orgId, includeInactive: false)),
          ),
        ),
        DashMenuItem(
          label: t('menu.addonRecipe.edit'),
          icon: 'chef-hat',
          onSelected: () =>
              showAddonRecipeDialog(context, orgId: orgId, addon: a),
          onIntent: () => ref
            ..warm(addonIngredientsProvider(a.id))
            ..warm(ingredientCatalogProvider(orgId)),
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
      onAddIntent: () => ref.warm(
        modifierGroupsProvider((orgId: orgId, includeInactive: false)),
      ),
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
