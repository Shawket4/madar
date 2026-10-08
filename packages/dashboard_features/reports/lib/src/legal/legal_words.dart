/// The words the Legal page derives from server codes (`audit-tab.tsx`
/// `auditReasonText`, `actionText`; `features/discounts/
/// discount-attribution.ts` `discountKindLabel`, `bpsLabel`), the tabs and
/// what each tab's amount measures. Pure, so they are tested directly.
library;

import 'package:dashboard_api/dashboard_api.dart' show AuditBreakdownEntry;
import 'package:dashboard_core/dashboard_core.dart';

/// The ten tabs, in the web's order (`leg:31-38`).
enum LegalTab {
  tax('tax', 'reports.legal.tabs.tax', OrgModule.pos),
  refunds('refunds', 'reports.legal.tabs.refunds', OrgModule.pos),
  voids('voids', 'reports.legal.tabs.voids', OrgModule.pos),
  discounts('discounts', 'reports.legal.tabs.discounts', OrgModule.pos),
  waivers('waivers', 'reports.legal.tabs.waivers', OrgModule.pos),
  priceOverrides(
    'priceOverrides',
    'reports.legal.tabs.priceOverrides',
    OrgModule.pos,
  ),
  manualDeductions(
    'manualDeductions',
    'reports.legal.tabs.manualDeductions',
    OrgModule.dawam,
    Cap.hrPayrollRead,
  ),
  deductionOverrides(
    'deductionOverrides',
    'reports.legal.tabs.deductionOverrides',
    OrgModule.dawam,
    Cap.hrPayrollRead,
  ),
  loyaltyAdjustments(
    'loyaltyAdjustments',
    'reports.legal.tabs.loyaltyAdjustments',
    OrgModule.pos,
  ),
  attendanceCorrections(
    'attendanceCorrections',
    'reports.legal.tabs.attendanceCorrections',
    OrgModule.dawam,
    Cap.hrAttendanceRead,
  );

  const LegalTab(this.id, this.labelKey, this.module, [this.extraCap]);

  /// The [DashRouteTab.id].
  final String id;
  final String labelKey;

  /// The module the tab reports on (`TAB_MODULE`, `leg:50-61`).
  final String module;

  /// What the tab needs beyond `reports.legal` (`EXTRA_CAP`, `leg:42-46`).
  final String? extraCap;

