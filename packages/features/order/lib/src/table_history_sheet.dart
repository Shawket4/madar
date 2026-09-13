/// What a table has done, and what it earns.
///
/// Reached from a table's own sheet on the floor. The figures answer the one
/// question a room full of tables could never answer before: which of these
/// actually earns. The link was always in the data — a settled bill carries
/// its open ticket, and the ticket carries its table — and nothing read it.
///
/// ONLINE ONLY, deliberately. Every other floor read in this app is cached so
/// a till can keep selling with the network down; this one is a manager's
/// question between services, and a stale copy would answer a question about
/// money with last week's numbers. An honest "not now" is worth more.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/floor_list.dart'
    show DurationUnits, formatSeatedFor;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Opens the sheet for [tableId].
Future<void> showTableHistory(
  BuildContext context, {
  required String tableId,
  required String label,
}) => showMadarSheet<void>(
  context,
  size: SheetSize.large,
  builder: (_) => TableHistorySheet(tableId: tableId, label: label),
);

/// See [showTableHistory].
class TableHistorySheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const TableHistorySheet({
    required this.tableId,
    required this.label,
    super.key,
  });

  /// The table being asked about.
  final String tableId;

  /// Its label, so the header reads before the figures land.
  final String label;

  @override
  ConsumerState<TableHistorySheet> createState() => _TableHistorySheetState();
}

class _TableHistorySheetState extends ConsumerState<TableHistorySheet> {
  TableHistoryView? _history;
  bool _loading = true;

