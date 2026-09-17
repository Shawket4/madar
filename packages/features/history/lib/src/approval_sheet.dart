import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Ask a manager (PERMISSIONS_ARCHITECTURE §4.2, phase 5): a manager types
/// THEIR PIN on this device, over the teller's session. The core finds them,
/// checks they may approve this act for this person, and returns the approval
/// the act then carries. Pops the approval, or null when dismissed.
///
/// An act on a sale names [orderId]; any other act passes [approve], which
/// asks the core to mint the approval for the typed PIN (e.g. a waste).
Future<ApprovalView?> askManager(
  BuildContext context, {
  required String reason,
  required String capKey,
  String? orderId,
  int? amountMinor,
  Future<ApprovalView> Function(MadarBridge bridge, String pin)? approve,
}) {
  assert(orderId != null || approve != null, 'an order or an approver');
  return showMadarSheet<ApprovalView>(
    context,
    size: SheetSize.hug,
    maxWidth: 420,
    builder: (_) => _ApprovalSheet(
      reason: reason,
      capKey: capKey,
      orderId: orderId,
      amountMinor: amountMinor,
      approve: approve,
    ),
  );
}

class _ApprovalSheet extends ConsumerStatefulWidget {
  const _ApprovalSheet({
    required this.reason,
    required this.capKey,
    required this.orderId,
    required this.amountMinor,
    required this.approve,
  });

  final String reason;
  final String capKey;
  final String? orderId;
  final int? amountMinor;
  final Future<ApprovalView> Function(MadarBridge bridge, String pin)? approve;

  @override
  ConsumerState<_ApprovalSheet> createState() => _ApprovalSheetState();
}

class _ApprovalSheetState extends ConsumerState<_ApprovalSheet> {
  final TextEditingController _pin = TextEditingController();
  bool _busy = false;
  UiText? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    if (_busy || _pin.text.trim().length < 4) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bridge = ref.read(bridgeProvider);
      final pin = _pin.text.trim();
      final approve = widget.approve;
      final approval = approve != null
          ? await approve(bridge, pin)
          : await bridge.approveOrderAct(
              approverPin: pin,
              capKey: widget.capKey,
              orderId: widget.orderId!,
              amountMinor: widget.amountMinor,
            );
      if (mounted) await Navigator.of(context).maybePop(approval);
    } on MadarError catch (e) {
      MadarHaptics.warning();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is MadarError_Forbidden
              ? UiText.raw(e.action)
              : UiText.error(e);
          _pin.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Text(
            t('approval.title'),
            style: MadarType.h3.copyWith(color: colors.textPrimary),
          ),
          Text(
            widget.reason,
            style: MadarType.body.copyWith(color: colors.textSecondary),
          ),
          Text(
            t('approval.desc'),
            style: MadarType.bodySm.copyWith(color: colors.textMuted),
          ),
          MadarField(
            controller: _pin,
            placeholder: t('approval.pin'),
            icon: 'lock',
            obscure: true,
            autofocus: true,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _approve(),
          ),
          if (_error != null)
            NoticeBanner(
              text: _error!.of(bridge),
              tone: ChipTone.danger,
              icon: 'exclamationmark.circle',
            ),
          MadarButton(
            label: t('approval.approve'),
            onTap: _approve,
            loading: _busy,
            icon: 'checkmark.circle',
          ),
        ],
      ),
    );
  }
}
