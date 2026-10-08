/// The staff drinks of the period, one row each, newest first (REP-SPL-015…
/// 020, `features/staff-pool/staff-drinks-table.tsx`).
///
/// The note is the reason this table exists: there is no "who is this for"
/// field anywhere in the pool, by design, so the note wraps in full. The
/// money columns read the server's verdict; a drink rung before staff drinks
/// were priced has no figures (a dash and a footnote, never 0), and a till
/// that claimed another comp is marked and says both figures.
library;

import 'package:dashboard_api/dashboard_api.dart' show StaffDrink;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../shared/report_shared.dart';
import 'staff_drink_money.dart';

/// "Latte · Large × 2": the size when sized, the quantity when more than one.
String staffDrinkItemText(StaffDrink d) {
  final size = d.sizeLabel;
  final label = size != null && size.isNotEmpty
      ? '${d.itemName} · $size'
      : d.itemName;
  return d.quantity > 1 ? '$label × ${d.quantity}' : label;
}

class StaffDrinksTable extends ConsumerWidget {
  const StaffDrinksTable({
    required this.drinks,
    this.loading = false,
    this.error,
    this.onRetry,
    this.showDate = false,
    this.onOpenOrder,
    super.key,
  });

  final List<StaffDrink> drinks;
  final bool loading;

  /// A failed load (its words are shown with Retry).
  final Object? error;
  final VoidCallback? onRetry;

  /// More than one business day is on screen, so each row says which.
  final bool showDate;

  /// Opens the sale a drink was rung on; without it no row offers the link.
  final ValueChanged<String>? onOpenOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final unpricedHint = t('staffPool.unpricedHint');
    final anyUnpriced = drinks.any(
      (d) => staffDrinkMoney(d) is StaffDrinkUnpriced,
    );

    String time(StaffDrink d) {
      final at = f.fmtTime(d.recordedAt.toIso8601String());
      // The business day, not the clock date: a drink poured at 1am belongs
      // to the day the branch is still working through.
      return showDate ? '${fmtBusinessDate(f, d.businessDate)} · $at' : at;
    }

