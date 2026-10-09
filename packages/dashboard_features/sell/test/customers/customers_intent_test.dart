// Intent warming on Customers: a row warms its sheet, a filter option, the
// Members only switch and Load more warm the list they ask for, and in the
// sheet Merge into… warms the dialog's suggestions and an order link the
// order sheet; each press then asks the server nothing more.
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Offset, Scrollable;
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The list reads asked with exactly [query].
int asked(DashHarness h, Map<String, String> query) =>
    listCalls(h).where((c) => mapEquals(q1(c), query)).length;

/// Rests a mouse on [target] (one read: [count] grows by one), presses it
/// (no second read), then parks the mouse where nothing warms.
Future<void> restThenPress(
  DashHarness h,
  Finder target,
  int Function() count,
  String what, {
  Finder? scrollable,
}) async {
  final tester = h.tester;
  if (scrollable == null) {
    await tester.ensureVisible(target);
    await h.settle();
  } else {
    await h.scrollUntilVisible(target, scrollable: scrollable);
  }
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  final before = count();
  await mouse.moveTo(tester.getCenter(target));
  await h.settle();
  expect(count(), before + 1, reason: '$what is warmed');
  await h.tap(target);
  expect(count(), before + 1, reason: '$what came from the cache');
  await mouse.removePointer();
  await h.settle();
}

void main() {
  testWidgets('the list: a row, Load more, Members only and a source option '
      'warm what they read', (tester) async {
    final h = await pumpCustomers(tester);

    await restThenPress(
      h,
      rowOf('Nada Kamal'),
      () => h.server.callsTo('/customers/{id}', method: 'GET').length,
      'the sheet',
    );
    // Nada is a member: her card was warmed beside her, and only once.
    expect(h.server.callsTo('/loyalty/members/{id}'), hasLength(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();

    await restThenPress(
      h,
      pageText('Load more'),
      () => asked(h, {'limit': '100', 'offset': '0'}),
      'the wider window',
    );
    await restThenPress(
      h,
      pageText('Members only'),
      () => asked(h, {'member': 'true', 'limit': '50', 'offset': '0'}),
      'the members',
    );
    await h.tap(pageText('Any source'));
    await restThenPress(
      h,
      optionText('Booking'),
      () => asked(h, {
        'member': 'true',
        'source': 'booking',
        'limit': '50',
        'offset': '0',
      }),
      'the source',
    );
  });

  testWidgets('the sheet: Merge into… and an order link warm what they read', (
    tester,
  ) async {
    final h = await pumpCustomers(tester);
    h.allowUnmatched = true; // the order sheet's own extra reads
    await openNada(h);

    await restThenPress(
      h,
      inSheet(
        find.byWidgetPredicate(
          (w) => w is DashButton && w.label == 'Merge into…',
        ),
      ),
      () => asked(h, {'limit': '20'}),
      'the merge suggestions',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();

    // Nada's newest order, by its ref (the link's label).
    final newest = (h.db!['orders'].where((o) => o['customer_id'] == nadaId)
          ..sort(
            (a, b) => (b['created_at']! as String).compareTo(
              a['created_at']! as String,
            ),
          ))
        .first;
    final label =
        newest['order_ref'] as String? ??
        (newest['id']! as String).substring(0, 8);
    final link = inSheet(
      find.byWidgetPredicate(
        (w) => w is DashPressable && w.semanticLabel == label,
      ),
    );
    expect(link, findsWidgets);
    await restThenPress(
      h,
      link.first,
      () => h.server.callsTo('/orders/{order_id}', method: 'GET').length,
      'the order sheet',
      scrollable: inSheet(find.byType(Scrollable)).first,
    );
  });
}
