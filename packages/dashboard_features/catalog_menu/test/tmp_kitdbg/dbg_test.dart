// The studio's Sizes, price & recipe section: the recipe grid, the base
// picker, the linked-copy bar and the "Set cost" popover
// (MENU-STUDIO-030..061, MENU-AREA-014). Figures from the area seed: Caffè
// Latte Regular = 180 ml full cream milk (EGP 0.042/ml) + 18 g house blend
// (EGP 0.95/g) + a 12oz cup (EGP 1.80) + a hot lid (EGP 0.60).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/studio/studio_widgets.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../studio/support.dart';

final String _latte = item('latte');
String _ing(String k) => MenuSeedIds.ingredient(k);

/// The quantity cell of [ingredient] in [size].
Finder cell(DashHarness h, String ingredient, String size) => studioLabel(
  h.t(
    'modeling.grid.cellAria',
    args: {'ingredient': ingredient, 'size': size},
  ),
);

/// The price box of [size].
Finder price(DashHarness h, String size) =>
    studioLabel(h.t('modeling.grid.priceAria', args: {'size': size}));

/// Every cell of the grid row [source]:[ingredientKey].
Finder row(String source, String ingredientKey) => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith(
        'studio-row-$source:${_ing(ingredientKey)}',
      ),
);

/// The ingredient cell of that row.
Finder rowHead(String source, String ingredientKey) =>
    find.byKey(ValueKey('studio-row-$source:${_ing(ingredientKey)}'));

/// The ⋯ menu of the [i]th size column.
Finder columnMenu(DashHarness h, int i) =>
    studioLabel(h.t('modeling.grid.columnActions')).at(i);

/// An option row's words in an open list (not the search box).
Finder option(Finder list, String name) => find.descendant(
  of: list,
  matching: find.byWidgetPredicate(
    (w) => w is Text && w.data == name,
  ),
);

/// [name] in an open dropdown menu.
Finder menuText(String name) => find.descendant(
  of: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuList'),
  matching: find.text(name),
);

/// The footer text containing [s].
Finder footerHas(String s) => studioHas(s);


void main() {
  testWidgets('dbg copy from', (tester) async {
    final h = await pumpStudio(tester);
    double scroll() => tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
    debugPrint('A scroll=${scroll()} trigger=${tester.getRect(columnMenu(h, 1))}');
    await h.tap(columnMenu(h, 1));
    debugPrint('B scroll=${scroll()} trigger=${tester.getRect(columnMenu(h, 1))} item=${tester.getRect(find.bySemanticsLabel(h.t('modeling.grid.copyFrom')))}');
    await tester.ensureVisible(find.bySemanticsLabel(h.t('modeling.grid.copyFrom')));
    await tester.pump();
    debugPrint('C scroll=${scroll()} trigger=${tester.getRect(columnMenu(h, 1))}');
    await tester.tap(find.bySemanticsLabel(h.t('modeling.grid.copyFrom')));
    await h.settle();
    debugPrint('D scroll=${scroll()} trigger=${tester.getRect(columnMenu(h, 1))} regular=${tester.getRect(menuText('Regular'))}');
  });
}
