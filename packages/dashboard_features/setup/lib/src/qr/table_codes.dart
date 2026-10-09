/// A code for every table in the room (`features/qr/table-codes.tsx`,
/// SET-QR-019 – 024, 028): made together, one request at a time, laid out on
/// one sheet with each table's label in large type (thirty identical squares
/// are unsortable once off the printer), and printed together.
///
/// The codes belong to the branch they were made for: moving the header to
/// another branch drops the sheet.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dashboard_api/dashboard_api.dart' show BranchTable, QrResponse;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../shared/qr_preview_dialog.dart';
import 'qr_providers.dart';
import 'qr_result.dart';

/// One table's code on the sheet.
typedef QrTableCode = (BranchTable table, QrResponse qr);

/// Hands the sheet's PDF to the system print dialog (the web's
/// `window.print()`).
// ponytail: a seam tests replace; becomes a print gateway in dashboard_core
// once a second page prints.
@visibleForTesting
Future<void> Function(Uint8List pdf, String name) qrPrintPdf = (pdf, name) =>
    Printing.layoutPdf(onLayout: (_) async => pdf, name: name);

class QrTableCodes extends ConsumerStatefulWidget {
  const QrTableCodes({required this.branchId, super.key});

  /// The header's branch; null asks for one.
  final String? branchId;

  @override
  ConsumerState<QrTableCodes> createState() => _QrTableCodesState();
}

class _QrTableCodesState extends ConsumerState<QrTableCodes> {
  List<QrTableCode> _codes = const [];
  bool _busy = false;
  bool _printing = false;

  @override
  void didUpdateWidget(QrTableCodes old) {
    super.didUpdateWidget(old);
    // Another branch's room is not this one's: a sheet left on screen would
    // be printed and stuck to the wrong tables.
    if (old.branchId != widget.branchId) _codes = const [];
  }

  Future<void> _makeAll(List<BranchTable> rows) async {
    final branchId = widget.branchId;
    if (branchId == null || rows.isEmpty) return;
    final t = ref.read(tProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    try {
      final out = await readTableCodes(container, branchId, rows);
      if (mounted && widget.branchId == branchId) {
        setState(() => _codes = out);
      }
    } on Object {
      if (mounted) DashToast.error(context, t('qr.tables.failed'));
    } finally {
      // The cache only bridges hover to press: each card is drawn from the
      // org's current brand, so the next press asks again.
      for (final row in rows) {
        container.invalidate(
          qrTableCodeProvider((
            branchId: branchId,
            tableId: row.id,
            caption: row.label,
          )),
        );
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Warms the codes the press will read, one at a time like the press.
  void _warmAll(List<BranchTable> rows) {
    final branchId = widget.branchId;
    if (branchId == null || rows.isEmpty) return;
    readTableCodes(
      ProviderScope.containerOf(context, listen: false),
      branchId,
      rows,
    ).ignore();
  }

  Future<void> _print() async {
    final t = ref.read(tProvider);
    setState(() => _printing = true);
    try {
      final pdf = await qrTableSheetPdf(_codes, rtl: t.isRtl);
      await qrPrintPdf(pdf, t('qr.tables.title'));
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final branchId = widget.branchId;
    final q = branchId == null ? null : ref.watch(qrTablesProvider(branchId));
    final width = MediaQuery.sizeOf(context).width;

    Widget quiet(String text) =>
        Text(text, style: DashType.body.copyWith(color: c.textSecondary));

    final Widget content;
    if (q == null) {
      content = quiet(t('qr.tables.pickBranch'));
    } else if (q.awaitingFirst) {
      content = _Grid(
        key: const ValueKey('qr-tables-loading'),
        columns: width >= DashBreakpoints.sm ? 4 : 2,
        gap: Space.sm,
        children: [
          for (var i = 0; i < 4; i++)
            const DashSkeleton(height: Space.xxl * 2.5, radius: Radii.card),
        ],
      );
    } else if (q.failedFirst) {
      content = DashErrorState(
        framed: false,
        title: t('common.loadFailed'),
        message: errorMessage(q.error, t),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(qrTablesProvider(branchId!)),
      );
    } else if ((q.value ?? const []).isEmpty) {
      content = quiet(t('qr.tables.none'));
    } else {
      final rows = q.value!;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              DashButton(
                key: const ValueKey('qr-tables-make'),
                label: _busy
                    ? t('qr.tables.making', count: rows.length)
                    : t('qr.tables.make', count: rows.length),
                icon: 'qr-code',
                onPressed: _busy ? null : () => _makeAll(rows),
                onIntent: () => _warmAll(rows),
              ),
              if (_codes.isNotEmpty)
                DashButton(
                  key: const ValueKey('qr-tables-print'),
                  label: t('qr.tables.print'),
                  icon: 'printer',
                  variant: DashButtonVariant.outline,
                  loading: _printing,
                  onPressed: _print,
                ),
            ],
          ),
          if (_codes.isNotEmpty)
            _Grid(
              key: const ValueKey('qr-tables-sheet'),
              columns: width >= DashBreakpoints.lg
                  ? 4
                  : width >= DashBreakpoints.sm
                  ? 3
                  : 2,
              gap: Space.md,
              children: [for (final code in _codes) _Tile(code: code)],
            ),
        ],
      );
    }

    return DashCard(
      key: const ValueKey('qr-tables'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.xs + DashMetrics.hair,
            children: [
              Row(
                spacing: Space.sm,
                children: [
                  DashIcon('table-2', size: IconSize.xs, color: c.textPrimary),
                  Expanded(
                    child: Text(
                      t('qr.tables.title'),
                      style: DashType.sectionTitle.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                t('qr.tables.description'),
                style: DashType.body.copyWith(color: c.textSecondary),
              ),
            ],
          ),
          content,
        ],
      ),
    );
  }
}

/// [children] in rows of [columns], equal widths.
class _Grid extends StatelessWidget {
  const _Grid({
    required this.columns,
    required this.gap,
    required this.children,
    super.key,
  });

  final int columns;
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: gap,
    children: [
      for (var i = 0; i < children.length; i += columns)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: gap,
          children: [
            for (var j = i; j < i + columns; j++)
              Expanded(
                child: j < children.length
                    ? children[j]
                    : const SizedBox.shrink(),
              ),
          ],
        ),
    ],
  );
}

