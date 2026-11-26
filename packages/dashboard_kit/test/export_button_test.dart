// DashExportButton (the web's ExportButton): one panel for every export.
// Format (Excel / PDF / CSV) at the top, remembered; the File when the page
// offers several; the Sheet when a PDF or CSV is asked of a workbook with
// several (each is one sheet); then Download, which hands the export the
// sheet picked.
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_kit/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _centered(Widget child) => Scaffold(body: Center(child: child));

/// The button itself.
Finder get _trigger => find.byType(DashButton).first;

/// The panel's Download button.
Finder get _download => find.byKey(const ValueKey('export-download'));

/// The format every export reads, as dashboard_core's provider holds it.
class _Formats {
  DashExportFormat format = DashExportFormat.xlsx;
  final List<DashExportFormat> changes = [];
}

/// [child] under a [DashExportFormatScope] over [formats].
Widget _scoped(_Formats formats, Widget child) => StatefulBuilder(
  builder: (context, setState) => DashExportFormatScope(
    format: formats.format,
    onChanged: (f) => setState(() {
      formats
        ..format = f
        ..changes.add(f);
    }),
    child: child,
  ),
);

/// The pressable row or pill reading [label] (the last one: the trigger may
/// read the same).
DashPressable _choice(WidgetTester tester, String label) =>
    tester.widget<DashPressable>(
      find
          .ancestor(
            of: find.text(label).last,
            matching: find.byType(DashPressable),
          )
          .first,
    );

bool _checked(WidgetTester tester, String label) =>
    _choice(tester, label).checked ?? false;

double _x(WidgetTester tester, String label) =>
    tester.getTopLeft(find.text(label).last).dx;

