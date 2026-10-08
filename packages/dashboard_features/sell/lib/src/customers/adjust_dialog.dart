/// Add or take away points by hand (the web's
/// `features/loyalty/admin/members/adjust-dialog.tsx` + `adjust-schema.ts`,
/// SELL-CUS-044 … 046). Every adjustment carries a reason, kept on the
/// member's history.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'customers_data.dart';

/// Opens the dialog for [member]. [branches] are the org's active branches;
/// [defaultBranchId] the scope the sheet was opened under.
Future<void> showAdjustDialog(
  BuildContext context, {
  required MemberView member,
  required List<Branch> branches,
  String? defaultBranchId,
}) => showDashDialog<void>(
  context,
  builder: (context) => AdjustDialog(
    member: member,
    branches: branches,
    defaultBranchId: defaultBranchId,
  ),
);

class AdjustDialog extends ConsumerStatefulWidget {
  const AdjustDialog({
    required this.member,
    required this.branches,
    this.defaultBranchId,
    super.key,
  });

  final MemberView member;
  final List<Branch> branches;
  final String? defaultBranchId;

  @override
  ConsumerState<AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends ConsumerState<AdjustDialog> {
  final _form = GlobalKey<FormState>();
  final _reasonFocus = FocusNode();
  late String _branchId =
      widget.defaultBranchId ??
      (widget.branches.length == 1 ? widget.branches.first.id : '');

  /// Whether the branch choice shows: decided once, from the initial values
  /// (`branches.length > 1 || !getValues("branch_id")`).
  late final bool _showBranch =
      widget.branches.length > 1 || _branchId.isEmpty;
  String _direction = 'add';
  String _amount = '';
  String _reason = '';
  String? _reasonServerError;
  bool _pending = false;

  MemberView get _m => widget.member;

  @override
  void dispose() {
    _reasonFocus.dispose();
    super.dispose();
  }

  Map<String, Object?> _vars(Translator t) => {
    'balance': _m.balance,
    'unit': loyaltyUnit(t, _m.mode, _m.balance),
  };

  String? _amountError(String v, Translator t) {
    final n = dashParseNumber(v);
    if (n == null || n != n.roundToDouble() || n <= 0 || n > adjustLimit) {
      return t('loyalty.errors.adjustAmount', args: _vars(t));
    }
    if (_direction == 'deduct' && n > _m.balance) {
      return t('loyalty.errors.adjustOverdraw', args: _vars(t));
    }
    return null;
  }

  String? _reasonError(String v, Translator t) {
    final r = v.trim();
    if (r.length < adjustReasonMin) {
      return t('loyalty.errors.adjustReason', args: _vars(t));
    }
    if (r.length > adjustReasonMax) {
      return t('loyalty.errors.adjustReasonLong', args: _vars(t));
    }
    return null;
  }

  Future<void> _submit() async {
    final t = ref.read(tProvider);
    setState(() => _reasonServerError = null);
    if (!(_form.currentState?.validate() ?? false)) return;
    final amount = dashParseNumber(_amount)!.round();
    setState(() => _pending = true);
    try {
      await ref
          .read(apiProvider)
          .loyalty
          .loyaltyAdjust(
            body: AdjustRequest(
              branchId: _branchId,
              customerId: _m.id,
              points: _direction == 'deduct' ? -amount : amount,
              note: _reason.trim(),
            ),
          );
      if (!mounted) return;
      DashToast.success(context, t('loyalty.adjusted'));
      invalidatePeople(ref);
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      // A refusal the form can point at goes on its field; the toast says it
      // either way.
      final refused = loyaltyServerError(e, t);
      if (refused.noteRequired) {
        setState(
          () => _reasonServerError = t('loyalty.errors.serverNoteRequired'),
        );
        _reasonFocus.requestFocus();
      }
      DashToast.error(context, refused.message);
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    return DashSurface(
      title: t('loyalty.adjustTitle'),
      description: t(
        'loyalty.adjustBody',
        args: {'name': _m.name, ..._vars(t)},
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(
          label: t('loyalty.adjustConfirm'),
          loading: _pending,
          onPressed: _submit,
        ),
      ],
      body: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DashSegmentedControl<String>(
                options: [
                  DashOption(value: 'add', label: t('loyalty.adjustAdd')),
                  DashOption(value: 'deduct', label: t('loyalty.adjustDeduct')),
                ],
                value: _direction,
                onChanged: (v) => setState(() => _direction = v),
              ),
            ),
            DashFormField<String>(
              key: const ValueKey('adjust-amount'),
              label:
                  '${t('loyalty.adjustAmount')} (${loyaltyUnit(t, _m.mode)})',
              value: _amount,
              validator: (v) => _amountError(v, t),
              builder: (context, invalid) => DashTextInput(
                value: _amount,
                semanticLabel: t('loyalty.adjustAmount'),
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                mono: true,
                invalid: invalid,
                onChanged: (v) => setState(() => _amount = v),
              ),
            ),
            if (_showBranch)
              DashSelectField<String>(
                key: const ValueKey('adjust-branch'),
                label: t('loyalty.adjustBranch'),
                placeholder: t('loyalty.adjustPickBranch'),
                options: [
                  for (final b in widget.branches)
                    DashOption(value: b.id, label: b.name),
                ],
                value: _branchId.isEmpty ? null : _branchId,
                validator: (v) => v == null || v.isEmpty
                    ? t('loyalty.errors.adjustBranch', args: _vars(t))
                    : null,
                onChanged: (v) => setState(() => _branchId = v),
              ),
            DashFormField<String>(
              key: const ValueKey('adjust-reason'),
              label: t('loyalty.adjustReason'),
              value: _reason,
              errorText: _reasonServerError,
              validator: (v) => _reasonError(v, t),
              builder: (context, invalid) => DashTextInput(
                value: _reason,
                focusNode: _reasonFocus,
                semanticLabel: t('loyalty.adjustReason'),
                placeholder: t('loyalty.adjustReasonPlaceholder'),
                minLines: 2,
                maxLines: 4,
                maxLength: adjustReasonMax,
                invalid: invalid,
                onChanged: (v) => setState(() {
                  _reason = v;
                  _reasonServerError = null;
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
