/// What the three pages of this unit share: the
/// page's own `<Restricted>` (REP-ALL-005), and the exports' mechanics with
/// the web's toasts (`lib/excel.ts`, REP-ALL-010…014).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart' show Space;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `<n> <unit>` (units g / kg / ml / L / pcs).
String invQty(DashFormat f, num qty, String? unit) =>
    '${f.fmtNumber(qty)} ${fmtUnit(unit)}';

/// The page's gate: nothing while the person's rights load (an error with
/// Retry if they could not be read, as the shell's gate: divergence
/// SH-10), then `<Restricted title who=reports.noAccess>` without
/// [canSee]. Null when the page may render.
Widget? lisGate(
  WidgetRef ref, {
  required String title,
  required bool Function(Authz a) canSee,
}) {
  final a = ref.watch(authzProvider);
  final t = ref.watch(tProvider);
  if (!a.ready) {
    final error = a.error;
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: DashErrorState(
        title: t('shell.accessLoadError'),
        message: errorMessage(error, t),
        retryLabel: t('common.retry'),
        onRetry: () => ref.read(authzProvider.notifier).refresh(),
      ),
    );
  }
  if (canSee(a)) return null;
  return Restricted(title: title, who: t('reports.noAccess'));
}

/// `useExportLogo`: the shop's own logo on the branding tier, else Madar's.
String? lisExportLogo(WidgetRef ref) {
  final brand = ref.watch(publicBrandProvider).value;
  return brand != null && brand.customBranding ? brand.logoUrl : null;
}

/// `exportToExcel(config)`: "Nothing to export", or "Gathering data…"
/// turning into "Exported N rows" / "Export failed".
Future<void> lisExportExcel(
  BuildContext context,
  WidgetRef ref,
  ExcelConfig config,
) async {
  final t = ref.read(tProvider);
  final exporter = ref.read(exporterProvider);
  if (config.sheets.every((s) => s.rows.isEmpty)) {
    DashToast.error(context, const ExportNothing().message(t));
    return;
  }
  final toast = DashToast.loading(context, t('excel.generating'));
  final outcome = await exporter.exportToExcel(config);
  toast.update(
    outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
    outcome.message(t),
  );
}

/// `exportToCsv(config)`: the first sheet only; "Exported N rows", or
/// "Nothing to export"; a failure toasts its words.
Future<void> lisExportCsv(
  BuildContext context,
  WidgetRef ref,
  ExcelConfig config,
) async {
  final t = ref.read(tProvider);
  final outcome = await ref.read(exporterProvider).exportToCsv(config);
  if (!context.mounted) return;
  if (outcome is ExportDone) {
    DashToast.success(context, outcome.message(t));
  } else if (outcome is ExportFailed) {
    DashToast.error(context, errorMessage(outcome.error, t));
  } else {
    DashToast.error(context, outcome.message(t));
  }
}
