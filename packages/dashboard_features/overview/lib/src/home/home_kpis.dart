/// The KPI strip (web `dashboard-page.tsx` kpis + `LedgerStrip dense`) and
/// the Open tills card under it (`features/tills/open-tills-card.tsx`,
/// `till-badges.tsx`).
library;

import 'package:dashboard_api/dashboard_api.dart' show Till;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'home_data.dart';
import 'home_parts.dart';
import 'home_providers.dart';

/// Revenue, Orders, Avg ticket, Voided — and Tips when there were any.
class HomeKpiStrip extends ConsumerWidget {
  const HomeKpiStrip({required this.data, super.key});

  final HomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final k = data.kpis;
    final loading = data.kpiLoading;
    return DashLedgerStrip(
      dense: true,
      items: [
        DashLedgerItem(
          key: 'revenue',
          label: t('dashboard.revenue'),
          icon: 'coins',
          value: k.revenue,
          format: DashStatFormat.money,
          loading: loading,
        ),
        DashLedgerItem(
          key: 'orders',
          label: t('nav.orders'),
          icon: 'receipt',
          value: k.orders,
          format: DashStatFormat.number,
          loading: loading,
        ),
        DashLedgerItem(
          key: 'avg',
          label: t('dashboard.avgTicket'),
          icon: 'trending-up',
          value: k.avgTicket,
          format: DashStatFormat.money,
          loading: loading,
        ),
        DashLedgerItem(
          key: 'voided',
          label: t('dashboard.voided'),
          icon: 'ban',
          tone: k.voided > 0 ? DashTone.warning : DashTone.neutral,
          value: k.voided,
          format: DashStatFormat.number,
          loading: loading,
        ),
        if (k.tips != 0)
          DashLedgerItem(
            key: 'tips',
            label: t('dashboard.tips'),
            icon: 'hand-coins',
            value: k.tips,
            format: DashStatFormat.money,
            loading: loading,
          ),
      ],
    );
  }
}

/// Who is selling right now at the picked branch; nothing on all branches.
/// A failed read (a refusal included) reads like no open till, as on the
/// web.
class HomeOpenTillsCard extends ConsumerWidget {
  const HomeOpenTillsCard({required this.branchId, super.key});

  final String branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(homeOpenTillsProvider(branchId));
    if (q.firstLoad) return const HomeSkeleton(height: HomeMetrics.tills);
    return HomeOpenTillsList(
      tills: q.hasError ? const [] : (q.value ?? const []),
    );
  }
}

class HomeOpenTillsList extends ConsumerWidget {
  const HomeOpenTillsList({required this.tills, super.key});

  final List<Till> tills;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    return DashCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: Space.sm,
            children: [
              DashIcon('wallet', color: c.textSecondary),
              Flexible(
                child: MadarClippedText(
                  t('dashboard.openTills'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
              ),
              Text(
                fmt.fmtNumber(tills.length),
                style: DashType.body.copyWith(
                  color: c.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              HomeLink(
                label: t('common.viewAll'),
                style: DashType.small,
                color: c.accent,
                onTap: () => context.go('/tills'),
              ),
            ],
          ),
          if (tills.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Text(
                t('dashboard.noOpenTill'),
                style: DashType.body.copyWith(color: c.textSecondary),
              ),
            )
          else
            for (final (i, till) in tills.indexed) ...[
              if (i > 0) Container(height: 1, color: c.hairline),
              _TillRow(till: till),
            ],
        ],
      ),
    );
  }
}

class _TillRow extends ConsumerWidget {
  const _TillRow({required this.till});

  final Till till;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final v = till.verification.value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.sm,
        runSpacing: Space.xs,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: till.tellerName,
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
                if (till.deviceCode != null && till.deviceCode!.isNotEmpty)
                  TextSpan(
                    text: ' ${till.deviceCode}',
                    style: DashType.mono.copyWith(color: c.textSecondary),
                  ),
              ],
            ),
          ),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (v == 'unverified' || v == 'lan')
                DashStatusPill(
                  small: true,
                  tone: v == 'unverified' ? DashTone.warning : DashTone.neutral,
                  icon: v == 'lan' ? 'wifi' : 'shield-question',
                  label: t('tills.verification.$v'),
                ),
              if (till.openedWhileAnotherOpen)
                DashStatusPill(
                  small: true,
                  tone: DashTone.warning,
                  label: t('tills.flagged'),
                ),
              Text(
                fmt.fmtDuration(till.openedAt.toIso8601String()),
                style: DashType.small.copyWith(
                  color: c.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
