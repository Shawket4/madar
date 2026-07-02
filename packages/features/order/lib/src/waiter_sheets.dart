import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_order/src/order_controller.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Dine-in capture before a waiter fires a NEW ticket: customer, table,
/// covers, kitchen notes — all optional, all passed to the core.
class FireDetailsSheet extends StatefulWidget {
  const FireDetailsSheet({required this.model, super.key});

  final OrderController model;

  @override
  State<FireDetailsSheet> createState() => _FireDetailsSheetState();
}

class _FireDetailsSheetState extends State<FireDetailsSheet> {
  final _customer = TextEditingController();
  final _table = TextEditingController();
  final _notes = TextEditingController();
  int _covers = 0;

  @override
  void dispose() {
    _customer.dispose();
    _table.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _fire() async {
    final model = widget.model;
    String? blank(String v) => v.trim().isEmpty ? null : v.trim();
    final ok = await model.fireOrAddRound(
      customerName: blank(_customer.text),
      tableId: blank(_table.text),
      notes: blank(_notes.text),
      guestCount: _covers > 0 ? _covers : null,
    );
    if (ok && mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final colors = context.madarColors;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsetsDirectional.all(Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              model.tr('waiter.fire'),
              style: MadarType.h2.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: Space.md),
            OrderTextField(
              controller: _customer,
              placeholder: model.tr('waiter.customer_optional'),
              icon: 'person',
            ),
            const SizedBox(height: Space.md),
            OrderTextField(
              controller: _table,
              placeholder: model.tr('waiter.table'),
              icon: 'square.grid.2x2',
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    model.tr('waiter.covers'),
                    style: MadarType.title.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                _CoverStepBox(
                  icon: 'minus',
                  onTap: () =>
                      setState(() => _covers = _covers > 0 ? _covers - 1 : 0),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 28 + Space.md * 2,
                  ),
                  child: Text(
                    '$_covers',
                    textAlign: TextAlign.center,
                    style: MadarType.h3.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                _CoverStepBox(
                  icon: 'plus',
                  onTap: () => setState(() => _covers += 1),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            OrderTextField(
              controller: _notes,
              placeholder: model.tr('order.notes_hint'),
              icon: 'text.bubble',
            ),
            const SizedBox(height: Space.md),
            ActionButton(
              label: model.tr('waiter.fire'),
              icon: 'arrow.up.circle',
              loading: model.isBusy,
              onTap: () => unawaited(_fire()),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverStepBox extends StatelessWidget {
  const _CoverStepBox({required this.icon, required this.onTap});

  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      scale: MotionSpec.pressScaleKey,
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      child: Container(
        width: kSquareControl,
        height: kSquareControl,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: colors.border),
        ),
        child: MadarIcon(icon, tint: colors.textPrimary),
      ),
    );
  }
}

/// The void sheet's confirm payload — wraps the (nullable) free-form reason
/// so a dismissed sheet (null result) is distinguishable from "no reason".
@immutable
class VoidTicketResult {
  const VoidTicketResult(this.reason);

  final String? reason;
}

/// Compact confirmation for voiding an OPEN ticket from the waiter cart: a
/// reason picker + free-text note (the shared `void.*` keys) and a
/// Cancel / danger-Void pair. Pops a [VoidTicketResult] on confirm.
class WaiterVoidSheet extends StatefulWidget {
  const WaiterVoidSheet({required this.model, required this.ticket, super.key});

  final OrderController model;
  final TicketView ticket;

  @override
  State<WaiterVoidSheet> createState() => _WaiterVoidSheetState();
}

class _WaiterVoidSheetState extends State<WaiterVoidSheet> {
  static const _reasonKeys = [
    'void.reason_mistake',
    'void.reason_customer',
    'void.reason_quality',
    'void.reason_other',
  ];

  final _note = TextEditingController();
  String? _reasonKey;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _confirm() {
    // A single free-form reason: the picked label + the note (either may be
    // absent — voidTicket accepts a null reason).
    final picked = _reasonKey == null ? null : widget.model.tr(_reasonKey!);
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final reason = [?picked, ?note].join(' — ');
    unawaited(
      Navigator.of(
        context,
      ).maybePop(VoidTicketResult(reason.isEmpty ? null : reason)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final colors = context.madarColors;
    final ref = widget.ticket.ticketRef;
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  model.tr('void.title'),
                  style: MadarType.h2.copyWith(color: colors.textPrimary),
                ),
              ),
              GestureDetector(
                onTap: () => unawaited(Navigator.of(context).maybePop()),
                behavior: HitTestBehavior.opaque,
                child: MadarIcon('xmark', tint: colors.textMuted),
              ),
            ],
          ),
          if (ref != null && ref.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(
              ref,
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: Space.md),
          Text(
            model.tr('void.reason'),
            style: MadarType.label.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: Space.sm),
          for (final key in _reasonKeys) ...[
            _VoidReasonRow(
              label: model.tr(key),
              active: _reasonKey == key,
              onTap: () => setState(() => _reasonKey = key),
            ),
            const SizedBox(height: Space.sm),
          ],
          OrderTextField(
            controller: _note,
            placeholder: model.tr('void.note'),
            icon: 'note.text',
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: ActionButton(
                  label: model.tr('void.cancel'),
                  variant: ActionVariant.outline,
                  onTap: () => unawaited(Navigator.of(context).maybePop()),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: ActionButton(
                  label: model.tr('void.confirm'),
                  variant: ActionVariant.danger,
                  icon: 'trash',
                  onTap: _confirm,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single selectable void-reason row — a radio glyph + label,
/// danger-tinted when picked.
class _VoidReasonRow extends StatelessWidget {
  const _VoidReasonRow({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      scale: 0.99,
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      child: Container(
        padding: const EdgeInsetsDirectional.all(Space.md),
        decoration: BoxDecoration(
          color: active ? colors.dangerBg : colors.surface,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: active
                ? colors.danger.withValues(alpha: Opacities.disabled)
                : colors.border,
          ),
        ),
        child: Row(
          children: [
            MadarIcon(
              active ? 'largecircle.fill.circle' : 'circle',
              tint: active ? colors.danger : colors.textMuted,
              size: IconSize.lg,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                label,
                style: MadarType.body.copyWith(
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
