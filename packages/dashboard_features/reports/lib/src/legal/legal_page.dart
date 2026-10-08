/// `/reports/legal` Legal (REP-LEG rows): the Tax tab and nine audit tabs
/// (`features/reports/legal/legal-reports-page.tsx`, `tax-report-page.tsx`,
/// `audit-tab.tsx`). The route has no module (every org); each tab has one.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/report_shared.dart';
import 'audit_tab.dart';
import 'legal_providers.dart';
import 'legal_words.dart';
import 'tax_tab.dart';

/// The route's page (`DashRoute.builder`).
Widget legalPageBuilder(BuildContext context, GoRouterState state) =>
    const LegalReportPage();

/// The tabs, in the web's order, with each tab's module and the extra
/// capability it needs beyond `reports.legal` (REP-LEG-002…004,
/// `leg:31-66`). Until the org's modules are known the web shows no tab at
/// all (REP-LEG-037); [DashRouteTab.visibleTo] lets an unknown module pass,
/// so the page decides with [visibleLegalTabs] instead. Same ids, modules
/// and capabilities as [LegalTab] (a test pins it).
const List<DashRouteTab> legalTabs = [
  DashRouteTab(
    id: 'tax',
    labelKey: 'reports.legal.tabs.tax',
    module: OrgModule.pos,
  ),
  DashRouteTab(
    id: 'refunds',
    labelKey: 'reports.legal.tabs.refunds',
    module: OrgModule.pos,
  ),
  DashRouteTab(
    id: 'voids',
    labelKey: 'reports.legal.tabs.voids',
    module: OrgModule.pos,
  ),
  DashRouteTab(
    id: 'discounts',
    labelKey: 'reports.legal.tabs.discounts',
    module: OrgModule.pos,
  ),
  DashRouteTab(
    id: 'waivers',
    labelKey: 'reports.legal.tabs.waivers',
    module: OrgModule.pos,
  ),
  DashRouteTab(
    id: 'priceOverrides',
    labelKey: 'reports.legal.tabs.priceOverrides',
    module: OrgModule.pos,
  ),
  DashRouteTab(
    id: 'manualDeductions',
    labelKey: 'reports.legal.tabs.manualDeductions',
    module: OrgModule.dawam,
    caps: [Cap.hrPayrollRead],
  ),
  DashRouteTab(
    id: 'deductionOverrides',
    labelKey: 'reports.legal.tabs.deductionOverrides',
    module: OrgModule.dawam,
    caps: [Cap.hrPayrollRead],
  ),
  DashRouteTab(
    id: 'loyaltyAdjustments',
    labelKey: 'reports.legal.tabs.loyaltyAdjustments',
    module: OrgModule.pos,
  ),
  DashRouteTab(
    id: 'attendanceCorrections',
    labelKey: 'reports.legal.tabs.attendanceCorrections',
    module: OrgModule.dawam,
    caps: [Cap.hrAttendanceRead],
  ),
];

/// The page: its own `<Restricted>` with the reports' words (REP-LEG-001,
/// REP-ALL-005), the period subtitle, the visible tabs and the active tab's
/// report — the only one requested (REP-LEG-007).
class LegalReportPage extends ConsumerStatefulWidget {
  const LegalReportPage({super.key});

  @override
  ConsumerState<LegalReportPage> createState() => _LegalReportPageState();
}

class _LegalReportPageState extends ConsumerState<LegalReportPage> {
  /// The picked tab (page state, not the URL: REP-ALL-022); Tax at first.
  LegalTab _picked = LegalTab.tax;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final authz = ref.watch(authzProvider);
    final title = t('reports.legal.title');
    if (!authz.ready) {
      // As the shell's gate (divergence SH-10): nothing while the person's
      // rights load, an error with Retry if they could not be read.
      final error = authz.error;
      if (error == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsetsDirectional.all(Space.xl),
        child: DashErrorState(
          title: t('shell.accessLoadError'),
          message: errorMessage(error, t),
          retryLabel: t('common.retry'),
          onRetry: () => ref.read(authzProvider.notifier).refresh(),
        ),
      );
    }
    final canSee = authz.can(Cap.reportsLegal);
    if (!canSee) return Restricted(title: title, who: t('reports.noAccess'));

    final modules = ref.watch(orgModulesProvider);
    final scope = ref.watch(currentScopeProvider);
    final visible = visibleLegalTabs(authz, modules);
    // A picked tab that is no longer visible falls back to the first one
    // (REP-LEG-005); none visible → the header alone.
    final tab = visible.contains(_picked)
        ? _picked
        : (visible.isEmpty ? null : visible.first);
    final query = legalQueryOf(scope);
    final enabled = query != null && canSee;
    return DashPageScaffold(
      title: title,
      subtitleWidget: const ReportPeriodSubtitle(),
      tabs: visible.isEmpty || tab == null
          ? null
          : DashPageTabs<LegalTab>(
              tabs: [
                for (final v in visible)
                  DashTab(value: v, label: t(v.labelKey)),
              ],
              value: tab,
              onChanged: (v) => setState(() => _picked = v),
            ),
      body: switch (tab) {
        null => const SizedBox.shrink(),
        LegalTab.tax => LegalTaxTab(
          key: const ValueKey('legal-tax'),
          query: query,
          enabled: enabled,
        ),
        final audit => LegalAuditTab(
          key: ValueKey('legal-${audit.id}'),
          tab: audit,
          query: query,
          enabled: enabled,
        ),
      },
    );
  }
}
