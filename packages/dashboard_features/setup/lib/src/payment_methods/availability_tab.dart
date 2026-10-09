/// The Availability tab (web `availability-tab.tsx`, SET-PAY-022..040): the
/// org's methods → the branch's subset → per teller → per device; a charge
/// offers the intersection. Needs a branch in the header.
///
/// Reads: the methods list, `GET /users?org_id=` (org-wide, filtered here),
/// the branch's availability and its devices. The tellers and devices reads
/// have no loading or error state of their own (SET-PAY-039): until they
/// answer, their sections say there is nobody.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show AllowList, Device, OrgPaymentMethod, PaymentMethodAvailability;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'allow_list_editor.dart';
import 'payment_methods_page.dart' show PmGrid;
import 'pm_data.dart';

/// The skeleton cards' height (`h-28`).
const double _skeletonHeight = Space.xxl * 3 + Space.lg;

class AvailabilityTab extends ConsumerStatefulWidget {
  const AvailabilityTab({super.key});

  @override
  ConsumerState<AvailabilityTab> createState() => _AvailabilityTabState();
}

class _AvailabilityTabState extends ConsumerState<AvailabilityTab> {
  /// Writes in flight (`usePutAvailability().isPending`): every editor's
  /// Save spins while any of them saves.
  int _pending = 0;

  Future<void> _save(PmOwner owner, String id, AllowList data) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).paymentMethods;
    final bus = ref.read(realtimeBusProvider);
    setState(() => _pending++);
    try {
      await switch (owner) {
        PmOwner.branches => api.putBranchAvailability(branchId: id, body: data),
        PmOwner.users => api.putUserAvailability(userId: id, body: data),
        PmOwner.devices => api.putDeviceAvailability(deviceId: id, body: data),
      };
      invalidatePaymentMethods(bus);
      if (mounted) DashToast.success(context, t('common.saved'));
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      if (mounted) setState(() => _pending--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final orgId = ref.watch(orgIdProvider);
    final branchId = ref.watch(currentScopeProvider.select((s) => s.branchId));
    // The web's hooks run before its branch check: the list and the people
    // are read even with "All branches".
    final methodsQ = ref.watch(paymentMethodsProvider);
    final usersQ = orgId == null ? null : ref.watch(pmUsersProvider(orgId));
    if (branchId == null) {
      return DashEmptyState(
        key: const ValueKey('pm-pick-branch'),
        icon: 'store',
        title: t('tills.pickBranch'),
        description: t('paymentMethods.availability.pickBranchHint'),
      );
    }
    final availability = ref.watch(pmAvailabilityProvider(branchId));
    final devicesQ = ref.watch(pmDevicesProvider(branchId));

    if (availability.awaitingFirst || methodsQ.awaitingFirst) {
      return Column(
        key: const ValueKey('pm-availability-loading'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          for (var i = 0; i < 3; i++)
            const DashSkeleton(height: _skeletonHeight, radius: Radii.card),
        ],
      );
    }
    // Never during Riverpod's automatic retries; kept while Retry runs.
    final error = availability.hasError && !availability.retrying
        ? availability.error
        : methodsQ.hasError && !methodsQ.retrying
        ? methodsQ.error
        : null;
    if (error != null) {
      return DashErrorState(
        key: const ValueKey('pm-availability-error'),
        title: t('paymentMethods.availability.loadError'),
        message: errorMessage(error, t),
        retrying: availability.isLoading || methodsQ.isLoading,
        onRetry: () {
          ref.invalidate(pmAvailabilityProvider(branchId));
          ref.invalidate(paymentMethodsProvider);
        },
      );
    }

    final PaymentMethodAvailability? av = availability.value;
    final all = [
      for (final OrgPaymentMethod m
          in methodsQ.value ?? const <OrgPaymentMethod>[])
        if (m.isActive) (id: m.id, name: labelOf(m, lang)),
    ];
    final branchList = allowListFor(av, PmOwner.branches, branchId);
    // Tellers and devices narrow the branch's set, never widen it.
    final branchMethods = branchList.restricted
        ? [
            for (final m in all)
              if (branchList.paymentMethodIds.contains(m.id)) m,
          ]
        : all;
    final tellers = availabilityTellers(usersQ?.value ?? const [], branchId);
    final devices = [
      for (final Device d in devicesQ.value ?? const <Device>[])
        if (d.retiredAt == null) d,
    ];
    final pending = _pending > 0;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg;

    Widget grid(List<Widget> editors) => wide
        ? PmGrid(columns: 2, children: editors)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: editors,
          );

    return Column(
      key: const ValueKey('pm-availability'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xxl,
      children: [
        _Section(
          header: DashSectionHeader(
            icon: 'store',
            title: t('paymentMethods.availability.branch'),
            description: t('paymentMethods.availability.branchHint'),
          ),
          child: AllowListEditor(
            key: const ValueKey('allow-list-branch'),
            title: t('paymentMethods.availability.branch'),
            value: branchList,
            source: av,
            methods: all,
            pending: pending,
            onSave: (v) => _save(PmOwner.branches, branchId, v),
          ),
        ),
        _Section(
          header: DashSectionHeader(
            icon: 'users',
            title: t('paymentMethods.availability.tellers'),
            count: tellers.length,
            description: t('paymentMethods.availability.tellersHint'),
          ),
          child: tellers.isEmpty
              ? DashEmptyState(
                  key: const ValueKey('pm-no-tellers'),
                  icon: 'users',
                  title: t('paymentMethods.availability.noTellers'),
                )
              : grid([
                  for (final u in tellers)
                    AllowListEditor(
                      key: ValueKey('allow-list-user-${u.id}'),
                      title: u.name,
                      value: allowListFor(av, PmOwner.users, u.id),
                      source: av,
                      methods: branchMethods,
                      pending: pending,
                      onSave: (v) => _save(PmOwner.users, u.id, v),
                    ),
                ]),
        ),
        _Section(
          header: DashSectionHeader(
            icon: 'tablet',
            title: t('paymentMethods.availability.devices'),
            count: devices.length,
            description: t('paymentMethods.availability.devicesHint'),
          ),
          child: devices.isEmpty
              ? DashEmptyState(
                  key: const ValueKey('pm-no-devices'),
                  icon: 'tablet',
                  title: t('paymentMethods.availability.noDevices'),
                )
              : grid([
                  for (final d in devices)
                    AllowListEditor(
                      key: ValueKey('allow-list-device-${d.id}'),
                      title: (d.label ?? '').isEmpty
                          ? d.code
                          : '${d.code} · ${d.label}',
                      mono: true,
                      value: allowListFor(av, PmOwner.devices, d.id),
                      source: av,
                      methods: branchMethods,
                      pending: pending,
                      onSave: (v) => _save(PmOwner.devices, d.id, v),
                    ),
                ]),
        ),
      ],
    );
  }
}

/// A section: its header, then its body (`space-y-3`).
class _Section extends StatelessWidget {
  const _Section({required this.header, required this.child});

  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Space.md,
    children: [header, child],
  );
}
