/// Close MY open till (`features/tills/close-till-dialog.tsx`,
/// SELL-TIL-038–044, -061): the counted cash, a note, and the payment check
/// of every non-cash method the till took; after a close that leaves bills
/// or seated tables with no till open, the last-till warning.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        CloseTillPreview,
        CloseTillRequest,
        LastTillWarning,
        ReconciliationInput,
        Till;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_dashboard/rules.dart' as rules;

import 'open_till_dialog.dart' show parseAmount;
import 'tills_data.dart';
import '../shared/error_text.dart';

/// Shows the close dialog for [till]; then, when the close's answer carries
/// one, the last-till warning.
Future<void> showCloseTillDialog(
  BuildContext context, {
  required Till till,
}) async {
  final warning = await showDashDialog<LastTillWarning>(
    context,
    builder: (_) => CloseTillDialog(till: till),
  );
  if (warning == null || !context.mounted) return;
  await showLastTillWarning(context, warning);
}

/// "That was the last open till" (SELL-TIL-044).
Future<void> showLastTillWarning(
  BuildContext context,
  LastTillWarning warning,
) => showDashDialog<void>(
  context,
  phoneFullScreen: false,
  builder: (_) => LastTillWarningDialog(warning: warning),
);

/// One row of the payment check (`reconciliationRowSchema`).
class CheckRow {
  CheckRow(this.method);

  final String method;
  bool disagreed = false;
  String declared = '';
  String note = '';

  /// Typed amounts must be ≥ 0; whether the row may be sent is the server's
  /// rule ([reconcileRefusal]): a "Doesn't match" needs an amount and a note.
  bool get valid {
    if (!disagreed) return true;
    final n = parseAmount(declared);
    if (declared.trim().isNotEmpty && !(n != null && n.isFinite && n >= 0)) {
      return false;
    }
    // The cash count never refuses a close, so a row is checked on its own.
    return reconcileRefusal(
          [
            rules.ReconcileTotal(
              method: method,
              isCash: false,
              systemTotal: 0,
              orderCount: 0,
            ),
          ],
          [toInput()],
          closingCashDeclared: 0,
          closingCashSystem: 0,
        ) ==
        null;
  }

  ReconciliationInput toInput() {
    if (!disagreed) {
      return ReconciliationInput(method: method, status: 'checked');
    }
    final n = parseAmount(declared);
    return ReconciliationInput(
      method: method,
      status: 'disagreed',
      // Blank is no amount, not 0 (the server takes 0 as an amount).
      declaredAmount: n == null ? null : egpToPiastres(n),
      note: note.trim(),
      explicitNulls: n == null ? const {'declared_amount'} : const {},
    );
  }
}

class CloseTillDialog extends ConsumerStatefulWidget {
  const CloseTillDialog({required this.till, super.key});

  final Till till;

  @override
  ConsumerState<CloseTillDialog> createState() => _CloseTillDialogState();
}

class _CloseTillDialogState extends ConsumerState<CloseTillDialog> {
  String _cash = '';
  String _cashNote = '';
  List<CheckRow> _rows = [];
  CloseTillPreview? _rowsFrom;
  bool _submitted = false;
  bool _pending = false;

  /// The rows for [preview]'s non-cash methods. A refetched preview keeps
  /// what was typed for the methods still there (the web blanks the form —
  /// a logged divergence, SELL-TIL-061).
  void _syncRows(CloseTillPreview preview) {
    if (identical(preview, _rowsFrom)) return;
    final old = {for (final r in _rows) r.method: r};
    _rows = [
      for (final m in preview.methods)
        if (!m.isCash) old[m.method] ?? CheckRow(m.method),
    ];
    _rowsFrom = preview;
  }

  bool get _cashValid {
    final n = parseAmount(_cash);
    return n != null && n.isFinite && n >= 0;
  }

