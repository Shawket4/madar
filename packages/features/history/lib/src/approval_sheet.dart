import 'package:app_core/app_core.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Ask a manager (PERMISSIONS_ARCHITECTURE §4.2): the shared manager-PIN
/// sheet ([askManagerWith]). Pops the approval, or null when dismissed.
///
/// An act on a sale (void, refund) names [orderId] and is approved over
/// `approveOrderAct`; any other act passes [approve], which asks the core to
/// mint the approval for the typed PIN (e.g. a waste).
Future<ApprovalView?> askManager(
  BuildContext context,
  WidgetRef ref, {
  required String reason,
  required String capKey,
  String? orderId,
  int? amountMinor,
  Future<ApprovalView> Function(MadarBridge bridge, String pin)? approve,
}) {
  assert(orderId != null || approve != null, 'an order or an approver');
  final bridge = ref.read(bridgeProvider);
  return askManagerWith(
    context,
    reason: reason,
    approve: (pin) => approve != null
        ? approve(bridge, pin)
        : bridge.approveOrderAct(
            approverPin: pin,
            capKey: capKey,
            orderId: orderId!,
            amountMinor: amountMinor,
          ),
  );
}
