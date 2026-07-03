/// Cash In/Out — the open shift's pay-in / pay-out ledger, a
/// pixel-and-behavior port of the Kotlin CashMovementsScreen (in
/// CashAndShiftsScreen.kt). Movements record a signed pay-in / pay-out
/// against the open shift — OFFLINE-FIRST (queued through the durable
/// outbox, idempotent on a client_ref). All data + rules live in the
/// core; state lives in [cashMovementsProvider]; this screen collects
/// input and renders. Full-screen over the order screen.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_shift/src/controls.dart';
import 'package:feature_shift/src/shift_providers.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Native metrics (CashAndShiftsScreen.kt) that fall between the 4-pt Space
// steps — kept verbatim so the Flutter chrome measures identically.

/// Content column cap (natives: widthIn(max = 560.dp)).
const double _contentMaxWidth = 560;

/// Summary-strip stat money size (natives: Type.money(16.sp)).
const double _statValueSize = 16;

/// Net-block label size (natives: Type.money(14.sp, Bold)).
const double _netLabelSize = 14;

/// Movement title/subtitle gap (natives: spacedBy(2.dp)).
const double _movementTextGap = 2;

/// The open shift's cash in/out ledger (full-screen over the order screen).
/// The header's back pops it via `Navigator.maybePop`; the shell hand-off
/// after a recorded movement happens inside [CashMovementsNotifier].
class CashMovementsScreen extends ConsumerStatefulWidget {
  /// Creates the cash in/out screen.
  const CashMovementsScreen({super.key});

  @override
  ConsumerState<CashMovementsScreen> createState() =>
      _CashMovementsScreenState();
}

