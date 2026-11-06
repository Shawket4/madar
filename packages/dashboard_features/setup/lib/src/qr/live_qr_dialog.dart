/// "QR code" buttons and enlarged codes that open a LIVE code
/// (`features/qr/qr-dialog.tsx`): the enlarged code with the output switches
/// under it. Flipping a switch there re-renders the code in place (the old
/// image held, dimmed, until the new one lands), and the same code on the
/// page with it, since both read the same key.
library;

import 'package:dashboard_api/dashboard_api.dart' show QrResponse;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/qr_preview_dialog.dart';
import 'qr_output.dart';
import 'qr_output_controls.dart';
import 'qr_providers.dart';

/// What a live preview watches for the output's current render query.
typedef QrLiveWatch =
    AsyncValue<QrResponse> Function(WidgetRef ref, QrRenderParams params);

/// [code]'s live read.
QrLiveWatch qrLiveWatch(QrCodeRef code) =>
    (ref, params) => ref.watch(qrCodeProvider((code: code, params: params)));

/// [code]'s read at the shop's current output: what a press reads, so what
/// resting on the button warms.
FutureProvider<QrResponse> qrCodeRead(WidgetRef ref, QrCodeRef code) =>
    qrCodeProvider((
      code: code,
      params: qrRenderParams(ref.read(qrOutputProvider(code.orgId))),
    ));

/// Opens the live preview titled [title] over [watch].
Future<void> showLiveQrPreview(
  BuildContext context, {
  required String orgId,
  required String title,
  required QrLiveWatch watch,
}) => showDashDialog<void>(
  context,
  width: QrPreviewDialog.width,
  builder: (_) => LiveQrPreview(orgId: orgId, title: title, watch: watch),
);

/// The web's `useQrDialog().show`: [code] is fetched at the current output
/// first (the caller's button spins meanwhile), then the live preview opens
/// on it. A failure says why in a toast: there is no code to show it beside.
Future<void> openLiveQr(
  BuildContext context,
  WidgetRef ref, {
  required QrCodeRef code,
  required String title,
}) async {
  final t = ref.read(tProvider);
  final container = ProviderScope.containerOf(context, listen: false);
  final params = qrRenderParams(container.read(qrOutputProvider(code.orgId)));
  final read = qrCodeProvider((code: code, params: params));
  try {
    await container.read(read.future);
  } on Object catch (e) {
    // Not kept: the next press asks again.
    container.invalidate(read);
    if (context.mounted) DashToast.error(context, errorMessage(e, t));
    return;
  }
  if (!context.mounted) return;
  await showLiveQrPreview(
    context,
    orgId: code.orgId,
    title: title,
    watch: qrLiveWatch(code),
  );
}

class LiveQrPreview extends ConsumerStatefulWidget {
  const LiveQrPreview({
    required this.orgId,
    required this.title,
    required this.watch,
    super.key,
  });

  final String orgId;
  final String title;
  final QrLiveWatch watch;

  @override
  ConsumerState<LiveQrPreview> createState() => _LiveQrPreviewState();
}

class _LiveQrPreviewState extends ConsumerState<LiveQrPreview> {
  final _hold = LiveQrHold<QrResponse>();
  bool _closing = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final o = ref.watch(qrOutputProvider(widget.orgId));
    final live = _hold.view(widget.watch(ref, qrRenderParams(o)));
    final qr = live.data;
    if (qr == null) {
      // A switch flipped here and the new render failed: say why, close.
      final error = live.error;
      if (error != null && !_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          DashToast.error(context, errorMessage(error, t));
          Navigator.of(context).maybePop();
        });
      }
      return DashSurface(
        title: widget.title,
        body: const Center(
          child: DashSkeleton(width: 224, height: 224, radius: Radii.card),
        ),
      );
    }
    return QrPreviewDialog(
      qr: qr,
      title: widget.title,
      busy: live.busy,
      shape: qrShape(o),
      controls: QrOutputControls(
        orgId: widget.orgId,
        noLogo: qrMissingLogo(o, live),
      ),
    );
  }
}
