/// `/settings/kitchen-routing` Order routing (web
/// `features/kitchen-stations/routing-page.tsx`, SET-KRT-001..021): each
/// menu category sent to one of the header branch's active stations, and a
/// per-item override over the org catalogue (searched, 50 a page). A choice
/// saves at once. "Export Excel" writes both views.
///
/// Rendered inside the settings shell (`routes.dart`), so its
/// [DashPageScaffold] draws as a pane. Nothing is gated in the client: the
/// reads 403 into the page's error and the writes toast the refusal.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        ApiRequest,
        ApiResponse,
        ApiTransport,
        Category,
        CategoryRouteInput,
        DashboardApi,
        ItemRouteInput,
        MenuItemWithCosts,
        PaginatedMenuItems;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kitchen_data.dart';
import 'kitchen_stations_page.dart' show kitchenSelectWidth;

/// The two views (page state, not in the URL).
enum KitchenRoutingTab { categories, items }

/// A station select from 640 wide (`sm:w-52`).
const double _selectWidthSm = 208;

/// The item search from 640 wide (`sm:w-64`).
const double _searchWidthSm = 256;

class KitchenRoutingPage extends ConsumerStatefulWidget {
  const KitchenRoutingPage({super.key});

  @override
  ConsumerState<KitchenRoutingPage> createState() => _KitchenRoutingPageState();
}

class _KitchenRoutingPageState extends ConsumerState<KitchenRoutingPage> {
  KitchenRoutingTab _tab = KitchenRoutingTab.categories;

  /// The settled search (300 ms after the last keystroke).
  String _search = '';

  /// 0-based.
  int _page = 0;
  bool _exporting = false;

  /// The last catalogue page shown (`keepPreviousData`).
  PaginatedMenuItems? _lastCatalog;

  Future<void> _write(Future<void> Function() write) async {
    final t = ref.read(tProvider);
    final bus = ref.read(realtimeBusProvider);
    try {
      await write();
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
      return;
    }
    invalidateRouting(bus);
  }

  void _setCategoryRoute(String branchId, String categoryId, String v) {
    final api = ref.read(apiProvider).kitchen;
    _write(
      () => v == kitchenUnassigned
          ? api.deleteCategoryRoute(branchId: branchId, categoryId: categoryId)
          : api.putCategoryRoute(
              body: CategoryRouteInput(
                branchId: branchId,
                categoryId: categoryId,
                stationId: v,
              ),
            ),
    );
  }

  void _setItemRoute(String branchId, String itemId, String v) {
    final api = ref.read(apiProvider).kitchen;
    _write(
      () => v == kitchenUnassigned
          ? api.deleteItemRoute(branchId: branchId, menuItemId: itemId)
          : api.putItemRoute(
              body: ItemRouteInput(
                branchId: branchId,
                menuItemId: itemId,
                stationId: v,
              ),
            ),
    );
  }

