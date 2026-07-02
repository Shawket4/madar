/// Cash In/Out — the open shift's pay-in / pay-out ledger, a
/// pixel-and-behavior port of the Kotlin CashMovementsScreen (in
/// CashAndShiftsScreen.kt). Movements record a signed pay-in / pay-out
/// against the open shift — OFFLINE-FIRST (queued through the durable
/// outbox, idempotent on a client_ref). All data + rules live in the
/// core; this screen collects input and renders. Full-screen over the
/// order screen.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_shift/src/controls.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
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

/// The open shift's cash in/out ledger (full-screen over the order
/// screen). Takes the shared screen contract: [core] for every bridge call
/// and [onStateChanged] after a movement records (the drawer's expected
/// cash moved). The header's back pops it via `Navigator.maybePop`.
class CashMovementsScreen extends StatefulWidget {
  /// Creates the cash in/out screen.
  const CashMovementsScreen({
    required this.core,
    required this.onStateChanged,
    this.onBack,
    super.key,
  });

  /// The core handle every bridge call goes through.
  final MadarCore core;

  /// Fired after a successful cash movement (the shift's expected cash
  /// moved).
  final void Function() onStateChanged;

  /// Back affordance — defaults to popping this route (the natives set
  /// `showCashMovements` = false).
  final VoidCallback? onBack;

  @override
  State<CashMovementsScreen> createState() => _CashMovementsScreenState();
}

class _CashMovementsScreenState extends State<CashMovementsScreen> {
  MadarBridge get _bridge => widget.core.bridge;

  List<CashMovementView> _movements = const [];
  bool _loading = false;
  bool _isIn = true;
  int _amountMinor = 0;
  final TextEditingController _note = TextEditingController();
  bool _busy = false;
  String? _error;

  String _t(String key) => _bridge.tr(key: key);

  bool get _canRecord => _amountMinor > 0 && !_busy;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _back() {
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
    } else {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  /// The open shift's cash movements — server rows merged with still-queued
  /// ones in the core. Load failures degrade to an empty list (the natives'
  /// `getOrDefault(emptyList())`).
  Future<void> _load() async {
    setState(() => _loading = true);
    List<CashMovementView> movements;
    try {
      movements = await _bridge.listCashMovements();
    } on Exception catch (_) {
      movements = const [];
    }
    if (!mounted) return;
    setState(() {
      _movements = movements;
      _loading = false;
    });
  }

  /// Record a pay-in (`> 0`) or pay-out (`< 0`), reload the list, and reset
  /// the form only on success — the natives' `recordCashMovement`.
  Future<void> _record() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final signed = _isIn ? _amountMinor : -_amountMinor;
      await _bridge.recordCashMovement(
        amountMinor: signed,
        note: _note.text.trim(),
      );
      await _load();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _amountMinor = 0;
        _note.clear();
      });
      widget.onStateChanged();
    } on MadarError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _bridge.humanMessage(e);
      });
    } on Exception catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _t('err.generic');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final currency = _bridge.currentSession()?.currencyCode ?? '';
    // Scaffold: every screen root owns its own Scaffold in this app.
    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Column(
          children: [
            ShiftHeaderBar(title: _t('cash.title'), onBack: _back),
            Expanded(
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
                        if (_error case final error?)
                          NoticeBanner(
                            text: error,
                            tone: ChipTone.danger,
                            icon: 'exclamationmark.circle',
                          ),
                        if (_movements.isNotEmpty)
                          _SummaryStrip(
                            movements: _movements,
                            currency: currency,
                            tr: _t,
                          ),
                        _RecordCard(
                          isIn: _isIn,
                          onDirection: (isIn) => setState(() => _isIn = isIn),
                          amountMinor: _amountMinor,
                          onAmountMinor: (v) => setState(
                            () => _amountMinor = v,
                          ),
                          note: _note,
                          currency: currency,
                          busy: _busy,
                          canRecord: _canRecord,
                          onRecord: () => unawaited(_record()),
                          tr: _t,
                        ),
                        ShiftSectionHeader(text: _t('cash.history')),
                        if (_loading && _movements.isEmpty)
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
                        else if (_movements.isEmpty)
                          Padding(
                            padding: const EdgeInsetsDirectional.symmetric(
                              vertical: Space.lg,
                            ),
                            child: Center(
                              child: Text(
                                _t('cash.empty'),
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
                              for (final (index, m) in _movements.indexed) ...[
                                if (index > 0) const ShiftHairline(),
                                _MovementRow(
                                  movement: m,
                                  currency: currency,
                                  bridge: _bridge,
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
          ],
        ),
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
/// Record CTA.
class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.isIn,
    required this.onDirection,
    required this.amountMinor,
    required this.onAmountMinor,
    required this.note,
    required this.currency,
    required this.busy,
    required this.canRecord,
    required this.onRecord,
    required this.tr,
  });

  final bool isIn;
  final ValueChanged<bool> onDirection;
  final int amountMinor;
  final ValueChanged<int> onAmountMinor;
  final TextEditingController note;
  final String currency;
  final bool busy;
  final bool canRecord;
  final VoidCallback onRecord;
  final String Function(String key) tr;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
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
                onTap: () => onDirection(true),
              ),
            ),
            Expanded(
              child: _DirectionChip(
                label: tr('cash.out'),
                active: !isIn,
                tone: colors.danger,
                onTap: () => onDirection(false),
              ),
            ),
          ],
        ),
        AmountField(
          amountMinor: amountMinor,
          onAmountMinor: onAmountMinor,
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
