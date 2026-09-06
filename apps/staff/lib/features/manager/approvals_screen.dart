import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_staff/rust_bridge_staff.dart';

import '../../app/providers.dart';
import '../../ui/kit.dart';
import '../home/home_screen.dart' show requestKindIcon, requestWindow;

/// The queue. Approve or reject, inline, without opening anything.
///
/// Approving is not a formality — it removes the day's penalty AT ITS SOURCE,
/// so the deduction is never charged rather than charged and refunded. For a
/// permission or an early departure it also decides whether the excused time is
/// PAID, which is why those two ask before they commit.
class ApprovalsScreen extends ConsumerStatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  ConsumerState<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

/// `null` = every kind.
enum _Filter { all, leave, corrections }

class _ApprovalsScreenState extends ConsumerState<ApprovalsScreen> {
  _Filter _filter = _Filter.all;
  final _deciding = <String>{};

  bool _matches(StaffRequestView r) => switch (_filter) {
    _Filter.all => true,
    _Filter.leave => r.kind == 'leave' || r.kind == 'mission',
    _Filter.corrections => r.kind == 'correction',
  };

  Future<void> _decide(
    StaffRequestView request, {
    required bool approve,
  }) async {
    final t = ref.read(tProvider);
    final core = ref.read(coreProvider);
    final messenger = ScaffoldMessenger.of(context);

    // The pay question only exists for the two kinds that excuse part of a
    // paid day. Asking it for leave would be meaningless — the leave type
    // already carries whether it is paid.
    bool? isPaid;
    if (approve &&
        (request.kind == 'excuse' || request.kind == 'early_departure')) {
      isPaid = await _askPaid(context, t);
      if (isPaid == null) return;
    }

    setState(() => _deciding.add(request.id));
    try {
      await core.bridge.managerDecideRequest(
        requestId: request.id,
        approve: approve,
        isPaid: isPaid,
      );
      ref
        ..invalidate(pendingRequestsProvider)
        ..invalidate(teamPresenceProvider(null));
      messenger.showSnackBar(
        SnackBar(content: Text(t(approve ? 'ap.approved' : 'ap.rejected'))),
      );
    } on MadarError catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(core.bridge.humanMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _deciding.remove(request.id));
    }
  }

  Future<bool?> _askPaid(BuildContext context, Translate t) {
    return showMadarSheet<bool>(
      context,
      builder: (sheetContext) {
        final colors = sheetContext.madarColors;
        return Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('ap.paidQuestion'),
                style: MadarType.h3.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: Space.lg),
              PrimaryButton(
                label: t('ap.paid'),
                onPressed: () => Navigator.of(sheetContext).pop(true),
              ),
              const SizedBox(height: Space.sm),
              SecondaryButton(
                label: t('ap.unpaid'),
                onPressed: () => Navigator.of(sheetContext).pop(false),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final queue = ref.watch(pendingRequestsProvider);

    return StaffPage(
      title: t('ap.title'),
      onRefresh: () async => ref.invalidate(pendingRequestsProvider),
      children: [
        Segmented<_Filter>(
          value: _filter,
          onChanged: (v) => setState(() => _filter = v),
          segments: [
            (value: _Filter.all, label: t('team.all')),
            (value: _Filter.leave, label: t('ap.filterLeave')),
            (value: _Filter.corrections, label: t('ap.filterFixes')),
          ],
        ),
        const SizedBox(height: Space.md),
        queue.when(
          loading: () => const SkeletonList(count: 4),
          error: (e, _) => ErrorState(
            message: '$e',
            retryLabel: t('common.retry'),
            onRetry: () => ref.invalidate(pendingRequestsProvider),
          ),
          data: (rows) {
            final visible = rows.where(_matches).toList();
            if (visible.isEmpty) {
              return EmptyState(
                icon: 'checkmark.circle',
                title: t('ap.empty'),
                message: t('ap.emptyHint'),
              );
            }
            return Column(
              children: [
                for (final r in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: _ApprovalCard(
                      request: r,
                      busy: _deciding.contains(r.id),
                      onApprove: () => _decide(r, approve: true),
                      onReject: () => _decide(r, approve: false),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ApprovalCard extends ConsumerWidget {
  const _ApprovalCard({
    required this.request,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final StaffRequestView request;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    // A correction proposes an EDIT rather than an excuse, so it is tinted
    // warning to read differently from a leave request at a glance.
    final isFix = request.kind == 'correction';

    return MadarCard(
      padding: const EdgeInsets.fromLTRB(
        Space.md,
        Space.sm + 2,
        Space.md,
        Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(
                icon: requestKindIcon(request.kind),
                background: isFix ? colors.warningBg : colors.accentBg,
                tint: isFix ? colors.warning : colors.accent,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      request.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.body.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      t('kind.${request.kind}'),
                      style: MadarType.labelSm.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Num(requestWindow(request), color: colors.textSecondary),
            ],
          ),
          if (request.reason.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Text(
              request.reason,
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: t('ap.approve'),
                  icon: 'checkmark',
                  height: 38,
                  busy: busy,
                  onPressed: busy ? null : onApprove,
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: SecondaryButton(
                  label: t('ap.reject'),
                  icon: 'xmark',
                  height: 38,
                  tone: colors.danger,
                  onPressed: busy ? null : onReject,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