  /// Both views in one file: the categories that have loaded, and EVERY
  /// catalogue page under the current search (a sheet that stopped at the
  /// first page would read as "these items have no station").
  Future<void> _export({
    required String orgId,
    required KitchenRouting routing,
    required List<Category> categories,
  }) async {
    final t = ref.read(tProvider);
    final lang = ref.read(localeProvider);
    final brand = ref.read(publicBrandProvider).value;
    final exporter = ref.read(exporterProvider);
    final api = DashboardApi(
      _HeaderTransport(ref.read(transportProvider), exportRequestHeaders),
    );
    final search = _search.isEmpty ? null : _search;
    setState(() => _exporting = true);
    final List<MenuItemWithCosts> items;
    try {
      items = await fetchAllPages<MenuItemWithCosts>((offset, limit) async {
        final res = await api.menu.listMenuCatalog(
          orgId: orgId,
          search: search,
          page: offset ~/ limit + 1,
          perPage: limit,
        );
        return ExportPage(res.data, total: res.total);
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() => _exporting = false);
        DashToast.error(
          context,
          e is ExportTooLargeError ? e.message(t) : errorMessage(e, t),
        );
      }
      return;
    }
    if (!mounted) return;
    final unassigned = t('kitchen.unassigned');
    final title = t('kitchen.routingTitle');
    final config = ExcelConfig(
      filename: 'Madar-Order-Routing',
      logoUrl: brand?.customBranding == true ? brand?.logoUrl : null,
      sheets: [
        ExcelSheet<Category>(
          name: t('kitchen.byCategory'),
          title: title,
          subtitle: t('kitchen.byCategory'),
          rows: categories,
          columns: [
            ExcelColumn(
              header: t('kitchen.category'),
              accessor: (c) => kitchenName(c.name, c.nameTranslations, lang),
              type: ExcelColumnType.text,
              width: 30,
            ),
            ExcelColumn(
              header: t('kitchen.station'),
              accessor: (c) =>
                  routing.stationName(routing.byCategory[c.id]) ?? unassigned,
              type: ExcelColumnType.text,
              width: 26,
            ),
          ],
        ),
        ExcelSheet<MenuItemWithCosts>(
          name: t('kitchen.byItem'),
          title: title,
          subtitle: search ?? t('kitchen.byItem'),
          rows: items,
          columns: [
            ExcelColumn(
              header: t('kitchen.item'),
              accessor: (it) => kitchenName(it.name, it.nameTranslations, lang),
              type: ExcelColumnType.text,
              width: 32,
            ),
            ExcelColumn(
              header: t('kitchen.inheritedStation'),
              accessor: (it) => routing.inherited(it) ?? '—',
              type: ExcelColumnType.text,
              width: 24,
            ),
            ExcelColumn(
              header: t('kitchen.overrideStation'),
              accessor: (it) => routing.override(it) ?? '—',
              type: ExcelColumnType.text,
              width: 24,
            ),
            ExcelColumn(
              header: t('kitchen.routedTo'),
              accessor: (it) =>
                  routing.override(it) ?? routing.inherited(it) ?? unassigned,
              type: ExcelColumnType.text,
              width: 26,
            ),
          ],
        ),
      ],
    );
    final toast = DashToast.loading(context, t('excel.generating'));
    final outcome = await exporter.exportToExcel(config);
    toast.update(
      outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
      outcome.message(t),
    );
    if (mounted) setState(() => _exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final branchId = ref.watch(currentScopeProvider.select((s) => s.branchId));
    final orgId = ref.watch(orgIdProvider);
    // A new branch starts the item list from its first page.
    ref.listen(
      currentScopeProvider.select((s) => s.branchId),
      (_, _) => setState(() => _page = 0),
    );
    final title = t('kitchen.routingTitle');
    final subtitle = t('kitchen.routingSubtitle');
    if (branchId == null) {
      return DashPageScaffold(
        title: title,
        subtitle: subtitle,
        width: DashPageWidth.reading,
        body: DashEmptyState(
          key: const ValueKey('routing-pick-branch'),
          icon: 'store',
          title: t('kitchen.pickBranch'),
        ),
      );
    }
    // The export's logo (the shop's own on the branding tier).
    ref.watch(publicBrandProvider);
    final stationsQ = ref.watch(kitchenStationsProvider(branchId));
    final categoriesQ = orgId == null
        ? null
        : ref.watch(kitchenCategoriesProvider(orgId));
    final routesQ = ref.watch(kitchenRoutesProvider(branchId));
    final routing = KitchenRouting(
      stations: stationsQ.value ?? const [],
      routes: routesQ.value,
    );
    final categories = categoriesQ?.value ?? const <Category>[];
    final ready = routing.active.isNotEmpty;

    // The web's `stationsQ.error ?? categoriesQ.error ?? routesQ.error`.
    final failedQ = [
      stationsQ,
      categoriesQ,
      routesQ,
    ].where((q) => q?.failedFirst ?? false).firstOrNull;
    bool firstLoad(AsyncValue<Object?>? q) => q?.awaitingFirst ?? false;

    final catalogKey = orgId == null
        ? null
        : (
            orgId: orgId,
            search: _search.isEmpty ? null : _search,
            page: _page + 1,
          );
    // Read only on the Per item tab (`enabled: tab === "items"`).
    final catalogQ = _tab == KitchenRoutingTab.items && catalogKey != null
        ? ref.watch(kitchenCatalogProvider(catalogKey))
        : null;
    if (catalogQ?.hasValue ?? false) _lastCatalog = catalogQ!.value;

    final wideSm = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    Widget body;
    if (failedQ != null) {
      body = DashErrorState(
        key: const ValueKey('routing-error'),
        title: t('kitchen.routingLoadFailed'),
        message: errorMessage(failedQ.error, t),
        retrying: [stationsQ, categoriesQ, routesQ].any(
          (q) => q?.isLoading ?? false,
        ),
        onRetry: () {
          ref.invalidate(kitchenStationsProvider(branchId));
          if (orgId != null) ref.invalidate(kitchenCategoriesProvider(orgId));
          ref.invalidate(kitchenRoutesProvider(branchId));
        },
      );
    } else if (firstLoad(stationsQ) || firstLoad(routesQ)) {
      body = const RoutingSkeleton();
    } else if (!ready) {
      body = DashEmptyState(
        key: const ValueKey('routing-no-stations'),
        icon: 'store',
        title: t('kitchen.noStationsForRouting'),
        description: t('kitchen.noStationsForRoutingHint'),
      );
    } else if (_tab == KitchenRoutingTab.categories) {
      if (firstLoad(categoriesQ)) {
        body = const RoutingSkeleton();
      } else if (categories.isEmpty) {
        body = DashEmptyState(
          key: const ValueKey('routing-no-categories'),
          title: t('kitchen.noCategories'),
        );
      } else {
        body = DashListCard(
          key: const ValueKey('routing-categories'),
          children: [
            for (final c in categories)
              DashListRow(
                key: ValueKey('routing-category-${c.id}'),
                title: kitchenName(c.name, c.nameTranslations, lang),
                trailing: _StationSelect(
                  key: ValueKey('routing-category-select-${c.id}'),
                  routing: routing,
                  stationId: routing.byCategory[c.id],
                  noneLabel: t('kitchen.unassigned'),
                  rowLabel: kitchenName(c.name, c.nameTranslations, lang),
                  width: wideSm ? _selectWidthSm : kitchenSelectWidth,
                  onChanged: (v) => _setCategoryRoute(branchId, c.id, v),
                ),
              ),
          ],
        );
      }
    } else {
      body = _itemsView(
        t: t,
        lang: lang,
        branchId: branchId,
        routing: routing,
        catalogQ: catalogQ,
        catalogKey: catalogKey,
        selectWidth: wideSm ? _selectWidthSm : kitchenSelectWidth,
      );
    }

    return DashPageScaffold(
      title: title,
      subtitle: subtitle,
      width: DashPageWidth.reading,
      actions: [
        if (ready)
          DashExportButton(
            key: const ValueKey('routing-export'),
            loading: _exporting,
            onExport: () {
              // `handleExport` returns at once without an org.
              if (orgId == null) return;
              _export(orgId: orgId, routing: routing, categories: categories);
            },
          ),
      ],
      tabs: ready
          ? Wrap(
              key: const ValueKey('routing-tabs'),
              spacing: Space.md,
              runSpacing: Space.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DashSegmentedControl<KitchenRoutingTab>(
                  value: _tab,
                  onChanged: (v) => setState(() => _tab = v),
                  // "Per item" reads the catalogue page it opens on.
                  onIntent: (v) {
                    if (v == KitchenRoutingTab.items && catalogKey != null) {
                      ref.warm(kitchenCatalogProvider(catalogKey));
                    }
                  },
                  options: [
                    DashOption(
                      value: KitchenRoutingTab.categories,
                      label: t('kitchen.byCategory'),
                    ),
                    DashOption(
                      value: KitchenRoutingTab.items,
                      label: t('kitchen.byItem'),
                    ),
                  ],
                ),
                if (_tab == KitchenRoutingTab.items)
                  LayoutBuilder(
                    builder: (context, box) => DashSearchInput(
                      key: const ValueKey('routing-search'),
                      value: _search,
                      placeholder: t('common.search'),
                      debounce: DashSearchInput.listDelay,
                      width: wideSm ? _searchWidthSm : box.maxWidth,
                      onChanged: (v) => setState(() {
                        _search = v;
                        _page = 0;
                      }),
                    ),
                  ),
              ],
            )
          : null,
      body: body,
    );
  }

