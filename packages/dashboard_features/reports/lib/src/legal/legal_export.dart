/// The Legal exports' mechanics, as the web's `exportToExcel` /
/// `exportToCsv` run them (`lib/excel.ts:316-391`, REP-ALL-011…013):
///
/// - nothing in any sheet → an error toast "Nothing to export", no file;
/// - Excel: a loading toast "Gathering data…" that becomes "Exported
///   {{count}} rows" (every sheet's rows) or "Export failed";
/// - CSV: the first sheet only, then "Exported {{count}} rows".
///
/// The Legal exports are built from data already on screen, so they make no
/// request and are never throttled (REP-ALL-027).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The logo a generated spreadsheet wears (`useExportLogo`): the shop's own
/// on the branding tier, else null (Madar's).
String? legalExportLogo(WidgetRef ref) {
  final brand = ref.read(publicBrandProvider).value;
  final logo = brand?.logoUrl?.trim();
  if (brand == null || !brand.customBranding) return null;
  return logo == null || logo.isEmpty ? null : logo;
}

/// `exportToExcel(config)` with the web's toasts.
Future<void> legalExportExcel(
  BuildContext context,
  WidgetRef ref,
  ExcelConfig config,
) async {
  final t = ref.read(tProvider);
  if (config.sheets.every((s) => s.rows.isEmpty)) {
    DashToast.error(context, const ExportNothing().message(t));
    return;
  }
  final toast = DashToast.loading(context, t('excel.generating'));
  final outcome = await ref.read(exporterProvider).exportToExcel(config);
  toast.update(
    outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
    outcome.message(t),
  );
}

/// `exportToCsv(config)` with the web's toasts.
Future<void> legalExportCsv(
  BuildContext context,
  WidgetRef ref,
  ExcelConfig config,
) async {
  final t = ref.read(tProvider);
  final outcome = await ref.read(exporterProvider).exportToCsv(config);
  if (!context.mounted) return;
  if (outcome is ExportDone) {
    DashToast.success(context, outcome.message(t));
  } else {
    DashToast.error(context, outcome.message(t));
  }
}