  /// The i18n key that says why the history is not here, or null.
  String? _failedKey;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final h = await ref
          .read(bridgeProvider)
          .tableHistory(tableId: widget.tableId);
      if (mounted) setState(() => (_history = h, _loading = false));
    } on MadarError catch (e) {
      // Say WHICH no. Every failure used to read "needs a connection", which
      // sent a manager to check the wifi over a permissions problem.
      final key = switch (e) {
        MadarError_Offline() ||
        MadarError_Transient() => 'tables.history_offline',
        MadarError_Forbidden() => 'tables.history_forbidden',
        MadarError_Server(status: 404) => 'tables.history_missing',
        MadarError_Internal() => 'tables.history_unreadable',
        _ => 'err.generic',
      };
      if (mounted) setState(() => (_failedKey = key, _loading = false));
    } on Object {
      if (mounted) {
        setState(() => (_failedKey = 'err.generic', _loading = false));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    final h = _history;

    final body = switch ((_loading, _failedKey, h)) {
      (true, _, _) => const SkeletonList(count: 4),
      (_, final String key, _) => EmptyState(
        icon: switch (key) {
          'tables.history_offline' => 'wifi.slash',
          'tables.history_forbidden' => 'lock',
          'tables.history_missing' => 'questionmark.circle',
          _ => 'xmark.circle',
        },
        title: t(key),
        actionLabel: key == 'tables.history_offline'
            ? t('history.retry')
            : null,
        onAction: key == 'tables.history_offline'
            ? () {
                setState(() => (_failedKey = null, _loading = true));
                unawaited(_load());
              }
            : null,
      ),
      (_, _, final TableHistoryView v) when v.sittings.isEmpty => EmptyState(
        icon: 'clock',
        title: t('tables.history_empty'),
        message: t('tables.history_empty_hint'),
      ),
      (_, _, final TableHistoryView v) => _Body(
        bridge: bridge,
        history: v,
        currency: currency,
        tr: t,
      ),
      _ => const SizedBox.shrink(),
    };

    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MadarHeader(
            title: '${t('tables.history')} · ${widget.label}',
            subtitle: t('tables.history_hint'),
            actions: [
              MadarGlyphTile(
                glyph: MadarGlyph.close,
                semanticLabel: t('common.cancel'),
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.history,
    required this.currency,
    required this.tr,
    required this.bridge,
  });

  final MadarBridge bridge;
  final TableHistoryView history;
  final String currency;
  final String Function(String) tr;

  @override
  Widget build(BuildContext context) {
    final h = history;
    return ListView(
      padding: const EdgeInsetsDirectional.symmetric(vertical: Space.md),
      children: [
        // The figures first: a manager opens this to compare tables, not to
        // read a ledger.
        _Figures(history: h, currency: currency, tr: tr),
        const SizedBox(height: Space.xl),
        MadarSectionHeader(
          text: tr('tables.sittings'),
          trailing: Text(
            '${h.sittings.length}',
            style: MadarType.numMd.copyWith(
              color: context.madarColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: Space.sm),
        for (final s in h.sittings)
          _SittingRow(
            sitting: s,
            currency: currency,
            tr: tr,
            when: (iso) =>
                bridge.formatTime(rfc3339: iso, style: TimeStyle.dateTime),
            clock: (iso) =>
                bridge.formatTime(rfc3339: iso, style: TimeStyle.time),
          ),
      ],
    );
  }
}

/// Covers, takings, average bill, average stay, turns a day.
class _Figures extends StatelessWidget {
  const _Figures({
    required this.history,
    required this.currency,
    required this.tr,
  });

  final TableHistoryView history;
  final String currency;
  final String Function(String) tr;

  @override
  Widget build(BuildContext context) {
    final h = history;
    // Turns ride the wire ×100 so it stays integer money-style; one decimal
    // is all a turn rate is ever read to.
    final turns = (h.turnsPerDayX100 / 100).toStringAsFixed(1);
    return Wrap(
      spacing: Space.md,
      runSpacing: Space.md,
      children: [
        _Figure(
          label: tr('tables.takings'),
          value: Money.format(h.totalMinor, currency: currency),
        ),
        _Figure(
          label: tr('tables.avg_bill'),
          value: Money.format(h.averageBillMinor, currency: currency),
        ),
        _Figure(label: tr('tables.covers'), value: '${h.covers}'),
        _Figure(
          label: tr('tables.avg_time'),
          value: formatSeatedFor(
            Duration(minutes: h.averageMinutes),
            units: _units(tr),
          ),
        ),
        _Figure(label: tr('tables.turns'), value: turns),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return MadarCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: MadarType.labelSm.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.xs),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: MadarType.numLg.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// One sitting: who, how long, and what it came to.
class _SittingRow extends StatelessWidget {
  const _SittingRow({
    required this.sitting,
    required this.currency,
    required this.tr,
    required this.when,
    required this.clock,
  });

  /// Branch-zone date + time, and time alone, for an RFC3339 instant.
  final String Function(String) when;
  final String Function(String) clock;

  final TableSittingView sitting;
  final String currency;
  final String Function(String) tr;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final s = sitting;
    final who = s.customerName?.trim();
    final ref = s.displayRef.isEmpty ? null : s.displayRef;
    final title = (who?.isNotEmpty ?? false)
        ? who!
        : (ref ?? tr('tables.sittings'));
    final covers = s.guestCount ?? 0;
    // When they sat, and until when — the row is a moment in the room's day.
    final span = s.closedAt == null
        ? when(s.seatedAt)
        : '${when(s.seatedAt)}–${clock(s.closedAt!)}';
    final parts = <String>[
      span,
      formatSeatedFor(Duration(minutes: s.minutes), units: _units(tr)),
      if ((who?.isNotEmpty ?? false) && ref != null) ref,
      if (covers > 0) '$covers ${tr('tables.guests')}',
    ];
    return MadarRow(
      title: title,
      subtitle: parts.join(' · '),
      // A bill that took no money says so instead of showing a zero, which
      // would read as a table that earns nothing rather than one that was
      // voided or is still running.
      value: s.totalMinor == null
          ? null
          : MoneyText(
              s.totalMinor!,
              currency: currency,
              color: colors.textPrimary,
            ),
      trailing: s.totalMinor != null
          ? null
          : MadarTag(
              label: s.status == 'open'
                  ? tr('tables.still_open')
                  : tr('history.voided'),
              tone: s.status == 'open' ? MadarTone.accent : MadarTone.neutral,
            ),
      dense: true,
      titleStyle: MadarType.body.copyWith(color: colors.textPrimary),
    );
  }
}

/// The clock's short hour/minute letters, through the sheet's own `tr`.
DurationUnits _units(String Function(String) tr) => DurationUnits(
  hour: tr('common.hours_short'),
  minute: tr('common.minutes_short'),
);