    final columns = <DashColumn<StaffDrink>>[
      DashColumn<StaffDrink>(
        id: 'time',
        label: t('staffPool.colTime'),
        numeric: true,
        align: DashAlign.start,
        minWidth: showDate ? 168 : 96,
        text: time,
      ),
      DashColumn<StaffDrink>(
        id: 'item',
        label: t('staffPool.colItem'),
        phone: DashPhoneRole.title,
        flex: 2,
        minWidth: 160,
        text: staffDrinkItemText,
        cell: (context, d) {
          final text = Text(staffDrinkItemText(d));
          final orderId = d.orderId;
          // A record-only drink has no sale behind it: nothing to open.
          if (onOpenOrder == null || orderId == null) return text;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              text,
              _OrderLink(
                label: t('staffPool.viewOrder'),
                onTap: () => onOpenOrder!(orderId),
              ),
            ],
          );
        },
      ),
      DashColumn<StaffDrink>(
        id: 'note',
        label: t('staffPool.colNote'),
        flex: 3,
        minWidth: 224,
        text: (d) => d.note,
        cell: (context, d) {
          final money = staffDrinkMoney(d);
          // `dir="auto"`: the first strong character decides.
          final rtl = intl.Bidi.startsWithRtl(d.note);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs,
            children: [
              Text(
                d.note,
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                style: DashType.body.copyWith(color: c.textPrimary),
              ),
              if (money is StaffDrinkPriced && money.tillSaid != null)
                Text(
                  t(
                    'staffPool.compMismatch',
                    args: {
                      'reported': f.fmtMoney(money.tillSaid),
                      'server': f.fmtMoney(money.comp),
                    },
                  ),
                  key: const Key('comp-mismatch'),
                  style: DashType.small.copyWith(
                    color: DashTone.warning.foreground(c),
                  ),
                ),
            ],
          );
        },
      ),
      DashColumn<StaffDrink>(
        id: 'comp',
        label: t('staffPool.colComp'),
        numeric: true,
        text: (d) => switch (staffDrinkMoney(d)) {
          StaffDrinkPriced(:final comp) => f.fmtMoney(comp),
          StaffDrinkUnpriced() => '—',
        },
        cell: (context, d) => switch (staffDrinkMoney(d)) {
          StaffDrinkUnpriced() => _Unpriced(hint: unpricedHint),
          final StaffDrinkPriced m => Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs,
            children: [
              Text(dashFigure(f.fmtMoney(m.comp))),
              if (m.tillSaid != null)
                DashStatusPill(
                  label: t('staffPool.compMismatchBadge'),
                  tone: DashTone.warning,
                  small: true,
                ),
            ],
          ),
        },
      ),
      DashColumn<StaffDrink>(
        id: 'extras',
        label: t('staffPool.colExtras'),
        numeric: true,
        text: (d) => switch (staffDrinkMoney(d)) {
          StaffDrinkPriced(:final extras) => f.fmtMoney(extras),
          StaffDrinkUnpriced() => '—',
        },
        cell: (context, d) => switch (staffDrinkMoney(d)) {
          StaffDrinkUnpriced() => _Unpriced(hint: unpricedHint),
          final StaffDrinkPriced m => Text(dashFigure(f.fmtMoney(m.extras))),
        },
      ),
      DashColumn<StaffDrink>(
        id: 'cost',
        label: t('staffPool.colCost'),
        numeric: true,
        text: (d) => d.costMinor == null ? '—' : f.fmtMoney(d.costMinor),
      ),
      DashColumn<StaffDrink>(
        id: 'overspent',
        label: t('staffPool.colOver'),
        align: DashAlign.end,
        minWidth: 152,
        searchable: false,
        text: (d) => d.overspent ? t('staffPool.overBadge') : '',
        cell: (context, d) => d.overspent
            ? _OverBadge(replay: d.overspentOnReplay)
            : const SizedBox.shrink(),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        DashDataTable<StaffDrink>(
          columns: columns,
          rows: drinks,
          rowKey: (d) => d.id,
          loading: loading,
          errorMessage: error == null ? null : errorMessage(error, t),
          onRetry: onRetry,
          empty: DashEmptyState(title: t('staffPool.drinksEmpty')),
        ),
        if (anyUnpriced)
          // The dash needs its reason on the page, not only in a tooltip.
          Text(
            t('staffPool.unpricedNote'),
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
      ],
    );
  }
}

/// "—" for a figure an old till never had; its reason on hover and to a
/// screen reader.
class _Unpriced extends StatelessWidget {
  const _Unpriced({required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) => MadarHoldHint(
    message: hint,
    child: Semantics(
      key: const Key('comp-unpriced'),
      label: hint,
      excludeSemantics: true,
      child: const Text('—'),
    ),
  );
}

/// The destructive "Over allowance" badge, with "· on recount" when the
/// server's recount, not the till, made it an overspend.
class _OverBadge extends ConsumerWidget {
  const _OverBadge({required this.replay});

  final bool replay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final fg = DashTone.danger.foreground(c);
    final badge = Container(
      key: const Key('over-badge'),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: DashMetrics.hair,
      ),
      decoration: BoxDecoration(
        color: DashTone.danger.wash(c),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text.rich(
        TextSpan(
          text: t('staffPool.overBadge'),
          children: [
            if (replay)
              TextSpan(
                text: ' ${t('staffPool.overOnReplay')}',
                style: DashType.small.copyWith(
                  color: fg.withValues(alpha: 1 - Opacities.subtle),
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
        style: DashType.smallStrong.copyWith(color: fg),
      ),
    );
    if (!replay) return badge;
    return MadarHoldHint(
      message: t('staffPool.overOnReplayHint'),
      semantics: true,
      child: badge,
    );
  }
}

/// "View order": a quiet link under the item, 44 tall to the finger.
class _OrderLink extends StatelessWidget {
  const _OrderLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: onTap,
      semanticLabel: label,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          child: Text(
            label,
            style: DashType.small.copyWith(
              color: s.hovered || s.focused ? c.textPrimary : c.textSecondary,
              fontWeight: FontWeight.w400,
              decoration: TextDecoration.underline,
              decorationColor: c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
