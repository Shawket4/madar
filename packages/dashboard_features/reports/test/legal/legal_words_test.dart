// Legal's pure rules over the real word tables: reason wording
// (REP-LEG-022, the web's `audit-tab.test.ts`), discount kinds and percents
// (REP-LEG-023/024), history acts (REP-LEG-025), event counts (REP-LEG-021),
// export columns (REP-LEG-026), and which tabs show (REP-LEG-002…004).
import 'dart:convert';
import 'dart:io';

import 'package:dashboard_api/dashboard_api.dart'
    show AuditBreakdownEntry, MyAuthz;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_reports/src/legal/legal_page.dart';
import 'package:dashboard_reports/src/legal/legal_sheets.dart';
import 'package:dashboard_reports/src/legal/legal_words.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, String> _table(String path) =>
    (json.decode(File(path).readAsStringSync()) as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, '$v'),
    );

final Strings _strings = Strings(
  {
    'en': _table('../../dashboard_core/assets/i18n/en.json'),
    'ar': _table('../../dashboard_core/assets/i18n/ar.json'),
  },
  supplements: [
    {
      'en': _table('assets/i18n/legal.en.json'),
      'ar': _table('assets/i18n/legal.ar.json'),
    },
  ],
);

final Translator en = Translator(_strings, 'en');
final Translator ar = Translator(_strings, 'ar');

AuditBreakdownEntry _r(String label, [String? code]) =>
    AuditBreakdownEntry(label: label, code: code, count: 1, amountMinor: 0);

final RegExp _latin = RegExp('[A-Za-z]');

