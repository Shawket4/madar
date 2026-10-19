// `/setup`: every check the server can send has words in both languages,
// each row's button and named problem open the real page that fixes it, the
// stages (setting up, ready, live, no POS), the tablet sheet and the apps.
import 'dart:convert';
import 'dart:io';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_overview/src/apps/app_tiles.dart';
import 'package:dashboard_overview/src/apps/apps.dart';
import 'package:dashboard_overview/src/setup/check_row.dart';
import 'package:dashboard_overview/src/setup/checks.dart';
import 'package:dashboard_overview/src/setup/setup_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'support.dart';

/// The check keys the server's contract lists (`ReadinessCheck.key` in the
/// spec dashboard_api is generated from).
List<String> specKeys() {
  final spec =
      jsonDecode(
            File('../../dashboard_api/spec/openapi.json').readAsStringSync(),
          )
          as Map<String, Object?>;
  final schemas = (spec['components']! as Map)['schemas']! as Map;
  final key =
      ((schemas['ReadinessCheck']! as Map)['properties']! as Map)['key']!
          as Map;
  final doc = key['description']! as String;
  return [
    for (final m in RegExp('`([a-z_]+)`').allMatches(doc.split(':').last))
      m.group(1)!,
  ];
}

Finder inRow(String key, Finder f) =>
    find.descendant(of: find.byKey(ValueKey('check-$key')), matching: f);

Finder buttonIn(String key, String label) => inRow(
  key,
  find.byWidgetPredicate((w) => w is DashButton && w.label == label),
);

