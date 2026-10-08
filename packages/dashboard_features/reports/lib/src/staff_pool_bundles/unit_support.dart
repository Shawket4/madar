/// What the Staff drinks and Bundles pages share: React Query's notion of a
/// first load, the page's own `<Restricted>`, the spreadsheet a page exports
/// (the web's `exportToExcel` with its three toasts and the shop's logo) and
/// the wire's rate decimals (`rateOf` / `fmtRate`).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

/// React Query's `isLoading`: the first load, with nothing to show yet. A
/// refetch keeps what it had; a failed one shows the failure.
extension ReportAsync<T> on AsyncValue<T> {
  bool get firstLoad => isLoading && !hasValue && !hasError;
}

/// A read the web keeps disabled (no capability yet, no branch): neither
/// loading nor failed, with no data.
AsyncValue<T?> watchWhen<T>(
  WidgetRef ref,
  bool enabled,
  ProviderListenable<AsyncValue<T>> provider,
) => enabled ? ref.watch(provider) : AsyncData<T?>(null);

/// The page's own refusal (`<Restricted title who=reports.noAccess>`), once
/// the person's permissions are known and lack [canSee] (REP-ALL-005).
/// Null while the page may render.
Widget? reportRestricted(
  WidgetRef ref, {
  required String title,
  required bool canSee,
}) {
  final ready = ref.watch(authzProvider.select((a) => a.ready));
  if (!ready || canSee) return null;
  return Restricted(
    title: title,
    who: ref.watch(tProvider)('reports.noAccess'),
  );
}

/// The logo a generated spreadsheet wears (`useExportLogo`): the shop's own
/// on the branding tier, else none (Madar's).
String? exportLogoUrl(WidgetRef ref) {
  final brand = ref.watch(publicBrandProvider).value;
  return brand != null && brand.customBranding ? brand.logoUrl : null;
}

/// `exportToExcel` as the web runs it (REP-ALL-011/013): "Nothing to
/// export" when every sheet is empty; otherwise "Gathering data…" turning
/// into "Exported N rows" or "Export failed".
Future<void> runExcelExport(
  BuildContext context,
  WidgetRef ref,
  ExcelConfig config,
) async {
  final t = ref.read(tProvider);
  if (config.sheets.every((s) => s.rows.isEmpty)) {
    DashToast.error(context, const ExportNothing().message(t));
    return;
  }
  final toast = DashToast.loading(
    context,
    t('excel.generating', defaultValue: 'Generating spreadsheet…'),
  );
  final outcome = await ref.read(exporterProvider).exportToExcel(config);
  switch (outcome) {
    case ExportDone():
      toast.update(DashToastKind.success, outcome.message(t));
    case ExportFailed():
    case ExportNothing():
      toast.update(DashToastKind.error, outcome.message(t));
  }
}

/// `rateOf`: the wire's decimal string ("0.6248") as a number; null when
/// blank or not a number.
double? rateOfWire(Object? v) {
  if (v == null) return null;
  if (v is num) return v.isFinite ? v.toDouble() : null;
  final s = '$v'.trim();
  if (s.isEmpty) return null;
  final n = double.tryParse(s);
  return n != null && n.isFinite ? n : null;
}

/// `fmtRate`: a wire rate as a percent ("62.5%"), or an em dash.
String fmtRateWire(DashFormat f, Object? v) {
  final r = rateOfWire(v);
  return r == null ? '—' : f.fmtPercent(r);
}
