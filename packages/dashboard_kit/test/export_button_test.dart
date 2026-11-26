// DashExportButton (the web's ExportButton): every export as Excel or PDF.
// One file: the menu is the choice ("Export as Excel / PDF") and picking one
// exports at once. Several files (a CSV, `more`): the format sits at the top,
// keeping the menu open, and the files under it (`excelLabel`, CSV, `more`,
// `moreHeading`).
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_kit/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _centered(Widget child) => Scaffold(body: Center(child: child));

/// The button itself.
Finder get _trigger => find.byType(DashButton);

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

/// The menu row reading [label] (the last one: the trigger may read the same).
Finder _row(String label) => find
    .ancestor(of: find.text(label).last, matching: find.byType(DashPressable))
    .first;

/// Whether that row shows its check.
bool _checked(String label) => find
    .descendant(
      of: _row(label),
      matching: find.byWidgetPredicate(
        (w) => w is DashIcon && w.name == 'check',
      ),
    )
    .evaluate()
    .isNotEmpty;

double _y(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

void main() {
  testWidgets('one file: the menu is the choice, and picking a format '
      'exports in it at once', (tester) async {
    final formats = _Formats();
    // The export reads the format at the moment it runs.
    final ran = <DashExportFormat>[];
    await pumpDashApp(
      tester,
      _centered(
        _scoped(
          formats,
          DashExportButton(onExport: () => ran.add(formats.format)),
        ),
      ),
    );
    // "Export", with the menu's chevron: no format in its words.
    expect(find.text('Export'), findsOneWidget);
    expect(find.text('Export Excel'), findsNothing);
    await tester.tap(_trigger);
    await tester.pumpAndSettle();
    expect(find.text('Export as'), findsOneWidget);
    expect(find.text('Excel'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(
      _y(tester, find.text('Export as')),
      lessThan(_y(tester, find.text('Excel'))),
    );
    expect(
      _y(tester, find.text('Excel')),
      lessThan(_y(tester, find.text('PDF'))),
    );
    // Plain items, not a choice that stays: no checks.
    expect(_checked('Excel'), isFalse);
    expect(_checked('PDF'), isFalse);
    // The heading is words, not something to press.
    await tester.tap(find.text('Export as'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(ran, isEmpty);

    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    expect(ran, [DashExportFormat.pdf]);
    expect(formats.format, DashExportFormat.pdf, reason: 'remembered');
    expect(find.text('PDF'), findsNothing, reason: 'the menu closed');

    await tester.tap(_trigger);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excel'));
    await tester.pumpAndSettle();
    expect(ran, [DashExportFormat.pdf, DashExportFormat.xlsx]);
  });

  testWidgets('several files: the format sits at the top, keeps the menu '
      'open, and the file follows it', (tester) async {
    final formats = _Formats();
    final picked = <String>[];
    await pumpDashApp(
      tester,
      _centered(
        _scoped(
          formats,
          DashExportButton(
            onExport: () => picked.add('menu ${formats.format.name}'),
            excelLabel: 'Menu',
            moreHeading: 'Recipes',
            more: [
              DashExportOption(
                label: 'Recipes with costs',
                onSelected: () => picked.add('recipes ${formats.format.name}'),
              ),
              DashExportOption(
                label: 'Recipe lines (CSV)',
                onSelected: () => picked.add('csv'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(_trigger);
    await tester.pumpAndSettle();
    // In order: the format's heading and choices, a rule, the page's file,
    // a rule, the section's heading, its files.
    final order = [
      find.text('Format'),
      find.text('Excel'),
      find.text('PDF'),
      find.byType(Divider).first,
      find.text('Menu'),
      find.byType(Divider).last,
      find.text('Recipes'),
      find.text('Recipes with costs'),
      find.text('Recipe lines (CSV)'),
    ];
    for (final f in order) {
      expect(f, findsOneWidget);
    }
    for (var i = 1; i < order.length; i++) {
      expect(_y(tester, order[i - 1]), lessThan(_y(tester, order[i])));
    }
    expect(find.byType(Divider), findsNWidgets(2));
    expect(_checked('Excel'), isTrue);
    expect(_checked('PDF'), isFalse);

    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    expect(formats.format, DashExportFormat.pdf);
    expect(picked, isEmpty, reason: 'choosing a format exports nothing');
    // Still open: the file is picked next, and the check moved.
    expect(find.text('Menu'), findsOneWidget);
    expect(_checked('PDF'), isTrue);
    expect(_checked('Excel'), isFalse);
    // Choosing it again keeps it chosen (a radio, not a checkbox).
    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    expect(_checked('PDF'), isTrue);
    expect(formats.format, DashExportFormat.pdf);

    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();
    expect(picked, ['menu pdf']);
    expect(find.text('Menu'), findsNothing, reason: 'closed');

    // The other files follow the format too; the heading presses nothing.
    await tester.tap(_trigger);
    await tester.pumpAndSettle();
    expect(_checked('PDF'), isTrue, reason: 'the choice is remembered');
    await tester.tap(find.text('Recipes'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(picked, ['menu pdf']);
    await tester.tap(find.text('Excel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recipes with costs'));
    await tester.pumpAndSettle();
    expect(picked, ['menu pdf', 'recipes xlsx']);
    expect(formats.changes, [
      DashExportFormat.pdf,
      DashExportFormat.pdf,
      DashExportFormat.xlsx,
    ]);
  });

  testWidgets('with CSV: the format, the page\'s file, then CSV (its own '
      'item, whatever the format)', (tester) async {
    final formats = _Formats();
    final picked = <String>[];
    await pumpDashApp(
      tester,
      _centered(
        _scoped(
          formats,
          DashExportButton(
            onExport: () => picked.add('file'),
            onExportCsv: () => picked.add('csv'),
            more: [DashExportOption(label: 'Cards', onSelected: () {})],
          ),
        ),
      ),
    );
    await tester.tap(_trigger);
    await tester.pumpAndSettle();
    // The trigger's words and the page's file's (`common.exportFile`).
    expect(find.text('Export'), findsNWidgets(2));
    final file = find.text('Export').last;
    expect(_y(tester, find.text('PDF')), lessThan(_y(tester, file)));
    expect(_y(tester, file), lessThan(_y(tester, find.text('Export CSV'))));
    expect(
      _y(tester, find.text('Export CSV')),
      lessThan(_y(tester, find.text('Cards'))),
    );
    expect(find.byType(Divider), findsNWidgets(2), reason: 'no heading given');
    // The page's file wears the format's glyph.
    bool glyph(String name) => find
        .descendant(
          of: _row('Export'),
          matching: find.byWidgetPredicate(
            (w) => w is DashIcon && w.name == name,
          ),
        )
        .evaluate()
        .isNotEmpty;
    expect(glyph('file-spreadsheet'), isTrue);
    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    expect(glyph('file-text'), isTrue);

    await tester.tap(find.text('Export CSV'));
    await tester.pumpAndSettle();
    expect(picked, ['csv']);
  });

  testWidgets('without a format scope the button keeps its own choice', (
    tester,
  ) async {
    await pumpDashApp(
      tester,
      _centered(DashExportButton(onExport: () {}, onExportCsv: () {})),
    );
    await tester.tap(_trigger);
    await tester.pumpAndSettle();
    expect(_checked('Excel'), isTrue);
    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    expect(_checked('PDF'), isTrue);
    expect(_checked('Excel'), isFalse);
  });

  testWidgets('a label of its own, loading and disabled, as before', (
    tester,
  ) async {
    var ran = 0;
    await pumpDashApp(
      tester,
      _centered(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DashExportButton(label: 'Pay lists', onExport: () => ran++),
            DashExportButton(
              label: 'Off',
              enabled: false,
              onExport: () => ran++,
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
    await tester.tap(find.text('Excel'));
    await tester.pumpAndSettle();
    expect(ran, 1);
  });
}
