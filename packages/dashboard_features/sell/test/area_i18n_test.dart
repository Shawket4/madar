// The area's supplement tables: one pair per unit, each found in English and
// Arabic (the file name is the language).
import 'package:flutter_test/flutter_test.dart';

import 'support/sell_harness.dart';

void main() {
  const added = {
    'orderStatus.cancelled': ('Cancelled', 'ملغي'),
    'orderStatus.rejected': ('Rejected', 'مرفوض'),
    'floor.errSeats': (
      'Seats must be a whole number from 0 to 99',
      'يجب أن يكون عدد المقاعد رقمًا صحيحًا من 0 إلى 99',
    ),
    'bookings.endsAt': ('Ends', 'ينتهي'),
    'bookings.source': ('Source', 'المصدر'),
    'bookings.byPhone': ('Taken here', 'سُجّل هنا'),
  };

  testWidgets('unit supplements load in English', (tester) async {
    final h = await pumpSell(tester, '/orders');
    for (final e in added.entries) {
      expect(h.t(e.key), e.value.$1, reason: e.key);
    }
  });

  testWidgets('unit supplements load in Arabic', (tester) async {
    final h = await pumpSell(tester, '/orders', locale: 'ar', dark: true);
    for (final e in added.entries) {
      expect(h.t(e.key), e.value.$2, reason: e.key);
    }
    await h.shot('orders/smoke');
  });
}