void main() {
  group('REP-LEG-022 auditReasonText', () {
    test('words server codes and keeps people\'s own words', () {
      expect(
        auditReasonText(
          ar,
          _r('Approved punch correction request', 'correction_request'),
        ),
        isNot(matches(_latin)),
      );
      expect(
        auditReasonText(ar, _r('unspecified', 'unspecified')),
        isNot(contains('unspecified')),
      );
      expect(
        auditReasonText(ar, _r('wrong_order', 'wrong_order')),
        ar('orders.voidReasons.wrong_order'),
      );
      expect(auditReasonText(ar, _r('Broken glassware')), 'Broken glassware');
      expect(
        auditReasonText(ar, _r('some_new_code', 'some_new_code')),
        'some_new_code',
      );
    });

    test('every server code in English', () {
      expect(auditReasonText(en, _r('x', 'unspecified')), 'Not given');
      expect(
        auditReasonText(en, _r('x', 'correction_request')),
        'Approved correction request',
      );
      expect(
        auditReasonText(en, _r('x', 'auto_closed')),
        'Closed automatically: no check-out',
      );
      expect(
        auditReasonText(en, _r('x', 'marked_absent')),
        'Marked absent automatically: no check-in',
      );
      expect(auditReasonText(en, _r('x', 'waived')), 'Waived');
      expect(auditReasonText(en, _r('x', 'overridden')), 'Overridden');
      expect(
        auditReasonText(en, _r('x', 'customer_request')),
        'Customer request',
      );
      expect(auditReasonText(en, _r('x', 'other')), 'Other');
      expect(auditReasonText(en, _r('x', 'quality_issue')), 'Quality issue');
      expect(auditReasonText(en, _r('x', 'wrong_order')), 'Wrong order');
      expect(auditReasonText(en, _r('x', 'preset')), 'Preset');
      expect(auditReasonText(en, _r('x', 'manual_amount')), 'Amount by hand');
      expect(auditReasonText(en, _r('x', 'manual_percent')), 'Percent by hand');
    });

    test('the deduction-override types the server sends without a code', () {
      expect(auditReasonText(ar, _r('waived')), isNot(contains('waived')));
      expect(
        auditReasonText(ar, _r('overridden')),
        isNot(contains('overridden')),
      );
      expect(auditReasonText(en, _r('waived')), 'Waived');
      expect(auditReasonText(en, _r('overridden', 'overridden')), 'Overridden');
    });

    test('(divergence) a bare discount type and an uncoded "unspecified" '
        'are worded, not shown raw', () {
      expect(auditReasonText(en, _r('percentage', 'percentage')), 'Percentage');
      expect(auditReasonText(en, _r('fixed', 'fixed')), 'Fixed amount');
      expect(auditReasonText(en, _r('unspecified')), 'Not given');
      expect(
        auditReasonText(ar, _r('percentage', 'percentage')),
        isNot(matches(_latin)),
      );
    });
  });

  test('REP-LEG-023 discountKindLabel', () {
    expect(discountKindLabel(en, 'preset'), 'Preset');
    expect(discountKindLabel(en, 'manual_amount'), 'Amount by hand');
    expect(discountKindLabel(en, 'manual_percent'), 'Percent by hand');
    expect(discountKindLabel(en, null), 'Not recorded');
    expect(discountKindLabel(en, 'unattributed'), 'Not recorded');
    expect(discountKindLabel(ar, 'preset'), isNot(matches(_latin)));
  });

  test('REP-LEG-024 bpsLabel', () {
    expect(bpsLabel(null), isNull);
    expect(bpsLabel(1000), '10%');
    expect(bpsLabel(1250), '12.5%');
    expect(bpsLabel(1234), '12.34%');
    expect(bpsLabel(5), '0.05%');
    expect(bpsLabel(0), '0%');
  });

  test('REP-LEG-025 historyActionText', () {
    expect(historyActionText(en, 'waive'), 'Waived');
    expect(historyActionText(en, 'unwaive'), 'Waiver undone');
    expect(historyActionText(en, 'override'), 'Overridden');
    expect(historyActionText(en, 'rename'), 'rename');
    expect(historyActionText(ar, 'unwaive'), isNot(matches(_latin)));
  });

  test('REP-LEG-021 event counts, with the plural forms', () {
    final fEn = const DashFormat();
    final fAr = const DashFormat(lang: 'ar');
    expect(eventsCountText(en, fEn, 1), '1 event');
    expect(eventsCountText(en, fEn, 4), '4 events');
    expect(eventsCountText(en, fEn, 1234), '1,234 events');
    expect(
      ar('reports.legal.eventsCount', count: 3, args: {'n': '3'}),
      '3 أحداث',
    );
    expect(
      ar('reports.legal.eventsCount', count: 1, args: {'n': '1'}),
      'حدث واحد',
    );
    expect(eventsCountText(ar, fAr, 11), isNot(matches(_latin)));
  });

  test('REP-LEG-026 the export columns in the reader\'s language', () {
    final headers = [
      for (final c in auditColumns(ar, AuditAmount.money)) c.header,
    ];
    expect(headers.join(' '), isNot(matches(RegExp('Label|Events|Amount'))));
    expect(
      [for (final c in auditColumns(en, AuditAmount.money)) c.header],
      ['Label', 'Events', 'Amount'],
    );
    expect(
      [for (final c in auditColumns(en, AuditAmount.points)) c.header],
      ['Label', 'Events', 'Points moved'],
    );
    expect(
      [for (final c in auditColumns(en, AuditAmount.none)) c.header],
      ['Label', 'Events'],
    );
    expect(
      [for (final c in historyColumns(en)) c.header],
      ['When', 'Employee', 'What', 'By', 'Reason', 'Before', 'After'],
    );
  });

  group('REP-LEG-002…004 the visible tabs', () {
    Authz authz(Set<String> caps) => Authz.from(
      MyAuthz.fromJson({
        'user_id': 'u',
        'capabilities': caps.toList(),
        'everywhere': caps.toList(),
        'ask_manager': <String>[],
        'limits': <String, Object?>{},
        'owner': false,
        'platform': false,
        'role_kinds': ['org_admin'],
        'epoch': 1,
        'spec_version': 2,
      }),
    );
    const both = OrgModulesState(
      modules: [OrgModule.pos, OrgModule.dawam],
      known: true,
    );
    final all = {Cap.reportsLegal, Cap.hrPayrollRead, Cap.hrAttendanceRead};

    test('every tab, in the web\'s order, with both modules and caps', () {
      expect(visibleLegalTabs(authz(all), both), LegalTab.values);
    });

    test('payroll and attendance caps hide their tabs', () {
      final tabs = visibleLegalTabs(authz({Cap.reportsLegal}), both);
      expect(tabs, isNot(contains(LegalTab.manualDeductions)));
      expect(tabs, isNot(contains(LegalTab.deductionOverrides)));
      expect(tabs, isNot(contains(LegalTab.attendanceCorrections)));
      expect(tabs.first, LegalTab.tax);
    });

    test('a Dawam-only org: the three pay and attendance tabs', () {
      expect(
        visibleLegalTabs(
          authz(all),
          const OrgModulesState(modules: [OrgModule.dawam], known: true),
        ),
        [
          LegalTab.manualDeductions,
          LegalTab.deductionOverrides,
          LegalTab.attendanceCorrections,
        ],
      );
    });

    test('modules unknown: no tab (REP-LEG-037)', () {
      expect(visibleLegalTabs(authz(all), const OrgModulesState()), isEmpty);
    });

    test('the route\'s tabs mirror LegalTab', () {
      expect(
        [for (final t in legalTabs) t.id],
        [for (final t in LegalTab.values) t.id],
      );
      for (final (i, t) in legalTabs.indexed) {
        final tab = LegalTab.values[i];
        expect(t.labelKey, tab.labelKey);
        expect(t.module, tab.module);
        expect(t.caps, [?tab.extraCap]);
      }
    });
  });
}
