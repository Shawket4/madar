// The small text and number rules the menu pages share.
import 'package:dashboard_catalog_menu/src/shared/menu_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('humanizes add-on types like the web', () {
    expect(humanizeAddonType('milk_type'), 'Milk');
    expect(humanizeAddonType('extra_shot'), 'Extra Shot');
    expect(humanizeAddonType('extra'), 'Extra');
  });

  test('picks the Arabic name only in Arabic', () {
    const tr = {'en': 'Latte', 'ar': 'لاتيه'};
    expect(translatedName('Latte', tr, 'ar'), 'لاتيه');
    expect(translatedName('Latte', tr, 'en'), 'Latte');
    expect(translatedName('Latte', const {'en': 'Latte'}, 'ar'), 'Latte');
  });

  test('cleans typed quantities to digits and one dot', () {
    expect(cleanDecimal('12,5'), '12.5');
    expect(cleanDecimal('1a2.3.4'), '12.34');
    expect(cleanDecimal('—'), '');
  });

  test('formats quantities and pounds as the web prints numbers', () {
    expect(fmtQty(180), '180');
    expect(fmtQty(0.33333), '0.333');
    expect(fmtQty(2.0005), '2.001');
    expect(egpText(4550), '45.5');
    expect(egpText(11500), '115');
    expect(jsParseFloat('45 EGP'), 45);
    expect(jsNumber(''), 0);
    expect(jsNumber('4x').isNaN, isTrue);
  });
}
