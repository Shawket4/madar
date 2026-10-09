/// Rules every reports unit shares: when a read shows its error
/// (REP-ALL-018) and the logo an export wears (`useExportLogo`).
library;

import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The error with Retry: dashboard_core's `failedFirst`, and also a refetch
/// that failed over rows already shown (the web checks `isError`, which
/// drops them, REP-ALL-018). Never during Riverpod's automatic retries; it
/// stays up while a manual Retry runs.
extension ReportAsync<T> on AsyncValue<T> {
  bool get failed => hasError && !retrying;
}

/// The logo a generated spreadsheet wears (`useExportLogo`): the shop's own
/// on the branding tier, blank → none (`use-brand.ts` trims it); null means
/// Madar's.
String? exportLogoUrl(WidgetRef ref) {
  final brand = ref.read(publicBrandProvider).value;
  final logo = brand?.logoUrl?.trim();
  if (brand == null || !brand.customBranding) return null;
  return logo == null || logo.isEmpty ? null : logo;
}
