// Set-up step 1, "Where is each branch?" (TEAM-SET-013…023): the branch
// rows, the pin from the device or a pasted link, the radius, and the save,
// driven through the real shell on the mock server.
import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:dashboard_api/dashboard_api.dart' show ApiException, ApiRequest;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/team_setup/setup_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'setup_support.dart';

DashButton _button(WidgetTester tester, String key) =>
    tester.widget<DashButton>(byKey(key));

/// Maadi has its spot but no radius (the web test's `unpinned`); Zamalek
/// has nothing.
void _twoUnpinned(MockDb db) {
  unpin(db, maadi, keepCoordinates: true);
  unpin(db, zamalek);
}

Future<void> _paste(DashHarness h, String branch, String text) =>
    h.enterText(byKey('setup-paste-$branch'), text);

void main() {
  testWidgets('TEAM-SET-013 no branches: the empty state and "Add a branch" '
      'to the Branches page\'s new-branch editor', (tester) async {
    final h = await pumpSetup(
      tester,
      edit: (db) =>
          db['branches'].removeWhere((b) => b['org_id'] == SeedIds.sabahOrg),
    );
    expect(byKey('setup-no-branches'), findsOneWidget);
    expect(find.text(h.t('dawam.setupNoBranches')), findsOneWidget);
    expect(find.text(h.t('dawam.setupNoBranchesHint')), findsOneWidget);
    await h.shot('branches-empty');
    // The admin area's page answers there.
    h.allowUnmatched = true;
    await h.tapText(h.t('dawam.setupAddBranch'));
    expect(h.location.path, '/branches');
    expect(h.location.queryParameters['edit'], 'new');
  });

  testWidgets('TEAM-SET-014 one row per branch; the first unpinned one is '
      'open; Pinned / Not pinned; Close / Edit / Pin it', (tester) async {
    final h = await pumpSetup(tester, edit: _twoUnpinned);
    expect(
      textIn(
        'setup-pin-$heliopolis',
        h.t('dawam.pinnedSummary', args: {'radius': 200}),
      ),
      findsOneWidget,
    );
    expect(textIn('setup-pin-$heliopolis', h.t('common.edit')), findsOneWidget);
    expect(textIn('setup-pin-$maadi', h.t('dawam.notPinned')), findsOneWidget);
    // Maadi (the first unpinned) is open; Zamalek is not.
    expect(textIn('setup-pin-$maadi', h.t('common.close')), findsOneWidget);
    expect(byKey('setup-paste-$maadi'), findsOneWidget);
    expect(textIn('setup-pin-$zamalek', h.t('dawam.pinIt')), findsOneWidget);
    expect(byKey('setup-paste-$zamalek'), findsNothing);
    expect(
      tester
          .getSemantics(byKey('setup-pin-toggle-$maadi'))
          .flagsCollection
          .isExpanded,
      Tristate.isTrue,
    );
    await h.shot('branches-open');

    // One open at a time.
    await h.tapKey(ValueKey('setup-pin-toggle-$zamalek'));
    expect(byKey('setup-paste-$zamalek'), findsOneWidget);
    expect(byKey('setup-paste-$maadi'), findsNothing);
    // Tapping the open one closes it.
    await h.tapKey(ValueKey('setup-pin-toggle-$zamalek'));
    expect(byKey('setup-paste-$zamalek'), findsNothing);
    expect(textIn('setup-pin-$zamalek', h.t('dawam.pinIt')), findsOneWidget);
  });

  testWidgets('TEAM-SET-014 every branch pinned: all closed', (tester) async {
    final h = await pumpSetup(tester);
    await h.tapKey(const ValueKey('setup-step-branches'));
    for (final b in [heliopolis, maadi, newCairo, zamalek]) {
      expect(byKey('setup-paste-$b'), findsNothing);
    }
  });

  testWidgets('TEAM-SET-015 without branches.edit: the note, and every pin '
      'control disabled', (tester) async {
    final s = setupServer(edit: _twoUnpinned);
    answerAuthz(s.server, const [
      'hr.rules.edit',
      'hr.staff.read',
      'hr.schedule.read',
      'branches.read',
    ]);
    final h = await pumpSetup(tester, s: s);
    expect(
      textIn('setup-pin-no-access', h.t('dawam.setupPinNoAccess')),
      findsOneWidget,
    );
    expect(_button(tester, 'setup-locate-$maadi').onPressed, isNull);
    expect(
      tester.widget<DashTextInput>(byKey('setup-paste-$maadi')).enabled,
      isFalse,
    );
    expect(
      tester.widget<DashNumberInput>(byKey('setup-radius-$maadi')).enabled,
      isFalse,
    );
    // Maadi already has a spot, so only the right stops the save.
    expect(_button(tester, 'setup-save-pin-$maadi').onPressed, isNull);
    await h.shot('branches-no-access');
  });

  testWidgets('TEAM-SET-016 "Use my location": a 15 s high-accuracy fix, '
      'rounded to 6 decimals, becomes the pin', (tester) async {
    final h = await pumpSetup(tester, edit: _twoUnpinned);
    final locator = FakeLocator(fixAt(29.96012345, 31.25045678, 25));
    useLocator(h, locator);
    expect(find.text(h.t('dawam.pinHere')), findsOneWidget);
    await h.tapKey(ValueKey('setup-locate-$maadi'));
    expect(locator.calls, 1);
    expect(locator.lastTimeout, const Duration(seconds: 15));
    expect(textIn('setup-pin-$maadi', '29.96012, 31.25046'), findsOneWidget);
    // A good fix: no warning.
    expect(textHas(h.t('dawam.pinRough', args: {'m': 25})), findsNothing);
    await h.tapKey(ValueKey('setup-save-pin-$maadi'));
    final patch = h.server.callsTo('/branches/{id}', method: 'PATCH').single;
    expect(patch.body, {
      'latitude': 29.960123,
      'longitude': 31.250457,
      'geo_radius_meters': 200,
    });
    await h.flushTimers();
  });

  testWidgets('TEAM-SET-016 while locating the button is busy', (tester) async {
    final h = await pumpSetup(tester, edit: _twoUnpinned);
    final slow = _SlowLocator();
    useLocator(h, slow);
    await h.tapKey(ValueKey('setup-locate-$maadi'));
    expect(_button(tester, 'setup-locate-$maadi').loading, isTrue);
    slow.finish(fixAt(29.96, 31.25, 10));
    await h.settle();
    expect(_button(tester, 'setup-locate-$maadi').loading, isFalse);
  });

  group('TEAM-SET-017 location refusals say how to fix them', () {
    for (final (failure, key) in [
      (LocationFailure.unsupported, 'dawam.pinNoGeo'),
      (LocationFailure.denied, 'dawam.pinDenied'),
      (LocationFailure.unavailable, 'dawam.pinUnavailable'),
    ]) {
      testWidgets(failure.name, (tester) async {
        final h = await pumpSetup(tester, edit: _twoUnpinned);
        useLocator(h, FakeLocator(LocationResult.failed(failure)));
        await h.tapKey(ValueKey('setup-locate-$maadi'));
        expect(textIn('setup-pin-$maadi', h.t(key)), findsOneWidget);
        if (failure == LocationFailure.denied) {
          await h.shot('branches-location-denied');
        }
      });
    }

    testWidgets('the build without a location reader says "paste a link"', (
      tester,
    ) async {
      final h = await pumpSetup(tester, edit: _twoUnpinned);
      await h.tapKey(ValueKey('setup-locate-$maadi'));
      expect(textIn('setup-pin-$maadi', h.t('dawam.pinNoGeo')), findsOneWidget);
    });
  });

  testWidgets('TEAM-SET-018 a rough fix (> 100 m) warns, never refuses', (
    tester,
  ) async {
    final h = await pumpSetup(tester, edit: _twoUnpinned);
    useLocator(h, FakeLocator(fixAt(29.9601, 31.2504, 140.4)));
    await h.tapKey(ValueKey('setup-locate-$maadi'));
    expect(
      textIn('setup-pin-$maadi', h.t('dawam.pinRough', args: {'m': 140})),
      findsOneWidget,
    );
    expect(_button(tester, 'setup-save-pin-$maadi').onPressed, isNotNull);
  });

  testWidgets('TEAM-SET-019 the paste field: label, LTR, placeholder; a good '
      'paste sets the pin at once', (tester) async {
    final h = await pumpSetup(tester, edit: _twoUnpinned, locale: 'ar');
    expect(textIn('setup-pin-$maadi', h.t('dawam.pastePin')), findsOneWidget);
    final field = tester.widget<DashTextInput>(byKey('setup-paste-$maadi'));
    expect(
      field.placeholder,
      'https://www.google.com/maps/… · 30.0444, 31.2357',
    );
    expect(
      Directionality.of(tester.element(byKey('setup-paste-$maadi'))),
      TextDirection.ltr,
    );
    // Arabic digits and comma, as an Arabic keyboard types them.
    await _paste(h, maadi, '٢٩٫٩٦٠١٢٣، ٣١٫٢٥٠٤٥٦');
    expect(textIn('setup-pin-$maadi', '29.96012, 31.25046'), findsOneWidget);
    await h.shot('branches-pasted');
  });

  group('TEAM-SET-020 paste problems', () {
    for (final (text, key) in [
      ('https://maps.app.goo.gl/abc', 'dawam.pinShortLink'),
      ('95.1, 31.2', 'dawam.pinOutOfRange'),
      ('the corner of Road 9', 'dawam.pinNone'),
    ]) {
      testWidgets(key, (tester) async {
        final h = await pumpSetup(tester, edit: _twoUnpinned);
        await _paste(h, maadi, text);
        expect(textIn('setup-pin-$maadi', h.t(key)), findsOneWidget);
        expect(
          tester.widget<DashTextInput>(byKey('setup-paste-$maadi')).invalid,
          isTrue,
        );
        // The pin is left as it was (Maadi's saved spot).
        expect(textIn('setup-pin-$maadi', '29.96010, 31.25040'), findsNothing);
      });
    }

    testWidgets('a long Maps link wins over the map centre', (tester) async {
      final h = await pumpSetup(tester, edit: _twoUnpinned);
      await _paste(h, maadi, 'https://maps.app.goo.gl/abc');
      expect(
        textIn('setup-pin-$maadi', h.t('dawam.pinShortLink')),
        findsOneWidget,
      );
      await _paste(
        h,
        maadi,
        'https://www.google.com/maps/place/X/@29.9,31.2,17z/data=!3d29.960123!4d31.250456',
      );
      expect(
        textIn('setup-pin-$maadi', h.t('dawam.pinShortLink')),
        findsNothing,
      );
      expect(textIn('setup-pin-$maadi', '29.96012, 31.25046'), findsOneWidget);
      await h.tapKey(ValueKey('setup-check-maps'));
      expect(
        h.openedLinks.single.toString(),
        'https://www.google.com/maps?q=29.960123,31.250456',
      );
    });
  });

  testWidgets('TEAM-SET-021 the radius: label, presets, hint, the saved '
      'value or 200, 10–5000', (tester) async {
    final h = await pumpSetup(
      tester,
      edit: (db) {
        _twoUnpinned(db);
        db['branches'].update(heliopolis, {'geo_radius_meters': 350});
      },
    );
    final radius = tester.widget<DashNumberInput>(byKey('setup-radius-$maadi'));
    expect(radius.value, 200);
    expect(radius.min, 10);
    expect(radius.max, 5000);
    expect(radius.step, 50);
    expect(radius.presets, [100, 200, 300, 500]);
    expect(textIn('setup-pin-$maadi', h.t('dawam.radius')), findsOneWidget);
    expect(textIn('setup-pin-$maadi', h.t('dawam.radiusHint')), findsOneWidget);
    expect(
      textIn('setup-pin-$maadi', '300 ${h.t('dawam.metres')}'),
      findsOneWidget,
    );
    // A pinned branch starts from its own radius.
    await h.tapKey(ValueKey('setup-pin-toggle-$heliopolis'));
    expect(
      tester.widget<DashNumberInput>(byKey('setup-radius-$heliopolis')).value,
      350,
    );
    expect(
      _button(tester, 'setup-save-pin-$heliopolis').onPressed,
      isNull,
      reason: 'nothing changed',
    );
    // A preset is a change.
    await h.tapText('500 ${h.t('dawam.metres')}');
    expect(_button(tester, 'setup-save-pin-$heliopolis').onPressed, isNotNull);
    // Out of range: the field says so and the save is off.
    await h.enterText(byKey('setup-radius-$heliopolis'), '6000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await h.settle();
    expect(
      textHas(
        h.t('inputs.between', args: {'min': '10', 'max': '5,000', 'unit': ''}),
      ),
      findsWidgets,
    );
    expect(_button(tester, 'setup-save-pin-$heliopolis').onPressed, isNull);
  });

  testWidgets('TEAM-SET-022 the pin summary; outside Egypt warns; no pin '
      'yet says what to do', (tester) async {
    final h = await pumpSetup(tester, edit: _twoUnpinned);
    // Maadi has its spot: "Pin:" and a Maps link.
    expect(
      find.descendant(
        of: byKey('setup-pin-$maadi'),
        matching: textHas(h.t('dawam.pinAt')),
      ),
      findsWidgets,
    );
    expect(byKey('setup-check-maps'), findsOneWidget);
    // Zamalek has nothing.
    await h.tapKey(ValueKey('setup-pin-toggle-$zamalek'));
    expect(textIn('setup-pin-$zamalek', h.t('dawam.pinNone2')), findsOneWidget);
    expect(_button(tester, 'setup-save-pin-$zamalek').onPressed, isNull);
    // A pin in Riyadh: warned, still savable.
    await _paste(h, zamalek, '24.7136, 46.6753');
    expect(textIn('setup-pin-$zamalek', '24.71360, 46.67530'), findsOneWidget);
    expect(
      textIn('setup-pin-$zamalek', h.t('dawam.pinNotEgypt')),
      findsOneWidget,
    );
    expect(_button(tester, 'setup-save-pin-$zamalek').onPressed, isNotNull);
    await h.shot('branches-outside-egypt');
    await h.tapKey(const ValueKey('setup-check-maps'));
    expect(
      h.openedLinks.single.toString(),
      'https://www.google.com/maps?q=24.7136,46.6753',
    );
  });

  testWidgets('TEAM-SET-023 "Pin Maadi" PATCHes the branch, toasts, ticks '
      'it and opens the next unpinned one', (tester) async {
    final h = await pumpSetup(tester, edit: _twoUnpinned);
    expect(
      _button(tester, 'setup-save-pin-$maadi').label,
      h.t('dawam.pinBranch', args: {'name': 'Maadi'}),
    );
    final branchReads = h.server.callsTo('/branches', method: 'GET').length;
    await _paste(
      h,
      maadi,
      'https://www.google.com/maps/place/X/@29.9,31.2,17z/data=!3d29.960123!4d31.250456',
    );
    await h.tapKey(ValueKey('setup-save-pin-$maadi'));
    final patch = h.server.callsTo('/branches/{id}', method: 'PATCH').single;
    expect(patch.path, '/branches/$maadi');
    expect(patch.body, {
      'latitude': 29.960123,
      'longitude': 31.250456,
      'geo_radius_meters': 200,
    });
    await h.expectToast(
      h.t('dawam.pinSaved', args: {'name': 'Maadi'}),
      keep: true,
    );
    // The branches are read again; Maadi reads pinned; Zamalek opens.
    expect(
      h.server.callsTo('/branches', method: 'GET').length,
      greaterThan(branchReads),
    );
    expect(
      textIn(
        'setup-pin-$maadi',
        h.t('dawam.pinnedSummary', args: {'radius': 200}),
      ),
      findsOneWidget,
    );
    expect(byKey('setup-paste-$zamalek'), findsOneWidget);
    expect(byKey('setup-paste-$maadi'), findsNothing);
    // The server kept it.
    final row = h.db!['branches'].get(maadi);
    expect(row['latitude'], 29.960123);
    expect(row['geo_radius_meters'], 200);
    await h.flushTimers();
  });

  testWidgets('TEAM-SET-023 the last pin closes every row and ticks the step', (
    tester,
  ) async {
    final h = await pumpSetup(
      tester,
      edit: (db) => unpin(db, maadi, keepCoordinates: true),
    );
    expect(
      find.text(h.t('dawam.setupProgress', args: {'n': 3, 'total': 4})),
      findsOneWidget,
    );
    await h.tapKey(ValueKey('setup-save-pin-$maadi'));
    for (final b in [heliopolis, maadi, newCairo, zamalek]) {
      expect(byKey('setup-paste-$b'), findsNothing);
    }
    expect(
      find.text(h.t('dawam.setupProgress', args: {'n': 4, 'total': 4})),
      findsOneWidget,
    );
    expect(byKey('setup-complete'), findsOneWidget);
    await h.flushTimers();
  });

  testWidgets('TEAM-SET-023 "Save the pin" on a pinned branch; a refusal '
      'toasts and keeps the editor', (tester) async {
    final h = await pumpSetup(tester);
    await h.tapKey(const ValueKey('setup-step-branches'));
    await h.tapKey(ValueKey('setup-pin-toggle-$zamalek'));
    expect(
      _button(tester, 'setup-save-pin-$zamalek').label,
      h.t('dawam.savePin'),
    );
    await h.tapText('300 ${h.t('dawam.metres')}');
    h.server.fail(
      'PATCH',
      '/branches/{id}',
      MockResponse.denied('branches.edit'),
    );
    await h.tapKey(ValueKey('setup-save-pin-$zamalek'));
    // The server's refusal, as sent (it names the capability's description).
    expect(
      find.textContaining("Forbidden: You don't have permission to do this"),
      findsOneWidget,
    );
    await h.flushTimers();
    expect(byKey('setup-paste-$zamalek'), findsOneWidget);
    expect(h.db!['branches'].get(zamalek)['geo_radius_meters'], 200);
  });

  testWidgets('TEAM-SET-023 the mock refuses a pin without branches.edit '
      '(the server decides)', (tester) async {
    final s = setupServer(persona: Persona.manager);
    await expectLater(
      s.server.send(
        ApiRequest(
          method: 'PATCH',
          path: '/branches/$zamalek',
          body: {
            'latitude': 30.06,
            'longitude': 31.22,
            'geo_radius_meters': 150,
          },
        ),
      ),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
    );
  });

  testWidgets('TEAM-SET-039 phone: the pin controls stack', (tester) async {
    final h = await pumpSetup(tester, edit: _twoUnpinned, size: DashSize.phone);
    final locate = tester.getRect(byKey('setup-locate-$maadi'));
    final paste = tester.getRect(byKey('setup-paste-$maadi'));
    expect(paste.top, greaterThan(locate.bottom));
    await h.shot('branches-open');
  });

  testWidgets('TEAM-SET-039 wide: locate beside paste', (tester) async {
    await pumpSetup(tester, edit: _twoUnpinned);
    final locate = tester.getRect(byKey('setup-locate-$maadi'));
    final paste = tester.getRect(byKey('setup-paste-$maadi'));
    expect(paste.left, greaterThan(locate.right));
  });
}

class _SlowLocator implements SetupLocator {
  final _done = <void Function(LocationResult)>[];

  @override
  Future<LocationResult> locate({Duration timeout = locateTimeout}) {
    final c = Completer<LocationResult>();
    _done.add(c.complete);
    return c.future;
  }

  void finish(LocationResult r) {
    for (final f in _done) {
      f(r);
    }
  }
}
