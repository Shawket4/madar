/// Drawers — every shift at the branch, on a manager's Till. Read-only: who
/// is on a drawer, since when, what it declared at close. Tapping a row
/// opens that drawer's report in the shared preview sheet.
///
/// What is NOT here, on purpose: Force-close. The wire has
/// `force_close_shift`, the bridge does not, and a button that cannot work
/// is worse than no button — so the card says so in one line instead.
/// The till's NAME is not on `ShiftSummaryView` either, so a row is led by
/// the teller, not the drawer.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_shift/src/shift_providers.dart';
import 'package:feature_shift/src/shift_report_sheet.dart';
import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Row report-fetch spinner (the history rows' 14 / 2).
const double _rowSpinnerSize = 14;
const double _rowSpinnerStroke = 2;

/// How many drawers the card lists before pointing at Past shifts.
const int _maxDrawerRows = 8;

/// Every drawer at the branch, open ones first. Pass [onSeeAll] to route the
/// overflow at Past shifts.
class DrawersCard extends ConsumerWidget {
  /// Creates the card.
  const DrawersCard({super.key, this.onSeeAll});

  /// Opens Past shifts when the list is longer than the card shows.
  final VoidCallback? onSeeAll;

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    ShiftSummaryView shift,
  ) async {
    MadarHaptics.selection();
    final report = await ref
        .read(tillProvider.notifier)
        .fetchDrawerReport(shift.id);
    if (report == null || !context.mounted) return;
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (_) => ShiftReportSheet(report: report, shiftId: shift.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    String t(String key) => bridge.tr(key: key);
    final currency = bridge.currentSession()?.currencyCode ?? '';
    final drawers = ref.watch(tillProvider.select((s) => s.drawers));
    final loading = ref.watch(tillProvider.select((s) => s.loading));
    final loadingId = ref.watch(
      tillProvider.select((s) => s.drawerReportLoadingId),
    );
    final branch = bridge.deviceConfig().branchName?.trim() ?? '';
    final shown = drawers.length > _maxDrawerRows
        ? drawers.sublist(0, _maxDrawerRows)
        : drawers;
    return MadarCard.column(
      flush: true,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.card,
            vertical: Space.lg,
          ),
          child: MadarSectionHeader(
            text: branch.isEmpty
                ? t('till.drawers')
                : '${t('till.drawers')} · $branch',
            trailing: Text(
              '${drawers.where((d) => d.isOpen).length} ${t('shifts.open_now')}',
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            ),
          ),
        ),
        if (loading && drawers.isEmpty)
          const Padding(
            padding: EdgeInsetsDirectional.all(Space.lg),
            child: SkeletonList(count: 3),
          )
        else if (drawers.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: Space.card,
              end: Space.card,
              bottom: Space.lg,
            ),
            child: Text(
              t('shifts.empty'),
              style: MadarType.bodySm.copyWith(color: colors.textMuted),
            ),
          )
        else
          for (final d in shown) ...[
            const MadarHairline.row(),
            _DrawerRow(
              shift: d,
              currency: currency,
              bridge: bridge,
              loading: loadingId == d.id,
              onTap: () => unawaited(_open(context, ref, d)),
            ),
          ],
        if (drawers.length > shown.length && onSeeAll != null) ...[
          const MadarHairline.row(),
          MadarRow(
            title: t('shifts.title'),
            glyph: MadarGlyph.clock,
            value: Text('${drawers.length - shown.length}'),
            onTap: onSeeAll,
          ),
        ],
        const MadarHairline.row(),
        // Honest about the one thing the design asks for that the bridge
        // cannot do yet.
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.card,
            vertical: Space.md,
          ),
          child: Text(
            t('till.force_close_unavailable'),
            style: MadarType.bodySm.copyWith(color: colors.textMuted),
          ),
        ),
      ],
    );
  }
}

/// One drawer: the state bar carries open / closed / force-closed, the
/// teller leads, the opened time follows, the declared close (when there is
/// one) sits at the end under a state tag.
class _DrawerRow extends StatelessWidget {
  const _DrawerRow({
    required this.shift,
    required this.currency,
    required this.bridge,
    required this.loading,
    required this.onTap,
  });

  final ShiftSummaryView shift;
  final String currency;
  final MadarBridge bridge;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final s = shift;
    String t(String key) => bridge.tr(key: key);
    final (MadarTone tone, String label) = switch (s.status) {
      'open' => (MadarTone.success, t('shifts.open_now')),
      'force_closed' => (MadarTone.danger, t('shifts.force_closed')),
      _ => (MadarTone.neutral, t('shifts.closed')),
    };
    final opened = bridge.formatTime(
      rfc3339: s.openedAt,
      style: s.isOpen ? TimeStyle.time : TimeStyle.dateTime,
    );
    final declared = s.closingDeclaredMinor;
    return MadarRow(
      title: s.tellerName ?? '—',
      subtitle: '${t('shift.opened_at')} $opened',
      bar: tone.color(colors),
      value: declared == null
          ? null
          : MoneyText(declared, currency: currency, color: colors.textPrimary),
      trailing: loading
          ? SizedBox.square(
              dimension: _rowSpinnerSize,
              child: CircularProgressIndicator(
                color: colors.accent,
                strokeWidth: _rowSpinnerStroke,
              ),
            )
          : MadarTag(label: label, tone: tone),
      onTap: onTap,
    );
  }
}
