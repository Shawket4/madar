/// "When someone isn't allowed" (ADM-ROL-019..022; web
/// `features/access/ask-manager-card.tsx`): per approval capability, for the
/// whole business, hide the act or let the person ask a manager to approve
/// it with their PIN.
library;

import 'package:dashboard_api/dashboard_api.dart' show PolicyEntry;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../orgs/org_errors.dart' show orgErrorWords;
import '../shared/capability_catalog.dart' show approvalCapabilities;
import 'roles_data.dart';

class AskManagerCard extends ConsumerStatefulWidget {
  const AskManagerCard({super.key});

  @override
  ConsumerState<AskManagerCard> createState() => _AskManagerCardState();
}

class _AskManagerCardState extends ConsumerState<AskManagerCard> {
  /// The capability whose change is in flight.
  String? _busy;

  Future<void> _change(String capability, bool ask) async {
    if (_busy == capability) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    setState(() => _busy = capability);
    try {
      await api.authz.setPolicy(
        body: PolicyEntry(capability: capability, askManager: ask),
      );
    } on Object catch (e) {
      if (mounted) {
        DashToast.error(context, orgErrorWords(e, t));
        setState(() => _busy = null);
      }
      return;
    }
    bus.invalidate(policyKey);
    // `await invalidateQueries(...)`: the row stays busy until the new
    // answer is in; a failed refetch keeps the last one and toasts nothing.
    if (mounted) {
      try {
        await ref.read(rolesPolicyProvider.future);
      } on Object {
        // The card shows its own state.
      }
    }
    if (mounted) setState(() => _busy = null);
  }

  @override
  Widget build(BuildContext context) {
    final caps = approvalCapabilities();
    if (caps.isEmpty) return const SizedBox.shrink();
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    final q = ref.watch(rolesPolicyProvider);
    final asks = {
      for (final p in q.value ?? const <PolicyEntry>[])
        if (p.askManager) p.capability,
    };

    final Widget body;
    if (q.isLoading && !q.hasValue && !q.hasError) {
      body = Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          spacing: Space.sm,
          children: [
            for (final _ in caps)
              const DashSkeleton(height: DashMetrics.control),
          ],
        ),
      );
    } else if (!q.hasValue) {
      // The web shows every row "Hidden" (see the divergence log).
      body = DashErrorState(
        framed: false,
        message: orgErrorWords(q.error, t),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(rolesPolicyProvider),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, cap) in caps.indexed) ...[
            if (i > 0) const MadarHairline(light: true),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.sm,
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Space.md,
                runSpacing: Space.sm,
                children: [
                  Text(
                    cap.label(lang),
                    style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                  ),
                  DashSegmentedControl<bool>(
                    key: ValueKey('policy-${cap.key}'),
                    semanticLabel: cap.label(lang),
                    value: asks.contains(cap.key),
                    // Disabled while the row saves (the web ignores the
                    // taps; see the divergence log).
                    enabled: _busy != cap.key,
                    options: [
                      DashOption(value: false, label: t('access.hidden')),
                      DashOption(value: true, label: t('access.askManager')),
                    ],
                    onChanged: (v) => _change(cap.key, v),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.lg,
              vertical: Space.md,
            ),
            decoration: BoxDecoration(
              color: c.muted,
              border: Border(bottom: BorderSide(color: c.hairline)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    t('access.askTitle'),
                    style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                  ),
                ),
                Text(
                  t('access.askHint'),
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          body,
        ],
      ),
    );
  }
}
