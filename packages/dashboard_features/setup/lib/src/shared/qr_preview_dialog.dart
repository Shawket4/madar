/// The enlarged QR code, its short link, and the things you do with it
/// (`features/qr/qr-preview-dialog.tsx`, SET-QR-025): copy the link, print
/// the code, share it (where the platform can), download it. Opened by every
/// code on Settings › Links & QR codes (live, with the output switches under
/// the code, `live_qr_dialog.dart`) and by Loyalty ("Join code").
///
/// Download, Print and Share all hand over the server's image untouched, so
/// an unbranded code leaves as the code alone. The destination URL wraps
/// rather than truncates (a wrong base URL is invisible until a printed card
/// is scanned); the code sits on white so it scans in either theme.
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' show QrResponse;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show linkOpenerProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../qr/qr_output.dart';
import '../qr/qr_print.dart';

/// Opens [qr] in the preview dialog titled [title] (default "QR Code"): a
/// code that does not follow the output switches (Loyalty's join code).
Future<void> showQrPreview(
  BuildContext context, {
  required QrResponse qr,
  String? title,
}) => showDashDialog<void>(
  context,
  width: QrPreviewDialog.width,
  // A small card on every screen, as on the web (never edge to edge).
  builder: (_) => QrPreviewDialog(qr: qr, title: title),
);

/// The file name a downloaded code is saved under (`qrFileName`): it says
/// which variant it is, so two downloads never collide:
/// `qr-<short_code>[-unbranded].svg|png`.
String qrFileName(QrResponse qr, {bool unbranded = false}) =>
    'qr-${qr.shortCode}${unbranded ? '-unbranded' : ''}.'
    '${qr.qrDataUrl.startsWith('data:image/svg') ? 'svg' : 'png'}';

/// The decoded image bytes of a `data:` URL (null when it is not one).
Uint8List? qrImageBytes(String dataUrl) {
  try {
    return UriData.parse(dataUrl).contentAsBytes();
  } on FormatException {
    return null;
  }
}

/// Where the system can take a file to share (`canShare`): a phone, a
/// tablet, a Mac, Windows. Linux has no share sheet.
bool qrCanShare() => switch (defaultTargetPlatform) {
  TargetPlatform.android ||
  TargetPlatform.iOS ||
  TargetPlatform.macOS ||
  TargetPlatform.windows => true,
  TargetPlatform.linux || TargetPlatform.fuchsia => false,
};

/// Saves [qr]'s image as [qrFileName]; a failure toasts.
Future<void> downloadQr(
  BuildContext context,
  WidgetRef ref,
  QrResponse qr, {
  required bool unbranded,
}) async {
  final t = ref.read(tProvider);
  try {
    await saveDataUri(
      ref.read(fileGatewayProvider),
      qr.qrDataUrl,
      qrFileName(qr, unbranded: unbranded),
    );
  } on Object catch (e) {
    if (context.mounted) DashToast.error(context, errorMessage(e, t));
  }
}

/// Prints [qr] alone at its real size ([printQrCodes]); a failure toasts.
Future<void> printQr(
  BuildContext context,
  WidgetRef ref,
  QrResponse qr, {
  required QrShape shape,
  required String title,
}) async {
  final t = ref.read(tProvider);
  try {
    await printQrCodes(
      [(src: qr.qrDataUrl, label: null)],
      shape,
      name: title,
      rtl: t.isRtl,
    );
  } on Object catch (e) {
    if (context.mounted) DashToast.error(context, errorMessage(e, t));
  }
}

/// Hands [qr]'s image to the share sheet, with its short link as the text
/// (`shareCode`); a failure toasts "Could not share the code".
Future<void> shareQr(
  BuildContext context,
  WidgetRef ref,
  QrResponse qr, {
  required bool unbranded,
}) async {
  final t = ref.read(tProvider);
  final bytes = qrImageBytes(qr.qrDataUrl);
  try {
    if (bytes == null) throw const FormatException('not a data: URI');
    await ref
        .read(fileGatewayProvider)
        .share(
          bytes,
          filename: qrFileName(qr, unbranded: unbranded),
          mimeType: UriData.parse(qr.qrDataUrl).mimeType,
          text: qr.shortUrl,
        );
  } on Object {
    if (context.mounted) DashToast.error(context, t('qr.shareFailed'));
  }
}

class QrPreviewDialog extends ConsumerStatefulWidget {
  const QrPreviewDialog({
    required this.qr,
    this.title,
    this.busy = false,
    this.shape = QrShape.card,
    this.controls,
    super.key,
  });

  /// The web's `sm:max-w-md`.
  static const double width = 448;

  /// How long "Copied!" shows.
  static const Duration copiedFor = Duration(seconds: 2);

  final QrResponse qr;
  final String? title;

  /// A new render is on its way (a switch was flipped); this one stays up.
  final bool busy;

  /// What the image is, so Print sizes it true. Default: the A6 card.
  final QrShape shape;

  /// The output switches, under the code so they sit beside what they
  /// change.
  final Widget? controls;

  @override
  ConsumerState<QrPreviewDialog> createState() => _QrPreviewDialogState();
}