void main() {
  group('the words', () {
    test('every check the server can send has a glyph, a page and words '
        'in English and Arabic', () async {
      final keys = specKeys();
      expect(keys, hasLength(13), reason: 'the spec lists the keys');
      expect(checkDefs.keys.toSet(), keys.toSet());
      for (final lang in ['en', 'ar']) {
        final raw =
            jsonDecode(File('assets/i18n/$lang.json').readAsStringSync())
                as Map<String, Object?>;
        final checks = ((raw['setup']! as Map)['checks']! as Map);
        for (final k in keys) {
          final words = checks[k] as Map?;
          expect(words, isNotNull, reason: '$lang has no words for $k');
          for (final part in ['title', 'action', 'ok', 'todo']) {
            expect(
              words!.keys.any((w) => w == part || '$w'.startsWith('${part}_')),
              isTrue,
              reason: '$lang setup.checks.$k.$part',
            );
          }
        }
      }
    });

    for (final lang in ['en', 'ar']) {
      testWidgets('every row reads in $lang, to do and done (no missing '
          'word, no English on an Arabic screen)', (tester) async {
        await pumpSetup(tester, freshShop(), locale: lang);
        expect(find.byType(CheckRow), findsNWidgets(13));
        await pumpSetup(tester, readyShop(), locale: lang);
        expect(find.byType(CheckRow), findsNWidgets(13));
        // The harness fails the test on a missing word at tear-down.
      });
    }

    test('names read as one phrase', () {
      final t = Translator(Strings({'en': const {}, 'ar': const {}}), 'en');
      expect(joinNames(t, ['Maadi'], 0), 'Maadi');
      expect(joinNames(t, ['Maadi', 'Zamalek'], 0), 'Maadi and Zamalek');
      expect(joinNames(t, ['A', 'B', 'C'], 0), 'A, B and C');
      final ar = Translator(t.strings, 'ar');
      expect(joinNames(ar, ['المعادي', 'الزمالك'], 0), 'المعادي والزمالك');
    });
  });

  group('the stage', () {
    test('the home card shows until ready and live', () {
      expect(showsHomeCard(freshShop()), isTrue);
      expect(showsHomeCard(readyShop()), isTrue);
      expect(showsHomeCard(readyShop(live: true)), isFalse);
      final broken = Readiness(
        orgId: 'o',
        ready: false,
        live: true,
        checks: freshShop().checks,
      );
      expect(stageOf(broken), SetupStage.setup);
      expect(showsHomeCard(broken), isTrue);
      expect(
        showsHomeCard(
          const Readiness(orgId: 'o', ready: true, live: false, checks: []),
        ),
        isFalse,
      );
      // An unknown key from a newer server is skipped, not drawn.
      final newer = Readiness(
        orgId: 'o',
        ready: false,
        live: false,
        checks: [check('drawer_float', blocking: true), ...freshShop().checks],
      );
      expect(knownChecks(newer), hasLength(13));
    });

    testWidgets('a new shop: the welcome with its name, the two sections, '
        'the pips, the cashier first', (tester) async {
      await pumpSetup(tester, freshShop());
      expect(find.text('Set up your shop'), findsWidgets);
      expect(
        find.text('Sabah Coffee, let\'s get you selling.'),
        findsOneWidget,
      );
      expect(
        find.text(
          '3 things stand between you and your first sale. Each one ticks '
          'itself off as soon as it\'s done.',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('2 of 5 done'), findsOneWidget);
      expect(find.text('TO START SELLING'), findsOneWidget);
      expect(find.text('WORTH DOING'), findsOneWidget);
      expect(find.text('Start here: put it on your tablet'), findsOneWidget);
      expect(
        find.text('Nothing is left to pay with at Maadi.'),
        findsOneWidget,
      );
      expect(find.text('No tablet at Maadi yet.'), findsOneWidget);
      // State is said, not only coloured.
      expect(find.bySemanticsLabel('To do before selling'), findsNWidgets(3));
      expect(find.bySemanticsLabel('Worth doing'), findsNWidgets(2));
    });

    testWidgets('ready: the hero says so, no welcome', (tester) async {
      await pumpSetup(tester, readyShop());
      expect(find.text('Sabah Coffee is ready to sell.'), findsOneWidget);
      expect(find.text('Start here: put it on your tablet'), findsNothing);
    });

    testWidgets('live: Shop health, the first sale\'s date, no pips', (
      tester,
    ) async {
      await pumpSetup(tester, readyShop(live: true));
      expect(find.text('Shop health'), findsWidgets);
      expect(find.text('Sabah Coffee is live.'), findsOneWidget);
      expect(find.textContaining('First sale on'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('of 5 done')), findsNothing);
    });

    testWidgets('a Dawam-only org: nothing to set up for the till', (
      tester,
    ) async {
      await pumpSetup(
        tester,
        const Readiness(orgId: 'o', ready: true, live: false, checks: []),
      );
      expect(find.text('Nothing to set up for the till'), findsOneWidget);
      expect(find.byType(CheckRow), findsNothing);
    });

    testWidgets('a person who may not see the settings is refused the page', (
      tester,
    ) async {
      final h = await pumpSetup(tester, freshShop(), persona: Persona.limited);
      expect(find.byType(SetupPage), findsNothing);
      expect(h.server.callsTo(readinessRoute), isEmpty);
    });

    testWidgets('an old /onboarding link opens Setup', (tester) async {
      final s = serving(freshShop());
      final h = await pumpHome(
        tester,
        path: '/onboarding',
        server: s.server,
        db: s.db,
      );
      expect(h.location.path, '/setup');
      expect(find.byType(SetupPage), findsOneWidget);
    });
  });

  group('where each fix is', () {
    final pages = {
      'branch': '/branches',
      'payment': '/settings/payment-methods',
      'sign_in': '/access/users',
      'items_no_category': '/menu/items',
      'items_zero_price': '/menu/items',
      'required_group_empty': '/menu/groups',
      'menu_lint': '/menu/items',
      'recipes': '/menu/items?tab=items&recipe=missing',
      'ingredient_costs': '/inventory/ingredients',
      'team': '/access/users',
      'receipt': '/settings/brand',
    };
    for (final MapEntry(key: k, value: to) in pages.entries) {
      testWidgets('$k opens $to', (tester) async {
        final r = Readiness(
          orgId: SeedIds.sabahOrg,
          ready: false,
          live: false,
          checks: [check(k, count: 1, total: 2, blocking: k == 'branch')],
        );
        final h = await pumpSetup(tester, r);
        h.allowUnmatched = true; // the page opened is another area's
        await h.tap(buttonIn(k, h.t('setup.checks.$k.action')));
        expect(h.location.toString(), to);
      });
    }

    testWidgets('an empty menu: Import from Foodics or add items', (
      tester,
    ) async {
      final h = await pumpSetup(tester, freshShop());
      h.allowUnmatched = true;
      expect(buttonIn('menu', 'Add items myself'), findsOneWidget);
      await h.tap(buttonIn('menu', 'Import from Foodics'));
      expect(h.location.path, '/menu/import');
    });

    testWidgets('a named problem opens its own editor; the rest are counted', (
      tester,
    ) async {
      final h = await pumpSetup(tester, readyShop());
      h.allowUnmatched = true;
      // Branch-named checks say the names; the item lists open.
      await h.tap(buttonIn('recipes', 'See which'));
      expect(inRow('recipes', find.text('Item 20')), findsOneWidget);
      expect(inRow('recipes', find.text('and 4 more')), findsOneWidget);
      await h.tap(buttonIn('required_group_empty', 'See which'));
      await h.tap(inRow('required_group_empty', find.text('Milk')));
      expect(h.location.toString(), '/menu/groups?edit=g-1');
      await h.go('/setup');
      await h.tap(buttonIn('items_no_category', 'See which'));
      await h.tap(inRow('items_no_category', find.text('Matcha')));
      expect(h.location.path, '/menu/items/i-2');
    });

    test('problem routes', () {
      expect(problemRoute(item('x', 'X')), '/menu/items/x');
      expect(problemRoute(branch('b', 'B')), '/branches?edit=b');
      expect(
        problemRoute(
          const ReadinessProblem(
            entityType: 'ingredient',
            entityId: 'i',
            name: 'I',
          ),
        ),
        '/inventory/ingredients',
      );
      expect(
        problemRoute(
          const ReadinessProblem(
            entityType: 'attachment',
            entityId: 'a',
            name: 'A',
          ),
        ),
        '/menu/groups',
      );
    });

    testWidgets('the tablet: install from the QR or the App Store, then '
        'Devices on the branch without one', (tester) async {
      final h = await pumpSetup(tester, freshShop());
      h.allowUnmatched = true;
      await h.tap(buttonIn('tablet', 'Connect a tablet'));
      final sheet = find.byType(DashSurface).last;
      expect(
        find.descendant(of: sheet, matching: find.text('Connect a tablet')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sheet,
          matching: find.bySemanticsLabel('QR code: download Madar Cashier'),
        ),
        findsOneWidget,
      );
      await h.tap(
        find.bySemanticsLabel(
          RegExp('^Download Madar Cashier on the App Store'),
        ),
      );
      expect(h.openedLinks.last, Uri.parse(MadarApp.cashier.appStore!));
      await h.tapText('Open Devices');
      expect(h.location.path, '/devices');
      expect(h.container.read(scopeProvider).branchId, SeedIds.maadi);
    });
  });

  group('the apps', () {
    testWidgets('every app has its QR in both languages; a badge only where '
        'a store lists it', (tester) async {
      for (final app in MadarApp.values) {
        for (final lang in ['en', 'ar']) {
          expect(
            File(
              app.qr(lang).replaceFirst('packages/dashboard_overview/', ''),
            ).existsSync(),
            isTrue,
            reason: app.qr(lang),
          );
        }
        expect(app.isLive, app == MadarApp.cashier);
      }
      final h = await pumpSetup(tester, freshShop());
      for (final app in madarFamily) {
        await h.tap(find.byKey(ValueKey('app-tile-${app.name}')).first);
        final name = appCopy(h.container.read(tProvider), app).name;
        expect(
          find.bySemanticsLabel('QR code: download $name'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp('on the App Store')),
          app.isLive ? findsOneWidget : findsNothing,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await h.settle();
      }
    });

    testWidgets('the frame foot: four tiles; a tile opens the app\'s card '
        'and its downloads page', (tester) async {
      final h = await pumpSetup(tester, readyShop(live: true));
      // The foot shows at the end of the page.
      final scroll = find
          .descendant(
            of: find.byType(SetupPage),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scroll).position;
      position.jumpTo(position.maxScrollExtent);
      await h.settle();
      final foot = find.byType(MadarAppsRow);
      expect(foot, findsOneWidget);
      expect(
        find.descendant(of: foot, matching: find.byType(AppTile)),
        findsNWidgets(4),
      );
      expect(
        find.descendant(of: foot, matching: find.byType(SvgPicture)),
        findsNWidgets(4),
      );
      await h.tap(
        find.descendant(
          of: foot,
          matching: find.byKey(const ValueKey('app-tile-dawam')),
        ),
      );
      await h.tap(find.bySemanticsLabel(RegExp('^Android, Mac and Windows')));
      expect(
        h.openedLinks.last.toString(),
        'https://downloads.madar-pos.cloud/?app=dawam',
      );
      expect(
        downloadsUri('ar', MadarApp.cashier).toString(),
        'https://downloads.madar-pos.cloud/ar/?app=pos',
      );
    });
  });
}
