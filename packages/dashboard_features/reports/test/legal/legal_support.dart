// Shared set-up for the Legal tests: the real app shell with the reports
// area, on the seeded mock server.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/legal/audit_cards.dart';
import 'package:dashboard_reports/src/legal/audit_tab.dart';
import 'package:dashboard_reports/src/legal/legal_page.dart';
import 'package:dashboard_reports/src/legal/legal_words.dart';
import 'package:dashboard_reports/src/mock/legal_mock.dart';
import 'package:design_system/design_system.dart' show MadarClippedText;
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

/// The reports area as the shell mounts it, with only the Legal page (its
/// route exactly as routes.dart declares it: no shell gate, the page's own
/// `<Restricted>` answers) and its mocks, so these tests do not depend on
/// the other units' files.
const DashArea legalArea = DashArea(
  key: 'reports',
  routes: [
    DashRoute(
      path: legalPath,
      builder: legalPageBuilder,
      titleKey: 'reports.legal.title',
      titleFallback: 'Legal',
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
}) => DashHarness.pump(
  tester,
  areas: const [legalArea],
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

// ── audit tabs ───────────────────────────────────────────────────────────

/// [f] inside the open audit tab.
Finder inAudit(Finder f) =>
    find.descendant(of: find.byType(LegalAuditTab), matching: f);

/// The card titled [title] in the open audit tab.
Finder auditCard(String title) => find.ancestor(
  of: inAudit(find.text(title)),
  matching: find.byType(LegalCard),
);

/// [f] inside the card titled [title].
Finder inCard(String title, Finder f) =>
    find.descendant(of: auditCard(title), matching: f);

/// A breakdown card's row labels, top to bottom.
List<String> cardLabels(WidgetTester tester, String title) => [
  for (final w in tester.widgetList<MadarClippedText>(
    inCard(title, find.byType(MadarClippedText)),
  ))
    w.data ?? '',
];

/// The audit tab's export button.
Finder get auditExport => inAudit(find.byType(DashExportButton));

/// Whether the audit export can be pressed.
bool auditExportEnabled(WidgetTester tester) =>
    tester
        .widget<DashButton>(
          find.descendant(of: auditExport, matching: find.byType(DashButton)),
        )
        .onPressed !=
    null;

/// The KPI card [key] (`count` / `amount`) of the open audit tab.
DashStatCard auditKpi(WidgetTester tester, String key) =>
    tester.widget<DashStatCard>(inAudit(find.byKey(ValueKey(key))));

/// A seed user's display name.
String userName(MockDb db, String key) =>
    db['users'].get(SeedIds.user(key))['name']! as String;

/// The file name's UTC date stamp (the mock clock's).
String exportStamp(DashHarness h) =>
    isoString(h.container.read(clockProvider)()).substring(0, 10);

/// Picks [item] from the open audit tab's export menu.
Future<void> auditMenu(DashHarness h, String item) async {
  await h.tap(auditExport);
  await h.tap(find.text(item).last);
}

/// A muted detail line as shown: each part in its own first-strong isolate
/// (U+2068…U+2069), joined by " · ".
String detailLine(List<String> parts) =>
    parts.map((p) => '\u2068$p\u2069').join(' · ');
