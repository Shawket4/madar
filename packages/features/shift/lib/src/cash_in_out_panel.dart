/// Cash in / out — the record card and this shift's movement ledger, as ONE
/// panel so the iPad's Till tab can carry it inline beside the shift rows
/// and the phone can push it as its own screen (`CashMovementsScreen`). The
/// kind is the chip (Pay out · Pay in), the amount is the hero field, the
/// note is required, and the button names what it will record.
///
/// State lives in [cashMovementsProvider]; the panel collects input and
/// renders. Movements are OFFLINE-FIRST (queued through the durable outbox,
/// idempotent on a client_ref), so a recorded row appears at once.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_shift/src/shift_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// A movement row's minimum height (canvas: 56).
const double _movementRowMinHeight = 56;

/// Gap between a movement's title and its meta line (canvas: 1).
const double _movementTextGap = 1;

/// The cash in / out panel: kind chips, amount, note, Record, then the
/// shift's movements. [maxRows] caps the inline ledger (the Till tab shows
/// the latest few; the full screen passes null for all of them).
/// [autofocusAmount] is for the pushed screen — on the Till tab the amount
/// must NOT grab the keyboard every time the tab opens.
class CashInOutPanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const CashInOutPanel({
    super.key,
    this.maxRows,
    this.autofocusAmount = false,
    this.showTitle = true,
    this.onSeeAll,
  });

  /// Ledger rows to show inline, or null for every movement.
  final int? maxRows;

  /// Focus the amount once the route's entrance settles.
  final bool autofocusAmount;

  /// The card's own title — off when a screen header already names it.
  final bool showTitle;

  /// Shown as the ledger header's affordance when [maxRows] hides rows.
  final VoidCallback? onSeeAll;

  @override
  ConsumerState<CashInOutPanel> createState() => _CashInOutPanelState();
}

class _CashInOutPanelState extends ConsumerState<CashInOutPanel> {
  /// Note text — widget-local ephemera mirrored into the provider through
  /// `setNote` so the Record button's enablement is state-derived.
  final TextEditingController _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The provider outlives a rebuild of this panel (the tablet keeps it
    // alive beside the pushed screen), so a half-typed note comes back.
    _note.text = ref.read(cashMovementsProvider).note;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    final ok = await ref.read(cashMovementsProvider.notifier).record();
    if (ok && mounted) _note.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    String t(String key) => bridge.tr(key: key);
    final currency = bridge.currentSession()?.currencyCode ?? '';
    // Narrow slices — amount keystrokes repaint the form, not the ledger.
    final isIn = ref.watch(cashMovementsProvider.select((s) => s.isIn));
    final amountMinor = ref.watch(
      cashMovementsProvider.select((s) => s.amountMinor),
    );
    final busy = ref.watch(cashMovementsProvider.select((s) => s.busy));
    final canRecord = ref.watch(
      cashMovementsProvider.select((s) => s.canRecord),
    );
    final error = ref.watch(cashMovementsProvider.select((s) => s.error));
    final notifier = ref.read(cashMovementsProvider.notifier);
    return MadarCard.column(
      children: [
        if (widget.showTitle)
          Text(
            t('cash.title'),
            style: MadarType.h3.copyWith(color: colors.textPrimary),
          ),
        // The kind IS the chip. Pay out leads: it is the movement a shift
        // actually makes. Safe drop and Correct › are not here — see
        // CashMovementsState's doc for why.
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            MadarChip(
              label: t('cash.pay_out'),
              glyph: MadarGlyph.arrowUpEnd,
              selected: !isIn,
              onTap: () => notifier.setDirection(isIn: false),
            ),
            MadarChip(
              label: t('cash.pay_in'),
              glyph: MadarGlyph.arrowDownStart,
              selected: isIn,
              onTap: () => notifier.setDirection(isIn: true),
            ),
          ],
        ),
        MadarAmountField(
          amountMinor: amountMinor,
          onAmountMinor: notifier.setAmount,
          currencyCode: currency,
          autofocus: widget.autofocusAmount,
        ),
        MadarField(
          controller: _note,
          placeholder: t('cash.note_hint'),
          glyph: MadarGlyph.note,
          onChanged: notifier.setNote,
          onSubmitted: (_) => unawaited(_record()),
          trailing: Text(
            t('cash.note_required'),
            style: MadarType.labelSm.copyWith(color: colors.textMuted),
          ),
        ),
        if (error != null)
          NoticeBanner(
            text: error,
            tone: ChipTone.danger,
            icon: 'exclamationmark.circle',
          ),
        MadarButton(
          label: t(isIn ? 'cash.record_pay_in' : 'cash.record_pay_out'),
          loading: busy,
          enabled: canRecord,
          tooltip: canRecord ? null : t('cash.note_hint'),
          onTap: () => unawaited(_record()),
        ),
        _Ledger(
          maxRows: widget.maxRows,
          onSeeAll: widget.onSeeAll,
          currency: currency,
          bridge: bridge,
        ),
      ],
    );
  }
}

