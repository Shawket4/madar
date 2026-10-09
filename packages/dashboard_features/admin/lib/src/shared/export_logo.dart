import 'package:dashboard_api/dashboard_api.dart' show PublicBrand;

/// The logo an Excel export carries (the web's `useExportLogo`): the shop's
/// own on the branding tier, trimmed, and none when blank (`use-brand.ts`
/// `logo_url?.trim() || null`).
String? exportLogoUrl(PublicBrand? brand) {
  final logo = brand?.logoUrl?.trim();
  return brand?.customBranding == true && logo != null && logo.isNotEmpty
      ? logo
      : null;
}