  Future<void> _submit() async {
    if (_pending) return;
    setState(() => _submitted = true);
    if (!_cashValid || _rows.any((r) => !r.valid)) return;
    final t = ref.read(tProvider);
    final refresh = tillsInvalidator(ref);
    setState(() => _pending = true);
    try {
      final note = _cashNote.trim();
      final res = await ref
          .read(apiProvider)
          .tills
          .closeTill(
            tillId: widget.till.id,
            body: CloseTillRequest(
              closingCashDeclared: egpToPiastres(parseAmount(_cash)!),
              cashNote: note.isEmpty ? null : note,
              reconciliation: [for (final r in _rows) r.toInput()],
              explicitNulls: note.isEmpty ? const {'cash_note'} : const {},
            ),
          );
      refresh();
      if (!mounted) return;
      DashToast.success(context, t('tills.closedToast'));
      Navigator.of(context).pop(res.lastTillWarning);
    } on Object catch (e) {
      if (!mounted) return;
      DashToast.error(context, sellErrorText(e, t));
      setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final preview = ref.watch(closePreviewProvider(widget.till.id));
    final data = preview.value;
    Widget body;
    if (data != null) {
      _syncRows(data);
      body = _form(context, t, data);
    } else if (preview.failedFirst) {
      body = DashErrorState(
        message: sellErrorText(preview.error, t),
        onRetry: () => ref.invalidate(closePreviewProvider(widget.till.id)),
        retrying: preview.isLoading,
        framed: false,
      );
    } else {
      body = const DashSkeleton(
        key: ValueKey('close-preview-loading'),
        height: Space.xxl * 5,
        radius: Radii.sm,
      );
    }
    return DashSurface(
      title: t('tills.closeTill'),
      description: t('tills.closeDesc'),
      body: body,
      actions: data == null
          ? const []
          : [
              DashButton(
                label: t('common.cancel'),
                variant: DashButtonVariant.outline,
                onPressed: () => Navigator.of(context).pop(),
              ),
              DashButton(
                key: const ValueKey('close-till-submit'),
                label: t('tills.closeTill'),
                loading: _pending,
                onPressed: _submit,
              ),
            ],
    );
  }

  Widget _form(BuildContext context, Translator t, CloseTillPreview p) {
    final c = context.madarColors;
    final fmt = ref.watch(formatProvider);
    final cashError = _submitted && !_cashValid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.lg,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: Space.sm,
          children: [
            Text(
              t('tills.closingCash'),
              style: DashType.bodyMedium.copyWith(
                color: cashError ? c.errorText : c.textPrimary,
              ),
            ),
            DashTextInput(
              key: const ValueKey('closing-cash'),
              value: _cash,
              onChanged: (v) => setState(() => _cash = v),
              semanticLabel: t('tills.closingCash'),
              invalid: cashError,
              onSubmitted: (_) => _submit(),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textDirection: TextDirection.ltr,
              mono: true,
            ),
            Text(
              '${t('tills.expectedCash')}: ${fmt.fmtMoney(p.expectedCash)}',
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
            if (cashError)
              Semantics(
                liveRegion: true,
                child: Text(
                  t('tills.cashRequired'),
                  style: DashType.small.copyWith(color: c.errorText),
                ),
              ),
          ],
        ),
        DashTextAreaField(
          key: const ValueKey('close-note'),
          label: t('common.notes'),
          value: _cashNote,
          onChanged: (v) => setState(() => _cashNote = v),
          minLines: 2,
          maxLines: 4,
        ),
        if (_rows.isNotEmpty)
          Semantics(
            container: true,
            label: t('tills.reconciliation.title'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: Space.md,
              children: [
                Text(
                  t('tills.reconciliation.title'),
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
                for (final r in _rows) _checkRow(context, t, fmt, p, r),
              ],
            ),
          ),
      ],
    );
  }

  Widget _checkRow(
    BuildContext context,
    Translator t,
    DashFormat fmt,
    CloseTillPreview p,
    CheckRow r,
  ) {
    final c = context.madarColors;
    final system = p.methods
        .where((m) => m.method == r.method)
        .map((m) => m.systemTotal)
        .firstOrNull;
    final rowError = _submitted && !r.valid;
    return Container(
      key: ValueKey('reconcile-row-${r.method}'),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: Space.sm,
            runSpacing: Space.xs,
            children: [
              Text(
                paymentMethodLabel(t, r.method),
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
              Text(
                '${t('tills.reconciliation.system')}: '
                '${fmt.fmtMoney(system ?? 0)}',
                style: DashType.body.copyWith(color: c.textSecondary),
              ),
            ],
          ),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              Semantics(
                toggled: !r.disagreed,
                child: DashButton(
                  label: t('tills.reconciliation.checked'),
                  size: DashButtonSize.compact,
                  variant: r.disagreed
                      ? DashButtonVariant.outline
                      : DashButtonVariant.primary,
                  onPressed: () => setState(() => r.disagreed = false),
                ),
              ),
              Semantics(
                toggled: r.disagreed,
                child: DashButton(
                  label: t('tills.reconciliation.disagreed'),
                  size: DashButtonSize.compact,
                  variant: r.disagreed
                      ? DashButtonVariant.primary
                      : DashButtonVariant.outline,
                  onPressed: () => setState(() => r.disagreed = true),
                ),
              ),
            ],
          ),
          if (r.disagreed) ...[
            DashTextInput(
              key: ValueKey('reconcile-amount-${r.method}'),
              value: r.declared,
              onChanged: (v) => setState(() => r.declared = v),
              placeholder: t('tills.reconciliation.amount'),
              semanticLabel: t('tills.reconciliation.amount'),
              invalid: rowError,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textDirection: TextDirection.ltr,
              mono: true,
              onSubmitted: (_) => _submit(),
            ),
            DashTextInput(
              key: ValueKey('reconcile-note-${r.method}'),
              value: r.note,
              onChanged: (v) => setState(() => r.note = v),
              placeholder: t('tills.reconciliation.note'),
              semanticLabel: t('tills.reconciliation.note'),
              invalid: rowError,
              minLines: 2,
              maxLines: 4,
            ),
            if (rowError)
              Semantics(
                liveRegion: true,
                child: Text(
                  t('tills.reconciliation.noteRequired'),
                  style: DashType.small.copyWith(color: c.errorText),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class LastTillWarningDialog extends ConsumerWidget {
  const LastTillWarningDialog({required this.warning, super.key});

  final LastTillWarning warning;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final fmt = ref.watch(formatProvider);
    return DashSurface(
      title: t('tills.lastTillTitle'),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.md,
        children: [
          DashIcon(
            'alert-triangle',
            size: IconSize.md,
            color: DashTone.warning.foreground(c),
          ),
          Expanded(
            child: Text(
              t(
                'tills.lastTillBody',
                args: {
                  'bills': warning.openBillsCount,
                  'amount': fmt.fmtMoney(warning.openBillsAmount),
                  'tables': warning.seatedTablesCount,
                },
              ),
              style: DashType.body.copyWith(color: c.textSecondary),
            ),
          ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.ok'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
