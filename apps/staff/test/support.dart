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

/// Real frames: sheets slide in on a spring and a badge pulses for ever, so
/// pumpAndSettle would never settle.
Future<void> frames(WidgetTester t, [int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
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

  /// The fixture as the core would answer it now.
  String picture() {
    final v = jsonDecode(fixture(who)) as Map<String, dynamic>;
    v['privacy_accepted'] = accepted;
    if (fences != null) v['fences'] = fences;
    edit?.call(v);
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
  Future<String> snapshot({required bool refresh}) async => picture();

  /// When set, every action is refused with it (the server's answer).
  DawamError? refuse;

  @override
  Future<String> act(Map<String, dynamic> action) async {
    acts.add(action);
    if (refuse != null) throw refuse!;
    if (action['action'] == 'accept_privacy') accepted = true;
    return picture();
  }

  @override
  Future<String> ping(DawamFix fix) async => picture();

  @override
  Future<String> sync() async => picture();

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
