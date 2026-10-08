/// Take someone out of the loyalty programme (the web's
/// `features/loyalty/admin/members/leave-programme-dialog.tsx`,
/// SELL-CUS-047): the card stops, the customer stays, rejoining restores the
/// balance. The alert cannot be dismissed while the request is out.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'customers_data.dart';

/// Asks, then removes [member]; resolves true once they have left.
Future<bool> showLeaveProgrammeDialog(
  BuildContext context, {
  required MemberView member,
}) async {
  final left = await showDashDialog<bool>(
    context,
    phoneFullScreen: false,
    barrierDismissible: false,
    builder: (context) => LeaveProgrammeDialog(member: member),
  );
  return left ?? false;
}

class LeaveProgrammeDialog extends ConsumerStatefulWidget {
  const LeaveProgrammeDialog({required this.member, super.key});

  final MemberView member;

  @override
  ConsumerState<LeaveProgrammeDialog> createState() =>
      _LeaveProgrammeDialogState();
}

class _LeaveProgrammeDialogState extends ConsumerState<LeaveProgrammeDialog> {
  bool _pending = false;

  Future<void> _confirm() async {
    final t = ref.read(tProvider);
    setState(() => _pending = true);
    try {
      await ref
          .read(apiProvider)
          .loyalty
          .deleteLoyaltyMember(id: widget.member.id);
      if (!mounted) return;
      DashToast.success(context, t('loyalty.leave.done'));
      // The customer is still there, no longer a member: every list of
      // people is stale.
      invalidatePeople(ref);
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      DashToast.error(context, loyaltyServerError(e, t).message);
      setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    Widget line(String key) =>
        Text(t(key), style: DashType.body.copyWith(color: c.textSecondary));
    return PopScope(
      canPop: !_pending,
      child: DashSurface(
        title: t('loyalty.leave.title', args: {'name': widget.member.name}),
        showClose: false,
        actions: [
          DashButton(
            label: t('common.cancel'),
            variant: DashButtonVariant.outline,
            onPressed: _pending ? null : () => Navigator.of(context).pop(false),
          ),
          DashButton(
            label: t('loyalty.leave.confirm'),
            loading: _pending,
            onPressed: _confirm,
          ),
        ],
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm,
          children: [
            line('loyalty.leave.stops'),
            line('loyalty.leave.stays'),
            line('loyalty.leave.rejoin'),
          ],
        ),
      ),
    );
  }
}