  Widget _itemsView({
    required Translator t,
    required String lang,
    required String branchId,
    required KitchenRouting routing,
    required AsyncValue<PaginatedMenuItems>? catalogQ,
    required KitchenCatalogKey? catalogKey,
    required double selectWidth,
  }) {
    final failed = catalogQ?.failedFirst ?? false;
    // `keepPreviousData`: the last page stays while the next one loads.
    final shown = failed ? null : catalogQ?.value ?? _lastCatalog;
    final loading = !failed && shown == null && catalogQ != null;
    final items = shown?.data ?? const <MenuItemWithCosts>[];
    final pageCount = shown?.totalPages ?? 0;
    Widget list;
    if (failed) {
      list = DashErrorState(
        key: const ValueKey('routing-items-error'),
        title: t('kitchen.itemsLoadFailed'),
        message: errorMessage(catalogQ!.error, t),
        retrying: catalogQ.isLoading,
        onRetry: () => ref.invalidate(kitchenCatalogProvider(catalogKey!)),
      );
    } else if (loading) {
      list = const RoutingSkeleton();
    } else if (items.isEmpty) {
      list = DashEmptyState(
        key: const ValueKey('routing-no-items'),
        icon: 'search',
        title: t('kitchen.noItems'),
      );
    } else {
      list = DashListCard(
        key: const ValueKey('routing-items'),
        children: [
          for (final it in items)
            DashListRow(
              key: ValueKey('routing-item-${it.id}'),
              title: kitchenName(it.name, it.nameTranslations, lang),
              meta: _itemMeta(t, routing, it),
              trailing: _StationSelect(
                key: ValueKey('routing-item-select-${it.id}'),
                routing: routing,
                stationId: routing.byItem[it.id],
                noneLabel: t('kitchen.inheritCategory'),
                rowLabel: kitchenName(it.name, it.nameTranslations, lang),
                width: selectWidth,
                onChanged: (v) => _setItemRoute(branchId, it.id, v),
              ),
            ),
        ],
      );
    }
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        Text(
          t('kitchen.byItemHint'),
          style: DashType.body.copyWith(color: c.textSecondary),
        ),
        list,
        if (pageCount > 1 && !failed)
          DashPagination(
            key: const ValueKey('routing-pager'),
            pageIndex: _page,
            pageCount: pageCount,
            onChanged: (p) => setState(() => _page = p),
            onIntent: (p) => ref.warm(
              kitchenCatalogProvider((
                orgId: catalogKey!.orgId,
                search: catalogKey.search,
                page: p + 1,
              )),
            ),
          ),
      ],
    );
  }

  /// "Overridden" when the item has its own route (to any station), else
  /// the station it inherits, else "No category station".
  String _itemMeta(Translator t, KitchenRouting r, MenuItemWithCosts it) {
    if (r.byItem.containsKey(it.id)) return t('kitchen.overridden');
    final inherited = r.inherited(it);
    return inherited == null
        ? t('kitchen.noInheritedStation')
        : t('kitchen.inheritsStation', args: {'station': inherited});
  }
}

