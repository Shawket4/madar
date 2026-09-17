import 'package:app_core/app_core.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Ask a manager to approve an act on one sale (void, refund): the shared
/// manager-PIN sheet over `approveOrderAct`. Pops the approval, or null.
Future<ApprovalView?> askManager(
  BuildContext context,
  WidgetRef ref, {
  required String reason,
  required String capKey,
  required String orderId,
  int? amountMinor,
}) {
  final bridge = ref.read(bridgeProvider);
  return askManagerWith(
    context,
    reason: reason,
    approve: (pin) => bridge.approveOrderAct(
      approverPin: pin,
      capKey: capKey,
      orderId: orderId,
      amountMinor: amountMinor,
    ),
  );
}
