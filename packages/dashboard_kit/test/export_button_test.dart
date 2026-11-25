// DashExportButton (the web's ExportButton): a plain button, the Excel/CSV
// menu, and the menu with a section of more files (`excelLabel`, `more`,
// `moreHeading`).
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_kit/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _centered(Widget child) => Scaffold(body: Center(child: child));

/// The button itself (it reads "Export Excel" in every form, `common.export`).
Finder get _trigger => find.byType(DashButton);

void main() {
  testWidgets('no CSV and nothing more: one button, as before', (tester) async {
    var excel = 0;
    await pumpDashApp(
      tester,
      _centered(DashExportButton(onExport: () => excel++)),
    );
    expect(find.text('Export Excel'), findsOneWidget);
    await tester.tap(find.text('Export Excel'));
    await tester.pumpAndSettle();
    expect(excel, 1);
    expect(find.byType(DashMenu), findsNothing);
  });

  testWidgets('with CSV: a menu of Excel and CSV, as before', (tester) async {
    var csv = 0;
    await pumpDashApp(
      tester,
      _centered(DashExportButton(onExport: () {}, onExportCsv: () => csv++)),
    );
    await tester.tap(_trigger);
    await tester.pumpAndSettle();
    // The trigger's words and the item's.
    expect(find.text('Export Excel'), findsNWidgets(2));
    expect(find.text('Export CSV'), findsOneWidget);
    expect(find.byType(Divider), findsNothing);
    await tester.tap(find.text('Export CSV'));
    await tester.pumpAndSettle();
    expect(csv, 1);
  });

  testWidgets('more files: their own section under the page\'s own file, '
      'with its heading', (tester) async {
    final picked = <String>[];
    await pumpDashApp(
      tester,
      _centered(
        DashExportButton(
          onExport: () => picked.add('menu'),
          excelLabel: 'Menu (Excel)',
          moreHeading: 'Recipes',
          more: [
            DashExportOption(
              label: 'Recipes with costs (Excel)',
              onSelected: () => picked.add('recipes'),
            ),
            DashExportOption(
              label: 'Recipe lines (CSV)',
              onSelected: () => picked.add('csv'),
            ),
          ],
        ),
      ),
    );
    // A menu now, even with no CSV.
    await tester.tap(_trigger);
    await tester.pumpAndSettle();
    expect(find.text('Menu (Excel)'), findsOneWidget);
    expect(find.text('Export Excel'), findsOneWidget, reason: 'the trigger');
    expect(find.text('Export CSV'), findsNothing);
    expect(find.byType(Divider), findsOneWidget);
    final heading = find.text('Recipes');
    expect(heading, findsOneWidget);
    // In order: the page's file, the rule, the heading, the files.
    double y(Finder f) => tester.getTopLeft(f).dy;
    expect(y(find.text('Menu (Excel)')), lessThan(y(find.byType(Divider))));
    expect(y(find.byType(Divider)), lessThan(y(heading)));
    expect(y(heading), lessThan(y(find.text('Recipes with costs (Excel)'))));
    expect(
      y(find.text('Recipes with costs (Excel)')),
      lessThan(y(find.text('Recipe lines (CSV)'))),
    );
    // The heading is a label, not something to press.
    await tester.tap(heading, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(picked, isEmpty);
    expect(find.text('Recipe lines (CSV)'), findsOneWidget, reason: 'open');

    await tester.tap(find.text('Recipe lines (CSV)'));
    await tester.pumpAndSettle();
    expect(picked, ['csv']);
    expect(find.text('Recipe lines (CSV)'), findsNothing, reason: 'closed');

    await tester.tap(_trigger);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menu (Excel)'));
    await tester.pumpAndSettle();
    expect(picked, ['csv', 'menu']);
  });

  testWidgets('more files with CSV: Excel, CSV, then the section', (
    tester,
  ) async {
    await pumpDashApp(
      tester,
      _centered(
        DashExportButton(
          onExport: () {},
          onExportCsv: () {},
          more: [DashExportOption(label: 'Cards', onSelected: () {})],
        ),
      ),
    );
    await tester.tap(_trigger);
    await tester.pumpAndSettle();
    double y(String s) => tester.getTopLeft(find.text(s).last).dy;
    expect(y('Export Excel'), lessThan(y('Export CSV')));
    expect(y('Export CSV'), lessThan(y('Cards')));
    expect(find.byType(Divider), findsOneWidget, reason: 'no heading given');
  });
}
