/// The enlarged QR code, its short link, and the two things you do with it
/// (`features/qr/qr-preview-dialog.tsx`, SET-QR-025). Opened by the QR page
/// (a generated code, a table code), the Links page ("Links page code") and
/// Loyalty ("Join code").
///
/// The destination URL wraps rather than truncates (a wrong base URL is
/// invisible until a printed card is scanned); the code sits on white so it
/// scans in either theme; the buttons stack on a phone.
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' show QrResponse;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show linkOpenerProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens [qr] in the preview dialog titled [title] (default "QR Code").
Future<void> showQrPreview(
  BuildContext context, {
  required QrResponse qr,
  String? title,
}) => showDashDialog<void>(
  context,
  width: QrPreviewDialog.width,
  // A small card on every screen, as on the web (never edge to edge).
  phoneFullScreen: false,
  builder: (_) => QrPreviewDialog(qr: qr, title: title),
);

/// The file name a downloaded code is saved under: `qr-<short_code>.svg`
/// for an SVG data URL, else `.png`.
String qrFileName(QrResponse qr) =>
    'qr-${qr.shortCode}.${qr.qrDataUrl.startsWith('data:image/svg') ? 'svg' : 'png'}';

/// The decoded image bytes of a `data:` URL (null when it is not one).
Uint8List? qrImageBytes(String dataUrl) {
  try {
    return UriData.parse(dataUrl).contentAsBytes();
  } on FormatException {
    return null;
  }
}

class QrPreviewDialog extends ConsumerStatefulWidget {
  const QrPreviewDialog({required this.qr, this.title, super.key});

  /// The web's `sm:max-w-sm`.
  static const double width = 384;

  /// How long "Copied!" shows.
  static const Duration copiedFor = Duration(seconds: 2);

  final QrResponse qr;
  final String? title;

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

  Future<void> _download() async {
    final t = ref.read(tProvider);
    try {
      await saveDataUri(
        ref.read(fileGatewayProvider),
        widget.qr.qrDataUrl,
        qrFileName(widget.qr),
      );
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final qr = widget.qr;
    final label = widget.title ?? t('qr.preview.title');
    final bytes = qrImageBytes(qr.qrDataUrl);
    final stacked = MediaQuery.sizeOf(context).width < DashBreakpoints.sm;

    final image = Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: c.hairline),
      ),
      child: Center(
        child: ConstrainedBox(
          // `max-w-56`: big enough to scan off a screen, never the dialog.
          constraints: const BoxConstraints(maxWidth: 224),
          child: Container(
            padding: const EdgeInsets.all(Space.xs),
            decoration: BoxDecoration(
              // The quiet zone is white in both themes (the light paper's
              // card): a code on a dark card does not scan.
              color: MadarColors.light.surface,
              borderRadius: BorderRadius.circular(Space.xs),
            ),
            child: AspectRatio(
              aspectRatio: 1,
              child: bytes == null
                  ? Center(
                      child: DashIcon(
                        'qr-code',
                        size: IconSize.xl,
                        color: c.textMuted,
                      ),
                    )
                  : Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.none,
                      gaplessPlayback: true,
                      semanticLabel: t('qr.imageAlt', args: {'title': label}),
                      errorBuilder: (_, _, _) => Center(
                        child: DashIcon(
                          'qr-code',
                          size: IconSize.xl,
                          color: c.textMuted,
                        ),
                      ),
                    ),
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
          DashBadge(qr.shortCode, mono: true),
        ],
      ),
    );

    final copy = DashButton(
      label: _copied ? t('common.copied') : t('common.copyLink'),
      icon: _copied ? 'check' : 'copy',
      variant: DashButtonVariant.outline,
      expand: true,
      onPressed: _copy,
    );
    final download = DashButton(
      label: t('common.download'),
      icon: 'download',
      expand: true,
      onPressed: _download,
    );

    return DashSurface(
      title: label,
      description: qr.longUrl,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          image,
          link,
          if (stacked)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.sm,
              children: [copy, download],
            )
          else
            Row(
              spacing: Space.sm,
              children: [
                Expanded(child: copy),
                Expanded(child: download),
              ],
            ),
        ],
      ),
    );
  }
}
