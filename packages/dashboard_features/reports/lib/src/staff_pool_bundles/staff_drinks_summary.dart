/// What the period's staff drinks came to, in one ruled line of figures above
/// the rows (REP-SPL-012…014, `features/staff-pool/staff-drinks-summary.tsx`).
///
/// Not a second row of stat cards: the cards above are the day's allowance,
/// these are the period's money, and the server sums exactly the rows listed
/// under them.
library;

import 'package:dashboard_api/dashboard_api.dart' show StaffDrinksSummary;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StaffDrinksSummaryStrip extends ConsumerWidget {
  const StaffDrinksSummaryStrip({
    required this.summary,
    this.loading = false,
    this.failed = false,
    this.onRetry,
    super.key,
  });

  final StaffDrinksSummary? summary;
  final bool loading;
  final bool failed;
  final VoidCallback? onRetry;

  /// The loading bar's height (`h-14`).
  static const double loadingHeight = Space.xxl + Space.xl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    if (loading) {
      return const DashSkeleton(
        height: loadingHeight,
        key: Key('staff-summary-loading'),
      );
    }
    final s = summary;
    if (failed || s == null) {
      if (!failed) return const SizedBox.shrink();
      // The rows below still load on their own; losing the totals must not
      // take the list with it, nor read as "the totals are zero".
      return Semantics(
        container: true,
        liveRegion: true,
        child: Wrap(
          spacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              t('staffPool.summaryFailed'),
              style: DashType.body.copyWith(color: c.textSecondary),
            ),
            if (onRetry != null)
              DashButton(
                label: t('common.retry'),
                variant: DashButtonVariant.link,
                size: DashButtonSize.compact,
                onPressed: onRetry,
              ),
          ],
        ),
      );
    }
    // Nothing was rung: the table's own empty state says so once.
    if (s.drinks == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        Semantics(
          key: const Key('staff-summary'),
          container: true,
          label: t('staffPool.summaryLabel'),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(color: c.hairline),
              ),
            ),
            child: Wrap(
              spacing: Space.xxl,
              runSpacing: Space.md,
              children: [
                _Figure(t('staffPool.sumDrinks'), f.fmtNumber(s.quantity)),
                _Figure(t('staffPool.sumComp'), f.fmtMoney(s.compMinor)),
                _Figure(t('staffPool.sumExtras'), f.fmtMoney(s.extrasMinor)),
                _Figure(t('staffPool.sumCost'), f.fmtMoney(s.costMinor)),
                _Figure(
                  t('staffPool.sumOver'),
                  f.fmtNumber(s.overspent),
                  tone: s.overspent > 0 ? DashTone.danger : null,
                ),
                if (s.compMismatches > 0)
                  _Figure(
                    t('staffPool.sumMismatches'),
                    f.fmtNumber(s.compMismatches),
                    tone: DashTone.warning,
                  ),
              ],
            ),
          ),
        ),
        if (s.unpriced > 0)
          Text(
            t('staffPool.sumUnpriced', count: s.unpriced),
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
      ],
    );
  }
}

/// A label over its figure (`<dt>` / `<dd>`).
class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, {this.tone});

  final String label;
  final String value;

  /// Over allowance (danger) and Till differs (warning) tint the figure.
  final DashTone? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: DashType.small.copyWith(color: c.textSecondary)),
        Text(
          dashFigure(value),
          style: DashType.monoStrong.copyWith(
            color: tone?.foreground(c) ?? c.textPrimary,
            fontSize: MadarType.title.fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
