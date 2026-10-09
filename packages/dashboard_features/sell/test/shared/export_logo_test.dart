import 'package:dashboard_api/dashboard_api.dart' show PublicBrand;
import 'package:dashboard_sell/src/shared/export_logo.dart';
import 'package:flutter_test/flutter_test.dart';

PublicBrand _brand({required bool tier, String? logo}) => PublicBrand(
  accentColor: '#000',
  backgroundColor: '#fff',
  customBranding: tier,
  foregroundColor: '#000',
  logoIsMark: false,
  logoUrl: logo,
  name: 'Shop',
  orgId: 'o',
);

void main() {
  test("the export logo: the shop's own on the tier, trimmed; blank or "
      'no tier is none (Madar\'s)', () {
    expect(
      exportLogoOf(_brand(tier: true, logo: ' https://x/l.png ')),
      'https://x/l.png',
    );
    expect(exportLogoOf(_brand(tier: true, logo: '   ')), isNull);
    expect(exportLogoOf(_brand(tier: true)), isNull);
    expect(exportLogoOf(_brand(tier: false, logo: 'https://x/l.png')), isNull);
    expect(exportLogoOf(null), isNull);
  });
}
