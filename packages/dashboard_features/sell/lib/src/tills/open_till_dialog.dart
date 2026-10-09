/// Open a till (`features/tills/open-till-dialog.tsx`, SELL-TIL-031–033):
/// the opening float, pre-filled with the suggestion (the last declared
/// close, else the branch's standard float).
library;

import 'package:dashboard_api/dashboard_api.dart' show OpenTillRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tills_data.dart';

/// Shows the dialog (a full-screen sheet on a phone).
Future<void> showOpenTillDialog(
  BuildContext context, {
  required String branchId,
}) => showDashDialog<void>(
  context,
  builder: (_) => OpenTillDialog(branchId: branchId),
);

/// A typed amount in pounds (`Number(v)`), Arabic digits too; null when it
/// is not one.
double? parseAmount(String raw) =>
    raw.trim().isEmpty ? null : dashParseNumber(raw);

class OpenTillDialog extends ConsumerStatefulWidget {
  const OpenTillDialog({required this.branchId, super.key});

  final String branchId;

  @override
  ConsumerState<OpenTillDialog> createState() => _OpenTillDialogState();
}

class _OpenTillDialogState extends ConsumerState<OpenTillDialog> {
  /// What the person typed; null while untouched, the field then follows
  /// the suggestion as the pre-fill read lands or changes.
  String? _typed;
  bool _pending = false;

  /// The suggested float in minor units, as of the last build; 0 = none
  /// (`suggested_opening_cash`).
  int _suggested = 0;

  String get _cash =>
      _typed ??
      (_suggested > 0 ? Strings.jsString(piastresToEgp(_suggested)) : '');

  double? get _amount {
    final n = parseAmount(_cash);
    return n != null && n.isFinite && n >= 0 ? n : null;
  }

  Future<void> _submit() async {
    final amount = _amount;
    if (amount == null || _pending) return;
    final t = ref.read(tProvider);
    setState(() => _pending = true);
    try {
      await ref
          .read(apiProvider)
          .tills
          .openTill(
            branchId: widget.branchId,
            body: OpenTillRequest(openingCash: egpToPiastres(amount)),
          );
      if (!mounted) return;
      DashToast.success(context, t('tills.openedToast'));
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
    final fmt = ref.watch(formatProvider);
    _suggested =
        ref
            .watch(tillPreFillProvider(widget.branchId))
            .value
            ?.suggestedOpeningCash ??
        0;
    return DashSurface(
      title: t('tills.openShift'),
      description: t('tills.openDesc'),
      body: DashTextField(
        key: const ValueKey('opening-cash'),
        label: t('tills.openingCash'),
        value: _cash,
        onChanged: (v) => setState(() => _typed = v),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textDirection: TextDirection.ltr,
        mono: true,
        description: _suggested > 0
            ? '${t('tills.suggested')}: ${fmt.fmtMoney(_suggested)}'
            : null,
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(),
        ),
        DashButton(
          label: t('tills.openShift'),
          loading: _pending,
          onPressed: _amount == null ? null : _submit,
        ),
      ],
    );
  }
}
