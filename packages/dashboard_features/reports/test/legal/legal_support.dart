// Shared set-up for the Legal tests: the real app shell with the reports
// area, on the seeded mock server.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/legal/legal_page.dart';
import 'package:dashboard_reports/src/legal/legal_words.dart';
import 'package:dashboard_reports/src/mock/legal_mock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String legalPath = '/reports/legal';

/// The audit and tax routes, as the mock records them.
const String taxRoute = '/reports/orgs/{org_id}/tax';
String auditRoute(String segment) => '/reports/orgs/{org_id}/$segment';

/// The default period (30 days up to the seed's now, Cairo days).
const String defaultFrom = '2026-09-08T21:00:00.000Z';
const String defaultTo = '2026-10-08T20:59:59.999Z';

/// The supplements the Legal page reads (the area-wide pair and its own).
const List<String> legalSupplements = [
  'packages/dashboard_reports/assets/i18n/en.json',
  'packages/dashboard_reports/assets/i18n/ar.json',
  'packages/dashboard_reports/assets/i18n/legal.en.json',
  'packages/dashboard_reports/assets/i18n/legal.ar.json',
];

/// The reports area as the shell mounts it, with only the Legal page and
/// its mocks, so these tests do not depend on the other units' files.
/// [ownGate] drops the route's capability, so the page's own
/// `<Restricted>` answers (what routes.dart should declare: see the unit's
/// open issue); otherwise the route is exactly routes.dart's.
DashArea legalArea({bool ownGate = false}) => DashArea(
  key: 'reports',
  routes: [
    DashRoute(
      path: legalPath,
      builder: legalPageBuilder,
      titleKey: 'reports.legal.title',
      titleFallback: 'Legal',
      caps: ownGate ? const [] : const [Cap.reportsLegal],
      tabs: legalTabs,
    ),
  ],
  registerMocks: registerLegalMocks,
  i18nSupplements: legalSupplements,
);

/// A seeded server with the core's and the Legal handlers, for a test that
/// changes the data before the page opens.
({MockServer server, MockDb db}) legalServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerLegalMocks(server, db);
  return (server: server, db: db);
}

/// Opens the Legal page as [persona].
Future<DashHarness> pumpLegal(
  WidgetTester tester, {
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
  Map<String, String>? prefs,
  bool ownGate = false,
}) => DashHarness.pump(
  tester,
  areas: [legalArea(ownGate: ownGate)],
  path: legalPath,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: server,
  db: db,
  prefs: prefs,
  shotArea: 'reports',
);

/// Every call to a Legal report endpoint.
List<MockCall> legalCalls(DashHarness h) => [
  for (final c in h.server.calls)
    if ((c.template ?? '').startsWith('/reports/orgs/')) c,
];

/// The Legal tab strip.
final Finder legalStrip = find.byType(DashTabStrip<LegalTab>);

/// A tab's label inside the strip.
Finder tabText(String label) =>
    find.descendant(of: legalStrip, matching: find.text(label));

/// The tab strip's labels in reading order (the strip scrolls sideways, so
/// order is read from the row, not the screen).
List<String> tabLabels(DashHarness h) {
  final texts = find
      .descendant(of: legalStrip, matching: find.byType(Text))
      .evaluate()
      .map((e) => (e.widget as Text).data ?? '')
      .where((s) => s.isNotEmpty)
      .toList();
  return texts;
}

/// Taps the tab labelled [label].
Future<void> tapTab(DashHarness h, String label) => h.tap(tabText(label));

/// The ways a KPI figure may read in its slot (full, whole, compact money).
List<String> moneyForms(DashFormat f, num piastres) => [
  f.fmtMoney(piastres),
  f.fmtMoney(piastres, maxFractionDigits: 0),
  f.fmtMoneyCompact(piastres),
];

List<String> numberForms(DashFormat f, num n) => [
  f.fmtNumber(n),
  f.fmtNumberCompact(n),
];

/// Expects one of [forms] on screen.
void expectAnyText(List<String> forms, {String? reason}) {
  final found = forms.any((s) => find.text(s).evaluate().isNotEmpty);
  expect(found, isTrue, reason: reason ?? 'one of $forms');
}

/// Text widgets whose text contains [s] (spans included).
Finder textHas(String s) => find.textContaining(s, findRichText: true);

DashFormat fmtOf(DashHarness h) => h.container.read(formatProvider);