double _y(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

Future<void> _open(WidgetTester tester) async {
  await tester.tap(_trigger);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

String _downloadWords(WidgetTester tester) =>
    tester.widget<DashButton>(_download).label;

void main() {
  testWidgets('one file: the format, then Download in it; the format is '
      'remembered', (tester) async {
    final formats = _Formats();
    // The export reads the format at the moment it runs.
    final ran = <(DashExportFormat, DashExportPick)>[];
    await pumpDashApp(
      tester,
      _centered(
        _scoped(
          formats,
          DashExportButton(onExport: (p) => ran.add((formats.format, p))),
        ),
      ),
    );
    // "Export", with the panel's chevron: no format in its words.
    expect(find.text('Export'), findsOneWidget);
    await _open(tester);
    expect(find.text('Format'), findsOneWidget);
    // Every export offers all three, in a row.
    expect(_x(tester, 'Excel'), lessThan(_x(tester, 'PDF')));
    expect(_x(tester, 'PDF'), lessThan(_x(tester, 'CSV')));
    expect(_checked(tester, 'Excel'), isTrue);
    // No file list and no sheet: there is only the one.
    expect(find.text('File'), findsNothing);
    expect(find.text('Sheet'), findsNothing);
    expect(_y(tester, find.text('CSV')), lessThan(_y(tester, _download)));
    expect(_downloadWords(tester), 'Download Excel');

    await _tap(tester, 'PDF');
    expect(formats.format, DashExportFormat.pdf, reason: 'remembered');
    expect(ran, isEmpty, reason: 'choosing is not exporting');
    expect(_downloadWords(tester), 'Download PDF');
    await tester.tap(_download);
    await tester.pumpAndSettle();
    expect(ran, [(DashExportFormat.pdf, const DashExportPick())]);
    expect(_download, findsNothing, reason: 'the panel closed');

    // Next time it opens on PDF, and CSV is remembered the same way.
    await _open(tester);
    expect(_checked(tester, 'PDF'), isTrue);
    await _tap(tester, 'CSV');
    expect(_downloadWords(tester), 'Download CSV');
    await tester.tap(_download);
    await tester.pumpAndSettle();
    expect(ran.last.$1, DashExportFormat.csv);
    expect(formats.changes, [DashExportFormat.pdf, DashExportFormat.csv]);
  });

  testWidgets('a PDF or CSV of a workbook with several sheets asks which, '
      'and hands the pick to the export', (tester) async {
    final formats = _Formats();
    final picks = <DashExportPick>[];
    await pumpDashApp(
      tester,
      _centered(
        _scoped(
          formats,
          DashExportButton(
            onExport: picks.add,
            sheets: const [
              DashExportSheet('Items'),
              DashExportSheet('Categories'),
              DashExportSheet('Addons'),
            ],
          ),
        ),
      ),
    );
    await _open(tester);
    // Excel is the whole workbook: no sheet to choose.
    expect(find.text('Sheet'), findsNothing);
    await _tap(tester, 'PDF');
    expect(find.text('Sheet'), findsOneWidget);
    expect(_x(tester, 'Items'), lessThan(_x(tester, 'Categories')));
    expect(_x(tester, 'Categories'), lessThan(_x(tester, 'Addons')));
    expect(_checked(tester, 'Items'), isTrue);
    await _tap(tester, 'Categories');
    await tester.tap(_download);
    await tester.pumpAndSettle();
    expect(picks.last, const DashExportPick(sheet: 1));

    // A CSV asks the same, and keeps the sheet chosen.
    await _open(tester);
    await _tap(tester, 'CSV');
    expect(_checked(tester, 'Categories'), isTrue);
    await tester.tap(_download);
    await tester.pumpAndSettle();
    expect(picks.last, const DashExportPick(sheet: 1));

    // In Excel the pick is empty: the workbook is every sheet.
    await _open(tester);
    await _tap(tester, 'Excel');
    await tester.tap(_download);
    await tester.pumpAndSettle();
    expect(picks.last, const DashExportPick());
  });

  testWidgets('a sheet of tables has no CSV: the CSV is the other sheet, '
      'without asking', (tester) async {
    final formats = _Formats();
    final picks = <DashExportPick>[];
    await pumpDashApp(
      tester,
      _centered(
        _scoped(
          formats,
          DashExportButton(
            onExport: picks.add,
            sheets: const [
              DashExportSheet('Recipe tables', csv: false),
              DashExportSheet('Ingredient lines'),
            ],
          ),
        ),
      ),
    );
    await _open(tester);
    await _tap(tester, 'PDF');
    expect(find.text('Recipe tables'), findsOneWidget);
    expect(find.text('Ingredient lines'), findsOneWidget);
    await _tap(tester, 'CSV');
    expect(find.text('Sheet'), findsNothing);
    expect(find.text('Recipe tables'), findsNothing);
    await tester.tap(_download);
    await tester.pumpAndSettle();
    expect(picks.last, const DashExportPick(sheet: 1));

    await _open(tester);
    await _tap(tester, 'PDF');
    expect(_checked(tester, 'Recipe tables'), isTrue);
    await tester.tap(_download);
    await tester.pumpAndSettle();
    expect(picks.last, const DashExportPick(sheet: 0));
  });

  testWidgets('several files: the panel lists them under the format, and '
      'each runs like the page\'s own', (tester) async {
    final formats = _Formats();
    final ran = <String>[];
    await pumpDashApp(
      tester,
      _centered(
        _scoped(
          formats,
          DashExportButton(
            onExport: (p) => ran.add('menu $p'),
            fileLabel: 'Menu',
            more: [
              DashExportFile(
                key: 'recipes',
                label: 'Recipes with costs',
                sheets: const [
                  DashExportSheet('Recipe tables', csv: false),
                  DashExportSheet('Ingredient lines'),
                ],
                onExport: (p) => ran.add('recipes $p'),
              ),
            ],
          ),
        ),
      ),
    );
    await _open(tester);
    expect(find.text('File'), findsOneWidget);
    expect(
      _y(tester, find.text('CSV')),
      lessThan(_y(tester, find.text('Menu'))),
    );
    expect(
      _y(tester, find.text('Menu')),
      lessThan(_y(tester, find.text('Recipes with costs'))),
    );
    expect(_checked(tester, 'Menu'), isTrue);
    await _tap(tester, 'Recipes with costs');
    expect(_checked(tester, 'Recipes with costs'), isTrue);
    expect(_checked(tester, 'Menu'), isFalse);
    await tester.tap(_download);
    await tester.pumpAndSettle();
    expect(ran, ['recipes ${const DashExportPick()}']);

    // The file stays picked for the next export.
    await _open(tester);
    expect(_checked(tester, 'Recipes with costs'), isTrue);
    await _tap(tester, 'CSV');
    await tester.tap(_download);
    await tester.pumpAndSettle();
    expect(ran.last, 'recipes ${const DashExportPick(sheet: 1)}');
  });

  testWidgets('without a format scope the button keeps its own choice', (
    tester,
  ) async {
    await pumpDashApp(tester, _centered(DashExportButton(onExport: (_) {})));
    await _open(tester);
    expect(_checked(tester, 'Excel'), isTrue);
    await _tap(tester, 'PDF');
    expect(_checked(tester, 'PDF'), isTrue);
    expect(_checked(tester, 'Excel'), isFalse);
  });

  testWidgets('a label of its own, and disabled', (tester) async {
    var ran = 0;
    await pumpDashApp(
      tester,
      _centered(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DashExportButton(label: 'Pay lists', onExport: (_) => ran++),
            DashExportButton(
              label: 'Off',
              enabled: false,
              onExport: (_) => ran++,
            ),
          ],
        ),
      ),
    );
    expect(find.text('Pay lists'), findsOneWidget);
    final off = tester.widget<DashButton>(
      find.ancestor(of: find.text('Off'), matching: find.byType(DashButton)),
    );
    expect(off.onPressed, isNull);
    await tester.tap(find.text('Pay lists'));
    await tester.pumpAndSettle();
    await tester.tap(_download);
    await tester.pumpAndSettle();
    expect(ran, 1);
  });

  testWidgets('on a phone the panel stays clear of the screen\'s edges', (
    tester,
  ) async {
    await pumpDashApp(
      tester,
      Scaffold(
        body: Align(
          alignment: AlignmentDirectional.topEnd,
          child: DashExportButton(onExport: (_) {}),
        ),
      ),
      size: DashSize.phone,
    );
    await _open(tester);
    final card = tester.getRect(
      find
          .ancestor(of: find.text('Format'), matching: find.byType(Container))
          .last,
    );
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(card.left, greaterThanOrEqualTo(16));
    expect(card.right, lessThanOrEqualTo(screen.width - 16));
  });
}
