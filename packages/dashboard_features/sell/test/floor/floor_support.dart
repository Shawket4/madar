// Shared set-up for the floor's tests: the real app shell with the sell area,
// Heliopolis picked, on the seeded mock server.
import 'package:dashboard_api/dashboard_api.dart' show ApiException;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show tProvider;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_sell/src/area_seed.dart';
import 'package:dashboard_sell/src/floor/floor_page.dart';
import 'package:dashboard_sell/src/mock/register.dart';
import 'package:dashboard_sell/src/orders/error_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sell_harness.dart';

const sectionsPath = '/floor/sections';
const tablesPath = '/floor/tables';
const transfersPath = '/floor/transfers';
const ticketsPath = '/open-tickets';
const historyPath = '/floor/tables/{id}/history';
const layoutPath = '/floor/layout';

/// A seeded server with the core's and the sell area's handlers, to change
/// before the page opens.
({MockServer server, MockDb db}) floorServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerSellMocks(server, db);
  return (server: server, db: db);
}

/// `/floor` with [branchId] picked (Heliopolis by default; [allBranches]
/// picks none).
Future<DashHarness> pumpFloor(
  WidgetTester tester, {
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  String? branchId,
  bool allBranches = false,
  ({MockServer server, MockDb db})? s,
}) => pumpSell(
  tester,
  '/floor',
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  branchId: allBranches ? null : (branchId ?? SeedIds.heliopolis),
  server: s?.server,
  db: s?.db,
);

/// [f] inside the floor page only.
Finder inFloor(Finder f) =>
    find.descendant(of: find.byType(FloorPage), matching: f);

Finder floorText(String text) => inFloor(find.text(text));

/// A Heliopolis table on the canvas, by label.
Finder tableBox(String label, {String branch = 'heliopolis'}) =>
    find.byKey(ValueKey('floor-table-${SellIds.table(branch, label)}'));

/// The system clipboard, kept in memory; [refuse] makes it throw.
class FakeClipboard {
  FakeClipboard(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          if (refuse) throw PlatformException(code: 'denied');
          text = (call.arguments as Map)['text'] as String?;
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          if (refuse) throw PlatformException(code: 'denied');
          return text == null ? null : {'text': text};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  String? text;
  bool refuse = false;
}

/// Presses [key] with ⌘ (or ctrl) held.
Future<void> pressMod(
  DashHarness h,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  final t = h.tester;
  await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(key);
  if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await h.settle();
}

Future<void> press(DashHarness h, LogicalKeyboardKey key) async {
  await h.tester.sendKeyEvent(key);
  await h.settle();
}

/// Lets an autosave fire and land.
Future<void> letSave(DashHarness h) async {
  await h.tester.pump(const Duration(milliseconds: 700));
  await h.settle();
}

/// What a refusal reads on the floor: the app's words for [r]
/// (`h.refusalWords`) through the area's mapping (SELL-ALL-017: an uncoded
/// 403 is the permission sentence, a "Kind: " prefix is dropped).
String shownFor(DashHarness h, MockResponse r) {
  final e = MockServer.toApiException(r);
  return ordersErrorText(
    ApiException(
      status: e.status,
      code: e.code,
      message: h.refusalWords(r),
      details: e.details,
    ),
    h.container.read(tProvider),
  );
}

/// The permission sentence a capability refusal shows.
String deniedWords(DashHarness h) =>
    shownFor(h, MockResponse.denied('floor.layout.edit'));
