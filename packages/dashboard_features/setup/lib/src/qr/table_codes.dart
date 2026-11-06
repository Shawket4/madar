/// A code for every table in the room (`features/qr/table-codes.tsx`,
/// SET-QR-019 – 024, 028): made together, one request at a time, laid out on
/// one sheet with each table's label in large type (thirty identical squares
/// are unsortable), and printed together.
///
/// The set follows the page's output switches like every other code: flip
/// Unbranded and the sheet is made again, unbranded (a read keyed by the
/// output, the old sheet held up until the new one is complete). On paper
/// the label goes with the branded card, as it always has; an unbranded
/// sheet prints the codes and nothing else ([printQrCodes]).
///
/// The codes belong to the branch they were made for: moving the header to
/// another branch drops the sheet, and a run that lands after the move is
/// not shown.
library;

import 'package:dashboard_api/dashboard_api.dart' show BranchTable;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/qr_preview_dialog.dart';
import 'live_qr_dialog.dart';
import 'qr_output.dart';
import 'qr_print.dart';
import 'qr_providers.dart';

class QrTableCodes extends ConsumerStatefulWidget {
  const QrTableCodes({required this.orgId, required this.branchId, super.key});

  final String orgId;

  /// The header's branch; null asks for one.
  final String? branchId;

  @override
  ConsumerState<QrTableCodes> createState() => _QrTableCodesState();
}

class _QrTableCodesState extends ConsumerState<QrTableCodes> {
  /// The branch the sheet was asked for in (`requestedFor`).
  String? _requestedFor;
  bool _printing = false;
  final _hold = LiveQrHold<List<QrTableCode>>();

  QrTableSheetKey _key(String branchId, List<BranchTable> rows) =>
      qrTableSheetKey(
        branchId,
        rows,
        qrRenderParams(ref.read(qrOutputProvider(widget.orgId))),
      );

  void _makeAll(String branchId, List<BranchTable> rows) {
    if (rows.isEmpty) return;
    if (_requestedFor == branchId) {
      // Asked again: every card is drawn again (a Brand edit since).
      ref.invalidate(qrTableSheetProvider(_key(branchId, rows)));
    } else {
      setState(() => _requestedFor = branchId);
    }
  }

  /// Warms the sheet the press reads, one code at a time like the press.
  void _warmAll(String branchId, List<BranchTable> rows) {
    if (rows.isEmpty || _requestedFor == branchId) return;
    ref.warm(qrTableSheetProvider(_key(branchId, rows)));
  }

  Future<void> _print(List<QrTableCode> codes, QrShape shape) async {
    final t = ref.read(tProvider);
    setState(() => _printing = true);
    try {
      await printQrCodes(
        [for (final c in codes) (src: c.qr.qrDataUrl, label: c.label)],
        shape,
        name: t('qr.tables.title'),
        rtl: t.isRtl,
      );
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
    final o = ref.watch(qrOutputProvider(widget.orgId));
    final shape = qrShape(o);

    final rows = q?.value ?? const <BranchTable>[];
    final enabled =
        branchId != null && _requestedFor == branchId && rows.isNotEmpty;
    final key = enabled
        ? qrTableSheetKey(branchId, rows, qrRenderParams(o))
        : null;
    if (key != null) {
      // Any failure, the first run's or a re-render's after a switch.
      ref.listen(qrTableSheetProvider(key), (_, next) {
        if (next.hasError && !next.isLoading && mounted) {
          DashToast.error(context, t('qr.tables.failed'));
        }
      });
    }
    final sheet = _hold.view(
      key == null ? null : ref.watch(qrTableSheetProvider(key)),
    );
    final codes = sheet.data ?? const <QrTableCode>[];
    final making = enabled && sheet.busy;

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
    } else if (rows.isEmpty) {
      content = quiet(t('qr.tables.none'));
    } else {
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
                // `count` picks the plural: Arabic has six forms.
                label: making
                    ? t('qr.tables.making', count: rows.length)
                    : t('qr.tables.make', count: rows.length),
                icon: 'qr-code',
                loading: making,
                onPressed: making && codes.isEmpty
                    ? null
                    : () => _makeAll(branchId!, rows),
                onIntent: () => _warmAll(branchId!, rows),
              ),
              if (codes.isNotEmpty)
                DashButton(
                  key: const ValueKey('qr-tables-print'),
                  label: t('qr.tables.print'),
                  icon: 'printer',
                  variant: DashButtonVariant.outline,
                  loading: _printing,
                  onPressed: making || _printing
                      ? null
                      : () => _print(codes, shape),
                ),
            ],
          ),
          if (codes.isNotEmpty)
            _Grid(
              key: const ValueKey('qr-tables-sheet'),
              columns: width >= DashBreakpoints.lg
                  ? 4
                  : width >= DashBreakpoints.sm
                  ? 3
                  : 2,
              gap: Space.md,
              children: [
                for (final code in codes)
                  _Tile(
                    code: code,
                    busy: making,
                    onPreview: () => _preview(code, rows),
                  ),
              ],
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

  /// The table's code, live: the switches in the preview re-make the sheet.
  void _preview(QrTableCode code, List<BranchTable> rows) {
    final t = ref.read(tProvider);
    final branchId = widget.branchId;
    if (branchId == null) return;
    showLiveQrPreview(
      context,
      orgId: widget.orgId,
      title: t('qr.tables.previewTitle', args: {'label': code.label}),
      watch: (ref, params) => ref
          .watch(qrTableSheetProvider(qrTableSheetKey(branchId, rows, params)))
          .whenData((codes) => codes.firstWhere((c) => c.id == code.id).qr),
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
  const _Tile({
    required this.code,
    required this.busy,
    required this.onPreview,
  });

  final QrTableCode code;
  final bool busy;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final radius = BorderRadius.circular(Radii.card);
    return DashPressable(
      key: ValueKey('qr-table-${code.id}'),
      tooltip: t('qr.tables.previewHint'),
      semanticLabel: t('qr.tables.imageAlt', args: {'label': code.label}),
      excludeChildSemantics: true,
      pressScale: false,
      onTap: onPreview,
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
            QrBusyVeil(
              busy: busy,
              child: QrImage(
                dataUrl: code.qr.qrDataUrl,
                semanticLabel: t(
                  'qr.tables.imageAlt',
                  args: {'label': code.label},
                ),
              ),
            ),
            // The label, large: thirty identical squares are unsortable. It
            // prints under a branded card; an unbranded sheet prints the
            // codes alone.
            Text(
              code.label,
              textAlign: TextAlign.center,
              style: MadarType.h3.copyWith(color: c.textPrimary, height: 1),
            ),
          ],
        ),
      ),
    );
  }
}