class _QrPreviewDialogState extends ConsumerState<QrPreviewDialog> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final t = ref.read(tProvider);
    try {
      await Clipboard.setData(ClipboardData(text: widget.qr.shortUrl));
    } on Object {
      if (mounted) DashToast.error(context, t('common.copyFailed'));
      return;
    }
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(QrPreviewDialog.copiedFor, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final qr = widget.qr;
    final label = widget.title ?? t('qr.preview.title');
    final unbranded = widget.shape == QrShape.plain;
    final phone = MediaQuery.sizeOf(context).width < DashBreakpoints.sm;

    final image = Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: c.hairline),
      ),
      child: Center(
        child: ConstrainedBox(
          // `max-w-56` (`max-w-48` for the bare code): big enough to scan
          // off a screen, never the dialog.
          constraints: BoxConstraints(maxWidth: unbranded ? 192 : 224),
          child: QrBusyVeil(
            key: const ValueKey('qr-preview-image'),
            busy: widget.busy,
            child: QrImage(
              dataUrl: qr.qrDataUrl,
              semanticLabel: t('qr.imageAlt', args: {'title': label}),
            ),
          ),
        ),
      ),
    );

    final link = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.sm,
        children: [
          DashPressable(
            isButton: false,
            pressScale: false,
            semanticLabel: qr.shortUrl,
            onTap: () => ref.read(linkOpenerProvider)(Uri.parse(qr.shortUrl)),
            builder: (context, s) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.xs + DashMetrics.hair,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: DashIcon(
                    'external-link',
                    size: IconSize.xs - 2,
                    color: c.textPrimary,
                  ),
                ),
                Expanded(
                  child: Text(
                    qr.shortUrl,
                    textDirection: TextDirection.ltr,
                    style: DashType.bodyMedium.copyWith(
                      color: c.textPrimary,
                      decoration: s.highlighted
                          ? TextDecoration.underline
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          DashBadge(qr.shortCode, mono: true, outline: true),
        ],
      ),
    );

    final buttons = [
      DashButton(
        key: const ValueKey('qr-preview-copy'),
        label: _copied ? t('common.copied') : t('common.copyLink'),
        icon: _copied ? 'check' : 'copy',
        variant: DashButtonVariant.outline,
        expand: true,
        onPressed: _copy,
      ),
      DashButton(
        key: const ValueKey('qr-print'),
        label: t('qr.print'),
        icon: 'printer',
        variant: DashButtonVariant.outline,
        expand: true,
        onPressed: () =>
            printQr(context, ref, qr, shape: widget.shape, title: label),
      ),
      if (qrCanShare())
        DashButton(
          key: const ValueKey('qr-share'),
          label: t('qr.share'),
          icon: 'share-2',
          variant: DashButtonVariant.outline,
          expand: true,
          onPressed: () => shareQr(context, ref, qr, unbranded: unbranded),
        ),
      DashButton(
        key: const ValueKey('qr-download'),
        label: t('common.download'),
        icon: 'download',
        expand: true,
        onPressed: () => downloadQr(context, ref, qr, unbranded: unbranded),
      ),
    ];

    return DashSurface(
      title: label,
      description: qr.longUrl,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          image,
          if (widget.controls != null)
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: c.muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(Radii.xs),
                border: Border.all(color: c.hairline),
              ),
              child: widget.controls,
            ),
          link,
          // Two a row on a phone, all in one row from 640: never so narrow
          // that a label is cut short.
          if (phone || buttons.length > 3)
            _Rows(columns: 2, children: buttons)
          else
            Row(
              spacing: Space.sm,
              children: [for (final b in buttons) Expanded(child: b)],
            ),
        ],
      ),
    );
  }
}

/// [children] in rows of [columns], equal widths.
class _Rows extends StatelessWidget {
  const _Rows({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Space.sm,
    children: [
      for (var i = 0; i < children.length; i += columns)
        Row(
          spacing: Space.sm,
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

/// [child] dimmed, with a spinner over it, while a new render is on its way
/// (the web's `opacity-50` + RefreshCw).
class QrBusyVeil extends ConsumerWidget {
  const QrBusyVeil({required this.busy, required this.child, super.key});

  final bool busy;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.madarColors;
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedOpacity(
          opacity: busy ? 0.5 : 1,
          duration: DashMotion.of(context, DashMotion.fast),
          child: child,
        ),
        if (busy)
          Semantics(
            liveRegion: true,
            label: ref.watch(tProvider)('qr.updating'),
            child: SizedBox.square(
              dimension: IconSize.sm,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: c.textPrimary,
              ),
            ),
          ),
      ],
    );
  }
}

/// A code image on white (the light paper's surface in both themes: a code
/// on a dark card does not scan), square, scaled to its box. [aspectRatio]
/// is the image's own (the A6 card is taller than wide).
class QrImage extends StatelessWidget {
  const QrImage({
    required this.dataUrl,
    required this.semanticLabel,
    this.aspectRatio = 1,
    super.key,
  });

  final String dataUrl;
  final String semanticLabel;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final bytes = qrImageBytes(dataUrl);
    final missing = Center(
      child: DashIcon('qr-code', size: IconSize.xl, color: c.textMuted),
    );
    return Container(
      padding: const EdgeInsets.all(Space.xs),
      decoration: BoxDecoration(
        color: MadarColors.light.surface,
        borderRadius: BorderRadius.circular(Space.xs),
      ),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: bytes == null
            ? missing
            : Image.memory(
                bytes,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
                gaplessPlayback: true,
                semanticLabel: semanticLabel,
                errorBuilder: (_, _, _) => missing,
              ),
      ),
    );
  }
}