  static LegalTab? byId(String id) {
    for (final t in values) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// The audit endpoint's path segment (`/reports/orgs/{orgId}/<segment>`).
  String get segment => switch (this) {
    LegalTab.tax => 'tax',
    LegalTab.refunds => 'refunds-audit',
    LegalTab.voids => 'voids-audit',
    LegalTab.discounts => 'discounts-audit',
    LegalTab.waivers => 'waivers-audit',
    LegalTab.priceOverrides => 'price-overrides',
    LegalTab.manualDeductions => 'manual-deductions-audit',
    LegalTab.deductionOverrides => 'deduction-overrides-audit',
    LegalTab.loyaltyAdjustments => 'loyalty-adjustments-audit',
    LegalTab.attendanceCorrections => 'attendance-corrections-audit',
  };

  /// What `amount_minor` measures on this tab (`leg:147-155`).
  AuditAmount get amount => switch (this) {
    LegalTab.loyaltyAdjustments => AuditAmount.points,
    LegalTab.attendanceCorrections => AuditAmount.none,
    _ => AuditAmount.money,
  };

  /// The first breakdown card's title key: the report's second axis
  /// (REP-LEG-019).
  String get reasonLabelKey => switch (this) {
    LegalTab.discounts => 'reports.legal.byDiscount',
    LegalTab.waivers ||
    LegalTab.priceOverrides ||
    LegalTab.loyaltyAdjustments => 'reports.legal.byBranch',
    LegalTab.deductionOverrides => 'reports.legal.byType',
    _ => 'reports.legal.byReason',
  };
}

/// The tabs this person sees, in order (`legalTabs`, `leg:64-66`): the
/// tab's module is on and, where it needs one, the extra capability is
/// held. Until the org's modules are known there are none (REP-LEG-037).
List<LegalTab> visibleLegalTabs(Authz authz, OrgModulesState modules) => [
  if (modules.known)
    for (final t in LegalTab.values)
      if (modules.has(t.module) &&
          (t.extraCap == null || authz.can(t.extraCap!)))
        t,
];

/// What an audit's amount measures: money (default), loyalty points, or
/// nothing (attendance corrections).
enum AuditAmount { money, points, none }

/// Codes for labels the server wrote itself → their keys (`aud:39-46`).
const Map<String, String> _reasonCodeKeys = {
  'unspecified': 'reports.legal.reason.unspecified',
  'correction_request': 'reports.legal.reason.correction_request',
  'auto_closed': 'reports.legal.reason.auto_closed',
  'marked_absent': 'reports.legal.reason.marked_absent',
  'waived': 'reports.legal.reason.waived',
  'overridden': 'reports.legal.reason.overridden',
};

/// Labels the server writes with no code (`aud:48-49`: Deduction overrides'
/// by-type rows), plus `unspecified`, the Loyalty adjustments audit's word
/// for an adjustment made away from any branch (divergence REP-LEG-022b).
const Set<String> _uncodedServerWords = {'waived', 'overridden', 'unspecified'};

/// The discount type a manual (unnamed) discount carries as its by-discount
/// code (`discounts-audit`: `COALESCE(d.name, o.discount_type)`), worded
/// instead of shown raw (divergence REP-LEG-022a).
const Map<String, String> _discountTypeKeys = {
  'percentage': 'discounts.percentage',
  'fixed': 'discounts.fixed',
};

/// A breakdown row's label in the reader's language (`auditReasonText`,
/// REP-LEG-022): a server code is worded here; a person's own words stay as
/// typed; an unknown code shows as sent.
String auditReasonText(Translator t, AuditBreakdownEntry r) =>
    auditLabelText(t, r.label, r.code);

/// [auditReasonText] over a bare label and code.
String auditLabelText(Translator t, String label, String? code) {
  final c = code ?? (_uncodedServerWords.contains(label) ? label : null);
  if (c == null) return label;
  final known = _reasonCodeKeys[c];
  if (known != null) return t(known);
  final voidKey = 'orders.voidReasons.$c';
  if (t.exists(voidKey)) return t(voidKey);
  if (const {'preset', 'manual_amount', 'manual_percent'}.contains(c)) {
    return discountKindLabel(t, c);
  }
  final type = _discountTypeKeys[c];
  if (type != null) return t(type);
  return label;
}

/// `discountKindLabel`: a discount act's words; null or unknown reads as
/// "Not recorded".
String discountKindLabel(Translator t, String? kind) => switch (kind) {
  'preset' => t('discounts.kind.preset'),
  'manual_amount' => t('discounts.kind.manualAmount'),
  'manual_percent' => t('discounts.kind.manualPercent'),
  _ => t('discounts.kind.unattributed'),
};

/// `bpsLabel`: basis points → "12%" / "12.5%" / "12.34%"; null → null.
String? bpsLabel(int? bps) {
  if (bps == null) return null;
  final pct = bps / 100;
  final text = pct == pct.truncateToDouble()
      ? pct.toStringAsFixed(0)
      : pct.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  return '$text%';
}

/// An override event's act, worded (`HISTORY_ACTION`, `aud:279-288`); an
/// unknown act shows as sent.
String historyActionText(Translator t, String action) => switch (action) {
  'waive' => t('reports.legal.reason.waived'),
  'unwaive' => t('reports.legal.historyUnwaived'),
  'override' => t('reports.legal.reason.overridden'),
  _ => action,
};

/// "{{n}} events" with the right plural form, `n` grouped as the app's
/// numbers are (`aud:218`).
String eventsCountText(Translator t, DashFormat f, int count) => t(
  'reports.legal.eventsCount',
  count: count,
  args: {'n': f.fmtNumber(count)},
);
