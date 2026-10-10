/// The spreadsheet export every inventory page shares (INV-ALL-012/013):
/// `exportToExcel` with the web's toasts.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