/// A row's station select: [noneLabel] ("Default / unassigned", "Inherit
/// (category)") and the active stations. A route to a station that is not
/// offered (inactive) reads as an empty select (SET-KRT-019).
class _StationSelect extends StatelessWidget {
  const _StationSelect({
    required this.routing,
    required this.stationId,
    required this.noneLabel,
    required this.rowLabel,
    required this.width,
    required this.onChanged,
    super.key,
  });

  final KitchenRouting routing;
  final String? stationId;
  final String noneLabel;
  final String rowLabel;
  final double width;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = routing.selectValue(stationId);
    return DashSelect<String>(
      value: value,
      width: width,
      expand: false,
      placeholder: value == null ? '' : noneLabel,
      semanticLabel: rowLabel,
      options: [
        DashOption(value: kitchenUnassigned, label: noneLabel),
        for (final s in routing.active) DashOption(value: s.id, label: s.name),
      ],
      onChanged: onChanged,
    );
  }
}

/// Six skeleton rows (a title bar and a select bar), as the web's.
class RoutingSkeleton extends StatelessWidget {
  const RoutingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final wideSm = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    return DashListCard(
      key: const ValueKey('routing-skeleton'),
      children: [
        for (var i = 0; i < 6; i++)
          Container(
            constraints: const BoxConstraints(minHeight: DashMetrics.listRow),
            padding: EdgeInsets.symmetric(
              horizontal: wideSm ? Space.card : Space.lg,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              spacing: Space.md,
              children: [
                const Flexible(child: DashSkeleton(width: 160)),
                DashSkeleton(
                  width: wideSm ? _selectWidthSm : kitchenSelectWidth,
                  height: Space.xxl + Space.xs,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Every request through [inner] carries [headers] (`X-Madar-Export: 1`).
class _HeaderTransport implements ApiTransport {
  _HeaderTransport(this.inner, this.headers);

  final ApiTransport inner;
  final Map<String, String> headers;

  ApiRequest _with(ApiRequest r) => ApiRequest(
    method: r.method,
    path: r.path,
    query: r.query,
    body: r.body,
    files: r.files,
    headers: {...r.headers, ...headers},
  );

  @override
  Future<ApiResponse> send(ApiRequest request) => inner.send(_with(request));

  @override
  Stream<String> stream(ApiRequest request) => inner.stream(_with(request));
}
