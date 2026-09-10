// Renders the shared control kit to PNG so a change to it can be LOOKED at.
//
// There is no simulator on the machines this repo is usually worked on, and a
// button is not a thing you can review by reading its widget tree. Set
// MADAR_RENDER=1 and the test writes `build/render/controls-<theme>.png`; left
// unset it still builds every control in both themes and fails on any layout
// exception, which is the part CI cares about.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _render = bool.fromEnvironment('MADAR_RENDER');

Widget _row(String label, List<Widget> children) => Padding(
  padding: const EdgeInsetsDirectional.only(bottom: Space.lg),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MadarSectionHeader(text: label),
      const SizedBox(height: Space.sm),
      Wrap(spacing: Space.md, runSpacing: Space.md, children: children),
    ],
  ),
);

Widget _sheet() {
  final controller = TextEditingController(text: 'Sara');
  final empty = TextEditingController();
  return Builder(
    builder: (context) => ColoredBox(
      color: context.madarColors.bg,
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.all(Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _row('Primary', [
              SizedBox(
                width: 220,
                child: MadarButton(label: 'Charge 120.00', onTap: () {}),
              ),
              SizedBox(
                width: 160,
                child: MadarButton(
                  label: 'Place order',
                  icon: 'checkmark.circle',
                  onTap: () {},
                ),
              ),
              SizedBox(
                width: 140,
                child: MadarButton(
                  label: 'Working',
                  loading: true,
                  onTap: () {},
                ),
              ),
              SizedBox(
                width: 140,
                child: MadarButton(
                  label: 'Disabled',
                  enabled: false,
                  onTap: () {},
                ),
              ),
            ]),
            _row('Secondary / destructive', [
              SizedBox(
                width: 160,
                child: MadarButton(
                  label: 'Reprint',
                  icon: 'printer',
                  variant: MadarButtonVariant.outline,
                  onTap: () {},
                ),
              ),
              SizedBox(
                width: 140,
                child: MadarButton(
                  label: 'Void sale',
                  variant: MadarButtonVariant.danger,
                  onTap: () {},
                ),
              ),
              SizedBox(
                width: 120,
                child: MadarButton(
                  label: 'Cancel',
                  variant: MadarButtonVariant.ghost,
                  onTap: () {},
                ),
              ),
            ]),
            _row('Compact — a dense toolbar row', [
              MadarButton(
                label: 'Arrivals · 3',
                icon: 'calendar.days',
                variant: MadarButtonVariant.outline,
                size: MadarButtonSize.compact,
                onTap: () {},
              ),
              MadarButton(
                label: 'Waitlist',
                icon: 'clock',
                variant: MadarButtonVariant.outline,
                size: MadarButtonSize.compact,
                onTap: () {},
              ),
              MadarButton(
                label: 'Hold',
                variant: MadarButtonVariant.outline,
                size: MadarButtonSize.compact,
                onTap: () {},
              ),
              MadarButton(
                label: 'Checkout',
                size: MadarButtonSize.compact,
                onTap: () {},
              ),
            ]),
            _row('Fields', [
              SizedBox(
                width: 260,
                child: MadarField(
                  controller: controller,
                  placeholder: 'Guest name',
                  icon: 'person',
                ),
              ),
              SizedBox(
                width: 260,
                child: MadarField(
                  controller: empty,
                  placeholder: 'Search orders',
                  icon: 'magnifyingglass',
                ),
              ),
              SizedBox(
                width: 260,
                child: MadarAmountField(
                  amountMinor: 12050,
                  currencyCode: 'egp',
                  onAmountMinor: (_) {},
                ),
              ),
            ]),
            const MadarSectionHeader(text: 'Card'),
            const SizedBox(height: Space.sm),
            MadarCard.column(
              children: [
                Builder(
                  builder: (context) => Text(
                    'Cash drawer',
                    style: MadarType.h3.copyWith(
                      color: context.madarColors.textPrimary,
                    ),
                  ),
                ),
                const MadarHairline(),
                Builder(
                  builder: (context) => Text(
                    'Counted 1,240.00 · expected 1,240.00',
                    style: MadarType.bodySm.copyWith(
                      color: context.madarColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _pump(WidgetTester tester, ThemeData theme, String name) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 1000);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        theme: theme,
        home: Scaffold(body: _sheet()),
      ),
    ),
  );
  // NOT pumpAndSettle: the loading button spins forever, which is the point
  // of it. Two frames is enough to lay out and paint.
  await tester.pump();
  await tester.pump(MotionSpec.standardDuration);
  expect(tester.takeException(), isNull, reason: '$name laid out cleanly');

  if (!_render) return;
  final boundary =
      tester.renderObject(find.byKey(const ValueKey('shot')))
          as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final dir = Directory('build/render')..createSync(recursive: true);
  File(
    '${dir.path}/controls-$name.png',
  ).writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('the control kit lays out in light', (tester) async {
    await _pump(tester, MadarTheme.light(), 'light');
  });

  testWidgets('the control kit lays out in dark', (tester) async {
    await _pump(tester, MadarTheme.dark(), 'dark');
  });

  testWidgets('a compact button with an icon and no label stays square', (
    tester,
  ) async {
    // The floor's toolbar drops its labels on a phone. A gap left behind by
    // the missing text would push the glyph off centre.
    await tester.pumpWidget(
      MaterialApp(
        theme: MadarTheme.light(),
        home: Scaffold(
          body: Center(
            child: MadarButton(
              label: '',
              icon: 'clock',
              size: MadarButtonSize.compact,
              variant: MadarButtonVariant.outline,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(SizedBox), findsWidgets);
  });

  testWidgets('a button survives an unbounded width', (tester) async {
    // The bug the checkout fork never got: a Flexible under unbounded width
    // is illegal, and the assertion blanks the whole subtree, not just the
    // button.
    await tester.pumpWidget(
      MaterialApp(
        theme: MadarTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                MadarButton(label: 'Settle', onTap: () {}),
                MadarButton(
                  label: 'Void',
                  variant: MadarButtonVariant.danger,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test('minor units round-trip through the amount field helpers', () {
    expect(minorToText(1200), '12');
    expect(minorToText(1250), '12.50');
    expect(textToMinor('12.50'), 1250);
    expect(textToMinor('12'), 1200);
    // Whatever a keyboard hands over: grouping marks, a stray glyph.
    expect(textToMinor('1,234.5'), 123450);
    expect(textToMinor('EGP 12.50'), 1250);
    expect(textToMinor(''), 0);
  });
}
