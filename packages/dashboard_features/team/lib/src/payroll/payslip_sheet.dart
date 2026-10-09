/// One person's payslip (`PayslipSheet`, TEAM-PAY-030 … -037): every line
/// with its reason, the net, the carry, the PDF, and what may change while
/// the month is open (waive, override, un-waive, delete a manual line, add a
/// bonus or deduction). It reads the payslip by person from the page's
/// reads, so it shows the payslip as it is NOW (after a waiver or a line).
library;

import 'package:dashboard_api/dashboard_api.dart' show PayrollPeriod;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/staff_query.dart';
import 'money_dialogs.dart';
import 'money_errors.dart';
import 'payroll_data.dart';
import 'payroll_exports.dart';
import 'payroll_logic.dart';

class PayslipSheet extends ConsumerStatefulWidget {
  const PayslipSheet({required this.employeeId, super.key});

  final String employeeId;

  @override
  ConsumerState<PayslipSheet> createState() => _PayslipSheetState();
}

class _PayslipSheetState extends ConsumerState<PayslipSheet> {
  bool _closing = false;

  String _err(Object? e) =>
      dawamErrorMessage(e, ref.read(tProvider), ref.read(formatProvider));

  /// TEAM-PAY-034: a manual line, until the month is approved.
  Future<void> _remove(PayLine l) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('dawam.deleteLineTitle', args: {'line': l.label}),
      description: t('dawam.deleteLineHint'),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final api = ref.read(apiProvider).staff;
    final staff = ref.read(staffRevisionsProvider.notifier);
    try {
      if (l.manualKind == 'bonus') {
        await api.deleteBonus(id: l.manualId!);
      } else {
        await api.deleteDeduction(id: l.manualId!);
      }
    } on Object catch (e) {
      if (mounted) DashToast.error(context, _err(e));
      return;
    }
    staff.invalidateStaff();
    if (mounted) DashToast.success(context, t('dawam.lineDeleted'));
  }

  /// TEAM-PAY-036: the payslip as an A4 PDF, saved through the file gateway.
  Future<void> _pdf(SlipRow row, PayrollPeriod? period) async {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final files = ref.read(fileGatewayProvider);
    final company = ref.read(currentOrgProvider).value?.name ?? '';
    try {
      final doc = payslipDoc(
        t: t,
        f: f,
        row: row,
        period: period,
        company: company,
      );
      final bytes = await payslipPdf(doc);
      await files.saveBytes(
        bytes,
        filename: payslipFileName(doc, period),
        mimeType: 'application/pdf',
      );
    } on Object catch (e) {
      if (mounted) DashToast.error(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final authz = ref.watch(authzProvider);
    final s = ref.watch(payrollShownProvider);
    final row = s.rows
        .where((r) => r.employeeId == widget.employeeId)
        .firstOrNull;
    if (row == null) {
      // The person left the list (another month, a refresh): the web's
      // sheet closes with its row.
      if (!_closing && !s.loading) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).maybePop();
        });
      }
      return const SizedBox.shrink();
    }
    final open = s.older == null && s.phase == PayPhase.open;
    final editable = open && authz.can(Cap.hrAdjustmentsCreate);
    final canDeduct = open && authz.can(Cap.hrDeductionsCreate);
    final lines = payslipLines(row, f);
    bool mayTouch(PayLine l) =>
        l.manualKind == 'deduction' || l.rule || l.waivedId != null
        ? canDeduct
        : editable;

    Widget line(PayLine l) {
      final meta = l.waived
          ? waivedText(l, t)
          : l.overrideReason != null
          ? t('dawam.lineOverriddenWhy', args: {'reason': l.overrideReason})
          : l.rule
          ? t('dawam.ruleLine')
          : l.manual
          ? t('dawam.manualLine')
          : null;
      final struck = l.waived
          ? TextDecoration.lineThrough
          : TextDecoration.none;
      final amountColor = l.waived
          ? c.textMuted
          : l.amount < 0
          ? c.danger
          : c.textPrimary;
      return Padding(
        key: ValueKey('payslip-line-${l.key}'),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.xs,
                children: [
                  Text(
                    lineLabel(l, t),
                    style: DashType.body.copyWith(
                      color: l.waived ? c.textMuted : c.textPrimary,
                      decoration: struck,
                    ),
                  ),
                  if (meta != null)
                    Text(
                      meta,
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                ],
              ),
            ),
            Text(
              f.fmtMoneySigned(l.amount),
              textDirection: TextDirection.ltr,
              style: DashType.mono.copyWith(
                color: amountColor,
                decoration: struck,
              ),
            ),
            if (canDeduct && l.deductionId != null) ...[
              DashIconButton(
                icon: 'undo-2',
                semanticLabel: t('dawam.waive'),
                onPressed: () => showWaiveDialog(
                  context,
                  deductionId: l.deductionId!,
                  label: l.label,
                ),
              ),
              DashIconButton(
                icon: 'pencil-line',
                semanticLabel: t('dawam.override'),
                onPressed: () => showOverrideDialog(
                  context,
                  deductionId: l.deductionId!,
                  label: l.label,
                  current: -l.amount,
                ),
              ),
            ],
            if (canDeduct && l.waivedId != null)
              DashIconButton(
                icon: 'rotate-ccw',
                semanticLabel: t('dawam.unwaive'),
                onPressed: () => showUnwaiveDialog(
                  context,
                  deductionId: l.waivedId!,
                  label: l.label,
                ),
              ),
            if (mayTouch(l) && l.manual)
              DashIconButton(
                icon: 'trash-2',
                semanticLabel: t('common.delete'),
                onPressed: () => _remove(l),
              ),
          ],
        ),
      );
    }

    return DashSurface(
      title: row.name,
      description: s.phase == PayPhase.open
          ? t('dawam.estimateHint')
          : t('dawam.frozenHint'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          DashListCard(children: [for (final l in lines) line(l)]),
          Container(
            padding: const EdgeInsets.all(Space.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: c.hairline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t('dawam.net'),
                    style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                  ),
                ),
                Text(
                  f.fmtMoney(row.netPiastres),
                  style: DashType.monoMedium.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (row.carryOutPiastres > 0)
            Text(
              t(
                'dawam.carryHint',
                args: {'amount': f.fmtMoney(row.carryOutPiastres)},
              ),
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashButton(
              label: t('dawam.downloadPdf'),
              icon: 'file-down',
              variant: DashButtonVariant.outline,
              onPressed: () => _pdf(row, s.period),
            ),
          ),
          if (editable || canDeduct)
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                if (editable)
                  DashButton(
                    label: t('dawam.bonus'),
                    icon: 'plus',
                    variant: DashButtonVariant.outline,
                    onPressed: () => showAdjustmentDialog(
                      context,
                      employeeId: row.employeeId,
                    ),
                  ),
                if (canDeduct)
                  DashButton(
                    label: t('dawam.deduction'),
                    icon: 'plus',
                    variant: DashButtonVariant.outline,
                    onPressed: () => showAdjustmentDialog(
                      context,
                      employeeId: row.employeeId,
                      bonus: false,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
