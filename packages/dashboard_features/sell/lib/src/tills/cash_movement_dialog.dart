/// Move cash in or out of MY open till
/// (`features/tills/cash-movement-dialog.tsx`, SELL-TIL-034–037).
library;

import 'package:dashboard_api/dashboard_api.dart' show CashMovementRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'open_till_dialog.dart' show parseAmount;
import 'tills_data.dart';

Future<void> showCashMovementDialog(
  BuildContext context, {
  required String tillId,
}) => showDashDialog<void>(
  context,
  builder: (_) => CashMovementDialog(tillId: tillId),
);

/// Which way the cash goes.
enum CashDirection { cashIn, cashOut }

class CashMovementDialog extends ConsumerStatefulWidget {
  const CashMovementDialog({required this.tillId, super.key});

  final String tillId;

  @override
  ConsumerState<CashMovementDialog> createState() =>
      _CashMovementDialogState();
}

class _CashMovementDialogState extends ConsumerState<CashMovementDialog> {
  // Opens on Cash in with a blank amount and note.
  CashDirection _direction = CashDirection.cashIn;
  String _amount = '';
  String _note = '';
  bool _pending = false;

  double? get _value {
    final n = parseAmount(_amount);
    return n != null && n.isFinite && n > 0 ? n : null;
  }

  bool get _valid => _value != null && _note.trim().isNotEmpty;

  Future<void> _submit() async {
    final v = _value;
    if (v == null || !_valid || _pending) return;
    final t = ref.read(tProvider);
    final sign = _direction == CashDirection.cashOut ? -1 : 1;
    setState(() => _pending = true);
    try {
      await ref
          .read(apiProvider)
          .tills
          .addCashMovement(
            tillId: widget.tillId,
            body: CashMovementRequest(
              amount: egpToPiastres(v) * sign,
              note: _note.trim(),
            ),
          );
      if (!mounted) return;
      DashToast.success(context, t('tills.cashRecorded'));
      invalidateTills(ref);
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      DashToast.error(context, tillsErrorMessage(e, t));
      setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    return DashSurface(
      title: t('tills.cashMovement'),
      description: t('tills.cashMovementDesc'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.lg,
        children: [
          Semantics(
            container: true,
            label: t('tills.cashDialog.direction'),
            child: Row(
              spacing: Space.sm,
              children: [
                Expanded(
                  child: DirectionButton(
                    label: t('tills.cashIn'),
                    icon: 'arrow-down-left',
                    tone: DashTone.success,
                    pressed: _direction == CashDirection.cashIn,
                    onTap: () =>
                        setState(() => _direction = CashDirection.cashIn),
                  ),
                ),
                Expanded(
                  child: DirectionButton(
                    label: t('tills.cashOut'),
                    icon: 'arrow-up-right',
                    tone: DashTone.danger,
                    pressed: _direction == CashDirection.cashOut,
                    onTap: () =>
                        setState(() => _direction = CashDirection.cashOut),
                  ),
                ),
              ],
            ),
          ),
          DashTextField(
            key: const ValueKey('cash-amount'),
            label: t('common.amount'),
            value: _amount,
            onChanged: (v) => setState(() => _amount = v),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            mono: true,
          ),
          DashTextField(
            key: const ValueKey('cash-note'),
            label: t('common.notes'),
            placeholder: t('tills.cashNotePlaceholder'),
            value: _note,
            onChanged: (v) => setState(() => _note = v),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(),
        ),
        DashButton(
          label: t('common.save'),
          loading: _pending,
          onPressed: _valid ? _submit : null,
        ),
      ],
    );
  }
}

/// One half of a pressed/unpressed pair (`aria-pressed`): the chosen one is
/// filled with its [tone] (success for cash in, destructive for cash out),
/// the other is an outline.
class DirectionButton extends StatelessWidget {
  const DirectionButton({
    required this.label,
    required this.icon,
    required this.tone,
    required this.pressed,
    required this.onTap,
    super.key,
  });

  final String label;
  final String icon;
  final DashTone tone;
  final bool pressed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final onFill = Theme.of(context).brightness == Brightness.dark
        ? c.chrome
        : c.surface;
    return Semantics(
      toggled: pressed,
      child: DashPressable(
        onTap: onTap,
        selected: pressed,
        semanticLabel: label,
        excludeChildSemantics: true,
        builder: (context, s) {
          final fill = pressed
              ? tone.solid(c)
              : (s.highlighted ? c.hover : c.card);
          final fg = pressed ? onFill : c.textPrimary;
          return AnimatedContainer(
            duration: DashMotion.of(context, DashMotion.fast),
            height: DashMetrics.target,
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            foregroundDecoration: dashFocusRing(
              context,
              s,
              BorderRadius.circular(Radii.sm),
            ),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: pressed ? null : Border.all(color: c.input),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: Space.sm,
              children: [
                DashIcon(icon, size: IconSize.sm, color: fg),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashType.bodyMedium.copyWith(color: fg),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
