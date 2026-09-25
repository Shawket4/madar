// Shared by the app's widget tests: pump the real app for a persona, pump
// real frames, and tear the scope down before the test ends.
//
// The screens read snapshots the real core produced (test/fixtures, written
// by madar-core's `dawam_fixture` test), so a core change that breaks a
// screen's data shows up here too. The fake records every action a screen
// sends; what the action DOES is the core's and the server's, tested there.
import 'dart:convert';
import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madar_staff/main.dart';
import 'package:madar_staff/shell.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

/// The core's own words, straight from i18n.rs — what a device shows.
void useCoreWords() {
  words = (key) => coreWord(key, arabic: currentLang == 'ar');
  wordsIn = (lang, key) => coreWord(key, arabic: lang == 'ar');
}

/// The app's real Plex faces, so text is measured as a phone measures it
/// (the test font's square glyphs overflow rows no device would).
Future<void> loadFonts() async {
  const cuts = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  for (final family in [MadarType.fontFamily, MadarType.monoFamily]) {
    final loader = FontLoader('packages/${MadarType.fontPackage}/$family');
    for (final cut in cuts) {
      final file = File(
        '../../packages/design_system/assets/fonts/$family-$cut.ttf',
      );
      if (file.existsSync()) {
        loader.addFont(file.readAsBytes().then(ByteData.sublistView));
      }
    }
    await loader.load();
  }
}

