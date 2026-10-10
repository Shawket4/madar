// Shared set-up for the Till sessions tests: the real app shell with this
// unit's page only, on the seeded mock server.
import 'package:dashboard_api/dashboard_api.dart' show TillSessionRow;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/mock/tills_report_mock.dart';
import 'package:dashboard_reports/src/tills_report/tills_report_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const tillsPath = '/reports/tills';
const tillsTpl = '/reports/branches/{branch_id}/tills';

/// This unit's page exactly as the area's `routes.dart` mounts it, with this
/// unit's mock handlers and words only, so another unit's work in progress
/// never stops these tests compiling.
const DashArea tillsArea = DashArea(
  key: 'reports',
  routes: [
    DashRoute(
      path: tillsPath,
      builder: tillsReportPageBuilder,
      titleKey: 'reports.tills.title',
      titleFallback: 'Till sessions',
      module: OrgModule.pos,
      tabs: tillsReportTabs,
    ),
  ],
  registerMocks: registerTillsReportMocks,
  i18nSupplements: [
    'packages/dashboard_reports/assets/i18n/en.json',
    'packages/dashboard_reports/assets/i18n/ar.json',
    'packages/dashboard_reports/assets/i18n/tills_report.en.json',
    'packages/dashboard_reports/assets/i18n/tills_report.ar.json',
  ],
);

/// A seeded server with the core's handlers and this unit's, for a test that
/// changes the data or the answers before the page opens.
({MockServer server, MockDb db}) tillsServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerTillsReportMocks(server, db);
  return (server: server, db: db);
}

/// Opens [path] as [persona] in the real shell.
Future<DashHarness> pumpTills(
  WidgetTester tester, {
  String path = tillsPath,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
}) => DashHarness.pump(
  tester,
  areas: const [tillsArea],
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: server,
  db: db,
);

/// The sessions the web's own page test reads (`MOCK_TILL_SESSIONS`), at
/// the seed's branches: a short close, an over close with a negative
/// adjustment, a force-close nobody counted, a till still open.
List<MockRow> webSessions() => [
  {
    'till_id': 'till_1',
    'business_date': '2026-09-18',
    'branch_id': SeedIds.zamalek,
    'branch_name': 'Zamalek',
    'branch_code': 'ZAM',
    'teller_id': 'user_nour',
    'teller_name': 'Nour Adel',
    'opened_at': '2026-09-18T06:05:00Z',
    'status': 'closed',
    'opening_cash': 50000,
    'net_cash_payment': 412300,
    'pay_ins': 20000,
    'pay_outs': 7500,
    'cash_drops': 300000,
    'cash_adjustments': 0,
    'closing_cash_declared': 173300,
    'closing_cash_system': 174800,
    'cash_discrepancy': -1500,
    'orders_count': 148,
    'net_sales': 486200,
    'closed_at': '2026-09-18T17:40:00Z',
  },
  {
    'till_id': 'till_2',
    'business_date': '2026-09-18',
    'branch_id': SeedIds.maadi,
    'branch_name': 'Maadi',
    'branch_code': 'MAD',
    'teller_id': 'user_omar',
    'teller_name': 'Omar Fathy',
    'opened_at': '2026-09-18T06:10:00Z',
    'status': 'closed',
    'opening_cash': 50000,
    'net_cash_payment': 268900,
    'pay_ins': 0,
    'pay_outs': 12000,
    'cash_drops': 200000,
    'cash_adjustments': -500,
    'closing_cash_declared': 107150,
    'closing_cash_system': 106400,
    'cash_discrepancy': 750,
    'orders_count': 96,
    'net_sales': 312400,
    'closed_at': '2026-09-18T18:02:00Z',
  },
  {
    'till_id': 'till_4',
    'business_date': '2026-09-18',
    'branch_id': SeedIds.maadi,
    'branch_name': 'Maadi',
    'branch_code': 'MAD',
    'teller_id': 'user_sara',
    'teller_name': 'Sara Helmy',
    'opened_at': '2026-09-18T15:30:00Z',
    'status': 'force_closed',
    'opening_cash': 30000,
    'net_cash_payment': 143200,
    'pay_ins': 0,
    'pay_outs': 0,
    'cash_drops': 100000,
    'cash_adjustments': 0,
    'closing_cash_declared': null,
    'closing_cash_system': 73200,
    'cash_discrepancy': null,
    'orders_count': 52,
    'net_sales': 171900,
    'closed_at': '2026-09-18T22:20:00Z',
  },
  {
    'till_id': 'till_3',
    'business_date': '2026-09-19',
    'branch_id': SeedIds.zamalek,
    'branch_name': 'Zamalek',
    'branch_code': 'ZAM',
    'teller_id': 'user_nour',
    'teller_name': 'Nour Adel',
    'opened_at': '2026-09-19T06:00:00Z',
    'status': 'open',
    'opening_cash': 50000,
    'net_cash_payment': 98400,
    'pay_ins': 0,
    'pay_outs': 0,
    'cash_drops': 0,
    'cash_adjustments': 0,
    'closing_cash_declared': null,
    'closing_cash_system': null,
    'cash_discrepancy': null,
    'orders_count': 37,
    'net_sales': 104800,
    'closed_at': null,
  },
];

/// The read answers [rows] (still behind the handler's own gate).
void answerWith(MockServer server, List<MockRow> rows) =>
    server.on('GET', tillsTpl, (req) {
      req.requireCap('till.read');
      return MockResponse.ok(rows);
    });

/// A server whose read answers [rows].
({MockServer server, MockDb db}) serverWith(
  List<MockRow> rows, {
  Persona persona = Persona.owner,
}) {
  final s = tillsServer(persona: persona);
  answerWith(s.server, rows);
  return s;
}

List<TillSessionRow> rowsOf(List<MockRow> rows) => [
  for (final r in rows) TillSessionRow.fromJson(r),
];

Finder get tillsPage => find.byType(TillsReportPage);

/// [f] inside the page.
Finder inPage(Finder f) => find.descendant(of: tillsPage, matching: f);

/// The text [s] inside the page.
Finder pageText(String s) => inPage(find.text(s));

/// Texts inside the page containing [s].
Finder pageHas(String s) => inPage(find.textContaining(s, findRichText: true));

/// A Text (or rich text) reading exactly [s], with or without the LTR
/// isolates figures wear.
Finder figure(String s) => find.byWidgetPredicate((w) {
  final text = switch (w) {
    Text(:final data?) => data,
    Text(:final textSpan?) => textSpan.toPlainText(),
    _ => null,
  };
  return text != null && (text == s || text == dashFigure(s));
});

/// Opens the tab labelled [label].
Future<void> openTab(DashHarness h, String label) => h.tap(
  find.descendant(
    of: find.byType(DashPageTabs<String>),
    matching: find.text(label),
  ),
);

/// The header's export button.
Finder get exportButton => inPage(find.byType(DashExportButton));

/// "EGP 1,234.50" for [piastres], as the page writes it in English.
String egp(int piastres) => const DashFormat().fmtMoney(piastres);