/// One table's code: the code on white, its label large; press to enlarge.
class _Tile extends ConsumerWidget {
  const _Tile({required this.code});

  final QrTableCode code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final (table, qr) = code;
    final radius = BorderRadius.circular(Radii.card);
    return DashPressable(
      key: ValueKey('qr-table-${table.id}'),
      tooltip: t('qr.tables.previewHint'),
      semanticLabel: t('qr.tables.imageAlt', args: {'label': table.label}),
      excludeChildSemantics: true,
      pressScale: false,
      onTap: () => showQrPreview(
        context,
        qr: qr,
        title: t('qr.tables.previewTitle', args: {'label': table.label}),
      ),
      builder: (context, s) => Container(
        padding: const EdgeInsets.all(Space.md),
        foregroundDecoration: dashFocusRing(context, s, radius),
        decoration: BoxDecoration(
          color: s.highlighted ? c.hover : c.card,
          borderRadius: radius,
          border: Border.all(color: c.hairline),
        ),
        child: Column(
          spacing: Space.sm,
          children: [
            QrImage(
              dataUrl: qr.qrDataUrl,
              semanticLabel: t(
                'qr.tables.imageAlt',
                args: {'label': table.label},
              ),
            ),
            Text(
              table.label,
              textAlign: TextAlign.center,
              style: MadarType.h3.copyWith(color: c.textPrimary, height: 1),
            ),
          ],
        ),
      ),
    );
  }
}

Future<pw.Font> _font(String name) async => pw.Font.ttf(
  await rootBundle.load('packages/design_system/assets/fonts/$name.ttf'),
);

/// The printable sheet as an A4 PDF: three codes a row, each on white with a
/// dashed cut line and its label large, a row never split across pages.
Future<Uint8List> qrTableSheetPdf(
  List<QrTableCode> codes, {
  bool rtl = false,
}) async {
  final bold = await _font('IBMPlexSansArabic-Bold');
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: bold, bold: bold),
  );
  const columns = 3;
  pw.Widget tile(QrTableCode code) {
    final (table, qr) = code;
    final data = UriData.parse(qr.qrDataUrl);
    final pw.Widget image = data.mimeType.startsWith('image/svg')
        ? pw.SvgImage(svg: utf8.decode(data.contentAsBytes()))
        : pw.Image(pw.MemoryImage(data.contentAsBytes()));
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(
          color: PdfColors.grey600,
          style: pw.BorderStyle.dashed,
        ),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        children: [
          pw.AspectRatio(aspectRatio: 1, child: image),
          pw.SizedBox(height: 6),
          pw.Text(
            table.label,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 18, color: PdfColors.black),
          ),
        ],
      ),
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(12 * PdfPageFormat.mm),
      textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      build: (context) => [
        for (var i = 0; i < codes.length; i += columns)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (var j = i; j < i + columns; j++) ...[
                  if (j > i) pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: j < codes.length ? tile(codes[j]) : pw.SizedBox(),
                  ),
                ],
              ],
            ),
          ),
      ],
    ),
  );
  return doc.save();
}