/// Real frames: sheets slide in on a spring and a badge pulses for ever, so
/// pumpAndSettle would never settle.
Future<void> frames(WidgetTester t, [int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Opens the "Swaps waiting: N" line on Shifts (minor #23: the swap cards
/// fold into it) and waits for its sheet.
Future<void> openSwaps(WidgetTester t) async {
  final f = find.textContaining(
    tr('staff.swaps_waiting', {'count': ''}).trim(),
  );
  await t.ensureVisible(f.first);
  await t.tap(f.first);
  await frames(t, 30);
}

String fixture(String who) =>
    File('test/fixtures/$who.json').readAsStringSync();

/// The core behind the store, answering from the fixtures.
class FakeCore implements DawamBackend {
  FakeCore([this.who = 'e1']);

  String who;
  final acts = <Map<String, dynamic>>[];

  /// This phone accepted the location notice on the server (AT-5).
  bool accepted = true;

  /// The core's fence reading per branch (06 B4); null: as the fixture says.
  Map<String, dynamic>? fences;

  /// Any other change to the picture.
  void Function(Map<String, dynamic>)? edit;

  /// What the background tracking was last told (CL-4).
  final trackingCalls = <bool>[];

  /// The fixture as the core would answer it now. Offline, the core has
  /// only its mirror: the last picture, marked offline.
  String picture() {
    if (!online) return _saved(offline: true);
    final v = jsonDecode(fixture(who)) as Map<String, dynamic>;
    v['privacy_accepted'] = accepted;
    v['fetched_at'] = fetchedAt;
    if (fences != null) v['fences'] = fences;
    edit?.call(v);
    return _last = jsonEncode(v);
  }

  /// The core's `fetched_at`: moves each time a fetch reaches the server.
  int fetchedAt = 1;

  /// The last picture handed out: what the core's mirror holds.
  String? _last;

  /// The server can be reached. Off: a fetch answers the saved picture,
  /// marked offline, as the core does.
  bool online = true;

  /// Online, but the fetch never got an answer (a server blip the core
  /// swallows): the saved picture, `fetched_at` unmoved.
  bool unreachable = false;

  /// When set, a fetch is refused with it (the server's answer).
  DawamError? refuseFetch;

  /// Fetches asked for: the pill, a push, the poll, a pull, a resume.
  int syncs = 0;

  /// A fetch as the core answers it: the server's picture, or the mirror.
  String _fetched() {
    final e = refuseFetch;
    if (e != null) throw e;
    if (!online || unreachable) return _saved(offline: !online);
    fetchedAt++;
    return picture();
  }

  /// The core's mirror: the last picture handed out.
  String _saved({required bool offline}) {
    final v = jsonDecode(_last ?? fixture(who)) as Map<String, dynamic>;
    if (offline) v['online'] = false;
    return jsonEncode(v);
  }

  static const _phones = {
    '01001234567': 'e1',
    '01002345678': 'e2',
    '01003333333': 'e3',
  };

  @override
  Future<void> otpRequest(String phone) async {
    if (!_phones.containsKey(phone)) {
      throw DawamError(
        "This number isn't registered with any business.",
        'الرقم ده مش متسجل عند أي شغل.',
      );
    }
    who = _phones[phone]!;
  }

  /// What the code check answers, when a test wants something else (a
  /// person in two businesses, an answer with no person).
  Map<String, dynamic>? Function(String? orgId)? verifyAnswer;

  @override
  Future<Map<String, dynamic>> otpVerify(
    String phone,
    String code, {
    String? orgId,
  }) async => verifyAnswer?.call(orgId) ?? {'employee_id': who};

  @override
  Future<String> snapshot({required bool refresh}) async =>
      refresh ? _fetched() : picture();

  /// When set, every action is refused with it (the server's answer).
  DawamError? refuse;

  /// What the server made of the next filing (`filed`, RQ-5), laid over
  /// the picture the action returns.
  Map<String, dynamic>? filed;

  /// The next "I agree" fails in transit (not a server refusal) — once.
  Object? acceptError;

  /// The next "I agree" is recorded, but the app's picture still says not
  /// accepted (E2E S11: the owner's context failed after the server stored it).
  bool acceptLeavesNotice = false;

  @override
  Future<String> act(Map<String, dynamic> action) async {
    acts.add(action);
    if (refuse != null) throw refuse!;
    if (action['action'] == 'accept_privacy') {
      final e = acceptError;
      if (e != null) {
        acceptError = null;
        throw e;
      }
      if (acceptLeavesNotice) {
        acceptLeavesNotice = false;
        return picture();
      }
      accepted = true;
    }
    final f = filed;
    if (f == null) return picture();
    final v = jsonDecode(picture()) as Map<String, dynamic>;
    v['filed'] = f;
    return jsonEncode(v);
  }

  @override
  Future<String> ping(DawamFix fix) async => picture();

  @override
  Future<String> sync() async {
    syncs++;
    return _fetched();
  }

  @override
  Future<DawamFix?> locate() async => (
    lat: 30.0609,
    lng: 31.2197,
    accuracy: 8.0,
    mock: false,
    gpsTime: null,
    battery: 80,
  );

  @override
  Stream<DawamFix> track() => const Stream.empty();

  bool always = true;

  @override
  Future<bool> alwaysLocation() async => always;

  @override
  Future<void> tracking({required bool on}) async => trackingCalls.add(on);

  @override
  String? restoredUser() => restored;

  /// A session the core kept from before (a cold start).
  String? restored;

  @override
  Future<void> signOut() async {}
}

late ProviderContainer testContainer;
late FakeCore testCore;

/// Unmounts and disposes the scope, stopping the store's timers before the
/// test ends (a pending timer fails the test).
Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  testContainer.dispose();
}

/// Pumps the app for [who] (null: signed out) on the given side and tab.
/// [core] sets the fake up before the app reads it.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  required String lang,
  String? who,
  bool manage = false,
  int tab = 0,
  Size size = const Size(390, 844),
  ThemeChoice theme = ThemeChoice.light,
  void Function(FakeCore)? core,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // A fresh sign-in is a new phone: it has not accepted the notice yet.
  testCore = FakeCore(who ?? 'e1')..accepted = who != null;
  core?.call(testCore);
  final container = ProviderContainer(
    overrides: [
      dawamBackendProvider.overrideWithValue(testCore),
      localeProvider.overrideWith(() => LocaleNotifier(initial: lang)),
      themeChoiceProvider.overrideWith(
        () => ThemeChoiceNotifier(initial: theme),
      ),
    ],
  );
  testContainer = container;
  container.read(localeProvider);
  final store = container.read(dawamProvider);
  if (testCore.restored != null) {
    await store.restore();
  } else if (who != null) {
    await store.enter();
  }
  final shell = container.read(shellProvider.notifier);
  if (manage) shell.toggle();
  shell.select(tab);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const RepaintBoundary(key: ValueKey('shot'), child: DawamApp()),
    ),
  );
  return container;
}

/// The last action a screen sent to the core.
Map<String, dynamic> lastAct() => testCore.acts.last;

String pretty(Object o) => const JsonEncoder.withIndent(' ').convert(o);
