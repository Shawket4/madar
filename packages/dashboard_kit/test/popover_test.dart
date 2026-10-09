// DashPopover placement (below, above, capped and scrolling, centred) and
// DashMenu handing focus to what its item opens.
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_kit/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// [child] with its top edge at [top] (a field low in the window).
Widget _at(double top, Widget child, {double left = 600}) => Scaffold(
  body: Stack(
    children: [
      Positioned(top: top, left: left, width: 240, child: child),
    ],
  ),
);

Widget _dateField() => DashDateField(
  value: DateTime(2026, 10, 9),
  today: DateTime(2026, 10, 9),
  semanticLabel: 'Start',
  onChanged: (_) {},
);

/// The open calendar card (the popover's frame around the month bar).
Rect _card(WidgetTester tester) => tester.getRect(
  find
      .ancestor(of: find.byType(DashCalendar), matching: find.byType(Container))
      .last,
);

void main() {
  group('popover placement', () {
    testWidgets('room below: opens below the field', (tester) async {
      await pumpDashApp(tester, _at(100, _dateField()));
      await tester.tap(find.bySemanticsLabel(RegExp('^Start')));
      await tester.pumpAndSettle();
      final field = tester.getRect(find.byType(DashSelectTrigger));
      expect(_card(tester).top, greaterThan(field.bottom));
      expect(tester.takeException(), isNull);
    });

    for (final below in [220.0, 300.0, 360.0]) {
      testWidgets('${below.round()} px below: the calendar opens above', (
        tester,
      ) async {
        // 1440×900: the field's bottom sits `below` px over the window's foot.
        await pumpDashApp(tester, _at(900 - below - 44, _dateField()));
        await tester.tap(find.bySemanticsLabel(RegExp('^Start')));
        await tester.pumpAndSettle();
        final field = tester.getRect(find.byType(DashSelectTrigger));
        final card = _card(tester);
        expect(card.bottom, lessThanOrEqualTo(field.top));
        expect(card.top, greaterThanOrEqualTo(0));
        expect(find.text('Today'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('no room either side: capped to the window, and it scrolls', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 420);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(dashTestApp(child: _at(190, _dateField())));
      await tester.tap(find.bySemanticsLabel(RegExp('^Start')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'no overflow');
      final card = _card(tester);
      expect(card.top, greaterThanOrEqualTo(0));
      expect(card.bottom, lessThanOrEqualTo(420));
      // The footer is below the fold; scrolling the card brings it in.
      await tester.drag(find.byType(DashCalendar), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.byType(DashCalendar), findsNothing);
    });

    testWidgets('inside a dialog, near its foot', (tester) async {
      await pumpDashApp(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: DashButton(
                label: 'Open',
                onPressed: () => showDashDialog<void>(
                  context,
                  builder: (context) => DashSurface(
                    title: 'Request leave',
                    body: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [const SizedBox(height: 520), _dateField()],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(RegExp('^Start')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final field = tester.getRect(find.byType(DashSelectTrigger));
      final card = _card(tester);
      expect(card.bottom, lessThanOrEqualTo(field.top));
      expect(card.top, greaterThanOrEqualTo(0));
    });

    testWidgets('centre alignment puts the card under the trigger centre', (
      tester,
    ) async {
      await pumpDashApp(
        tester,
        _at(
          100,
          DashPopover(
            width: 200,
            align: DashPopoverAlign.center,
            anchor: (context, c) => DashButton(label: 'Cell', onPressed: c.open),
            content: (context, c) => const SizedBox(height: 60),
          ),
        ),
      );
      await tester.tap(find.text('Cell'));
      await tester.pumpAndSettle();
      final trigger = tester.getRect(find.byType(DashButton));
      final card = tester.getRect(
        find
            .ancestor(
              of: find.byType(SizedBox).last,
              matching: find.byType(Container),
            )
            .first,
      );
      expect(card.width, 200);
      expect(card.center.dx, moreOrLessEquals(trigger.center.dx));
    });
  });

  group('menu', () {
    testWidgets('an item that opens a dialog: Escape closes the dialog', (
      tester,
    ) async {
      await pumpDashApp(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: DashMenu(
                items: [
                  DashMenuItem(
                    label: 'Edit',
                    onSelected: () => showDashDialog<void>(
                      context,
                      builder: (context) => const DashSurface(
                        title: 'Edit supplier',
                        body: Text('dialog body'),
                      ),
                    ),
                  ),
                ],
                builder: (context, c) =>
                    DashButton(label: 'More', onPressed: c.toggle),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('dialog body'), findsOneWidget);
      expect(find.text('Edit'), findsNothing, reason: 'the menu closed');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('dialog body'), findsNothing);
    });
  });
}
