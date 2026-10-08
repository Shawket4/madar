import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/rig.dart';

String _en(String key) => syncedStrings().table('en')[key]!;
String _ar(String key) => syncedStrings().table('ar')[key]!;

const _page = Text('PAGE BODY');

void main() {
  setUpAll(ensureTimeZones);

  group('Restricted', () {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      for (final size in ShotSize.values) {
        testWidgets('a page that is not theirs, $lang ${size.name}', (
          tester,
        ) async {
          final rig = CoreRig(persona: Persona.limited);
          await pumpCore(
            tester,
            rig,
            Builder(
              builder: (context) => Restricted(title: context.t('nav.devices')),
            ),
            lang: lang,
            dark: dark,
            size: size,
          );
          final words = lang == 'en' ? _en : _ar;
          expect(find.text(words('nav.devices')), findsOneWidget);
          expect(find.text(words('common.restrictedTitle')), findsOneWidget);
          expect(find.text(words('common.restrictedBody')), findsOneWidget);
          await shot(
            tester,
            'gates',
            'restricted',
            size: size,
            lang: lang,
            dark: dark,
          );
        });
      }
    }

    testWidgets('works inside a scrolling page too', (tester) async {
      await pumpCore(
        tester,
        CoreRig(),
        const SingleChildScrollView(child: Restricted(title: 'Devices')),
      );
      expect(tester.takeException(), isNull);
      expect(find.text(_en('common.restrictedTitle')), findsOneWidget);
    });

    testWidgets('who it is for, when the page says', (tester) async {
      await pumpCore(
        tester,
        CoreRig(),
        const Restricted(title: 'Organizations', who: 'For Madar staff only.'),
      );
      expect(find.text('For Madar staff only.'), findsOneWidget);
    });
  });

  group('ModuleGate', () {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      for (final size in ShotSize.values) {
        testWidgets('a POS page in a Dawam-only org, $lang ${size.name}', (
          tester,
        ) async {
          final rig = CoreRig(persona: Persona.dawamOnly);
          await pumpCore(
            tester,
            rig,
            const ModuleGate(path: '/orders', child: _page),
            lang: lang,
            dark: dark,
            size: size,
          );
          final words = lang == 'en' ? _en : _ar;
          expect(find.text('PAGE BODY'), findsNothing);
          expect(find.text(words('dawam.moduleOffTitle')), findsOneWidget);
          expect(find.text(words('dawam.modulePosOff')), findsOneWidget);
          await shot(
            tester,
            'gates',
            'module-off',
            size: size,
            lang: lang,
            dark: dark,
          );
        });
      }
    }

    testWidgets('a Dawam page in a POS-less org says Dawam is off', (
      tester,
    ) async {
      final rig = CoreRig();
      rig.server.on(
        'GET',
        '/orgs/{id}/modules',
        (req) => MockResponse.json(200, {
          'org_id': req.param('id'),
          'modules': ['pos'],
        }),
      );
      await pumpCore(
        tester,
        rig,
        const ModuleGate(path: '/staff/team', child: _page),
      );
      expect(find.text(_en('dawam.moduleDawamOff')), findsOneWidget);
    });

    testWidgets('pages of a switched-on module open', (tester) async {
      await pumpCore(
        tester,
        CoreRig(),
        const ModuleGate(path: '/staff/team', child: _page),
      );
      expect(find.text('PAGE BODY'), findsOneWidget);
    });

    testWidgets('untagged pages open in any org', (tester) async {
      await pumpCore(
        tester,
        CoreRig(persona: Persona.dawamOnly),
        const ModuleGate(path: '/branches', child: _page),
      );
      expect(find.text('PAGE BODY'), findsOneWidget);
    });

    testWidgets('nothing on a guess while the modules load', (tester) async {
      final rig = CoreRig();
      final gate = rig.server.hold('GET', '/orgs/{id}/modules');
      await pumpCore(
        tester,
        rig,
        const ModuleGate(path: '/orders', child: _page),
      );
      expect(find.text('PAGE BODY'), findsNothing);
      expect(find.text(_en('dawam.moduleOffTitle')), findsNothing);
      gate.release();
      await settleRig(tester);
      expect(find.text('PAGE BODY'), findsOneWidget);
    });

    for (final (lang, dark, size) in [
      ('en', false, ShotSize.desktop),
      ('ar', false, ShotSize.phone),
    ]) {
      testWidgets(
        'says so when the modules cannot be read, then retries, $lang',
        (tester) async {
          final rig = CoreRig();
          rig.server.fail(
            'GET',
            '/orgs/{id}/modules',
            MockResponse.error(500, 'The server is down'),
          );
          await pumpCore(
            tester,
            rig,
            const ModuleGate(path: '/orders', child: _page),
            lang: lang,
            dark: dark,
            size: size,
          );
          final words = lang == 'en' ? _en : _ar;
          expect(
            find.textContaining(words('dawam.modulesLoadError')),
            findsOneWidget,
          );
          expect(find.textContaining('The server is down'), findsOneWidget);
          await shot(
            tester,
            'gates',
            'modules-error',
            size: size,
            lang: lang,
            dark: dark,
          );
          await tester.tap(find.text(words('common.retry')));
          await settleRig(tester);
          expect(find.text('PAGE BODY'), findsOneWidget);
        },
      );
    }
  });

  group('CapGate', () {
    testWidgets('shows to whoever holds any of the capabilities', (
      tester,
    ) async {
      await pumpCore(
        tester,
        CoreRig(persona: Persona.manager),
        const Column(
          children: [
            CapGate(
              anyOf: [Cap.orgSettingsEdit],
              fallback: Text('NO EDIT'),
              child: Text('EDIT'),
            ),
            CapGate(
              anyOf: [Cap.orgSettingsEdit, Cap.ordersRead],
              child: Text('READ'),
            ),
            CapGate(anyOf: [], child: Text('ANYONE')),
          ],
        ),
      );
      expect(find.text('EDIT'), findsNothing);
      expect(find.text('NO EDIT'), findsOneWidget);
      expect(find.text('READ'), findsOneWidget);
      expect(find.text('ANYONE'), findsOneWidget);
    });
  });

  group('the kit speaks the live i18n', () {
    testWidgets('DashKitScope fills DashKitLocalizations from the tables', (
      tester,
    ) async {
      await pumpCore(
        tester,
        CoreRig(),
        Builder(
          builder: (context) => Column(
            children: [
              Text(context.dashStrings.noResults),
              Text(context.dashStrings.retry),
              Text(context.dashFormats.currencyLabel),
            ],
          ),
        ),
        lang: 'ar',
      );
      expect(find.text(_ar('common.noResults')), findsOneWidget);
      expect(find.text(_ar('common.retry')), findsOneWidget);
      expect(find.text('ج.م'), findsOneWidget);
    });

    test('plurals reach the kit through args[count]', () {
      final t = Translator(syncedStrings(), 'en');
      final k = dashKitStringsFrom(t);
      expect(k.selectedCount(1), t('grid.selectedCount', count: 1));
      expect(k.page(2, 9), t('common.page', args: {'current': 2, 'total': 9}));
    });
  });
}
