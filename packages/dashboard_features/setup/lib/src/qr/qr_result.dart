/// One generated code under its card (`QrResult` in `features/qr/
/// codes-section.tsx`, SET-QR-015 – 018): the code on a white quiet zone
/// (press to enlarge, the live preview), the short link, the long address it
/// lands on, "Copy link", "Print" and "Download". While a flipped switch
/// re-renders it, the old image stays up, dimmed ([QrBusyVeil]).
///
/// URLs wrap at any character rather than truncate: a misconfigured public
/// base URL is invisible until a printed card is scanned.
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

import '../shared/qr_preview_dialog.dart';
import 'qr_output.dart';

class QrResultCard extends ConsumerStatefulWidget {
  const QrResultCard({
    required this.qr,
    required this.title,
    required this.onPreview,
    this.shape = QrShape.card,
    this.busy = false,
    super.key,
  });

  /// The web's `max-w-52` on the code.
  static const double codeWidth = 208;

  /// Below this, Print and Download stack (the 256-wide card beside the
  /// controls from 1024 would cut "Download" short).
  static const double pairWidth = 260;

  /// How long "Copied" shows.
  static const Duration copiedFor = Duration(milliseconds: 1600);

  final QrResponse qr;

  /// The card's title (the preview dialog's and the image's).
  final String title;

  /// Opens the enlarged, live code.
  final VoidCallback onPreview;

  /// What the image is (Print sizes it true; Download names it).
  final QrShape shape;

  /// A new render is on its way.
  final bool busy;

  @override
  ConsumerState<QrResultCard> createState() => _QrResultCardState();
}

class _QrResultCardState extends ConsumerState<QrResultCard> {
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
      if (mounted) DashToast.error(context, t('qr.copyFailed'));
      return;
    }
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(QrResultCard.copiedFor, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final qr = widget.qr;

    final code = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: QrResultCard.codeWidth),
      child: DashPressable(
        key: const ValueKey('qr-enlarge'),
        semanticLabel: t('qr.enlarge'),
        excludeChildSemantics: true,
        pressScale: false,
        onTap: widget.onPreview,
        builder: (context, s) => Container(
          foregroundDecoration: dashFocusRing(
            context,
            s,
            BorderRadius.circular(Radii.xs),
          ),
          child: QrBusyVeil(
            busy: widget.busy,
            child: QrImage(
              dataUrl: qr.qrDataUrl,
              semanticLabel: t('qr.imageAlt', args: {'title': widget.title}),
            ),
          ),
        ),
      ),
    );

    final link = DashPressable(
      isButton: false,
      pressScale: false,
      semanticLabel: qr.shortUrl,
      onTap: () => ref.read(linkOpenerProvider)(Uri.parse(qr.shortUrl)),
      builder: (context, s) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.sm,
          vertical: Space.xs + DashMetrics.hair,
        ),
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.sm,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: DashMetrics.hair),
              child: DashIcon(
                'link-2',
                size: IconSize.xs - 4,
                color: c.textMuted,
              ),
            ),
            Expanded(
              child: Text(
                qr.shortUrl,
                textDirection: TextDirection.ltr,
                style: DashType.mono.copyWith(
                  fontSize: DashType.small.fontSize,
                  color: c.textPrimary,
                  decoration: s.highlighted ? TextDecoration.underline : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final landing = Text(
      qr.longUrl,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      style: DashType.mono.copyWith(
        fontSize: MadarType.labelSm.fontSize,
        color: c.textMuted,
      ),
    );

    final copy = DashButton(
      key: const ValueKey('qr-copy'),
      label: _copied ? t('qr.copied') : t('qr.copyLink'),
      semanticLabel: t('common.copy'),
      icon: _copied ? 'check' : 'copy',
      variant: DashButtonVariant.outline,
      size: DashButtonSize.compact,
      expand: true,
      onPressed: _copy,
    );
    final print = DashButton(
      key: const ValueKey('qr-print'),
      label: t('qr.print'),
      icon: 'printer',
      variant: DashButtonVariant.outline,
      size: DashButtonSize.compact,
      expand: true,
      onPressed: () =>
          printQr(context, ref, qr, shape: widget.shape, title: widget.title),
    );
    final download = DashButton(
      key: const ValueKey('qr-download'),
      label: t('common.download'),
      icon: 'download',
      size: DashButtonSize.compact,
      expand: true,
      onPressed: () => downloadQr(
        context,
        ref,
        qr,
        unbranded: widget.shape == QrShape.plain,
      ),
    );

    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        spacing: Space.md,
        children: [
          code,
          link,
          SizedBox(width: double.infinity, child: landing),
          // Copy link on its own row; Print and Download beside each other
          // unless the card is too narrow for both labels.
          SizedBox(width: double.infinity, child: copy),
          LayoutBuilder(
            builder: (context, box) => box.maxWidth < QrResultCard.pairWidth
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: Space.sm,
                    children: [print, download],
                  )
                : Row(
                    spacing: Space.sm,
                    children: [
                      Expanded(child: print),
                      Expanded(child: download),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
