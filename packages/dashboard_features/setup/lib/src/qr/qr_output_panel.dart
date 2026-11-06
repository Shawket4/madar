/// The output switches above the codes, with a live sample beside them
/// (`features/qr/output-panel.tsx`).
///
/// Nothing on the page has been generated when someone first flips
/// Unbranded, so without a sample the switch would appear to do nothing. The
/// sample is the shop's main code (its links page when it has one, else the
/// menu without prices), rendered small (150 DPI is plenty for a thumbnail)
/// and re-rendered on every flip. Pressing it opens the real code at the
/// chosen resolution, with Download, Print and Share.
///
/// "When it has one" is the links page's own `public_url`, not the plan: the
/// links page lives at the shop's own address, which needs custom branding
/// and a slug on top of the paid plan. A paid shop without them is refused
/// that code (409), so it gets the menu's. On a plan with `branding` the
/// sample waits for the links page read (the editor's, one request); on Free
/// that read never runs.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show LinksPageSettings, QrResponse;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../links/links_providers.dart' show linksPageProvider;
import '../shared/qr_preview_dialog.dart';
import 'live_qr_dialog.dart';
import 'qr_output.dart';
import 'qr_output_controls.dart';
import 'qr_providers.dart';

/// Whether the links page has an address its code can open: a non-empty
/// `public_url` on the links page settings ([linksPageProvider]).
bool qrLinksHasAddress(LinksPageSettings? links) =>
    (links?.publicUrl ?? '').isNotEmpty;

/// The shop's main code, the sample's subject: its links page where it has
/// an address ([linksCode]), else the menu without prices.
QrCodeRef qrSampleCode(String orgId, {required bool linksCode}) => (
  kind: linksCode ? QrKind.orgLinks : QrKind.orgMenuDisplay,
  orgId: orgId,
  scopeId: orgId,
  place: null,
);

/// The sample's exact read for [output]: what the panel watches once it
/// knows which code it is, so what the page's prefetch warms (a cache hit on
/// open).
QrLiveKey qrSampleKey(
  String orgId, {
  required bool linksCode,
  required QrOutput output,
}) => (
  code: qrSampleCode(orgId, linksCode: linksCode),
  params: qrAtDpi(qrRenderParams(output), QrOutputPanel.sampleDpi),
);

class QrOutputPanel extends ConsumerStatefulWidget {
  const QrOutputPanel({required this.orgId, super.key});

  /// The thumbnail's resolution only; downloads use the chosen DPI.
  static const int sampleDpi = 150;

  /// The sample column (`9.5rem`) and the image in it (`w-32`, `max-h-44`).
  static const double column = 152;
  static const double sample = 128;
  static const double sampleMaxHeight = 176;

  final String orgId;

  @override
  ConsumerState<QrOutputPanel> createState() => _QrOutputPanelState();
}

class _QrOutputPanelState extends ConsumerState<QrOutputPanel> {
  final _hold = LiveQrHold<QrResponse>();
  bool _opening = false;

  Future<void> _open(QrCodeRef code, String title) async {
    setState(() => _opening = true);
    try {
      await openLiveQr(context, ref, code: code, title: title);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final branding = planHasFeature(
      ref.watch(planFeaturesProvider),
      'branding',
    );
    // The same read the links editor makes; never on Free.
    final links = branding ? ref.watch(linksPageProvider(widget.orgId)) : null;
    final decided = links == null || !links.awaitingFirst;
    final linksCode = qrLinksHasAddress(links?.value);
    final title = linksCode
        ? t('links.editor.qrTitle')
        : t('menuDisplay.editor.qrTitle');
    final o = ref.watch(qrOutputProvider(widget.orgId));
    final key = qrSampleKey(widget.orgId, linksCode: linksCode, output: o);
    final code = key.code;
    // Not asked for until the links page read has settled: the code it is
    // depends on the answer.
    final live = _hold.view(decided ? ref.watch(qrCodeProvider(key)) : null);
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;

    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DashMetrics.hair,
          children: [
            Text(
              t('qr.output.title'),
              style: DashType.bodyStrong.copyWith(color: c.textPrimary),
            ),
            Text(
              t('qr.output.hint'),
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          ],
        ),
        QrOutputControls(orgId: widget.orgId, noLogo: qrMissingLogo(o, live)),
      ],
    );

    final qr = live.data;
    final sample = qr == null
        ? null
        : Column(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs + DashMetrics.hair,
            children: [
              SizedBox(
                width: QrOutputPanel.sample,
                child: DashPressable(
                  key: const ValueKey('qr-sample'),
                  semanticLabel: t('qr.output.openSample'),
                  excludeChildSemantics: true,
                  pressScale: false,
                  onTap: _opening ? null : () => _open(code, title),
                  builder: (context, s) => Container(
                    foregroundDecoration: dashFocusRing(
                      context,
                      s,
                      BorderRadius.circular(Radii.xs),
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.xs),
                      border: Border.all(color: c.hairline),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: QrOutputPanel.sampleMaxHeight,
                      ),
                      child: QrBusyVeil(
                        busy: live.busy || _opening,
                        child: QrImage(
                          dataUrl: qr.qrDataUrl,
                          aspectRatio: qrShape(o) == QrShape.card
                              ? 105 / 148
                              : 1,
                          semanticLabel: t(
                            'qr.imageAlt',
                            args: {'title': title},
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                t('qr.output.preview'),
                textAlign: TextAlign.center,
                style: MadarType.labelSm.copyWith(color: c.textSecondary),
              ),
            ],
          );

    return DashCard(
      key: const ValueKey('qr-output-panel'),
      padding: const EdgeInsets.all(Space.lg),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.xl,
              children: [
                Expanded(child: words),
                if (sample != null)
                  SizedBox(width: QrOutputPanel.column, child: sample),
              ],
            )
          // First on a phone, so the code changes in sight of the switch.
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.xl,
              children: [?sample, words],
            ),
    );
  }
}
