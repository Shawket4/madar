/// The spreadsheet export every inventory page shares (INV-ALL-012/013):
/// the logo the workbook wears and `exportToExcel` with the web's toasts.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The logo a generated spreadsheet wears (`useExportLogo`): the shop's own
/// on the branding tier, else null (Madar's).
String? inventoryExportLogo(WidgetRef ref) {
  final brand = ref.read(publicBrandProvider).value;
  final logo = brand?.logoUrl?.trim();
  if (brand == null || !brand.customBranding) return null;
  return logo == null || logo.isEmpty ? null : logo;
}

/// `exportToExcel(config)` with the web's toasts (INV-ALL-013): nothing →
/// "Nothing to export"; else "Gathering data…" that turns into "Exported N
/// rows" or "Export failed".
Future<void> inventoryExportExcel(
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