/// This shift's movements under the form: a section line carrying the count
/// and the net, then one row per movement (newest first). Watches only the
/// ledger slices so form keystrokes leave it alone.
class _Ledger extends ConsumerWidget {
  const _Ledger({
    required this.maxRows,
    required this.onSeeAll,
    required this.currency,
    required this.bridge,
  });

  final int? maxRows;
  final VoidCallback? onSeeAll;
  final String currency;
  final MadarBridge bridge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    String t(String key) => bridge.tr(key: key);
    final movements = ref.watch(
      cashMovementsProvider.select((s) => s.movements),
    );
    final loading = ref.watch(cashMovementsProvider.select((s) => s.loading));
    // The net is a sum for the header line, not a business figure — the
    // report's cash_in/cash_out are the ones that count.
    var net = 0;
    for (final m in movements) {
      net += m.amountMinor;
    }
    final cap = maxRows;
    final shown = cap == null || movements.length <= cap
        ? movements
        : movements.sublist(0, cap);
    final hidden = movements.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MadarSectionHeader(
          text: t('till.this_shift'),
          trailing: movements.isEmpty
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.xs,
                  children: [
                    Text(
                      '${movements.length}',
                      textDirection: TextDirection.ltr,
                      style: MadarType.num.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    Text(
                      '· ${t('cash.net')}',
                      style: MadarType.bodySm.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    Text(
                      _signed(net, currency),
                      textDirection: TextDirection.ltr,
                      style: MadarType.num.copyWith(
                        color: net < 0 ? colors.danger : colors.success,
                      ),
                    ),
                  ],
                ),
        ),
        if (loading && movements.isEmpty)
          const Padding(
            padding: EdgeInsetsDirectional.only(top: Space.sm),
            child: SkeletonScope(
              child: Column(
                spacing: Space.sm,
                children: [SkeletonRow(), SkeletonRow()],
              ),
            ),
          )
        else if (movements.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(vertical: Space.md),
            child: Text(
              t('cash.empty'),
              style: MadarType.bodySm.copyWith(color: colors.textMuted),
            ),
          )
        else ...[
          for (final m in shown) ...[
            const MadarHairline.row(),
            _MovementRow(movement: m, currency: currency, bridge: bridge),
          ],
          if (hidden > 0 && onSeeAll != null) ...[
            const MadarHairline.row(),
            MadarButton(
              label: '${t('chrome.view')} · $hidden',
              variant: MadarButtonVariant.ghost,
              size: MadarButtonSize.compact,
              onTap: onSeeAll!,
            ),
          ],
        ],
      ],
    );
  }
}

/// `+120.00` / `−90.00`, LTR, for a ledger figure.
String _signed(int minor, String currency) =>
    (minor < 0 ? '−' : '+') + Money.format(minor.abs(), currency: currency);

/// One movement: a toned direction glyph, "Pay out · what it was for" over
/// who moved it and when, and the signed amount in the same tone.
class _MovementRow extends StatelessWidget {
  const _MovementRow({
    required this.movement,
    required this.currency,
    required this.bridge,
  });

  final CashMovementView movement;
  final String currency;
  final MadarBridge bridge;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final m = movement;
    final positive = m.amountMinor >= 0;
    final tone = positive ? colors.success : colors.danger;
    final kind = bridge.tr(key: positive ? 'cash.pay_in' : 'cash.pay_out');
    final title = m.note.trim().isEmpty ? kind : '$kind · ${m.note.trim()}';
    final time = bridge.formatTime(rfc3339: m.createdAt, style: TimeStyle.time);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _movementRowMinHeight),
      child: Row(
        spacing: Space.md,
        children: [
          MadarGlyphIcon(
            positive ? MadarGlyph.arrowDownStart : MadarGlyph.arrowUpEnd,
            color: tone,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: _movementTextGap,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.title.copyWith(color: colors.textPrimary),
                ),
                Row(
                  spacing: Space.xs,
                  children: [
                    Flexible(
                      child: Text(
                        m.movedByName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.bodySm.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                    Text(
                      '·',
                      style: MadarType.bodySm.copyWith(color: colors.textMuted),
                    ),
                    Text(
                      time,
                      textDirection: TextDirection.ltr,
                      style: MadarType.num.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            _signed(m.amountMinor, currency),
            textDirection: TextDirection.ltr,
            style: MadarType.money.copyWith(color: tone),
          ),
        ],
      ),
    );
  }
}
