// The logo an Excel export carries (the web's `useExportLogo` over
// `use-brand.ts`): the shop's own on the branding tier, trimmed; blank → none.
import 'package:dashboard_api/dashboard_api.dart' show PublicBrand;

/// The export logo URL for [brand], or null for none.
String? exportLogoUrl(PublicBrand? brand) {
  final url = brand?.logoUrl?.trim() ?? '';
  return brand?.customBranding == true && url.isNotEmpty ? url : null;
}
