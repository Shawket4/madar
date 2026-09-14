import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('money tables move the drawer and nothing else', () {
    expect(ticksForTables(['orders']), [drawerTickProvider]);
    expect(ticksForTables(['refunds', 'cash_movements']), [drawerTickProvider]);
  });

  test('bookings move the arrivals and the floor', () {
    expect(ticksForTables(['bookings']), [
      bookingTickProvider,
      floorTickProvider,
    ]);
  });

  test('a lagging subscriber re-reads every board', () {
    expect(
      ticksForTables(['*']),
      containsAll([
        drawerTickProvider,
        ticketTickProvider,
        kitchenTickProvider,
        deliveryTickProvider,
        bookingTickProvider,
        floorTickProvider,
        catalogTickProvider,
        syncTickProvider,
      ]),
    );
  });

  test('an unknown table bumps nothing', () {
    expect(ticksForTables(['nope']), isEmpty);
  });
}
