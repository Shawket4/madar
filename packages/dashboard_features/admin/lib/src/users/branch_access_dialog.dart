/// Branch Access (ADM-USR-033..036, 052, 055; web
/// `features/users/branch-assign-dialog.tsx`): one switch per branch of the
/// person's org; on assigns, off unassigns. No success toast; a failure
/// toasts and the switch stays as the server has it.
library;

import 'package:dashboard_api/dashboard_api.dart' show AssignBranchRequest, Branch, UserPublic;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../branches/branches_data.dart' show adminBranchesProvider;
import '../orgs/org_errors.dart' show orgErrorWords;
import 'users_data.dart';

/// Opens Branch Access for [user]; resolves when it closes.
Future<void> showBranchAccessDialog(
  BuildContext context, {
  required UserPublic user,
}) => showDashDialog<void>(
  context,
  builder: (_) => BranchAccessDialog(user: user),
);

class BranchAccessDialog extends ConsumerStatefulWidget {
  const BranchAccessDialog({required this.user, super.key});

  final UserPublic user;

  @override
  ConsumerState<BranchAccessDialog> createState() => _BranchAccessState();
}

class _BranchAccessState extends ConsumerState<BranchAccessDialog> {
  /// The branches whose call is in flight.
  final Set<String> _busy = {};

  /// Kept for after a call: the dialog may have closed while it ran.
  late final _bus = ref.read(realtimeBusProvider);

  @override
  void initState() {
    super.initState();
    _bus;
  }

  Future<void> _toggle(String branchId, bool assigned) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).users;
    final id = widget.user.id;
    setState(() => _busy.add(branchId));
    try {
      if (assigned) {
        await api.unassignBranch(id: id, branchId: branchId);
      } else {
        await api.assignBranch(
          id: id,
          body: AssignBranchRequest(branchId: branchId),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        DashToast.error(context, orgErrorWords(e, t));
        setState(() => _busy.remove(branchId));
      }
      return;
    }
    // `assignedQ.refetch()` + `invalidateUsers()`: one prefix covers both. A
    // failed refetch never fails the change that was saved.
    _bus.invalidate(const ['/users']);
    if (!mounted) return;
    try {
      await ref.read(userBranchesProvider(id).future);
    } on Object {
      // The switches keep the last answer.
    }
    if (mounted) setState(() => _busy.remove(branchId));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final orgId = widget.user.orgId ?? '';
    final branchesQ = orgId.isEmpty
        ? null
        : ref.watch(adminBranchesProvider(orgId));
    final assignedQ = ref.watch(userBranchesProvider(widget.user.id));
    final branches = branchesQ?.value ?? const <Branch>[];
    final assigned = {for (final a in assignedQ.value ?? const []) a.branchId};
    bool first(AsyncValue<Object?>? q) =>
        q != null && q.isLoading && !q.hasValue && !q.hasError;
    final loading = first(branchesQ) || first(assignedQ);

    final Widget body;
    if (loading) {
      body = const Column(
        spacing: Space.sm,
        children: [
          DashSkeleton(height: DashMetrics.listRow),
          DashSkeleton(height: DashMetrics.listRow),
        ],
      );
    } else if (branches.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        child: Text(
          t('common.noResults'),
          textAlign: TextAlign.center,
          style: DashType.small.copyWith(color: c.textSecondary),
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          for (final b in branches)
            _BranchRow(
              branch: b,
              assigned: assigned.contains(b.id),
              busy: _busy.contains(b.id),
              onToggle: () => _toggle(b.id, assigned.contains(b.id)),
            ),
        ],
      );
    }

    return DashSurface(
      title: t('users.branchAccess'),
      description: t(
        'users.branchAccessHint',
        args: {'name': widget.user.name},
      ),
      body: body,
      actions: [
        DashButton(
          key: const ValueKey('branch-access-done'),
          label: t('common.done'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _BranchRow extends StatelessWidget {
  const _BranchRow({
    required this.branch,
    required this.assigned,
    required this.busy,
    required this.onToggle,
  });

  final Branch branch;
  final bool assigned;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final address = branch.address;
    return Container(
      constraints: const BoxConstraints(minHeight: DashMetrics.listRow),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        spacing: Space.md,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MadarClippedText(
                  branch.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
                if (address != null && address.isNotEmpty)
                  MadarClippedText(
                    address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
              ],
            ),
          ),
          DashSwitch(
            key: ValueKey('branch-access-${branch.id}'),
            value: assigned,
            semanticLabel: branch.name,
            // One call at a time per branch (see the divergence log).
            onChanged: busy ? null : (_) => onToggle(),
          ),
        ],
      ),
    );
  }
}
