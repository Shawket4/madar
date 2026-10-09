/// The logo a generated spreadsheet wears (`useExportLogo`,
/// `use-brand.ts`): the shop's own on the branding tier, a blank one none;
/// null means Madar's.
library;

import 'package:dashboard_api/dashboard_api.dart' show PublicBrand;

String? exportLogoOf(PublicBrand? brand) {
  final logo = brand?.logoUrl?.trim() ?? '';
  return brand != null && brand.customBranding && logo.isNotEmpty ? logo : null;
}
