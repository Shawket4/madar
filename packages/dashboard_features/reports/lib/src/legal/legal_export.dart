/// The Legal exports' mechanics, as the web's `exportFile` runs them
/// (REP-ALL-011…013):
///
/// - nothing in any sheet → an error toast "Nothing to export", no file;
/// - otherwise a loading toast "Gathering data…" that becomes "Exported
///   {{count}} rows" or "Export failed", for the file chosen in the Export
///   panel (Excel, or a PDF or CSV of the sheet [DashExportPick] names).
///
/// The Legal exports are built from data already on screen, so they make no
/// request and are never throttled (REP-ALL-027).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `exportFile(config, pick)` with the web's toasts.
Future<void> legalExport(
  BuildContext context,
  WidgetRef ref,
  ExcelConfig config, [
  DashExportPick pick = const DashExportPick(),
]) async {
  final t = ref.read(tProvider);
  if (config.sheets.every((s) => s.size == 0)) {
    DashToast.error(context, const ExportNothing().message(t));
    return;
  }
  final toast = DashToast.loading(context, t('excel.generating'));
  final outcome = await ref.read(exporterProvider).exportFile(config, pick);
  toast.update(
    outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
    outcome.message(t),
  );
}
