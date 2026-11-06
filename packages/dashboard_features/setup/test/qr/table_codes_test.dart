// The table codes card (SET-QR-019 – 024, 028, 036, 040): pick a branch,
// its tables, one code per table made in sequence, the sheet, the output
// switches re-making it, printing (labels and cut lines on a branded sheet,
// the codes alone on an unbranded one), and the branch moving.

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/shared/qr_preview_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qr_support.dart';

const _make = ValueKey('qr-tables-make');
const _print = ValueKey('qr-tables-print');
const _sheet = ValueKey('qr-tables-sheet');

/// Heliopolis's tables in the backend's `ORDER BY label`.
final _heliopolis = [...qrSeedTables['heliopolis']!]..sort();

void main() {
  testWidgets('SET-QR-019 the "For each table" section; no branch asks for '
      'one and nothing is read', (tester) async {
    final h = await pumpQr(tester);
    expect(inQr(find.text('For each table')), findsOneWidget);
    expect(inTables(find.text('Table codes')), findsOneWidget);
    expect(inTables(find.text(h.t('qr.tables.description'))), findsOneWidget);
    expect(
      inTables(find.text('Choose a branch to see its tables.')),
      findsOneWidget,
    );
    expect(h.server.callsTo(QrRoutes.tables), isEmpty);
  });

  testWidgets('SET-QR-020 loading shows four tiles; a branch with no tables '
      'says where to add them', (tester) async {
    final m = setupMockServer();
    final gate = m.server.hold('GET', QrRoutes.tables);
    final h = await pumpQr(
      tester,
      backend: m,
      query: atBranch(SeedIds.heliopolis),
    );
    final loading = find.byKey(const ValueKey('qr-tables-loading'));
    expect(loading, findsOneWidget);
    expect(
      find.descendant(of: loading, matching: find.byType(DashSkeleton)),
      findsNWidgets(4),
    );
    expect(inTables(find.text(h.t('qr.tables.none'))), findsNothing);
    gate.release();
    await h.settle();
    expect(loading, findsNothing);

    m.db[qrTablesTable].removeWhere((r) => r['branch_id'] == SeedIds.maadi);
    await pickBranch(h, SeedIds.maadi);
    expect(
      inTables(
        find.text(
          'This branch has no tables yet. Add them on the floor plan first.',
        ),
      ),
      findsOneWidget,
    );
    expect(find.byKey(_make), findsNothing);
  });

  testWidgets('SET-QR-021 SET-QR-022 "Make 9 codes": one request per table, '
      'in order, captioned; then the sheet', (tester) async {
    final m = setupMockServer();
    final h = await pumpQr(
      tester,
      backend: m,
      query: atBranch(SeedIds.heliopolis),
    );
    expect(find.text('Make 9 codes'), findsOneWidget);

    final gate = m.server.hold('GET', QrRoutes.tableQr);
    await tester.ensureVisible(find.byKey(_make));
    await tester.pump();
    await tester.tap(find.byKey(_make));
    await tester.pump();
    expect(find.text('Making 9 codes…'), findsOneWidget);
    expect(tester.widget<DashButton>(find.byKey(_make)).onPressed, isNull);
    gate.release();
    await h.settle();

    final calls = h.server.callsTo(QrRoutes.tableQr);
    expect([for (final c in calls) queryOf(c)['caption']], _heliopolis);
    expect(
      calls.first.path,
      '/branches/${SeedIds.heliopolis}/tables/'
      '${qrTableId('heliopolis', 'T1')}/qr',
    );
    expect(find.text('Make 9 codes'), findsOneWidget);

    final sheet = find.byKey(_sheet);
    for (final label in _heliopolis) {
      expect(
        find.descendant(of: sheet, matching: find.text(label)),
        findsOneWidget,
      );
    }
    // Four a row at 1440.
    final rows = {
      for (final l in _heliopolis)
        tester
            .getTopLeft(find.descendant(of: sheet, matching: find.text(l)))
            .dy,
    };
    expect(rows, hasLength(3));

    await h.tap(find.descendant(of: sheet, matching: find.text('T1')));
    final dialog = find.byType(QrPreviewDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('Table T1')),
      findsOneWidget,
    );
  });

  testWidgets('SET-QR-022 the sheet: two a row on a phone, three from 640', (
    tester,
  ) async {
    final h = await pumpQr(
      tester,
      size: DashSize.phone,
      query: atBranch(SeedIds.maadi),
    );
    await h.tap(find.byKey(_make));
    final sheet = find.byKey(_sheet);
    double y(String l) => tester
        .getTopLeft(find.descendant(of: sheet, matching: find.text(l)))
        .dy;
    expect(y('T1'), y('T2'));
    expect(y('T3'), greaterThan(y('T2')));

    tester.view.physicalSize = const Size(700, 900) * DashSize.pixelRatio;
    await h.settle();
    expect(y('T3'), y('T1'));
    expect(y('T4'), greaterThan(y('T3')));
  });

  testWidgets('SET-QR-021 a failure toasts "Could not make the codes"', (
    tester,
  ) async {
    final m = setupMockServer();
    m.server.fail(
      'GET',
      QrRoutes.tableQr,
      MockResponse.error(500, 'boom'),
      times: null,
    );
    final h = await pumpQr(
      tester,
      backend: m,
      query: atBranch(SeedIds.heliopolis),
    );
    await h.tap(find.byKey(_make));
    await h.expectToast('Could not make the codes. Try again.');
    expect(find.byKey(_sheet), findsNothing);
    expect(find.byKey(_print), findsNothing);
  });

  testWidgets('SET-QR-023 "Print sheet" only once codes exist; a branded '
      'sheet prints each card with its label and a cut line', (tester) async {
    final printed = capturePrints();
    final h = await pumpQr(tester, query: atBranch(SeedIds.heliopolis));
    expect(find.byKey(_print), findsNothing);
    await h.tap(find.byKey(_make));
    expect(find.byKey(_print), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(_print));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await h.settle();
    expect(printed, hasLength(1));
    expect(String.fromCharCodes(printed.single.$1.take(5)), '%PDF-');
    expect(printed.single.$2, 'Table codes');
    final facts = pdfFacts(printed.single.$1);
    expect(facts.images, 9);
    expect(facts.text, isTrue, reason: 'each table\'s label');
    expect(facts.dashed, isTrue, reason: 'the cut lines');
  });

  testWidgets('SET-QR-036 an unbranded sheet prints the codes alone: no '
      'label, no cut line, nothing else', (tester) async {
    final printed = capturePrints();
    final h = await pumpQr(
      tester,
      query: atBranch(SeedIds.heliopolis),
      output: const QrOutput(unbranded: true),
    );
    await h.tap(find.byKey(_make));
    // On screen the labels stay: thirty identical squares are unsortable.
    expect(
      find.descendant(of: find.byKey(_sheet), matching: find.text('T1')),
      findsOneWidget,
    );
    await tester.runAsync(() async {
      await tester.tap(find.byKey(_print));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await h.settle();
    expect(pdfFacts(printed.single.$1), (
      images: 9,
      text: false,
      dashed: false,
      fonts: false,
    ));
  });

  testWidgets('SET-QR-040 the sheet follows the switches: asked for as the '
      'shop chose, made again on a flip with no second press', (tester) async {
    final h = await pumpQr(
      tester,
      query: atBranch(SeedIds.heliopolis),
      output: const QrOutput(unbranded: true, centreLogo: false, dpi: 300),
    );
    await h.tap(find.byKey(_make));
    final calls = h.server.callsTo(QrRoutes.tableQr);
    expect(calls, hasLength(9));
    expect(queryOf(calls.first), {
      'unbranded': 'true',
      'centre_logo': 'false',
      'dpi': '300',
      'caption': 'T1',
    });
    final plain = tester
        .widget<QrImage>(
          find.descendant(
            of: find.byKey(
              ValueKey('qr-table-${qrTableId('heliopolis', 'T1')}'),
            ),
            matching: find.byType(QrImage),
          ),
        )
        .dataUrl;

    await h.tap(inPanel(find.byKey(const ValueKey('qr-unbranded'))));
    expect(h.server.callsTo(QrRoutes.tableQr), hasLength(18));
    expect(queryOf(h.server.callsTo(QrRoutes.tableQr).last), {
      'card': 'true',
      'dpi': '300',
      'caption': 'T9',
    });
    final card = tester
        .widget<QrImage>(
          find.descendant(
            of: find.byKey(
              ValueKey('qr-table-${qrTableId('heliopolis', 'T1')}'),
            ),
            matching: find.byType(QrImage),
          ),
        )
        .dataUrl;
    expect(card, isNot(plain));

    // A table's preview carries the switches too.
    await h.tap(
      find.descendant(of: find.byKey(_sheet), matching: find.text('T1')),
    );
    final dialog = find.byType(QrPreviewDialog);
    expect(
      find.descendant(
        of: dialog,
        matching: find.byKey(const ValueKey('qr-output-controls')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('SET-QR-024 moving the header branch drops the sheet; back '
      'again, that room\'s own sheet', (tester) async {
    final h = await pumpQr(tester, query: atBranch(SeedIds.heliopolis));
    await h.tap(find.byKey(_make));
    expect(find.byKey(_sheet), findsOneWidget);
    await pickBranch(h, SeedIds.zamalek);
    expect(find.byKey(_sheet), findsNothing);
    expect(find.text('Make 10 codes'), findsOneWidget);
    final made = h.server.callsTo(QrRoutes.tableQr).length;
    await pickBranch(h, SeedIds.heliopolis);
    expect(find.byKey(_sheet), findsOneWidget);
    expect(h.server.callsTo(QrRoutes.tableQr), hasLength(made));
  });

  testWidgets('SET-QR-021 a run that lands after the branch moved is '
      'dropped', (tester) async {
    final m = setupMockServer();
    final h = await pumpQr(
      tester,
      backend: m,
      query: atBranch(SeedIds.heliopolis),
    );
    final gate = m.server.hold('GET', QrRoutes.tableQr);
    await h.tap(find.byKey(_make));
    await pickBranch(h, SeedIds.zamalek);
    gate.release();
    await h.settle();
    expect(find.byKey(_sheet), findsNothing);
    expect(find.text('Make 10 codes'), findsOneWidget);
  });

  testWidgets('SET-QR-028 (divergence) a failed tables read shows the error '
      'with Retry, not "no tables"', (tester) async {
    final m = setupMockServer();
    m.server.fail(
      'GET',
      QrRoutes.tables,
      MockResponse.error(500, 'boom'),
      times: null,
    );
    final h = await pumpQr(
      tester,
      backend: m,
      query: atBranch(SeedIds.heliopolis),
    );
    expect(inTables(find.text("Couldn't load this")), findsOneWidget);
    expect(inTables(find.text(h.t('qr.tables.none'))), findsNothing);
    m.server.clearFailures();
    await h.tap(inTables(find.text('Retry')));
    expect(find.text('Make 9 codes'), findsOneWidget);
  });

  testWidgets('SET-QR-028 a failure part-way through making it again '
      'keeps the sheet already made', (tester) async {
    final m = setupMockServer();
    final h = await pumpQr(
      tester,
      backend: m,
      query: atBranch(SeedIds.heliopolis),
    );
    await h.tap(find.byKey(_make));
    expect(find.byKey(_sheet), findsOneWidget);

    m.server.fail(
      'GET',
      QrRoutes.tableQr,
      MockResponse.error(500, 'boom'),
      times: null,
    );
    await h.tap(find.byKey(_make));
    await h.expectToast('Could not make the codes. Try again.');
    expect(
      find.descendant(of: find.byKey(_sheet), matching: find.text('T5')),
      findsOneWidget,
    );
  });

  testWidgets('SET-QR-028 a table renamed: the sheet is made again with its '
      'new label', (tester) async {
    final m = setupMockServer();
    final h = await pumpQr(
      tester,
      backend: m,
      query: atBranch(SeedIds.heliopolis),
    );
    await h.tap(find.byKey(_make));
    m.db[qrTablesTable].find(qrTableId('heliopolis', 'T5'))!['label'] = 'T5b';
    h.container.invalidate(qrTablesProvider);
    await h.settle();
    final sheet = find.byKey(_sheet);
    expect(
      find.descendant(of: sheet, matching: find.text('T5b')),
      findsOneWidget,
    );
    expect(find.descendant(of: sheet, matching: find.text('T5')), findsNothing);
    expect(queryOf(h.server.callsTo(QrRoutes.tableQr).last)['caption'], 'T9');
  });

  testWidgets('refusal: another org\'s branch is refused in the error '
      'state\'s words', (tester) async {
    final m = setupMockServer();
    m.server.fail(
      'GET',
      QrRoutes.tables,
      MockResponse.forbidden('Access to this org is not allowed'),
      times: null,
    );
    final h = await pumpQr(
      tester,
      backend: m,
      query: atBranch(SeedIds.heliopolis),
    );
    expect(
      inTables(
        find.text(
          h.refusalWords(
            MockResponse.forbidden('Access to this org is not allowed'),
          ),
        ),
      ),
      findsOneWidget,
    );
  });
}
