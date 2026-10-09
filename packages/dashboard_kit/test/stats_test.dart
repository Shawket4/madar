// DashLedgerStrip columns by window width, equal-height rows, the corner
// action; DashStatCard's skeleton in a narrow card.
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_kit/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

List<DashLedgerItem> _items({Widget? action, bool firstLoading = false}) => [
  DashLedgerItem(
    key: 'rev',
    label: 'Revenue',
    value: 452865,
    loading: firstLoading,
  ),
  const DashLedgerItem(key: 'tax', label: 'Tax', value: 6300),
  DashLedgerItem(
    key: 'items',
    label: 'Items sold',
    icon: 'shopping-basket',
    value: 1284,
    action: action,
  ),
  const DashLedgerItem(key: 'void', label: 'Voided', value: 3),
];

Rect _card(WidgetTester tester, String key) =>
    tester.getRect(find.byKey(ValueKey(key)));

void main() {
  testWidgets('the web lg: four across at a 1024 window, even in 800 px', (
    tester,
  ) async {
    await pumpDashApp(
      tester,
      Scaffold(
        body: SizedBox(width: 800, child: DashLedgerStrip(items: _items())),
      ),
      size: DashSize.tablet,
    );
    final tops = {
      for (final k in ['rev', 'tax', 'items', 'void']) _card(tester, k).top,
    };
    expect(tops, hasLength(1), reason: 'one row');

    // Below the window's lg the same strip is two by two.
    tester.view.physicalSize = const Size(900, 768) * DashSize.pixelRatio;
    await tester.pump();
    expect(_card(tester, 'items').top, greaterThan(_card(tester, 'rev').top));
  });

  testWidgets('cards in a row share one height (a skeleton, large text)', (
    tester,
  ) async {
    await pumpDashApp(
      tester,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: Scaffold(
          body: DashLedgerStrip(items: _items(firstLoading: true)),
        ),
      ),
    );
    final heights = {
      for (final k in ['rev', 'tax', 'items', 'void']) _card(tester, k).height,
    };
    expect(heights, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a 44 pt corner action: no taller card, the label not cut', (
    tester,
  ) async {
    var taps = 0;
    final funnel = DashIconButton(
      icon: 'list-filter',
      semanticLabel: 'Exclude items',
      iconSize: IconSize.xs,
      onPressed: () => taps++,
    );
    await pumpDashApp(
      tester,
      Scaffold(
        body: Center(
          child: SizedBox(
            // Six across at 1440: a card about 170 wide.
            width: 360,
            child: Row(
              spacing: 16,
              children: [
                Expanded(
                  child: DashStatCard(
                    key: const ValueKey('with'),
                    label: 'Items sold',
                    icon: 'shopping-basket',
                    value: 1284,
                    dense: true,
                    action: funnel,
                  ),
                ),
                const Expanded(
                  child: DashStatCard(
                    key: ValueKey('without'),
                    label: 'Voided',
                    icon: 'ban',
                    value: 3,
                    dense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(_card(tester, 'with').height, _card(tester, 'without').height);
    final label = tester.renderObject<RenderParagraph>(find.text('Items sold'));
    expect(label.didExceedMaxLines, isFalse, reason: 'not "Items S…"');
    final target = tester.getRect(find.byType(DashIconButton));
    expect(target.size, const Size.square(DashMetrics.target));
    final card = _card(tester, 'with');
    expect(
      card.contains(target.topLeft) &&
          card.contains(target.bottomRight - const Offset(1, 1)),
      isTrue,
    );
    await tester.tap(find.byType(DashIconButton));
    expect(taps, 1);
  });

  testWidgets('three skeleton cards across a phone do not overflow', (
    tester,
  ) async {
    await pumpDashApp(
      tester,
      const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            spacing: 12,
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: DashStatCard(
                    label: 'Orders',
                    icon: 'receipt',
                    loading: true,
                    dense: true,
                  ),
                ),
            ],
          ),
        ),
      ),
      size: DashSize.phone,
    );
    expect(tester.takeException(), isNull);
  });
}
