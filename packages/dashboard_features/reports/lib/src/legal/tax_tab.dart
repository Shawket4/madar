/// Legal › Tax (`features/reports/legal/tax-report-page.tsx`, REP-LEG-008…
/// 012): the VAT summary across the branches the caller may see. The report
/// carries the org's rate itself, so no org read is needed.
library;

import 'package:dashboard_api/dashboard_api.dart' show TaxReport;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'legal_export.dart';
import 'legal_providers.dart';
import 'legal_sheets.dart';

/// VAT-registered: a rate today, or tax collected or refunded in the period
/// under an earlier one (`tax:42-43`).
bool isVatRegistered(TaxReport d) =>
    d.orgTaxRate > 0 || d.taxCollected > 0 || d.refundedTax > 0;

class LegalTaxTab extends ConsumerStatefulWidget {
  const LegalTaxTab({required this.query, required this.enabled, super.key});

  /// The org and period; null while no org is in scope (a platform admin
  /// who has not picked one: the skeleton stays, REP-LEG-037).
  final LegalQuery? query;

  /// An org is in scope and the person holds `reports.legal`.
  final bool enabled;

  @override
  ConsumerState<LegalTaxTab> createState() => _LegalTaxTabState();
}

class _LegalTaxTabState extends ConsumerState<LegalTaxTab> {
  bool _exporting = false;

  List<DashLedgerItem> _kpis(Translator t, TaxReport? d, bool loading) => [
    DashLedgerItem(
      key: 'taxable_sales',
      label: t('analytics.tax.taxableSales'),
      icon: 'receipt',
      value: d == null ? 0 : d.subtotal - d.discountAmount,
      format: DashStatFormat.money,
      loading: loading,
    ),
    DashLedgerItem(
      key: 'tax_collected',
      label: t('analytics.tax.taxCollected'),
      icon: 'percent',
      tone: DashTone.info,
      value: d?.taxCollected ?? 0,
      format: DashStatFormat.money,
      loading: loading,
    ),
    DashLedgerItem(
      key: 'refunded_tax',
      label: t('analytics.tax.refundedTax'),
      icon: 'ban',
      tone: DashTone.warning,
      value: d?.refundedTax ?? 0,
      format: DashStatFormat.money,
      loading: loading,
    ),
    DashLedgerItem(
      key: 'net_tax_due',
      label: t('analytics.tax.netTaxDue'),
      icon: 'landmark',
      tone: DashTone.accent,
      value: d?.netTaxDue ?? 0,
      format: DashStatFormat.money,
      loading: loading,
    ),
    DashLedgerItem(
      key: 'service_charge',
      label: t('analytics.tax.serviceCharge'),
      icon: 'coins',
      value: d?.serviceChargeAmount ?? 0,
      format: DashStatFormat.money,
      loading: loading,
    ),
    DashLedgerItem(
      key: 'net_revenue',
      label: t('dashboard.revenue'),
      icon: 'trending-up',
      value: d?.netRevenue ?? 0,
      format: DashStatFormat.money,
      loading: loading,
    ),
  ];

  ExcelConfig _config(Translator t, DashFormat f, TaxReport d) {
    final note = t(
      'analytics.tax.rateNote',
      args: {'rate': f.fmtPercent(d.orgTaxRate)},
    );
    return ExcelConfig(
      filename: t('reports.legal.tabs.tax'),
      logoUrl: legalExportLogo(ref),
      sheets: [
        taxSheet(t, note, [
          for (final k in _kpis(t, d, false))
            (label: k.label, value: (k.value ?? 0).toInt()),
        ]),
      ],
    );
  }

  Future<void> _excel(TaxReport d) async {
    final t = ref.read(tProvider);
    setState(() => _exporting = true);
    try {
      await legalExportExcel(
        context,
        ref,
        _config(t, ref.read(formatProvider), d),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _csv(TaxReport d) => legalExportCsv(
    context,
    ref,
    _config(ref.read(tProvider), ref.read(formatProvider), d),
  );

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final query = widget.query;
    final AsyncValue<TaxReport?> q = widget.enabled && query != null
        ? ref.watch(legalTaxProvider(query))
        : const AsyncData<TaxReport?>(null);
    if (q.hasError) {
      return DashErrorState(
        onRetry: () => ref.invalidate(legalTaxProvider(query!)),
      );
    }
    if (query == null || q.firstLoad) {
      return const DashSkeleton(
        width: double.infinity,
        height: 112,
        radius: Radii.card,
      );
    }
    final d = q.value;
    if (d == null || !isVatRegistered(d)) {
      return DashEmptyState(
        icon: 'landmark',
        title: t('reports.legal.noVat'),
        description: t('reports.legal.noVatHint'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        Row(
          spacing: Space.md,
          children: [
            Expanded(
              child: Text(
                t(
                  'analytics.tax.rateNote',
                  args: {'rate': f.fmtPercent(d.orgTaxRate)},
                ),
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
            ),
            DashExportButton(
              compact: true,
              loading: _exporting,
              onExport: () => _excel(d),
              onExportCsv: () => _csv(d),
            ),
          ],
        ),
        DashLedgerStrip(items: _kpis(t, d, q.firstLoad)),
      ],
    );
  }
}
