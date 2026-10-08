/// The cards an audit tab lays out (`audit-tab.tsx` `BreakdownCard`,
/// `DiscountEntriesCard`, `HistoryCard`; REP-LEG-019…025, 038).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show DeductionOverrideEvent, DiscountAuditEntry;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show Bidi;

import 'legal_words.dart';

/// One breakdown row as shown: its (worded) label, count and amount.
typedef BreakdownLine = ({String label, int count, int amount});

/// A card with the web's `Card py-0` frame: a 16/600 title with a muted
/// glyph, then its content.
class LegalCard extends StatelessWidget {
  const LegalCard({
    required this.icon,
    required this.title,
    required this.child,
    super.key,
  });

  final String icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              Space.xl,
              Space.lg,
              Space.xl,
              Space.md,
            ),
            child: Semantics(
              header: true,
              child: Row(
                spacing: Space.xs + 2,
                children: [
                  DashIcon(icon, size: IconSize.sm, color: c.textSecondary),
                  Expanded(
                    child: Text(
                      title,
                      style: DashType.sectionTitle.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              Space.lg,
              0,
              Space.lg,
              Space.lg,
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// A list of rows divided by hairlines (`ul.divide-y`).
class _Divided extends StatelessWidget {
  const _Divided({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, w) in children.indexed)
          DecoratedBox(
            decoration: BoxDecoration(
              border: i == 0
                  ? null
                  : Border(top: BorderSide(color: c.hairline)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.sm + 2),
              child: w,
            ),
          ),
      ],
    );
  }
}

/// "Nothing recorded in this period" in a card that has no rows.
class _NothingRecorded extends ConsumerWidget {
  const _NothingRecorded();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Text(
    ref.watch(tProvider)('reports.legal.empty'),
    style: DashType.body.copyWith(color: context.madarColors.textSecondary),
  );
}

/// A breakdown card (REP-LEG-019…021): each row's label on one line (cut
/// with an ellipsis), "{{n}} events", and the amount on the end side —
/// money, points as a plain number, or nothing for attendance.
class BreakdownCard extends ConsumerWidget {
  const BreakdownCard({
    required this.icon,
    required this.title,
    required this.rows,
    required this.amount,
    super.key,
  });

  final String icon;
  final String title;
  final List<BreakdownLine> rows;
  final AuditAmount amount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    return LegalCard(
      icon: icon,
      title: title,
      child: rows.isEmpty
          ? const _NothingRecorded()
          : _Divided(
              children: [
                for (final r in rows)
                  Row(
                    spacing: Space.md,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MadarClippedText(
                              r.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DashType.bodyMedium.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                            Text(
                              eventsCountText(t, f, r.count),
                              style: DashType.small.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (amount != AuditAmount.none)
                        Text(
                          amount == AuditAmount.points
                              ? f.fmtNumber(r.amount)
                              : f.fmtMoney(r.amount),
                          style: DashType.mono.copyWith(color: c.textPrimary),
                        ),
                    ],
                  ),
              ],
            ),
    );
  }
}

/// The text of a muted detail line: the parts that are there, joined by
/// " · ".
String joinDetail(Iterable<String?> parts) =>
    parts.whereType<String>().where((s) => s.isNotEmpty).join(' · ');

/// The Discounts audit's per-sale list (REP-LEG-024): what kind, how much,
/// who applied it, who approved it, and whether the server flagged it.
class DiscountEntriesCard extends ConsumerWidget {
  const DiscountEntriesCard({required this.entries, super.key});

  final List<DiscountAuditEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    return LegalCard(
      icon: 'list-checks',
      title: t('reports.legal.discountSales'),
      child: _Divided(
        children: [
          for (final e in entries)
            Row(
              spacing: Space.md,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    spacing: DashMetrics.hair,
                    children: [
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          MadarClippedText(
                            e.orderRef ??
                                (e.orderId.length > 8
                                    ? e.orderId.substring(0, 8)
                                    : e.orderId),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DashType.bodyMedium.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                          Text(
                            discountKindLabel(t, e.kind),
                            style: DashType.bodyMedium.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                          if (e.presetName != null)
                            Text(
                              e.presetName!,
                              style: DashType.bodyMedium.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                          if (bpsLabel(e.percentBps) case final pct?)
                            Text(
                              f.isArabic ? ltr(pct) : pct,
                              style: DashType.monoMedium.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                          if (e.flagged)
                            DashBadge(
                              t('reports.legal.flagged'),
                              tone: DashTone.danger,
                            ),
                        ],
                      ),
                      Text(
                        joinDetail([
                          e.branchName,
                          f.fmtDateTime(e.createdAt.toIso8601String()),
                          if (e.appliedByName case final n?)
                            t('discounts.appliedBy', args: {'name': n}),
                          if (e.approvedByName case final n?)
                            t('discounts.approvedBy', args: {'name': n}),
                        ]),
                        style: DashType.small.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
                Text(
                  f.fmtMoney(e.amountMinor),
                  style: DashType.mono.copyWith(color: c.textPrimary),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The web's `Badge variant="outline"`: a hairline pill in the text colour.
class LegalOutlineBadge extends StatelessWidget {
  const LegalOutlineBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: DashMetrics.hair,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: c.border),
      ),
      child: Text(
        label,
        style: DashType.smallMedium.copyWith(color: c.textPrimary),
      ),
    );
  }
}

/// "EGP 50.00 → EGP 0.00" when the server sends both figures (the arrow
/// follows the reading direction: divergence REP-LEG-025).
String? amountChangeText(DashFormat f, DeductionOverrideEvent e) {
  final before = e.amountBeforePiastres;
  final after = e.amountAfterPiastres;
  if (before == null || after == null) return null;
  final arrow = f.isArabic ? '←' : '→';
  return '${f.fmtMoney(before)} $arrow ${f.fmtMoney(after)}';
}

/// Every waive, undo and override, newest first, with who, when and why
/// (REP-LEG-025).
class HistoryCard extends ConsumerWidget {
  const HistoryCard({required this.events, super.key});

  final List<DeductionOverrideEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return LegalCard(
      icon: 'history',
      title: t('reports.legal.history'),
      child: _Divided(
        children: [
          for (final e in events)
            LayoutBuilder(
              builder: (context, box) {
                final change = amountChangeText(f, e);
                final reason = e.reason;
                final left = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: DashMetrics.hair,
                  children: [
                    Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          e.employeeName ?? '—',
                          style: DashType.bodyMedium.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                        LegalOutlineBadge(historyActionText(t, e.action)),
                      ],
                    ),
                    Text(
                      joinDetail([
                        f.fmtDateTime(e.at.toIso8601String()),
                        if (e.actorName case final n?)
                          t('reports.legal.historyByName', args: {'name': n}),
                        if (e.effectiveDate case final d?)
                          t(
                            'reports.legal.historyLineOf',
                            args: {'date': f.fmtDate(d)},
                          ),
                      ]),
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                    if (reason != null && reason.isNotEmpty)
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          reason,
                          // `<bdi>`: the reason keeps its own direction and
                          // sits at the page's start edge.
                          textDirection: Bidi.detectRtlDirectionality(reason)
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          textAlign: rtl ? TextAlign.right : TextAlign.left,
                          style: DashType.small.copyWith(color: c.textPrimary),
                        ),
                      ),
                  ],
                );
                final amount = change == null
                    ? null
                    : Text(
                        change,
                        style: DashType.mono.copyWith(
                          fontSize: 12,
                          color: c.textPrimary,
                        ),
                      );
                if (amount == null) return left;
                // flex-wrap: the figures sit on the end side when there is
                // room, under the event otherwise.
                if (box.maxWidth >= 560) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.md,
                    children: [
                      Expanded(child: left),
                      amount,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.xs,
                  children: [left, amount],
                );
              },
            ),
        ],
      ),
    );
  }
}
