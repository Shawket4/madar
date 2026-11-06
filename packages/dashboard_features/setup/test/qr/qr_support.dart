// Shared set-up for the QR codes' tests: the real app shell on the seeded
// mock server at Settings › Links & QR codes, finders scoped to the page, to
// the codes section and to one card.
import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_setup/src/links_qr/links_qr_page.dart';
import 'package:dashboard_setup/src/qr/codes_section.dart';
import 'package:dashboard_setup/src/qr/qr_output.dart';
import 'package:dashboard_setup/src/qr/qr_print.dart';
import 'package:dashboard_setup/src/qr/qr_providers.dart';
import 'package:dashboard_setup/src/shared/qr_preview_dialog.dart'
    show QrBusyVeil;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

export 'package:dashboard_setup/src/mock/qr_mock.dart';
export 'package:dashboard_setup/src/mock/support.dart'
    show MockQrLook, mockQrResponse, mockShortLinkBase, qrPngDataUrl;
export 'package:dashboard_setup/src/qr/qr_output.dart';
export 'package:dashboard_setup/src/qr/qr_print.dart';
export 'package:dashboard_setup/src/qr/qr_providers.dart';

export '../support.dart' show setupMockServer;

const String qrPath = '/settings/links-qr';

abstract final class QrRoutes {
  static const String linksQr = '/orgs/{id}/links-qr';
  static const String orgQr = '/orgs/{id}/qr';
  static const String orgBooking = '/orgs/{id}/booking-qr';
  static const String branchQr = '/branches/{id}/qr';
  static const String branchBooking = '/branches/{id}/booking-qr';
  static const String tables = '/branches/{id}/tables';
  static const String tableQr = '/branches/{id}/tables/{tid}/qr';
}

/// `?branchId=` for [branchId] (empty = All branches).
String atBranch(String branchId) => '?branchId=$branchId';

/// Settings › Links & QR codes (+ [query]) as [persona]. A platform admin
/// works inside Sabah Coffee unless [pickOrg] is false. [output] is the shop's
/// remembered output on this device.
Future<DashHarness> pumpQr(
  WidgetTester tester, {
  String query = '',
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? backend,
  bool pickOrg = true,
  QrOutput? output,
  List<Override> overrides = const [],
}) {
  final b = backend ?? setupMockServer(persona: persona ?? Persona.owner);
  return pumpSetup(
    tester,
    path: '$qrPath$query',
    persona: persona,
    size: size,
    locale: locale,
    dark: dark,
    server: b.server,
    db: b.db,
    prefs: {
      if (persona == Persona.platform && pickOrg)
        ScopePrefKeys.org: jsonEncode({'id': SeedIds.sabahOrg}),
      if (output != null)
        qrOutputPrefKey(SeedIds.sabahOrg): jsonEncode(output.toJson()),
    },
    overrides: overrides,
  );
}

/// A Free organisation's plan: the floor and nothing else paid.
final Override freePlan = planFeaturesProvider.overrideWith(_FreePlan.new);

class _FreePlan extends PlanFeaturesNotifier {
  @override
  Set<String>? build() => const {'floor'};
}

/// The shop's output as this device remembers it.
QrOutput? storedOutput(DashHarness h) {
  final raw = h.container
      .read(preferencesProvider)
      .getString(qrOutputPrefKey(SeedIds.sabahOrg));
  return raw == null ? null : QrOutput.fromJson(jsonDecode(raw));
}

/// Moves the header scope to [branchId] (null = All branches).
Future<void> pickBranch(DashHarness h, String? branchId) async {
  await h.container.read(scopeProvider.notifier).setBranch(branchId);
  await h.settle();
}

/// [f] inside the page (not the shell's sidebar or rail, not a dialog).
Finder inPage(Finder f) =>
    find.descendant(of: find.byType(LinksQrPage), matching: f);

/// [f] inside the codes section.
Finder inQr(Finder f) =>
    find.descendant(of: find.byType(QrCodesSection), matching: f);

/// [f] inside the output panel above the codes.
Finder inPanel(Finder f) => find.descendant(
  of: find.byKey(const ValueKey('qr-output-panel')),
  matching: f,
);

/// [f] inside [kind]'s card.
Finder inKind(QrKind kind, Finder f) => find.descendant(
  of: find.byKey(ValueKey('qr-kind-${kind.name}')),
  matching: f,
);

/// [f] inside the table codes card.
Finder inTables(Finder f) =>
    find.descendant(of: find.byKey(const ValueKey('qr-tables')), matching: f);

/// [kind]'s Generate button.
Finder generateOf(QrKind kind) =>
    find.byKey(ValueKey('qr-generate-${kind.name}'));

/// [kind]'s result card.
Finder resultOf(QrKind kind) => find.byKey(ValueKey('qr-result-${kind.name}'));

/// Whether the code under [f] is veiled (a new render on its way).
bool veiled(WidgetTester tester, Finder f) => tester
    .widget<QrBusyVeil>(
      find.descendant(of: f, matching: find.byType(QrBusyVeil)).first,
    )
    .busy;

/// The query [call] sent, one value per key.
Map<String, String> queryOf(MockCall call) => {
  for (final e in call.query.entries) e.key: e.value.single,
};

/// What a printed PDF draws: how many images it paints (`Do`), and whether
/// any text, any dashed line or any font is in it.
typedef PdfFacts = ({int images, bool text, bool dashed, bool fonts});

/// Reads [pdf]'s objects (the `pdf` package writes no object streams, so
/// every dictionary is in the clear) and its page drawing (inflated).
PdfFacts pdfFacts(Uint8List pdf) {
  final src = latin1.decode(pdf);
  final head = RegExp(
    r'\d+ 0 obj\s*<<((?:(?!endobj).)*?)>>\s*stream\r?\n',
    dotAll: true,
  );
  var images = 0;
  var text = false;
  var dashed = false;
  for (final m in head.allMatches(src)) {
    final dict = m.group(1)!;
    final end = src.indexOf('endstream', m.end);
    if (RegExp(r'/Subtype\s*/Image').hasMatch(dict)) continue;
    if (dict.contains('/Length1') || dict.contains('/Subtype/XML')) continue;
    var bytes = pdf.sublist(m.end, end);
    if (dict.contains('/FlateDecode')) {
      try {
        bytes = Uint8List.fromList(ZLibCodec().decode(bytes));
      } on FormatException {
        continue;
      }
    }
    final drawing = latin1.decode(bytes);
    images += RegExp(r'/\S+\s+Do(\s|$)').allMatches(drawing).length;
    text = text || RegExp(r'(^|\s)BT(\s|$)').hasMatch(drawing);
    dashed = dashed || RegExp(r'\]\s*[\d.]+\s+d(\s|$)').hasMatch(drawing);
  }
  return (
    images: images,
    text: text,
    dashed: dashed,
    fonts: RegExp(r'/Type\s*/Font').hasMatch(src),
  );
}

/// Captures what is sent to the print dialog, for the test's length.
List<(Uint8List, String)> capturePrints() {
  final printed = <(Uint8List, String)>[];
  final real = qrPrintPdf;
  qrPrintPdf = (pdf, name) async => printed.add((pdf, name));
  addTearDown(() => qrPrintPdf = real);
  return printed;
}