class _CashMovementsScreenState extends ConsumerState<CashMovementsScreen> {
  /// Movement-note text — widget-local ephemera; visible state flows from
  /// [cashMovementsProvider].
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Record the movement; the form (and this note field) resets only on
  /// success — the natives' `recordCashMovement`.
  Future<void> _record() async {
    final ok = await ref
        .read(cashMovementsProvider.notifier)
        .record(note: _note.text);
    if (ok && mounted) _note.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    String t(String key) => bridge.tr(key: key);
    final currency = bridge.currentSession()?.currencyCode ?? '';
    // Narrow slices — form keystrokes repaint only the record card below.
    final movements = ref.watch(
      cashMovementsProvider.select((s) => s.movements),
    );
    final loading = ref.watch(cashMovementsProvider.select((s) => s.loading));
    final error = ref.watch(cashMovementsProvider.select((s) => s.error));
    // Scaffold: every screen root owns its own Scaffold in this app.
    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: [
          MadarHeader(
            title: t('cash.title'),
            onBack: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.all(Space.lg),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _contentMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: Space.lg,
                      children: [
                        if (error case final error?)
                          NoticeBanner(
                            text: error,
                            tone: ChipTone.danger,
                            icon: 'exclamationmark.circle',
                          ),
                        if (movements.isNotEmpty)
                          _SummaryStrip(
                            movements: movements,
                            currency: currency,
                            tr: t,
                          ),
                        _RecordCard(
                          note: _note,
                          currency: currency,
                          onRecord: () => unawaited(_record()),
                          tr: t,
                        ),
                        ShiftSectionHeader(text: t('cash.history')),
                        if (loading && movements.isEmpty)
                          const SkeletonScope(
                            child: Column(
                              spacing: Space.sm,
                              children: [
                                SkeletonRow(),
                                SkeletonRow(),
                                SkeletonRow(),
                              ],
                            ),
                          )
                        else if (movements.isEmpty)
                          Padding(
                            padding: const EdgeInsetsDirectional.symmetric(
                              vertical: Space.lg,
                            ),
                            child: Center(
                              child: Text(
                                t('cash.empty'),
                                style: MadarType.bodySm.copyWith(
                                  color: colors.textMuted,
                                ),
                              ),
                            ),
                          )
                        else
                          // One card, rows separated by hairlines (the
                          // natives' zero-inset MadarCard).
                          ShiftFlushCard(
                            children: [
                              for (final (index, m) in movements.indexed) ...[
                                if (index > 0) const ShiftHairline(),
                                _MovementRow(
                                  movement: m,
                                  currency: currency,
                                  bridge: bridge,
                                ),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Total in / out / net for the open shift — In / Out as lighter stats above
/// a tinted-teal Net block (the hero figure tellers look at, mirroring the
/// cart's grand-total panel).
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.movements,
    required this.currency,
    required this.tr,
  });

  final List<CashMovementView> movements;
  final String currency;
  final String Function(String key) tr;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    var totalIn = 0;
    var totalOut = 0;
    for (final m in movements) {
      if (m.amountMinor > 0) {
        totalIn += m.amountMinor;
      } else {
        totalOut -= m.amountMinor;
      }
    }
    final net = totalIn - totalOut;
    return ShiftCard(
      children: [
        Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: _Stat(
                label: tr('cash.total_in'),
                value: '+ ${Money.format(totalIn, currency: currency)}',
                tone: colors.success,
              ),
            ),
            Expanded(
              child: _Stat(
                label: tr('cash.total_out'),
                value: '− ${Money.format(totalOut, currency: currency)}',
                tone: colors.danger,
              ),
            ),
          ],
        ),
        // Net — the running figure for the shift, in the signature
        // tinted-teal block.
        Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.md,
            vertical: Space.md,
          ),
          decoration: BoxDecoration(
            color: colors.accentBg,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            children: [
              Text(
                tr('cash.net'),
                style: MadarType.money.copyWith(
                  fontSize: _netLabelSize,
                  color: colors.accent,
                ),
              ),
              const Spacer(),
              Text(
                (net < 0 ? '−' : '') +
                    Money.format(net.abs(), currency: currency),
                textDirection: TextDirection.ltr,
                style: MadarType.moneyLg.copyWith(
                  color: net < 0 ? colors.danger : colors.accent,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One lighter stat above the Net block: uppercase muted label + toned
/// tabular money.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.tone});

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.xs,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: MadarType.labelSm.copyWith(
            color: colors.textMuted,
            letterSpacing: MadarType.tracking,
          ),
        ),
        Text(
          value,
          maxLines: 1,
          textDirection: TextDirection.ltr,
          style: MadarType.money.copyWith(
            fontSize: _statValueSize,
            color: tone,
          ),
        ),
      ],
    );
  }
}

/// The record card: In/Out direction chips, the amount, the note, and the
/// Record CTA. Watches its own narrow slices so amount keystrokes repaint
/// only this card.
class _RecordCard extends ConsumerWidget {
  const _RecordCard({
    required this.note,
    required this.currency,
    required this.onRecord,
    required this.tr,
  });

  final TextEditingController note;
  final String currency;
  final VoidCallback onRecord;
  final String Function(String key) tr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final isIn = ref.watch(cashMovementsProvider.select((s) => s.isIn));
    final amountMinor = ref.watch(
      cashMovementsProvider.select((s) => s.amountMinor),
    );
    final busy = ref.watch(cashMovementsProvider.select((s) => s.busy));
    final canRecord = ref.watch(
      cashMovementsProvider.select((s) => s.canRecord),
    );
    return ShiftCard(
      children: [
        Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: _DirectionChip(
                label: tr('cash.in'),
                active: isIn,
                tone: colors.success,
                onTap: () => ref
                    .read(cashMovementsProvider.notifier)
                    .setDirection(isIn: true),
              ),
            ),
            Expanded(
              child: _DirectionChip(
                label: tr('cash.out'),
                active: !isIn,
                tone: colors.danger,
                onTap: () => ref
                    .read(cashMovementsProvider.notifier)
                    .setDirection(isIn: false),
              ),
            ),
          ],
        ),
        AmountField(
          amountMinor: amountMinor,
          onAmountMinor: (v) =>
              ref.read(cashMovementsProvider.notifier).setAmount(v),
          currencyCode: currency,
        ),
        ShiftTextField(
          controller: note,
          placeholder: tr('cash.note'),
          icon: 'text.bubble',
        ),
        ShiftButton(
          label: tr('cash.record'),
          icon: 'plus.forwardslash.minus',
          loading: busy,
          enabled: canRecord,
          onTap: onRecord,
        ),
      ],
    );
  }
}

/// Pay-in / pay-out toggle chip — success/danger fill when active,
/// surfaceAlt otherwise.
class _DirectionChip extends StatelessWidget {
  const _DirectionChip({
    required this.label,
    required this.active,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(vertical: Space.md),
        decoration: BoxDecoration(
          color: active ? tone : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: MadarType.title.copyWith(
            color: active ? colors.textOnAccent : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// One movement: toned direction tile, note (or the In/Out fallback) over
/// who moved it + when, and the signed amount.
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
    final title = m.note.isEmpty
        ? bridge.tr(key: positive ? 'cash.in' : 'cash.out')
        : m.note;
    final time = bridge.formatTime(
      rfc3339: m.createdAt,
      style: TimeStyle.time,
    );
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      child: Row(
        spacing: Space.md,
        children: [
          Container(
            width: Metrics.iconTile,
            height: Metrics.iconTile,
            decoration: BoxDecoration(
              color: positive ? colors.successBg : colors.dangerBg,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: MadarIcon(
                positive ? 'arrow.down.left' : 'arrow.up.right',
                tint: tone,
                size: IconSize.lg,
              ),
            ),
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
                Text(
                  '${m.movedByName} · $time',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.bodySm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${positive ? '+' : '−'} '
            '${Money.format(m.amountMinor.abs(), currency: currency)}',
            textDirection: TextDirection.ltr,
            style: MadarType.money.copyWith(color: tone),
          ),
        ],
      ),
    );
  }
}
