/// The menu export (`handleExport`): the Items sheet walks the grid's own
/// catalog query (same category / search / recipe filter) 500 at a time;
/// Categories and Add-ons are the full lists. One workbook,
/// `Madar-Menu-YYYY-MM-DD.xlsx`, branded with the org's own logo on the
/// branding tier.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        AddonItem,
        ApiRequest,
        ApiResponse,
        ApiTransport,
        Category,
        DashboardApi,
        MenuItemWithCosts;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/menu_text.dart';
import 'items_providers.dart';

/// Builds and saves the workbook; toasts as `exportToExcel` does. A failed
/// walk (or a too-large one) is an error toast with its words.
Future<void> exportMenu(
  BuildContext context,
  WidgetRef ref, {
  required CatalogQuery query,
  required List<Category> categories,
  required List<AddonItem> addons,
}) async {
  final t = ref.read(tProvider);
  final api = DashboardApi(
    _HeaderTransport(ref.read(transportProvider), exportRequestHeaders),
  );
  final brand = ref.read(publicBrandProvider).value;
  String name(String n, Object? tr) => translatedName(n, tr, t.lang);
  String status(bool on) => t(on ? 'common.active' : 'common.inactive');
  String categoryName(String? id) {
    for (final c in categories) {
      if (c.id == id) return name(c.name, c.nameTranslations);
    }
    return '—';
  }

  final List<MenuItemWithCosts> items;
  try {
    items = await fetchAllPages<MenuItemWithCosts>((offset, limit) async {
      final res = await api.menu.listMenuCatalog(
        orgId: query.orgId,
        categoryId: query.categoryId,
        search: query.search,
        hasRecipe: query.hasRecipe,
        page: offset ~/ limit + 1,
        perPage: limit,
      );
      return ExportPage(res.data, total: res.total);
    });
  } on ExportTooLargeError catch (e) {
    if (context.mounted) DashToast.error(context, e.message(t));
    return;
  } on Object catch (e) {
    if (context.mounted) DashToast.error(context, errorMessage(e, t));
    return;
  }
  if (!context.mounted) return;
  if (items.isEmpty && categories.isEmpty && addons.isEmpty) {
    DashToast.error(context, const ExportNothing().message(t));
    return;
  }
  final toast = DashToast.loading(context, t('excel.generating'));
  final outcome = await ref
      .read(exporterProvider)
      .exportToExcel(
        ExcelConfig(
          filename: 'Madar-Menu',
          logoUrl: exportLogoUrl(brand),
          sheets: [
            ExcelSheet<MenuItemWithCosts>(
              name: t('nav.items'),
              title: t('nav.items'),
              rows: items,
              totals: true,
              columns: [
                ExcelColumn(
                  header: t('common.name'),
                  accessor: (m) => name(m.name, m.nameTranslations),
                  type: ExcelColumnType.text,
                  width: 26,
                ),
                ExcelColumn(
                  header: t('common.category'),
                  accessor: (m) => categoryName(m.categoryId),
                  type: ExcelColumnType.text,
                  width: 20,
                ),
                ExcelColumn(
                  header: t('common.price'),
                  accessor: (m) => m.basePrice,
                  type: ExcelColumnType.money,
                  width: 14,
                  total: true,
                ),
                ExcelColumn(
                  header: t('common.status'),
                  accessor: (m) => status(m.isActive),
                  type: ExcelColumnType.text,
                  width: 12,
                ),
              ],
            ),
            ExcelSheet<Category>(
              name: t('menu.categories'),
              title: t('menu.categories'),
              rows: categories,
              columns: [
                ExcelColumn(
                  header: t('common.name'),
                  accessor: (c) => name(c.name, c.nameTranslations),
                  type: ExcelColumnType.text,
                  width: 24,
                ),
                ExcelColumn(
                  header: t('common.status'),
                  accessor: (c) => status(c.isActive),
                  type: ExcelColumnType.text,
                  width: 12,
                ),
              ],
            ),
            ExcelSheet<AddonItem>(
              name: t('menu.addons'),
              title: t('menu.addons'),
              rows: addons,
              totals: true,
              columns: [
                ExcelColumn(
                  header: t('common.name'),
                  accessor: (a) => name(a.name, a.nameTranslations),
                  type: ExcelColumnType.text,
                  width: 24,
                ),
                ExcelColumn(
                  header: t('menu.addonType'),
                  accessor: (a) => a.addonType,
                  type: ExcelColumnType.text,
                  width: 16,
                ),
                ExcelColumn(
                  header: t('common.price'),
                  accessor: (a) => a.defaultPrice,
                  type: ExcelColumnType.money,
                  width: 14,
                  total: true,
                ),
                ExcelColumn(
                  header: t('common.status'),
                  accessor: (a) => status(a.isActive),
                  type: ExcelColumnType.text,
                  width: 12,
                ),
              ],
            ),
          ],
        ),
      );
  toast.update(
    outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
    outcome.message(t),
  );
}

/// The API with the export mark on every request (`EXPORT_REQUEST`).
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
